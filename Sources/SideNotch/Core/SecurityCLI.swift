import Foundation
import Security
import os

let appLog = Logger(subsystem: "com.angelolandiza.SideNotch", category: "app")

/// Reads other apps' Keychain items via `/usr/bin/security` — the pattern
/// community trackers use, because the tool's access grant survives our app
/// being rebuilt/re-signed. The first read may show a one-time macOS
/// permission prompt, which is allowed to stand (callers run off the main
/// actor and time out via their HTTP layer, not here).
enum SecurityCLI {
    static func readGenericPassword(service: String, account: String? = nil) async -> String? {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
            var args = ["find-generic-password", "-s", service]
            if let account { args += ["-a", account] }
            args.append("-w")
            process.arguments = args
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()
            process.terminationHandler = { finished in
                // Payloads are tiny (~1 KB), far below the pipe buffer, so
                // reading after exit cannot deadlock.
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let out = String(decoding: data, as: UTF8.self).trimmed
                appLog.info("security tool (\(service, privacy: .public)) exit=\(finished.terminationStatus), bytes=\(data.count)")
                continuation.resume(returning: finished.terminationStatus == 0 && !out.isEmpty ? out : nil)
            }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                appLog.error("security tool failed to launch: \(error.localizedDescription)")
                continuation.resume(returning: nil)
            }
        }
    }

    /// Prompt-free existence check for a generic-password item (metadata only).
    static func itemExists(service: String, account: String? = nil) -> Bool {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        if let account { query[kSecAttrAccount as String] = account }
        var item: CFTypeRef?
        return SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess
    }
}
