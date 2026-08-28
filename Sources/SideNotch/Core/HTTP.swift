import Foundation

enum HTTPError: Error, LocalizedError {
    case status(Int, String)

    var errorDescription: String? {
        switch self {
        case let .status(code, body): "HTTP \(code): \(body.prefix(120))"
        }
    }
}

/// One-call JSON GET/POST with bearer-style headers.
enum HTTP {
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
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw HTTPError.status(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        return data
    }
}
