import XCTest
@testable import BlinkCore

final class ModelsTests: XCTestCase {
    private func screen(_ json: String) throws -> Homescreen { try Homescreen(data: Data(json.utf8)) }
    func testGroupsEveryCameraFamilyUnderItsSystem() throws {
        let screen = try screen("""
        {"networks":[{"id":2,"name":"Office","armed":false},{"id":1,"name":"Home","armed":true}],
         "cameras":[{"id":10,"network_id":1,"name":"Garden","enabled":true,"status":"offline","battery":"low"}],
         "owls":[{"id":10,"network_id":2,"name":"Desk","enabled":false,"status":"online"}],
         "doorbells":[{"id":10,"network_id":1,"name":"Door","enabled":true,"status":"online"}]}
        """)
        XCTAssertEqual(screen.systems.map(\.name), ["Home", "Office"])
        XCTAssertEqual(screen.systems[0].cameras.map(\.name), ["Door", "Garden"])
        XCTAssertEqual(Set(screen.systems.flatMap(\.cameras).map(\.identity)).count, 3)
        XCTAssertEqual(screen.systems[0].cameras[1].connectivity, "Offline")
        XCTAssertEqual(screen.systems[0].cameras[1].battery, "low")
        XCTAssertEqual(screen.systems.map(\.armLabel), ["Armed", "Disarmed"])
    }
    func testMissingStatusIsUnknownAndEmptySystemsRemainVisible() throws {
        let screen = try screen("""
        {"networks":[{"id":1,"name":"Empty"},{"id":2,"name":"Home"}],
         "cameras":[{"id":3,"network_id":2,"name":"Garden"}]}
        """)
        XCTAssertTrue(screen.systems[0].cameras.isEmpty)
        XCTAssertEqual(screen.systems[1].armLabel, "Unknown")
        XCTAssertNil(screen.systems[1].cameras[0].enabled)
        XCTAssertEqual(screen.systems[1].cameras[0].connectivity, "Unknown")
    }
    func testOrphanDevicesAreNotSilentlyDropped() throws {
        let screen = try screen("""
        {"networks":[],"owls":[{"id":1,"network_id":99,"name":"Mini"}]}
        """)
        XCTAssertEqual(screen.systems[0].id, 99)
        XCTAssertEqual(screen.systems[0].cameras.count, 1)
        XCTAssertNil(screen.systems[0].armed)
    }
    func testMalformedResponseFailsRatherThanShowingEverythingDisarmed() {
        XCTAssertThrowsError(try screen("{}"))
    }
    func testCameraRoutesAndPayloads() throws {
        for kind in [CameraKind.camera, .mini, .doorbell] {
            let camera = Camera(id: 4, networkID: 2, name: "Test", kind: kind, enabled: true, status: nil, battery: nil)
            for enabled in [true, false] {
                let route = BlinkRoute.camera(camera, account: 8, enabled: enabled)
                switch kind {
                case .camera: XCTAssertEqual(route.path, "/network/2/camera/4/\(enabled ? "enable" : "disable")")
                case .mini:
                    XCTAssertEqual(route.path, "/api/v1/accounts/8/networks/2/owls/4/config")
                    let body = try XCTUnwrap(route.body)
                    XCTAssertEqual(try JSONSerialization.jsonObject(with: body) as? [String: Bool], ["enabled": enabled])
                case .doorbell: XCTAssertEqual(route.path, "/api/v1/accounts/8/networks/2/doorbells/4/\(enabled ? "enable" : "disable")")
                }
                if kind != .mini { XCTAssertNil(route.body) }
            }
        }
    }
    func testSystemRoutes() {
        XCTAssertEqual(BlinkRoute.system(2, account: 8, armed: true), "/api/v1/accounts/8/networks/2/state/arm")
        XCTAssertEqual(BlinkRoute.system(2, account: 8, armed: false), "/api/v1/accounts/8/networks/2/state/disarm")
    }
    func testFormEncodingProtectsTokenCharacters() {
        let encoded = String(decoding: BlinkAPI.form(["token": "a+b&c=d", "scope": "client"]), as: UTF8.self)
        XCTAssertTrue(encoded.contains("a%2Bb%26c%3Dd"))
    }
}
