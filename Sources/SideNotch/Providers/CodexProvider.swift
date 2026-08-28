import Foundation

/// OpenAI usage for ChatGPT-plan Codex users. Reuses Codex CLI's login
/// (`~/.codex/auth.json`); shows the 5-hour and weekly rate-limit windows plus
/// any credits balance.
struct CodexProvider: UsageProvider {
    var info: ProviderInfo { ProviderInfo(id: "openai", name: "OpenAI", glyph: .openAI) }

    func isConfigured() -> Bool { Self.credentials() != nil }

    func fetch() async throws -> ProviderStatus {
        guard let creds = Self.credentials() else {
            throw HTTPError.status(401, "No Codex CLI login found. Run `codex login`.")
        }
        var headers = [
            "Authorization": "Bearer \(creds.accessToken)",
            "Accept": "application/json",
            "User-Agent": "SideNotch",
        ]
        if let account = creds.accountID { headers["ChatGPT-Account-Id"] = account }
        let data = try await HTTP.json(
            URL(string: "https://chatgpt.com/backend-api/wham/usage")!,
            headers: headers
        )
        return try Self.parse(data)
    }

    // MARK: - Credentials

    struct Credentials {
        var accessToken: String
        var accountID: String?
    }

    static func credentials() -> Credentials? {
        let home = ProcessInfo.processInfo.environment["CODEX_HOME"].map(URL.init(fileURLWithPath:))
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
        guard let data = try? Data(contentsOf: home.appendingPathComponent("auth.json")),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tokens = root["tokens"] as? [String: Any],
              let token = tokens["access_token"] as? String, !token.isEmpty
        else { return nil }
        return Credentials(accessToken: token, accountID: tokens["account_id"] as? String)
    }

    // MARK: - Parsing

    struct Window: Decodable {
        var used_percent: Double?
        var limit_window_seconds: Int?
        var reset_at: Double?
        var reset_after_seconds: Double?
    }

    struct RateLimit: Decodable {
        var primary_window: Window?
        var secondary_window: Window?
    }

    struct Credits: Decodable {
        var has_credits: Bool?
        var unlimited: Bool?
        var balance: String?
    }

    struct Response: Decodable {
        var plan_type: String?
        var rate_limit: RateLimit?
        var credits: Credits?
    }

    static func parse(_ data: Data, now: Date = Date()) throws -> ProviderStatus {
        let response = try JSONDecoder().decode(Response.self, from: data)
        var metrics: [Metric] = []
        for (label, window) in [
            ("Current session", response.rate_limit?.primary_window),
            ("Weekly", response.rate_limit?.secondary_window),
        ] {
            guard let window, let percent = window.used_percent else { continue }
            let fraction = (percent / 100).unitClamped
            let resetDate = window.reset_at.map { Date(timeIntervalSince1970: $0) }
                ?? window.reset_after_seconds.map { now.addingTimeInterval($0) }
            metrics.append(Metric(
                label: label,
                sublabel: resetDate.map { Fmt.reset($0, now: now) },
                fraction: fraction,
                footnote: "\(Fmt.percent(fraction)) Used"
            ))
        }
        var credits: String?
        if let c = response.credits {
            if c.unlimited == true {
                credits = "Unlimited"
            } else if c.has_credits == true, let balance = c.balance.flatMap(Double.init) {
                credits = Fmt.money(balance)
            }
        }
        let session = metrics.first?.fraction ?? 0
        return ProviderStatus(
            ringFraction: session,
            ringLabel: Fmt.percent(session),
            metrics: metrics,
            credits: credits
        )
    }
}
