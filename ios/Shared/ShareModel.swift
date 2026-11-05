import Foundation
import UniformTypeIdentifiers

/// One row of "which lesson is this file for?": a group's latest lesson, as the server lists it.
struct ShareTarget: Identifiable, Decodable, Equatable {
    let lessonId: String
    let groupId: String
    let title: String
    let students: [String]
    let endedAt: Date
    let summarized: Bool
    let fileCount: Int

    var id: String { lessonId }
}

struct SharedFile: Equatable {
    let url: URL
    let name: String
    let mime: String
    let size: Int

    static func mimeType(for url: URL) -> String {
        UTType(filenameExtension: url.pathExtension.lowercased())?.preferredMIMEType ?? "application/pdf"
    }
}

/// Talks to /api/native/share/* with the scoped share token (no Supabase session in the extension).
enum ShareAPI {
    struct Failure: LocalizedError {
        let status: Int
        let message: String
        var errorDescription: String? { message.isEmpty ? "שגיאת שרת" : message }
    }

    static var baseURL: URL {
        let host = (Bundle.main.object(forInfoDictionaryKey: "LugipodBaseURL") as? String) ?? ""
        let clean = (host.isEmpty || host.hasPrefix("$(")) ? "lugipod.com" : host
        return URL(string: clean.hasPrefix("http") ? clean : "https://\(clean)")!
    }

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { dec in
            let s = try dec.singleValueContainer().decode(String.self)
            let plain = ISO8601DateFormatter()
            plain.formatOptions = [.withInternetDateTime]
            let frac = ISO8601DateFormatter()
            frac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            guard let date = plain.date(from: s) ?? frac.date(from: s) else {
                throw DecodingError.dataCorrupted(.init(codingPath: dec.codingPath, debugDescription: "bad date \(s)"))
            }
            return date
        }
        return d
    }()

    static func call(_ method: String, _ path: String, json: [String: Any]? = nil) async throws -> Data {
        guard let token = ShareBridge.token else { throw Failure(status: 401, message: "") }
        guard let url = URL(string: path, relativeTo: baseURL) else { throw Failure(status: 0, message: "תקלה פנימית") }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = 25
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let json {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: json)
        }
        let (data, resp) = try await URLSession.shared.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if (200..<300).contains(status) { return data }
        let message = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["error"] as? String ?? ""
        throw Failure(status: status, message: status == 401 ? "" : message)
    }
}

/// The state of one share: load the lessons, let the teacher pick, upload, attach.
@MainActor
final class ShareModel: ObservableObject {
    enum Phase: Equatable {
        case loading, ready, sending, done
        case needsSignIn
        case failed(String)
    }

    @Published private(set) var phase: Phase = .loading
    @Published private(set) var targets: [ShareTarget] = []
    @Published var selectedId: String?
    @Published private(set) var maxBytes = 25 * 1024 * 1024
    let file: SharedFile

    init(file: SharedFile) { self.file = file }

    /// A fixed state for screenshots and tests (no network).
    init(file: SharedFile, preview targets: [ShareTarget], phase: Phase = .ready) {
        self.file = file
        self.targets = targets
        self.selectedId = targets.first?.id
        self.phase = phase
    }

    var selected: ShareTarget? { targets.first { $0.id == selectedId } }
    var tooBig: Bool { file.size > maxBytes }

    func load() async {
        phase = .loading
        guard ShareBridge.token != nil else { phase = .needsSignIn; return }
        struct Reply: Decodable { let maxBytes: Int; let targets: [ShareTarget] }
        do {
            let data = try await ShareAPI.call("GET", "/api/native/share/targets")
            let reply = try ShareAPI.decoder.decode(Reply.self, from: data)
            targets = reply.targets
            maxBytes = reply.maxBytes
            // The lesson that finished most recently is almost always the one: one tap to send.
            selectedId = targets.first?.id
            phase = .ready
        } catch let f as ShareAPI.Failure where f.status == 401 {
            phase = .needsSignIn
        } catch {
            phase = .failed((error as? LocalizedError)?.errorDescription ?? "לא הצלחנו לטעון את השיעורים")
        }
    }

    func send() async {
        guard let target = selected, phase == .ready || isFailed else { return }
        if tooBig { phase = .failed("הקובץ גדול מדי (עד \(maxBytes / 1_048_576)MB)"); return }
        phase = .sending
        do {
            struct Upload: Decodable { let path: String; let signedUrl: String }
            let up = try ShareAPI.decoder.decode(Upload.self, from: try await ShareAPI.call("POST", "/api/native/share/upload-url", json: [
                "lessonId": target.lessonId, "fileName": file.name, "size": file.size, "mime": file.mime,
            ]))
            guard let url = URL(string: up.signedUrl) else { throw ShareAPI.Failure(status: 0, message: "תקלה פנימית") }
            var put = URLRequest(url: url)
            put.httpMethod = "PUT"
            put.timeoutInterval = 180
            put.setValue(file.mime, forHTTPHeaderField: "Content-Type")
            put.setValue("false", forHTTPHeaderField: "x-upsert")
            let (_, resp) = try await URLSession.shared.upload(for: put, fromFile: file.url)
            let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(status) else { throw ShareAPI.Failure(status: status, message: "ההעלאה נכשלה, נסו שוב") }
            _ = try await ShareAPI.call("POST", "/api/native/share/attach", json: [
                "lessonId": target.lessonId, "path": up.path, "fileName": file.name, "mime": file.mime,
            ])
            phase = .done
        } catch let f as ShareAPI.Failure where f.status == 401 {
            phase = .needsSignIn
        } catch {
            phase = .failed((error as? LocalizedError)?.errorDescription ?? "ההעלאה נכשלה, נסו שוב")
        }
    }

    func retry() { phase = .ready }

    private var isFailed: Bool {
        if case .failed = phase { return true }
        return false
    }
}

/// Plain-Hebrew wording used by the share screen (kept free of UI so it can be unit tested).
enum ShareFormat {
    /// "הרגע" / "לפני 12 דק׳" / "לפני שעה" / "לפני 3 שעות" / "לפני יומיים" / "לפני 5 ימים".
    static func ago(_ date: Date, now: Date = Date()) -> String {
        let s = max(0, now.timeIntervalSince(date))
        let minutes = Int(s / 60)
        if minutes < 2 { return "הרגע" }
        if minutes < 60 { return "לפני \(minutes) דק׳" }
        let hours = minutes / 60
        if hours == 1 { return "לפני שעה" }
        if hours < 24 { return "לפני \(hours) שעות" }
        let days = hours / 24
        if days == 1 { return "אתמול" }
        if days == 2 { return "לפני יומיים" }
        return "לפני \(days) ימים"
    }

    static func size(_ bytes: Int) -> String {
        if bytes < 1_000_000 { return "\(max(1, bytes / 1000)) KB" }
        return String(format: "%.1f MB", Double(bytes) / 1_000_000)
    }

    static func names(_ students: [String]) -> String {
        let first = students.map { $0.split(separator: " ").first.map(String.init) ?? $0 }
        return first.isEmpty ? "ללא תלמידים" : first.joined(separator: ", ")
    }
}
