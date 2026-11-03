import Foundation

/// APIError is a non-success REST response the caller can branch on.
public enum APIError: Error, Equatable {
    case nonHTTPResponse
    case status(code: Int, body: String)
}

/// HTTPClient talks to a daemon over its REST plane. It is a value type with no
/// mutable state, so it is freely shared across tasks. A `bearerToken`, when present,
/// rides on the Authorization header of every request, including the raw request a
/// caller hands to a loader that cannot decorate itself.
public struct HTTPClient: Sendable {
    public let baseURL: URL
    public let bearerToken: String?
    private let urlSession: URLSession

    public init(baseURL: URL, bearerToken: String? = nil, urlSession: URLSession = .shared) {
        self.baseURL = baseURL
        self.bearerToken = bearerToken
        self.urlSession = urlSession
    }

    public func request(_ path: String, query: [URLQueryItem] = [], method: String = "GET") -> URLRequest {
        var url = baseURL.appending(path: path)
        if !query.isEmpty {
            url = url.appending(queryItems: query)
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        if let bearerToken {
            request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    public func get<T: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> T {
        try await send(request(path, query: query))
    }

    public func post<T: Decodable>(_ path: String, json body: some Encodable) async throws -> T {
        var request = request(path, method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        return try await send(request)
    }

    /// sessions GETs /api/sessions, the daemon's roster of live artifacts.
    public func sessions() async throws -> [SessionSummary] {
        try await get("api/sessions")
    }

    private func send<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.nonHTTPResponse
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            throw APIError.status(code: http.statusCode, body: String(decoding: data, as: UTF8.self))
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}
