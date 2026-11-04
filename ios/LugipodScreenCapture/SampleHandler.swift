import DailySystemBroadcast

/// Broadcast Upload Extension: iOS runs this in its own process while the system
/// screen recording is on, and Daily's handler forwards the frames to the app's call.
public class SampleHandler: DailyBroadcastSampleHandler {
    override init() {
        super.init(appGroupIdentifier: "group.com.itaybraha.lugipod")
    }
}
