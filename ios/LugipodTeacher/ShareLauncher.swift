import ReplayKit
import UIKit

/// Opens iOS's system broadcast sheet for our extension. Apple has no direct "start
/// recording" call; the picker's own button is the supported entry point, so we keep
/// one nearly invisible and press it.
final class ShareLauncher {
    static let extensionID = "com.itaybraha.lugipod.teacher.screen"

    private lazy var picker: RPSystemBroadcastPickerView = {
        let p = RPSystemBroadcastPickerView(frame: CGRect(x: 0, y: 0, width: 44, height: 44))
        p.preferredExtension = Self.extensionID
        p.showsMicrophoneButton = false
        return p
    }()

    func present(in host: UIView) {
        if picker.superview !== host {
            picker.alpha = 0.02
            host.addSubview(picker)
        }
        for case let button as UIButton in picker.subviews {
            button.sendActions(for: .touchUpInside)
        }
    }
}
