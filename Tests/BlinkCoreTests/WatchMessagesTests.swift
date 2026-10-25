import XCTest
@testable import BlinkCore

final class WatchMessagesTests: XCTestCase {
    func testWatchCommandsPreserveExplicitStateAndIdentity() throws {
        for command in [WatchCommand.refresh, .setSystem(id: 42, armed: true), .setSystem(id: 42, armed: false)] {
            let data = try JSONEncoder().encode(command)
            XCTAssertEqual(try JSONDecoder().decode(WatchCommand.self, from: data), command)
        }
    }
    func testUnknownCommandsAreRejectedRatherThanChangingAState() {
        XCTAssertThrowsError(try JSONDecoder().decode(WatchCommand.self, from: Data("{\"toggle\":{\"id\":42}}".utf8)))
        XCTAssertThrowsError(try JSONDecoder().decode(WatchCommand.self, from: Data("{\"setSystem\":{\"id\":42}}".utf8)))
    }
    func testSnapshotKeepsUnknownAndDisarmedDistinctAndExcludesCameras() throws {
        let screen = try Homescreen(data: Data("""
        {"networks":[{"id":1,"name":"Home","armed":false},{"id":2,"name":"Office"}],
        "cameras":[{"id":3,"network_id":1,"name":"Private camera name","enabled":true}]}
        """.utf8))
        let date = Date(timeIntervalSince1970: 1000)
        let snapshot = WatchSnapshot(signedIn: true, systems: screen.systems, updated: date)
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(WatchSnapshot.self, from: data)
        XCTAssertEqual(decoded.systems.map(\.armLabel), ["Disarmed", "Unknown"])
        XCTAssertEqual(decoded.systems[0].cameraCount, 1)
        XCTAssertEqual(decoded.updated, date)
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(text.contains("Private camera name"))
        let keys = Set(try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any]).keys)
        XCTAssertEqual(keys, ["signedIn", "systems", "updated"])
    }
    func testSignOutClearsStatusAndTimestamp() throws {
        let screen = try Homescreen(data: Data("{\"networks\":[{\"id\":1,\"name\":\"Home\",\"armed\":true}]}".utf8))
        let snapshot = WatchSnapshot(signedIn: false, systems: screen.systems, updated: Date())
        XCTAssertFalse(snapshot.signedIn)
        XCTAssertTrue(snapshot.systems.isEmpty)
        XCTAssertNil(snapshot.updated)
    }
    func testFailureReplyPreservesLastKnownStatusAndError() throws {
        let snapshot = WatchSnapshot(signedIn: true, systems: [], updated: Date(timeIntervalSince1970: 100))
        let reply = WatchReply(snapshot: snapshot, error: "Could not confirm command")
        let decoded = try JSONDecoder().decode(WatchReply.self, from: JSONEncoder().encode(reply))
        XCTAssertEqual(decoded.error, reply.error)
        XCTAssertEqual(decoded.snapshot.updated, snapshot.updated)
    }
}
