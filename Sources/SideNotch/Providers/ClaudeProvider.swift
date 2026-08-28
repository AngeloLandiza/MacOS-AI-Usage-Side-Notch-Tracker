import Foundation

/// Claude Code usage — the same 5-hour/weekly utilization the `/usage` command
/// shows. Reuses Claude Code's own OAuth token; no key entry needed.
struct ClaudeProvider: UsageProvider {
    var info: ProviderInfo { ProviderInfo(id: "claude", name: "Claude", glyph: .claude) }

    /// The usage endpoint rate-limits aggressive pollers; stay well behind it.
    var refreshInterval: TimeInterval { 300 }

    func isConfigured() -> Bool { Self.accessToken() != nil }

    func fetch() async throws -> ProviderStatus {
        guard let token = Self.accessToken() else {
            throw HTTPError.status(401, "No Claude Code login found. Run `claude` and sign in.")
        }
        let data = try await HTTP.json(
            URL(string: "https://api.anthropic.com/api/oauth/usage")!,
            headers: [
                "Authorization": "Bearer \(token)",
                "anthropic-beta": "oauth-2025-04-20",
                "Content-Type": "application/json",
                // Required: other user agents fall into an aggressively throttled bucket.
                "User-Agent": "claude-cli/2.0.0 (external, cli)",
            ]
        )
        return try Self.parse(data)
    }

    // MARK: - Credentials (Keychain item written by Claude Code, or file/env fallback)

    static func accessToken() -> String? {
        if let env = ProcessInfo.processInfo.environment["CLAUDE_CODE_OAUTH_TOKEN"], !env.isEmpty {
            return env
        }
        let json = keychainCredentialsJSON()
            ?? (try? String(
                contentsOf: FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent(".claude/.credentials.json"),
                encoding: .utf8
            ))
        guard let json,
              let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = root["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String, !token.isEmpty
        else { return nil }
        return token
    }

    /// Claude Code stores credentials as a generic password; read it the same
    /// way other trackers do (via `security`, which works without entitlements).
    /// The call can block on a one-time macOS permission prompt, so it gets a
    /// hard timeout and a short cache.
    private nonisolated(unsafe) static var cachedJSON: (value: String?, at: Date)?
    private static let cacheLock = NSLock()
    private static let cacheTTL: TimeInterval = 60

    private static func keychainCredentialsJSON() -> String? {
        cacheLock.lock()
        if let cached = cachedJSON, Date().timeIntervalSince(cached.at) < cacheTTL {
            cacheLock.unlock()
            return cached.value
        }
        cacheLock.unlock()

        let value = runSecurityTool()
        cacheLock.lock()
        cachedJSON = (value, Date())
        cacheLock.unlock()
        return value
    }

    private static func runSecurityTool() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
        } catch { return nil }
        let deadline = Date().addingTimeInterval(5)
        while process.isRunning && Date() < deadline {
            usleep(50_000)
        }
        if process.isRunning {
            process.terminate()
            return nil
        }
        guard process.terminationStatus == 0 else { return nil }
        let out = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let trimmed = out.trimmed
        return trimmed.isEmpty ? nil : trimmed
    }

    // MARK: - Parsing

    struct Window: Decodable {
        var utilization: Double?
        var resets_at: String?
    }

    struct ExtraUsage: Decodable {
        var is_enabled: Bool?
        var monthly_limit: Double?
        var used_credits: Double?
    }

    struct Response: Decodable {
        var five_hour: Window?
        var seven_day: Window?
        var seven_day_opus: Window?
        var seven_day_sonnet: Window?
        var extra_usage: ExtraUsage?
    }

    static func parse(_ data: Data, now: Date = Date()) throws -> ProviderStatus {
        let response = try JSONDecoder().decode(Response.self, from: data)
        var metrics: [Metric] = []
        for (label, window) in [
            ("Current session", response.five_hour),
            ("All models", response.seven_day),
            ("Opus", response.seven_day_opus),
            ("Sonnet", response.seven_day_sonnet),
        ] {
            guard let window, let utilization = window.utilization else { continue }
            let fraction = normalizedUtilization(utilization)
            metrics.append(Metric(
                label: label,
                sublabel: window.resets_at.flatMap(parseISODate).map { Fmt.reset($0, now: now) },
                fraction: fraction,
                footnote: "\(Fmt.percent(fraction)) Used"
            ))
        }
        if let extra = response.extra_usage, extra.is_enabled == true, let used = extra.used_credits {
            let limit = extra.monthly_limit.map { " of \(Fmt.money($0))" } ?? ""
            metrics.append(Metric(label: "Extra usage", sublabel: "\(Fmt.money(used))\(limit)"))
        }
        let session = metrics.first?.fraction ?? 0
        return ProviderStatus(
            ringFraction: session,
            ringLabel: Fmt.percent(session),
            metrics: metrics
        )
    }

    /// The API reports percent 0–100, but a fractional 0–1 variant exists in
    /// the wild; accept both and clamp.
    static func normalizedUtilization(_ value: Double) -> Double {
        let percent = value > 0 && value < 1 ? value * 100 : value
        return (percent / 100).unitClamped
    }
}

func parseISODate(_ string: String) -> Date? {
    let fractional = ISO8601DateFormatter()
    fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = fractional.date(from: string) { return date }
    return ISO8601DateFormatter().date(from: string)
}
