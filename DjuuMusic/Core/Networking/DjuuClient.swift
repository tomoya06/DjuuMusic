import Foundation

final class DjuuClient {
    static let shared = DjuuClient()

    static let baseURL = URL(string: "https://m.djuu.com")!

    static let mobileUserAgent =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) AppleWebKit/605.1.15 " +
        "(KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1"

    let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = [
            "User-Agent": DjuuClient.mobileUserAgent,
            "Referer": "https://m.djuu.com/",
            "X-Requested-With": "XMLHttpRequest",
        ]
        config.httpCookieAcceptPolicy = .always
        config.httpShouldSetCookies = true
        config.timeoutIntervalForRequest = 15
        return URLSession(configuration: config)
    }()

    func getHTML(path: String, query: [String: String] = [:]) async throws -> String {
        var comps = URLComponents(url: Self.baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty {
            comps.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }.sorted { $0.name < $1.name }
        }
        var request = URLRequest(url: comps.url!)
        request.setValue("text/html,application/xhtml+xml,*/*;q=0.8", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        try Self.checkHTTP(response)
        guard let text = String(data: data, encoding: .utf8) else {
            throw DjuuError.badResponse("页面编码错误")
        }
        return text
    }

    func postForm<T: Decodable>(path: String, query: [String: String] = [:],
                                fields: [String: String]) async throws -> T {
        let data = try await postFormRaw(path: path, query: query, fields: fields)
        return try JSONDecoder().decode(T.self, from: data)
    }

    func postFormRaw(path: String, query: [String: String] = [:],
                     fields: [String: String]) async throws -> Data {
        var comps = URLComponents(url: Self.baseURL.appendingPathComponent(path),
                                  resolvingAgainstBaseURL: false)!
        if !query.isEmpty {
            comps.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }.sorted { $0.name < $1.name }
        }
        var request = URLRequest(url: comps.url!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/javascript, */*; q=0.01", forHTTPHeaderField: "Accept")
        request.httpBody = Self.formEncode(fields).data(using: .utf8)
        let (data, response) = try await session.data(for: request)
        try Self.checkHTTP(response)
        return data
    }

    func download(_ url: URL) async throws -> Data {
        let (data, response) = try await session.data(from: url)
        try Self.checkHTTP(response)
        return data
    }

    static func checkHTTP(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) else { return }
        throw DjuuError.http(status: http.statusCode)
    }

    static func formEncode(_ fields: [String: String]) -> String {
        fields
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\(addingPercentEscapes($0.value))" }
            .joined(separator: "&")
    }

    private static func addingPercentEscapes(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}

enum DjuuError: LocalizedError {
    case http(status: Int)
    case badResponse(String)
    case server(code: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .http(let status): return "网络请求失败（\(status)）"
        case .badResponse(let msg): return msg
        case .server(_, let message): return message
        }
    }
}
