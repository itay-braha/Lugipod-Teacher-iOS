import XCTest
@testable import LugipodTeacher

final class BridgeMessageTests: XCTestCase {
    func testStartCall() {
        let m = BridgeMessage(body: ["type": "startCall", "kind": "lesson", "ref": "abc"])
        XCTAssertEqual(m, .startCall(kind: "lesson", ref: "abc"))
    }

    func testRejectsUnknownKindAndMissingRef() {
        XCTAssertNil(BridgeMessage(body: ["type": "startCall", "kind": "hack", "ref": "abc"]))
        XCTAssertNil(BridgeMessage(body: ["type": "startCall", "kind": "sos", "ref": ""]))
        XCTAssertNil(BridgeMessage(body: ["type": "nope"]))
        XCTAssertNil(BridgeMessage(body: "string"))
    }

    func testSimpleMessages() {
        XCTAssertEqual(BridgeMessage(body: ["type": "endCall"]), .endCall)
        XCTAssertEqual(BridgeMessage(body: ["type": "startShare"]), .startShare)
        XCTAssertEqual(BridgeMessage(body: ["type": "stopShare"]), .stopShare)
    }

    func testBaseURLIsHttps() {
        XCTAssertEqual(API.baseURL.scheme, "https")
        XCTAssertFalse(API.baseURL.host?.isEmpty ?? true)
    }
}
