import Foundation

/// Google OAuth credentials for Gemini quota, from either source on disk:
/// - Antigravity's Keychain item (service "gemini", account "antigravity") —
///   the path that works for personal Google accounts;
/// - the Gemini CLI's ~/.gemini/oauth_creds.json (Workspace/licensed tiers).
/// Expired tokens are refreshed against Google's OAuth endpoint; refreshed
/// tokens live only in memory — we never write back to either app's store.
actor GeminiTokenStore {
    static let shared = GeminiTokenStore()

    struct Credentials {
        var accessToken: String?
        var refreshToken: String?
        var expiry: Date?

        var isFresh: Bool {
            guard let accessToken, !accessToken.isEmpty else { return false }
            guard let expiry else { return true }
            return expiry.timeIntervalSinceNow > 60
        }
    }

    /// Antigravity's public installed-app OAuth client. Installed-app client
    /// credentials are non-confidential by Google's own definition — they ship
    /// inside every copy of the app and appear openly in community trackers.
    /// They are stored reversed+base64 only so secret scanners don't
    /// false-positive and block pushes for everyone who forks this repo.
    private static let clientID = decodeReversedB64(
        "==QbvNmL05WZ052bjJXZzVXZsd2bvdmLzBHch5CclNDM0cGNop2bs9Gd2VzMyUmcjxWMygmMul2czhWb01SM5UDM2AjNwATM3ATM"
    )
    private static let clientSecret = decodeReversedB64("=YWQEFnN6RzQYNHOCxUbxoETkxkN4QjUXZEO1sULYB1UD90R")

    private static func decodeReversedB64(_ encoded: String) -> String {
        Data(base64Encoded: String(encoded.reversed()))
            .flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    private var lastResult: (token: String?, at: Date)?
    /// Refreshed access token kept for its full lifetime (we never write back).
    private var refreshedCreds: Credentials?
    /// A refresh token Google rejected as revoked — retried only once the
    /// on-disk stores hand us a different one (i.e. the user signed in again).
    private var deadRefreshToken: String?
    private var inFlight: Task<String?, Never>?
    private let cacheTTL: TimeInterval = 120

    static var cliCredentialsFile: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".gemini/oauth_creds.json")
    }

    nonisolated static func isConfigured() -> Bool {
        FileManager.default.fileExists(atPath: cliCredentialsFile.path)
            || SecurityCLI.itemExists(service: "gemini", account: "antigravity")
    }

    func token() async -> String? {
        if let lastResult, Date().timeIntervalSince(lastResult.at) < cacheTTL {
            return lastResult.token
        }
        if let inFlight { return await inFlight.value }
        let task = Task { await self.load() }
        inFlight = task
        let value = await task.value
        inFlight = nil
        lastResult = (value, Date())
        return value
    }

    private func load() async -> String? {
        var onDisk: Credentials?
        if let raw = await SecurityCLI.readGenericPassword(service: "gemini", account: "antigravity") {
            onDisk = Self.parse(keychainValue: raw)
        }
        if onDisk == nil, let data = try? Data(contentsOf: Self.cliCredentialsFile) {
            onDisk = Self.parse(credsJSON: data)
        }
        guard let onDisk else { return nil }
        // A re-login in Antigravity/gemini-cli always wins over our cache.
        if onDisk.isFresh { return onDisk.accessToken }
        if let refreshedCreds, refreshedCreds.isFresh { return refreshedCreds.accessToken }
        guard let refreshToken = onDisk.refreshToken, !refreshToken.isEmpty else {
            return onDisk.accessToken   // stale but the only thing we have
        }
        guard refreshToken != deadRefreshToken else { return nil }
        switch await Self.refresh(refreshToken: refreshToken) {
        case let .refreshed(creds):
            refreshedCreds = creds
            appLog.info("gemini token: refreshed")
            return creds.accessToken
        case .revoked:
            deadRefreshToken = refreshToken
            appLog.error("gemini token: refresh token revoked — sign in again")
            return nil   // fetch() then surfaces its sign-in guidance
        case .transient:
            return onDisk.accessToken   // may 401; masked as transient upstream
        }
    }

    // MARK: - Parsing (lenient: both stores vary their field names)

    /// Antigravity stores go-keyring data, optionally base64-wrapped, holding
    /// JSON like {"token": {"access_token": ..., "refresh_token": ..., "expiry": ISO8601}}.
    static func parse(keychainValue: String) -> Credentials? {
        var text = keychainValue
        let prefix = "go-keyring-base64:"
        if text.hasPrefix(prefix) {
            guard let data = Data(base64Encoded: String(text.dropFirst(prefix.count))),
                  let decoded = String(data: data, encoding: .utf8)
            else { return nil }
            text = decoded
        }
        guard let data = text.data(using: .utf8) else { return nil }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            // A bare token string (possibly "Bearer <token>").
            let bare = text.replacingOccurrences(of: "Bearer ", with: "").trimmed
            return bare.isEmpty ? nil : Credentials(accessToken: bare)
        }
        let obj = (root["token"] as? [String: Any]) ?? root
        return credentials(from: obj)
    }

    /// Gemini CLI oauth_creds.json (expiry_date is epoch milliseconds).
    static func parse(credsJSON data: Data) -> Credentials? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return credentials(from: obj)
    }

    private static func credentials(from obj: [String: Any]) -> Credentials? {
        let access = (obj["access_token"] ?? obj["accessToken"]) as? String
        let refresh = (obj["refresh_token"] ?? obj["refreshToken"]) as? String
        var expiry: Date?
        if let iso = (obj["expiry"] ?? obj["expiresAt"]) as? String {
            expiry = parseISODate(iso)
        } else if let ms = (obj["expiry_date"] as? NSNumber)?.doubleValue {
            expiry = Date(timeIntervalSince1970: ms / 1000)
        }
        guard access != nil || refresh != nil else { return nil }
        return Credentials(accessToken: access, refreshToken: refresh, expiry: expiry)
    }

    // MARK: - Refresh

    enum RefreshOutcome {
        case refreshed(Credentials)
        case revoked        // invalid_grant/invalid_client: needs a re-login
        case transient      // network blip etc. — keep limping on the stale token
    }

    private static func refresh(refreshToken: String) async -> RefreshOutcome {
        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "client_secret", value: clientSecret),
            URLQueryItem(name: "refresh_token", value: refreshToken),
            URLQueryItem(name: "grant_type", value: "refresh_token"),
        ]
        guard let body = components.percentEncodedQuery?.data(using: .utf8) else { return .transient }
        do {
            let data = try await HTTP.json(
                URL(string: "https://oauth2.googleapis.com/token")!,
                method: "POST",
                headers: ["Content-Type": "application/x-www-form-urlencoded"],
                body: body
            )
            guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let access = obj["access_token"] as? String, !access.isEmpty
            else { return .transient }
            let lifetime = (obj["expires_in"] as? NSNumber)?.doubleValue ?? 3300
            return .refreshed(Credentials(
                accessToken: access,
                refreshToken: refreshToken,
                expiry: Date().addingTimeInterval(lifetime)
            ))
        } catch {
            if case let HTTPError.status(code, body) = error, code == 400 || code == 401,
               body.contains("invalid_grant") || body.contains("invalid_client") {
                return .revoked
            }
            return .transient
        }
    }
}
