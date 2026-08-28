import Foundation

/// Reads Claude Code's OAuth token off the main actor. Reads are serialized
/// and the result is cached briefly so the Keychain permission prompt appears
/// at most once.
actor ClaudeTokenStore {
    static let shared = ClaudeTokenStore()

    private var cached: (value: String?, at: Date)?
    private var inFlight: Task<String?, Never>?
    private let cacheTTL: TimeInterval = 60

    func token() async -> String? {
        if let env = ProcessInfo.processInfo.environment["CLAUDE_CODE_OAUTH_TOKEN"], !env.isEmpty {
            return env
        }
        if let cached, Date().timeIntervalSince(cached.at) < cacheTTL {
            return cached.value
        }
        if let inFlight { return await inFlight.value }
        let task = Task<String?, Never> {
            let keychainJSON = await SecurityCLI.readGenericPassword(service: "Claude Code-credentials")
            let json = keychainJSON
                ?? (try? String(contentsOf: ClaudeProvider.credentialsFile, encoding: .utf8))
            let token = json.flatMap(ClaudeProvider.token(fromCredentialsJSON:))
            appLog.info("claude token: keychain=\(keychainJSON != nil), file=\(keychainJSON == nil && json != nil), parsed=\(token != nil)")
            return token
        }
        inFlight = task
        let value = await task.value
        inFlight = nil
        cached = (value, Date())
        return value
    }
}
