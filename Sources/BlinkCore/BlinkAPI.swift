import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct Credentials: Codable, Sendable {
    public var accessToken: String
    public var refreshToken: String
    public var expiresAt: Date
    public var hardwareID: String
    public init(accessToken: String, refreshToken: String, expiresAt: Date, hardwareID: String) {
        self.accessToken = accessToken; self.refreshToken = refreshToken
        self.expiresAt = expiresAt; self.hardwareID = hardwareID
    }
}
public actor BlinkAPI {
    private var credentials: Credentials
    private let session: URLSession
    private let persist: @Sendable (Credentials) throws -> Void
    private var account: Int?
    private var base: URL?
    public init(credentials: Credentials, session: URLSession = .shared, persist: @escaping @Sendable (Credentials) throws -> Void) {
        self.credentials = credentials; self.session = session; self.persist = persist
    }
    public static func form(_ fields: [String: String]) -> Data {
        var components = URLComponents()
        components.queryItems = fields.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        // '+' must be escaped for form decoding.
        return Data((components.percentEncodedQuery ?? "").replacingOccurrences(of: "+", with: "%2B").utf8)
    }
    public static func token(fields: [String: String], hardwareID: String, session: URLSession = .shared) async throws -> Credentials {
        var request = URLRequest(url: URL(string: "https://api.oauth.blink.com/oauth/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("Blink/2511191620 CFNetwork/3860.200.71 Darwin/25.1.0", forHTTPHeaderField: "User-Agent")
        request.httpBody = form(fields.merging(["client_id": "ios", "hardware_id": hardwareID, "scope": "client"]) { a, _ in a })
        let (data, response) = try await session.data(for: request)
        try validate(response)
        struct Token: Decodable { let access_token: String; let refresh_token: String; let expires_in: Double }
        let token = try JSONDecoder().decode(Token.self, from: data)
        return Credentials(accessToken: token.access_token, refreshToken: token.refresh_token,
            expiresAt: Date().addingTimeInterval(token.expires_in), hardwareID: hardwareID)
    }
    private static func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw BlinkError.invalidResponse }
        if http.statusCode == 401 { throw BlinkError.signedOut }
        guard (200..<300).contains(http.statusCode) else { throw BlinkError.http(http.statusCode) }
    }
    private func request(_ url: URL, method: String = "GET", body: Data? = nil) async throws -> Data {
        if credentials.expiresAt.timeIntervalSinceNow < 60 {
            credentials = try await Self.token(fields: ["grant_type": "refresh_token", "refresh_token": credentials.refreshToken], hardwareID: credentials.hardwareID, session: session)
            try persist(credentials)
        }
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = method; request.httpBody = body
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await session.data(for: request)
        try Self.validate(response)
        return data
    }
    private func configure() async throws -> (URL, Int) {
        if let base, let account { return (base, account) }
        let data = try await request(URL(string: "https://rest-prod.immedia-semi.com/api/v1/users/tier_info")!)
        struct Tier: Decodable { let tier: String; let account_id: Int }
        let tier = try JSONDecoder().decode(Tier.self, from: data)
        guard !tier.tier.isEmpty, tier.tier.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }),
              let url = URL(string: "https://rest-\(tier.tier).immedia-semi.com") else { throw BlinkError.invalidResponse }
        self.base = url; self.account = tier.account_id
        return (url, tier.account_id)
    }
    public func homescreen() async throws -> Homescreen {
        let (base, account) = try await configure()
        return try Homescreen(data: await request(base.appendingPathComponent("api/v3/accounts/\(account)/homescreen")))
    }
    private func command(_ path: String, body: Data?, network: Int) async throws {
        let (base, _) = try await configure()
        let data = try await request(base.appendingPathComponent(path), method: "POST", body: body)
        struct Command: Decodable { let id: Int?; let complete: Bool?; let status_code: Int? }
        let command = try JSONDecoder().decode(Command.self, from: data)
        if let id = command.id {
            for _ in 0..<30 {
                try await Task.sleep(nanoseconds: 1_000_000_000)
                let result = try await request(base.appendingPathComponent("network/\(network)/command/\(id)"))
                let state = try JSONDecoder().decode(Command.self, from: result)
                if let code = state.status_code, code != 908 { throw BlinkError.commandFailed }
                if state.complete == true { return }
            }
            throw BlinkError.timedOut
        }
        // Some config endpoints return no command ID. The caller must verify homescreen state.
    }
    public func setCamera(_ camera: Camera, enabled: Bool) async throws -> Homescreen {
        let (_, account) = try await configure()
        let route = BlinkRoute.camera(camera, account: account, enabled: enabled)
        try await command(route.path, body: route.body, network: camera.networkID)
        return try await confirmed { $0.systems.flatMap(\.cameras).first { $0.identity == camera.identity }?.enabled == enabled }
    }
    public func setSystem(_ system: BlinkSystem, armed: Bool) async throws -> Homescreen {
        let (_, account) = try await configure()
        try await command(BlinkRoute.system(system.id, account: account, armed: armed), body: nil, network: system.id)
        return try await confirmed { $0.systems.first { $0.id == system.id }?.armed == armed }
    }
    private func confirmed(_ matches: (Homescreen) -> Bool) async throws -> Homescreen {
        for _ in 0..<5 {
            let screen = try await homescreen()
            if matches(screen) { return screen }
            try await Task.sleep(nanoseconds: 2_000_000_000)
        }
        throw BlinkError.notConfirmed
    }
}
