import Foundation

/// Gemini usage via Google's Cloud Code quota API — the same backend the
/// Gemini CLI and Antigravity read. Tries the pooled quota summary first
/// (session/weekly buckets), falling back to legacy per-model buckets.
struct GeminiProvider: UsageProvider {
    var info: ProviderInfo { ProviderInfo(id: "gemini", name: "Gemini", glyph: .gemini) }

    var refreshInterval: TimeInterval { 120 }

    func isConfigured() -> Bool { GeminiTokenStore.isConfigured() }

    func fetch() async throws -> ProviderStatus {
        guard let token = await GeminiTokenStore.shared.token() else {
            throw HTTPError.status(401, "No Gemini login found. Sign in to Antigravity or run `gemini`.")
        }
        let headers = [
            "Authorization": "Bearer \(token)",
            "Content-Type": "application/json",
            "Accept": "application/json",
            "User-Agent": "antigravity",
        ]
        let base = "https://cloudcode-pa.googleapis.com/v1internal"
        do {
            let data = try await HTTP.json(
                URL(string: "\(base):retrieveUserQuotaSummary")!,
                method: "POST", headers: headers, body: Data("{}".utf8)
            )
            if let status = try? Self.parseSummary(data), !status.metrics.isEmpty {
                return status
            }
        } catch let HTTPError.status(code, _) where code == 404 {
            // Older backend — use the legacy endpoint below.
        }
        let data = try await HTTP.json(
            URL(string: "\(base):retrieveUserQuota")!,
            method: "POST", headers: headers, body: Data("{}".utf8)
        )
        return try Self.parseLegacy(data)
    }

    // MARK: - Quota summary (pooled session/weekly buckets)

    static func parseSummary(_ data: Data, now: Date = Date()) throws -> ProviderStatus {
        guard var root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw HTTPError.status(200, "unexpected quota summary shape")
        }
        if let wrapped = root["response"] as? [String: Any] { root = wrapped }
        let groups = root["groups"] as? [[String: Any]] ?? []
        var byID: [String: (fraction: Double, reset: Date?)] = [:]
        for group in groups {
            for bucket in group["buckets"] as? [[String: Any]] ?? [] {
                guard let id = bucket["bucketId"] as? String,
                      let remaining = remainingFraction(of: bucket)
                else { continue }   // missing fraction means "no data", never 0 or 1
                let reset = (resetTime(of: bucket)).flatMap(parseISODate)
                byID[id] = (remaining, reset)
            }
        }
        var metrics: [Metric] = []
        for (id, label) in [
            ("gemini-5h", "Current session"),
            ("gemini-weekly", "Weekly"),
            ("3p-5h", "Other models"),
            ("3p-weekly", "Other weekly"),
        ] {
            guard let bucket = byID[id] else { continue }
            let used = (1 - bucket.fraction).unitClamped
            metrics.append(Metric(
                label: label,
                sublabel: bucket.reset.map { Fmt.reset($0, now: now) },
                fraction: used,
                footnote: "\(Fmt.percent(used)) Used"
            ))
        }
        let session = metrics.first?.fraction ?? 0
        return ProviderStatus(
            ringFraction: session,
            ringLabel: Fmt.percent(session),
            metrics: metrics
        )
    }

    /// The fraction may be flat, nested under `remaining`, or a {case,value}
    /// oneof — read all three, and never invent a value for a missing one.
    private static func remainingFraction(of bucket: [String: Any]) -> Double? {
        if let flat = bucket["remainingFraction"] as? Double { return flat }
        guard let nested = bucket["remaining"] as? [String: Any] else { return nil }
        if let value = nested["remainingFraction"] as? Double { return value }
        if nested["case"] as? String == "remainingFraction", let value = nested["value"] as? Double {
            return value
        }
        return nil
    }

    private static func resetTime(of bucket: [String: Any]) -> String? {
        (bucket["resetTime"] as? String)
            ?? ((bucket["remaining"] as? [String: Any])?["resetTime"] as? String)
    }

    // MARK: - Legacy per-model buckets

    static func parseLegacy(_ data: Data, now: Date = Date()) throws -> ProviderStatus {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw HTTPError.status(200, "unexpected quota shape")
        }
        // Keep the worst (lowest remaining) bucket per model.
        var worst: [String: (fraction: Double, reset: Date?)] = [:]
        for bucket in root["buckets"] as? [[String: Any]] ?? [] {
            guard let model = bucket["modelId"] as? String,
                  let remaining = bucket["remainingFraction"] as? Double
            else { continue }
            let reset = (bucket["resetTime"] as? String).flatMap(parseISODate)
            if worst[model] == nil || remaining < worst[model]!.fraction {
                worst[model] = (remaining, reset)
            }
        }
        guard !worst.isEmpty else {
            throw HTTPError.status(200, "No Gemini quota data for this account.")
        }
        let metrics = worst.sorted { $0.value.fraction < $1.value.fraction }.prefix(4).map { model, info in
            let used = (1 - info.fraction).unitClamped
            return Metric(
                label: model,
                sublabel: info.reset.map { Fmt.reset($0, now: now) },
                fraction: used,
                footnote: "\(Fmt.percent(used)) Used"
            )
        }
        // Headline: the most-used Gemini model (any model if none match).
        let gemini = metrics.first { $0.label.contains("gemini") } ?? metrics[0]
        return ProviderStatus(
            ringFraction: gemini.fraction,
            ringLabel: Fmt.percent(gemini.fraction ?? 0),
            metrics: Array(metrics)
        )
    }
}
