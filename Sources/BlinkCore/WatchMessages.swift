import Foundation

/// Only system status and explicit commands cross WatchConnectivity. Never credentials.
public struct WatchSystem: Identifiable, Codable, Sendable, Equatable {
    public let id: Int
    public let name: String
    public let armed: Bool?
    public let status: String?
    public let cameraCount: Int
    public init(system: BlinkSystem) {
        id = system.id; name = system.name; armed = system.armed
        status = system.status; cameraCount = system.cameras.count
    }
    public var armLabel: String { armed.map { $0 ? "Armed" : "Disarmed" } ?? "Unknown" }
}
public struct WatchSnapshot: Codable, Sendable {
    public let signedIn: Bool
    public let systems: [WatchSystem]
    public let updated: Date?
    public init(signedIn: Bool, systems: [BlinkSystem], updated: Date?) {
        self.signedIn = signedIn
        self.systems = signedIn ? systems.map(WatchSystem.init) : []
        self.updated = signedIn ? updated : nil
    }
}
public enum WatchCommand: Codable, Sendable, Equatable {
    case refresh
    case setSystem(id: Int, armed: Bool)
}
public struct WatchReply: Codable, Sendable {
    public let snapshot: WatchSnapshot
    public let error: String?
    public init(snapshot: WatchSnapshot, error: String? = nil) {
        self.snapshot = snapshot; self.error = error
    }
}
