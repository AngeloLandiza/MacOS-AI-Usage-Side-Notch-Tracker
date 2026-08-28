import Foundation

protocol UsageProvider: Sendable {
    var info: ProviderInfo { get }
    /// Minimum seconds between fetches (some endpoints throttle hard).
    var refreshInterval: TimeInterval { get }
    /// Whether credentials exist (auto-detected file/keychain or user-entered key).
    func isConfigured() -> Bool
    func fetch() async throws -> ProviderStatus
}

extension UsageProvider {
    var refreshInterval: TimeInterval { 60 }
}

/// All providers the app knows about, in display order.
@MainActor
enum ProviderRegistry {
    static var all: [any UsageProvider] {
        [ClaudeProvider(), CodexProvider(), GeminiProvider(), OpenRouterProvider(), DeepSeekProvider()]
    }

    /// Providers that currently have credentials available.
    static var configured: [any UsageProvider] {
        all.filter { $0.isConfigured() }
    }
}
