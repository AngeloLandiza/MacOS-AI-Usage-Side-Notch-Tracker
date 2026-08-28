import Foundation

enum HTTPError: Error, LocalizedError {
    case status(Int, String)
    case noResponse

    var errorDescription: String? {
        switch self {
        case let .status(code, body): "HTTP \(code): \(body.prefix(120))"
        case .noResponse:
            "No response from the network. If this keeps happening, allow "
                + "SideNotch under System Settings → Privacy & Security → Network."
        }
    }
}

/// One-call JSON request with bearer-style headers. Uses its own session with
/// a hard resource timeout: macOS's per-app network permission can silently
/// hold requests forever, and the UI needs a real error instead.
enum HTTP {
    static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    static func json(
        _ url: URL,
        method: String = "GET",
        headers: [String: String] = [:],
        body: Data? = nil
    ) async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = method
        request.httpBody = body
        for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
        do {
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw HTTPError.status(http.statusCode, String(data: data, encoding: .utf8) ?? "")
            }
            return data
        } catch let error as URLError where error.code == .timedOut || error.code == .cannotConnectToHost {
            throw HTTPError.noResponse
        }
    }
}
