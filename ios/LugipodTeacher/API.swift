import Foundation
import WebKit

enum APIError: Error { case badURL, notSignedIn, server(Int, String) }

/// Calls the Lugipod backend as the signed-in teacher. The login lives in the web view's
/// cookie jar; the same cookies are replayed here, so the app never handles credentials.
enum API {
    static var baseURL: URL {
        let host = (Bundle.main.object(forInfoDictionaryKey: "LugipodBaseURL") as? String) ?? "lugipod.com"
        return URL(string: host.hasPrefix("http") ? host : "https://\(host)")!
    }

    static func post(_ path: String, json: [String: Any]) async throws -> Data {
        guard let url = URL(string: path, relativeTo: baseURL) else { throw APIError.badURL }
        let host = url.host ?? ""
        let all = await WKWebsiteDataStore.default().httpCookieStore.allCookies()
        let cookies = all.filter { c in
            let d = c.domain.trimmingCharacters(in: CharacterSet(charactersIn: "."))
            return host == d || host.hasSuffix("." + d)
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.httpShouldHandleCookies = false
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (k, v) in HTTPCookie.requestHeaderFields(with: cookies) { req.setValue(v, forHTTPHeaderField: k) }
        req.httpBody = try JSONSerialization.data(withJSONObject: json)
        let (data, resp) = try await URLSession.shared.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 { throw APIError.notSignedIn }
        guard (200..<300).contains(status) else {
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            throw APIError.server(status, obj?["error"] as? String ?? "")
        }
        return data
    }
}

private extension WKHTTPCookieStore {
    func allCookies() async -> [HTTPCookie] {
        await withCheckedContinuation { cont in getAllCookies { cont.resume(returning: $0) } }
    }
}
