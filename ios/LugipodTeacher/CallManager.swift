import Daily
import Foundation
import UIKit

/// The teacher's native call client. It joins the lesson room as a second participant
/// ("<name> · iPad") carrying the teacher's voice (kept alive in the background, so
/// Notability can be in front) and the system screen share. The web page stays the
/// control surface: heartbeat, files, end/leave. This object also keeps the lesson's
/// presence heartbeat going, because a backgrounded web view stops running timers.
final class CallManager: NSObject, ObservableObject {
    enum Phase: Equatable { case idle, joining, live, failed(String) }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var micOn = true
    @Published private(set) var sharing = false

    /// Pushed to the web page so its share button mirrors the real state.
    var onEvent: (([String: Any]) -> Void)?

    private var client: CallClient?
    private var session: (kind: String, ref: String)?
    private var heartbeat: Task<Void, Never>?

    // MARK: - Lifecycle

    @MainActor
    func start(kind: String, ref: String) async {
        guard phase == .idle || isFailed else { return }
        phase = .joining
        session = (kind, ref)
        do {
            let data = try await API.post("/api/meeting/native-join", json: ["kind": kind, "ref": ref])
            guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let urlStr = obj["roomUrl"] as? String, let url = URL(string: urlStr),
                  let token = obj["token"] as? String else { throw APIError.badURL }

            let call = CallClient()
            call.delegate = self
            client = call
            call.setInputsEnabled([.camera: false, .microphone: true], completion: nil)
            micOn = true
            call.join(url: url, token: MeetingToken(stringValue: token)) { [weak self] result in
                DispatchQueue.main.async {
                    switch result {
                    case .success:
                        self?.phase = .live
                        self?.startHeartbeat()
                    case .failure(let e):
                        self?.fail("לא הצלחנו להתחבר לשיחה (\(e))")
                    }
                }
            }
        } catch {
            fail("לא הצלחנו לפתוח את השיחה")
        }
    }

    @MainActor
    func stop() {
        heartbeat?.cancel()
        heartbeat = nil
        client?.leave(completion: nil)
        client = nil
        session = nil
        micOn = true
        setSharing(false)
        phase = .idle
    }

    @MainActor
    func setMic(_ on: Bool) {
        micOn = on
        client?.setInputEnabled(.microphone, on, completion: nil)
    }

    /// iOS offers no API to end a system broadcast from the app; this stops sending it.
    @MainActor
    func stopShare() {
        client?.updateInputs(.set(screenVideo: .set(isEnabled: .set(false))), completion: nil)
        setSharing(false)
    }

    private var isFailed: Bool {
        if case .failed = phase { return true }
        return false
    }

    @MainActor
    private func fail(_ message: String) {
        client?.leave(completion: nil)
        client = nil
        heartbeat?.cancel()
        heartbeat = nil
        phase = .failed(message)
        onEvent?(["error": message])
    }

    @MainActor
    private func setSharing(_ on: Bool) {
        guard sharing != on else { return }
        sharing = on
        onEvent?(["sharing": on])
    }

    // MARK: - Presence

    @MainActor
    private func startHeartbeat() {
        guard let session else { return }
        heartbeat?.cancel()
        heartbeat = Task {
            while !Task.isCancelled {
                _ = try? await API.post("/api/meeting/state",
                                        json: ["kind": session.kind, "ref": session.ref, "intent": "heartbeat"])
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
    }
}

extension CallManager: CallClientDelegate {
    func callClientDidDetectStartOfSystemBroadcast(_ callClient: CallClient) {
        callClient.updateInputs(.set(screenVideo: .set(isEnabled: .set(true))), completion: nil)
        DispatchQueue.main.async { self.setSharing(true) }
    }

    func callClientDidDetectEndOfSystemBroadcast(_ callClient: CallClient) {
        callClient.updateInputs(.set(screenVideo: .set(isEnabled: .set(false))), completion: nil)
        DispatchQueue.main.async { self.setSharing(false) }
    }
}
