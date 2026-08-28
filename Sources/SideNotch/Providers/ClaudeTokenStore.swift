import Foundation

/// Reads Claude Code's OAuth token off the main actor. The Keychain secret is
/// fetched via `security` (works without entitlements); on first use macOS may
/// show a permission prompt, which is allowed to stand — reads are serialized
/// and the result is cached briefly so the prompt appears at most once.
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
            let json = await Self.keychainCredentialsJSON()
                ?? (try? String(contentsOf: ClaudeProvider.credentialsFile, encoding: .utf8))
            return json.flatMap(ClaudeProvider.token(fromCredentialsJSON:))
        }
        inFlight = task
        let value = await task.value
        inFlight = nil
        cached = (value, Date())
        return value
    }

    private static func keychainCredentialsJSON() async -> String? {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
            process.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()
            process.terminationHandler = { finished in
                // The payload (~1 KB) fits the pipe buffer, so reading after
                // exit cannot deadlock.
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let out = String(decoding: data, as: UTF8.self).trimmed
                continuation.resume(returning: finished.terminationStatus == 0 && !out.isEmpty ? out : nil)
            }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                continuation.resume(returning: nil)
            }
        }
    }
}
