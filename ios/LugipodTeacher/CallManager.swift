import Daily
import Foundation
import UIKit

/// How the screen is encoded for the students. `fast` asks for the iPad's hardware H.264 encoder
/// with one full-resolution 30 fps layer, to keep drawing in Notability close to real time;
/// `standard` leaves Daily's defaults alone so the two can be compared in a real lesson.
enum ShareMode: String, CaseIterable {
    case fast, standard

    static let storageKey = "shareMode"

    static var current: ShareMode {
        ShareMode(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .fast
    }

    var title: String {
        switch self {
        case .fast: return "מהיר (H.264)"
        case .standard: return "רגיל (ברירת מחדל)"
        }
    }

    var codecName: String { self == .fast ? "h264" : "default" }
}

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
    /// A one-line readout of what the iPad is uploading while sharing, e.g. "↑ 1.8 Mbps · אובדן 0.2%".
    @Published private(set) var shareStats: String?

    /// Pushed to the web page so its share button mirrors the real state.
    var onEvent: (([String: Any]) -> Void)?

    private var client: CallClient?
    private var session: (kind: String, ref: String)?
    private var heartbeat: Task<Void, Never>?
    private var activeShareMode: ShareMode = .standard
    private var lastTelemetry = Date.distantPast

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
        if !on { shareStats = nil }
        onEvent?(["sharing": on])
    }

    // MARK: - Screen share quality

    /// Applies the chosen encoding to the screen share, then starts publishing it. If Daily refuses the
    /// settings the share still starts on its defaults: a working share beats a tuned one.
    @MainActor
    private func startPublishingScreen(_ callClient: CallClient) {
        let mode = ShareMode.current
        activeShareMode = mode
        let publish = {
            callClient.updateInputs(.set(screenVideo: .set(isEnabled: .set(true))), completion: nil)
        }
        guard mode == .fast else { publish(); return }

        let layer = VideoEncodingSettingsConfigUpdate(
            maxBitrate: .set(3_000_000), maxFramerate: .set(30), scaleResolutionDownBy: .set(1))
        let send = VideoSendSettingsUpdate(
            maxQuality: .set(.low),
            encodings: .set(.config(VideoEncodingSettingsByQualityUpdate(low: .set(layer)))),
            preferredCodec: .set(.h264),
            allowAdaptiveLayers: .set(false))
        let screen = ScreenVideoPublishingSettingsUpdate(sendSettings: .set(send))
        callClient.updatePublishing(.set(PublishingSettingsUpdate(screenVideo: .set(screen)))) { _ in
            DispatchQueue.main.async { publish() }
        }
    }

    @MainActor
    private func record(_ stats: NetworkStats) {
        guard sharing else { return }
        let latest = stats.stats.latest
        let videoKbps = (latest.videoSendBitsPerSecond ?? 0) / 1000
        let loss = latest.videoSendPacketLoss ?? 0
        shareStats = String(format: "↑ %.1f Mbps · אובדן %.1f%%", videoKbps / 1000, loss)

        guard Date().timeIntervalSince(lastTelemetry) >= 10 else { return }
        lastTelemetry = Date()
        var body: [String: Any] = [
            "codec": activeShareMode.codecName,
            "videoSendKbps": videoKbps,
            "videoLossPct": loss,
            "quality": stats.quality,
            "threshold": stats.threshold.rawValue,
            "device": "\(UIDevice.current.model) iOS \(UIDevice.current.systemVersion)",
        ]
        if let total = latest.sendBitsPerSecond { body["sendKbps"] = total / 1000 }
        if let ref = session?.ref { body["ref"] = ref }
        Task { _ = try? await API.post("/api/native/telemetry", json: body) }
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
        Task { @MainActor in
            self.startPublishingScreen(callClient)
            self.setSharing(true)
        }
    }

    func callClient(_ callClient: CallClient, networkStatsUpdated networkStats: NetworkStats) {
        Task { @MainActor in self.record(networkStats) }
    }

    func callClientDidDetectEndOfSystemBroadcast(_ callClient: CallClient) {
        Task { @MainActor in
            callClient.updateInputs(.set(screenVideo: .set(isEnabled: .set(false))), completion: nil)
            self.setSharing(false)
        }
    }
}
