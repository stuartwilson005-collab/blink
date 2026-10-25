import XCTest
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import BlinkCore

private final class StubProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, String))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (code, json) = try Self.handler!(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(json.utf8))
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
final class APITests: XCTestCase {
    private func client(expired: Bool = false, persist: @escaping @Sendable (Credentials) throws -> Void = { _ in }) -> BlinkAPI {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        let credentials = Credentials(accessToken: "test-access", refreshToken: "test-refresh",
            expiresAt: Date().addingTimeInterval(expired ? -60 : 3600), hardwareID: "test-hardware")
        return BlinkAPI(credentials: credentials, session: URLSession(configuration: configuration), persist: persist)
    }
    override func tearDown() { StubProtocol.handler = nil; super.tearDown() }
    func testTierDiscoveryAndBearerAuthentication() async throws {
        StubProtocol.handler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-access")
            switch request.url!.path {
            case "/api/v1/users/tier_info": return (200, "{\"tier\":\"prde\",\"account_id\":42}")
            case "/api/v3/accounts/42/homescreen":
                XCTAssertEqual(request.url!.host, "rest-prde.immedia-semi.com")
                return (200, "{\"networks\":[{\"id\":1,\"name\":\"Home\",\"armed\":true}]}")
            default: XCTFail("Unexpected request"); return (500, "{}")
            }
        }
        let screen = try await client().homescreen()
        XCTAssertEqual(screen.systems.first?.armed, true)
    }
    func testExpiredTokenRefreshIsPersistedAndUsed() async throws {
        let persisted = expectation(description: "New token persisted")
        StubProtocol.handler = { request in
            if request.url!.path == "/oauth/token" {
                XCTAssertEqual(request.httpMethod, "POST")
                return (200, "{\"access_token\":\"new-token\",\"refresh_token\":\"rotated\",\"expires_in\":3600}")
            }
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer new-token")
            if request.url!.path.contains("tier_info") { return (200, "{\"tier\":\"prod\",\"account_id\":42}") }
            return (200, "{\"networks\":[]}")
        }
        _ = try await client(expired: true, persist: { credentials in
            XCTAssertEqual(credentials.refreshToken, "rotated"); persisted.fulfill()
        }).homescreen()
        await fulfillment(of: [persisted], timeout: 2)
    }
    func testUnauthorizedIsReportedAsSignInRequired() async throws {
        StubProtocol.handler = { _ in (401, "{}") }
        do { _ = try await client().homescreen(); XCTFail("Expected failure") }
        catch BlinkError.signedOut { }
    }
    func testCommandPollAndFinalStateConfirmation() async throws {
        var armed = false
        StubProtocol.handler = { request in
            switch request.url!.path {
            case "/api/v1/users/tier_info": return (200, "{\"tier\":\"prod\",\"account_id\":42}")
            case "/api/v3/accounts/42/homescreen":
                return (200, "{\"networks\":[{\"id\":1,\"name\":\"Home\",\"armed\":\(armed)}]}")
            case "/api/v1/accounts/42/networks/1/state/arm":
                XCTAssertEqual(request.httpMethod, "POST")
                return (200, "{\"id\":7,\"network_id\":1}")
            case "/network/1/command/7": armed = true; return (200, "{\"complete\":true,\"status_code\":908}")
            default: XCTFail("Unexpected route"); return (500, "{}")
            }
        }
        let api = client()
        let screen = try await api.homescreen()
        let updated = try await api.setSystem(screen.systems[0], armed: true)
        XCTAssertEqual(updated.systems[0].armed, true)
    }
    func testRejectedCommandDoesNotReportSuccess() async throws {
        StubProtocol.handler = { request in
            if request.url!.path.contains("tier_info") { return (200, "{\"tier\":\"prod\",\"account_id\":42}") }
            if request.httpMethod == "POST" { return (200, "{\"id\":7}") }
            if request.url!.path.contains("command") { return (200, "{\"complete\":true,\"status_code\":999}") }
            return (200, "{\"networks\":[{\"id\":1,\"name\":\"Home\",\"armed\":false}]}")
        }
        let api = client()
        let screen = try await api.homescreen()
        do { _ = try await api.setSystem(screen.systems[0], armed: true); XCTFail("Expected command failure") }
        catch BlinkError.commandFailed { }
    }
}
