import SwiftUI
import WebKit

/// A Lugipod website page inside the app, for the screens that are not native yet (the lesson room,
/// SOS, vault, ...). The user agent tells the page it is in the app, so the lesson room hands the
/// voice and the screen share to the native client.
struct WebShell: UIViewRepresentable {
    let call: CallManager
    let request: URLRequest

    func makeCoordinator() -> Coordinator { Coordinator(call: call) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.applicationNameForUserAgent = "LugipodTeacherApp/1"
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.userContentController.add(WeakHandler(context.coordinator), name: "lugipod")
        // The native client plays the room's audio (it keeps working in the background).
        // The page's own copy is silenced so students are not heard twice.
        config.userContentController.addUserScript(WKUserScript(
            source: Self.silencePageAudio, injectionTime: .atDocumentEnd, forMainFrameOnly: false))

        let web = WKWebView(frame: .zero, configuration: config)
        web.allowsBackForwardNavigationGestures = true
        web.uiDelegate = context.coordinator
        web.isInspectable = true
        context.coordinator.web = web
        web.load(request)
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {}

    /// Mutes audio and video elements, only inside the Daily frame.
    static let silencePageAudio = """
    (function () {
      if (!/daily\\.co$/.test(location.hostname)) return;
      setInterval(function () {
        document.querySelectorAll('audio,video').forEach(function (m) { m.muted = true; });
      }, 700);
    })();
    """

    final class Coordinator: NSObject, WKScriptMessageHandler, WKUIDelegate {
        let call: CallManager
        weak var web: WKWebView?
        private let share = ShareLauncher()

        init(call: CallManager) {
            self.call = call
            super.init()
            call.onEvent = { [weak self] detail in self?.dispatch(detail) }
        }

        func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let msg = BridgeMessage(body: message.body) else { return }
            Task { @MainActor in
                switch msg {
                case .startCall(let kind, let ref): await call.start(kind: kind, ref: ref)
                case .endCall: call.stop()
                case .startShare: if let web { share.present(in: web) }
                case .stopShare: call.stopShare()
                }
            }
        }

        // Camera/microphone prompts for pages inside the app: the site is ours, say yes.
        func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                     initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
                     decisionHandler: @escaping (WKPermissionDecision) -> Void) {
            decisionHandler(.grant)
        }

        private func dispatch(_ detail: [String: Any]) {
            guard let data = try? JSONSerialization.data(withJSONObject: detail),
                  let json = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async {
                self.web?.evaluateJavaScript(
                    "window.dispatchEvent(new CustomEvent('lugipod-native',{detail:\(json)}))")
            }
        }
    }

    /// WKUserContentController retains its handlers; this breaks the cycle.
    private final class WeakHandler: NSObject, WKScriptMessageHandler {
        weak var target: WKScriptMessageHandler?
        init(_ target: WKScriptMessageHandler) { self.target = target }
        func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
            target?.userContentController(ucc, didReceive: message)
        }
    }
}

/// Builds the request that signs the web view in with the native session, then lands on `path`.
enum WebLogin {
    static func request(next path: String) async throws -> URLRequest {
        let tokens = try await AuthStore.shared.sessionTokens()
        var req = URLRequest(url: API.baseURL.appendingPathComponent("api/native/web-login"))
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = formBody(["access_token": tokens.access, "refresh_token": tokens.refresh, "next": path])
        return req
    }

    static func formBody(_ fields: [String: String]) -> Data {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let pairs = fields.map { k, v in
            "\(k)=\(v.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")"
        }
        return pairs.sorted().joined(separator: "&").data(using: .utf8) ?? Data()
    }
}
