import Foundation

/// What the Lugipod web page (MeetingRoom.tsx) tells the app, via
/// `webkit.messageHandlers.lugipod.postMessage(...)`.
enum BridgeMessage: Equatable {
    case startCall(kind: String, ref: String)
    case endCall
    case startShare
    case stopShare

    init?(body: Any) {
        guard let dict = body as? [String: Any], let type = dict["type"] as? String else { return nil }
        switch type {
        case "startCall":
            guard let kind = dict["kind"] as? String, ["lesson", "sos"].contains(kind),
                  let ref = dict["ref"] as? String, !ref.isEmpty else { return nil }
            self = .startCall(kind: kind, ref: ref)
        case "endCall": self = .endCall
        case "startShare": self = .startShare
        case "stopShare": self = .stopShare
        default: return nil
        }
    }
}
