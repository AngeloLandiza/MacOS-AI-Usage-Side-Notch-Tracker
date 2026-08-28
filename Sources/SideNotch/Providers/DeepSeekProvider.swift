import Foundation

/// DeepSeek platform balance (balance-only provider: full ring, money label).
struct DeepSeekProvider: UsageProvider {
    static let keychainService = "SideNotch.deepseek"

    var info: ProviderInfo { ProviderInfo(id: "deepseek", name: "DeepSeek", glyph: .deepSeek) }

    func isConfigured() -> Bool { !(Keychain.read(service: Self.keychainService) ?? "").isEmpty }

    func fetch() async throws -> ProviderStatus {
        guard let key = Keychain.read(service: Self.keychainService), !key.isEmpty else {
            throw HTTPError.status(401, "No DeepSeek API key set.")
        }
        let data = try await HTTP.json(
            URL(string: "https://api.deepseek.com/user/balance")!,
            headers: ["Authorization": "Bearer \(key)", "Accept": "application/json"]
        )
        return try Self.parse(data)
    }

    // MARK: - Parsing (amounts are decimal *strings*, e.g. "110.00")

    struct BalanceInfo: Decodable {
        var currency: String?
        var total_balance: String?
        var granted_balance: String?
        var topped_up_balance: String?
    }

    struct Response: Decodable {
        var is_available: Bool?
        var balance_infos: [BalanceInfo]?
    }

    static func parse(_ data: Data) throws -> ProviderStatus {
        let response = try JSONDecoder().decode(Response.self, from: data)
        let infos = response.balance_infos ?? []
        var metrics: [Metric] = []
        for info in infos {
            let currency = info.currency ?? "USD"
            if let granted = info.granted_balance.flatMap(Double.init), granted > 0 {
                metrics.append(Metric(label: "Granted (\(currency))", sublabel: Fmt.money(granted, currency: currency)))
            }
            if let topped = info.topped_up_balance.flatMap(Double.init), topped > 0 {
                metrics.append(Metric(label: "Topped up (\(currency))", sublabel: Fmt.money(topped, currency: currency)))
            }
        }
        if response.is_available == false {
            metrics.append(Metric(label: "Balance exhausted", sublabel: "Top up to keep using the API"))
        }
        // The account may hold several currencies; lead with the first funded one.
        let balances: [(currency: String, amount: Double)] = infos.compactMap { info in
            info.total_balance.flatMap(Double.init).map { (info.currency ?? "USD", $0) }
        }
        let primary = balances.first { $0.amount > 0 } ?? balances.first
        let label = primary.map { Fmt.money($0.amount, currency: $0.currency) } ?? "—"
        let all = balances.map { Fmt.money($0.amount, currency: $0.currency) }.joined(separator: " · ")
        return ProviderStatus(
            ringFraction: response.is_available == false ? 0 : nil,
            ringLabel: label,
            metrics: metrics,
            credits: all.isEmpty ? nil : all
        )
    }
}
