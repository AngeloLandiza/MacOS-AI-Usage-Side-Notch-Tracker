import Foundation

/// OpenRouter credits and key usage. `/api/v1/key` works with a normal
/// inference key; `/api/v1/credits` (account balance) needs a management key,
/// so a 403 there is expected and quietly ignored.
struct OpenRouterProvider: UsageProvider {
    static let keychainService = "SideNotch.openrouter"

    var info: ProviderInfo { ProviderInfo(id: "openrouter", name: "OpenRouter", glyph: .openRouter) }

    func isConfigured() -> Bool { !(Keychain.read(service: Self.keychainService) ?? "").isEmpty }

    func fetch() async throws -> ProviderStatus {
        guard let key = Keychain.read(service: Self.keychainService), !key.isEmpty else {
            throw HTTPError.status(401, "No OpenRouter API key set.")
        }
        let headers = ["Authorization": "Bearer \(key)"]
        let keyData = try await HTTP.json(
            URL(string: "https://openrouter.ai/api/v1/key")!, headers: headers
        )
        let creditsData = try? await HTTP.json(
            URL(string: "https://openrouter.ai/api/v1/credits")!, headers: headers
        )
        return try Self.parse(keyData: keyData, creditsData: creditsData)
    }

    // MARK: - Parsing

    struct KeyData: Decodable {
        var usage: Double?
        var usage_daily: Double?
        var usage_weekly: Double?
        var usage_monthly: Double?
        var limit: Double?
        var limit_remaining: Double?
    }

    struct KeyResponse: Decodable { var data: KeyData }

    struct CreditsData: Decodable {
        var total_credits: Double?
        var total_usage: Double?
    }

    struct CreditsResponse: Decodable { var data: CreditsData }

    static func parse(keyData: Data, creditsData: Data?) throws -> ProviderStatus {
        let key = try JSONDecoder().decode(KeyResponse.self, from: keyData).data
        let credits = creditsData.flatMap { try? JSONDecoder().decode(CreditsResponse.self, from: $0).data }

        var balance: Double?
        if let total = credits?.total_credits {
            balance = total - (credits?.total_usage ?? 0)
        } else if let remaining = key.limit_remaining {
            balance = remaining
        }

        // Ring: usage against the key's credit cap when one exists, otherwise
        // against purchased credits; balance-only when neither is known.
        var fraction: Double?
        if let limit = key.limit, limit > 0 {
            fraction = ((limit - (key.limit_remaining ?? limit)) / limit).unitClamped
        } else if let total = credits?.total_credits, total > 0 {
            fraction = ((credits?.total_usage ?? 0) / total).unitClamped
        }

        var metrics: [Metric] = []
        for (label, amount) in [
            ("Today", key.usage_daily),
            ("This week", key.usage_weekly),
            ("This month", key.usage_monthly),
        ] {
            guard let amount else { continue }
            metrics.append(Metric(label: label, sublabel: "\(Fmt.money(amount)) spent"))
        }

        return ProviderStatus(
            ringFraction: fraction,
            ringLabel: fraction.map(Fmt.percent) ?? balance.map { Fmt.money($0) } ?? "—",
            metrics: metrics,
            credits: balance.map { Fmt.money($0) }
        )
    }
}
