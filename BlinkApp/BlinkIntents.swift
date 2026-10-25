import AppIntents
import BlinkCore

struct CameraEntity: AppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Blink camera")
    static var defaultQuery = CameraQuery()
    let id: String
    let name: String
    let system: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)", subtitle: "\(system)") }
}
struct CameraQuery: EntityStringQuery {
    func suggestedEntities() async throws -> [CameraEntity] {
        let screen = try await SessionStore.client().homescreen()
        return screen.systems.flatMap { system in
            system.cameras.map { CameraEntity(id: $0.identity, name: $0.name, system: system.name) }
        }
    }
    func entities(for identifiers: [String]) async throws -> [CameraEntity] {
        try await suggestedEntities().filter { identifiers.contains($0.id) }
    }
    func entities(matching string: String) async throws -> [CameraEntity] {
        try await suggestedEntities().filter { "\($0.system) \($0.name)".localizedCaseInsensitiveContains(string) }
    }
}
struct SystemEntity: AppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Blink system")
    static var defaultQuery = SystemQuery()
    let id: Int
    let name: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}
struct SystemQuery: EntityStringQuery {
    func suggestedEntities() async throws -> [SystemEntity] {
        try await SessionStore.client().homescreen().systems.map { SystemEntity(id: $0.id, name: $0.name) }
    }
    func entities(for identifiers: [Int]) async throws -> [SystemEntity] {
        try await suggestedEntities().filter { identifiers.contains($0.id) }
    }
    func entities(matching string: String) async throws -> [SystemEntity] {
        try await suggestedEntities().filter { $0.name.localizedCaseInsensitiveContains(string) }
    }
}
struct SetCameraMotionIntent: AppIntent {
    static var title: LocalizedStringResource = "Set Camera Motion"
    static var description = IntentDescription("Enable or disable a Blink camera’s motion detection. Its system must also be armed for motion detection to operate.")
    static var authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication
    @Parameter(title: "Camera") var camera: CameraEntity
    @Parameter(title: "Enabled") var enabled: Bool
    static var parameterSummary: some ParameterSummary { Summary("Set motion on \(\.$camera) to \(\.$enabled)") }
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let api = try SessionStore.client()
        let screen = try await api.homescreen()
        guard let device = screen.systems.flatMap(\.cameras).first(where: { $0.identity == camera.id }) else {
            throw IntentFailure.missing
        }
        let result = try await api.setCamera(device, enabled: enabled)
        let armed = result.systems.first { $0.id == device.networkID }?.armed == true
        if enabled && !armed { return .result(dialog: "Motion enabled. The system must also be armed to detect motion.") }
        return .result(dialog: enabled ? "Camera motion enabled." : "Camera motion disabled.")
    }
}
struct SetSystemArmedIntent: AppIntent {
    static var title: LocalizedStringResource = "Set System Armed"
    static var description = IntentDescription("Arm or disarm a Blink system. Individual camera motion settings are kept.")
    static var authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication
    @Parameter(title: "System") var system: SystemEntity
    @Parameter(title: "Armed") var armed: Bool
    static var parameterSummary: some ParameterSummary { Summary("Set \(\.$system) armed to \(\.$armed)") }
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let api = try SessionStore.client()
        let screen = try await api.homescreen()
        guard let target = screen.systems.first(where: { $0.id == system.id }) else { throw IntentFailure.missing }
        _ = try await api.setSystem(target, armed: armed)
        return .result(dialog: armed ? "System armed." : "System disarmed.")
    }
}
struct BlinkShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: SetCameraMotionIntent(), phrases: ["Set camera motion with \(.applicationName)"],
                    shortTitle: "Camera motion", systemImageName: "video")
        AppShortcut(intent: SetSystemArmedIntent(), phrases: ["Set system armed with \(.applicationName)"],
                    shortTitle: "Arm or disarm", systemImageName: "shield")
    }
}
private enum IntentFailure: LocalizedError {
    case missing
    var errorDescription: String? { "This camera or system is no longer available. Choose it again in Shortcuts." }
}
