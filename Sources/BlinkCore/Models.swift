import Foundation

public enum CameraKind: String, Codable, Sendable { case camera, mini, doorbell }
public struct Camera: Identifiable, Codable, Sendable, Equatable {
    public let id: Int
    public let networkID: Int
    public let name: String
    public let kind: CameraKind
    public let enabled: Bool?
    public let status: String?
    public let battery: String?
    public var identity: String { "\(kind.rawValue):\(networkID):\(id)" }
    public var connectivity: String { status?.capitalized ?? "Unknown" }
}
public struct BlinkSystem: Identifiable, Codable, Sendable, Equatable {
    public let id: Int
    public let name: String
    public let armed: Bool?
    public let status: String?
    public let cameras: [Camera]
    public var armLabel: String { armed.map { $0 ? "Armed" : "Disarmed" } ?? "Unknown" }
    public var connectivity: String { status?.capitalized ?? "Unknown" }
}
public struct Homescreen: Sendable {
    public let systems: [BlinkSystem]
    public init(data: Data) throws {
        let raw = try JSONDecoder().decode(RawHomescreen.self, from: data)
        let cameras = (raw.cameras ?? []).map { $0.camera(.camera) }
            + (raw.owls ?? []).map { $0.camera(.mini) }
            + (raw.doorbells ?? []).map { $0.camera(.doorbell) }
        var systems = raw.networks.map { network in
            BlinkSystem(id: network.id, name: network.name, armed: network.armed,
                status: network.status ?? raw.sync_modules?.first(where: { $0.network_id == network.id })?.status, cameras: cameras.filter { $0.networkID == network.id }.sorted { $0.name < $1.name })
        }
        // Preserve devices even if Blink omits their network metadata.
        for id in Set(cameras.map(\.networkID)).subtracting(Set(raw.networks.map(\.id))) {
            systems.append(BlinkSystem(id: id, name: "System \(id)", armed: nil, status: nil,
                cameras: cameras.filter { $0.networkID == id }.sorted { $0.name < $1.name }))
        }
        self.systems = systems.sorted { $0.name < $1.name }
    }
}
private struct RawHomescreen: Decodable {
    let networks: [Network]
    let cameras: [Device]?
    let owls: [Device]?
    let doorbells: [Device]?
    let sync_modules: [SyncModule]?
    struct SyncModule: Decodable { let network_id: Int; let status: String? }
    struct Network: Decodable { let id: Int; let name: String; let armed: Bool?; let status: String? }
    struct Device: Decodable {
        let id: Int; let network_id: Int; let name: String
        let enabled: Bool?; let status: String?; let battery: String?
        func camera(_ kind: CameraKind) -> Camera {
            Camera(id: id, networkID: network_id, name: name, kind: kind, enabled: enabled, status: status, battery: battery)
        }
    }
}
public enum BlinkRoute {
    public static func camera(_ camera: Camera, account: Int, enabled: Bool) -> (path: String, body: Data?) {
        let action = enabled ? "enable" : "disable"
        switch camera.kind {
        case .camera: return ("/network/\(camera.networkID)/camera/\(camera.id)/\(action)", nil)
        case .doorbell: return ("/api/v1/accounts/\(account)/networks/\(camera.networkID)/doorbells/\(camera.id)/\(action)", nil)
        case .mini: return ("/api/v1/accounts/\(account)/networks/\(camera.networkID)/owls/\(camera.id)/config", Data("{\"enabled\":\(enabled)}".utf8))
        }
    }
    public static func system(_ id: Int, account: Int, armed: Bool) -> String {
        "/api/v1/accounts/\(account)/networks/\(id)/state/\(armed ? "arm" : "disarm")"
    }
}
public enum BlinkError: LocalizedError {
    case signedOut, invalidResponse, http(Int), commandFailed, timedOut, notConfirmed
    public var errorDescription: String? {
        switch self {
        case .signedOut: return "Open Blink Control and sign in again."
        case .invalidResponse: return "Blink returned an unexpected response."
        case .http(let code): return "Blink request failed (HTTP \(code)). Try again later."
        case .commandFailed: return "Blink could not complete the command. Refresh to check its status."
        case .timedOut: return "Blink took too long. Refresh before trying the command again."
        case .notConfirmed: return "The requested state was not confirmed by Blink. Refresh to check the current status."
        }
    }
}
