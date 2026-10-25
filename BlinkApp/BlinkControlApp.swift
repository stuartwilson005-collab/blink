import SwiftUI
import BlinkCore

@main
struct BlinkControlApp: App {
    var body: some Scene { WindowGroup { DashboardView() } }
}
@MainActor
final class Dashboard: ObservableObject {
    @Published var systems: [BlinkSystem] = []
    @Published var updated: Date?
    @Published var error: String?
    @Published var busy = false
    @Published var signedIn = false
    private var api: BlinkAPI?
    func restore() async {
        guard !busy else { return }
        do {
            if api == nil { api = try SessionStore.client(); signedIn = true }
            await refresh()
        } catch BlinkError.signedOut { signedIn = false }
        catch { self.error = error.localizedDescription }
    }
    func signIn(_ credentials: Credentials) async {
        do {
            try SessionStore.save(credentials)
            api = try SessionStore.client(); signedIn = true
            await refresh()
        } catch { self.error = error.localizedDescription }
    }
    func refresh() async {
        guard !busy, let api else { return }
        await perform { try await api.homescreen() }
    }
    func setCamera(_ camera: Camera, enabled: Bool) async {
        guard !busy, let api else { return }
        await perform { try await api.setCamera(camera, enabled: enabled) }
    }
    func setSystem(_ system: BlinkSystem, armed: Bool) async {
        guard !busy, let api else { return }
        await perform { try await api.setSystem(system, armed: armed) }
    }
    private func perform(_ action: () async throws -> Homescreen) async {
        busy = true; error = nil
        defer { busy = false }
        do { systems = try await action().systems; updated = Date() }
        catch BlinkError.signedOut { signedIn = false; api = nil; systems = []; updated = nil; error = BlinkError.signedOut.localizedDescription }
        catch { self.error = error.localizedDescription }
    }
    func signOut() {
        do {
            try SessionStore.clear(); api = nil; systems = []; updated = nil; signedIn = false; error = nil
        } catch { self.error = error.localizedDescription }
    }
}
struct DashboardView: View {
    @StateObject private var model = Dashboard()
    @Environment(\.scenePhase) private var scenePhase
    @State private var showSignIn = false
    @State private var showHelp = false
    var body: some View {
        NavigationStack {
            Group {
                if model.signedIn { dashboard }
                else {
                    VStack(spacing: 20) {
                        Image(systemName: "camera.shutter.button.fill").font(.system(size: 64)).foregroundStyle(.teal)
                        Text("Your cameras. One place.").font(.title2.bold())
                        Text("See every Blink system and camera, control motion detection, and create iPhone Shortcuts.")
                            .multilineTextAlignment(.center).foregroundStyle(.secondary)
                        Button("Sign in to Blink") { showSignIn = true }.buttonStyle(.borderedProminent).tint(.teal)
                        Text("An independent app using Blink’s unofficial API. Sign-in is handled by Blink.")
                            .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        if let error = model.error { Text(error).foregroundStyle(.red) }
                    }.padding(30)
                }
            }
            .navigationTitle("Blink Control")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Shortcuts help", systemImage: "square.stack.3d.up") { showHelp = true }
                        if model.signedIn { Button("Sign out", role: .destructive) { model.signOut() }.disabled(model.busy) }
                    } label: { Image(systemName: "ellipsis.circle") }
                }
            }
            .sheet(isPresented: $showSignIn) {
                SignInView { credentials in showSignIn = false; Task { await model.signIn(credentials) } }
            }
            .sheet(isPresented: $showHelp) { shortcutsHelp }
            .task { await model.restore() }
            .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await model.restore() } } }
            .task(id: model.signedIn) {
                while model.signedIn && !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(30)) } catch { return }
                    if scenePhase == .active { await model.refresh() }
                }
            }
        }
    }
    private var dashboard: some View {
        List {
            Section {
                HStack {
                    Label("\(model.systems.count) systems", systemImage: "house.fill")
                    Spacer()
                    Text("\(model.systems.flatMap(\.cameras).count) cameras").foregroundStyle(.secondary)
                }
                let armed = model.systems.filter { $0.armed == true }.count
                Text("\(armed) armed · \(model.systems.filter { $0.armed == false }.count) disarmed · \(model.systems.filter { $0.armed == nil }.count) unknown")
                    .font(.subheadline)
                if let date = model.updated {
                    TimelineView(.periodic(from: .now, by: 15)) { context in
                        Text("Updated \(date.formatted(date: .omitted, time: .standard))\(context.date.timeIntervalSince(date) > 60 ? " · Status may be stale" : "")")
                            .font(.caption).foregroundStyle(context.date.timeIntervalSince(date) > 60 ? .orange : .secondary)
                    }
                }
                if model.busy { ProgressView("Checking with Blink…") }
                if let error = model.error { Text(error).foregroundStyle(.red).font(.callout) }
            }
            if model.systems.isEmpty && !model.busy {
                ContentUnavailableView("No systems to display", systemImage: "camera", description: Text("Pull to refresh. Any Blink error will appear above."))
            }
            ForEach(model.systems) { system in
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label(system.armLabel, systemImage: system.armed == true ? "shield.checkered" : "shield")
                                .font(.headline)
                            Spacer()
                            Text(system.connectivity).font(.caption).foregroundStyle(.secondary)
                        }
                        HStack {
                            Button("Arm system") { Task { await model.setSystem(system, armed: true) } }
                                .disabled(model.busy || system.armed == true)
                            Spacer()
                            Button("Disarm system") { Task { await model.setSystem(system, armed: false) } }
                                .disabled(model.busy || system.armed == false)
                        }.buttonStyle(.bordered)
                    }.padding(.vertical, 4)
                    ForEach(system.cameras, id: \.identity) { camera in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Label(camera.name, systemImage: camera.kind == .doorbell ? "doorbell.video" : "video")
                                    .font(.headline)
                                Spacer()
                                Text(camera.connectivity).font(.caption).foregroundStyle(.secondary)
                            }
                            if let battery = camera.battery { Label("Battery: \(battery)", systemImage: "battery.75percent").font(.caption).foregroundStyle(.secondary) }
                            if let enabled = camera.enabled {
                                Toggle("Motion detection", isOn: Binding(get: { enabled }, set: { value in Task { await model.setCamera(camera, enabled: value) } }))
                                    .disabled(model.busy).tint(.teal)
                                Text(enabled ? (system.armed == true ? "Motion enabled · system armed" : "Motion enabled · system is not known to be armed") : "Motion disabled")
                                    .font(.caption).foregroundStyle(.secondary)
                            } else {
                                Text("Motion status unknown").font(.caption).foregroundStyle(.secondary)
                                HStack {
                                    Button("Enable motion") { Task { await model.setCamera(camera, enabled: true) } }
                                    Button("Disable motion") { Task { await model.setCamera(camera, enabled: false) } }
                                }.buttonStyle(.bordered).disabled(model.busy)
                            }
                        }.padding(.vertical, 6)
                    }
                } header: { Text(system.name) }
                footer: { Text("Motion detection requires the system to be armed. Disabling motion does not power off the camera or block live view.") }
            }
        }
        .refreshable { await model.refresh() }
    }
    private var shortcutsHelp: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Control cameras with a tap").font(.title2.bold())
                    Text("1. Sign in here, then open Apple’s Shortcuts app.")
                    Text("2. Create a shortcut and add Blink Control’s Set Camera Motion action. Choose the camera and turn Enabled on or off.")
                    Text("3. Add Set System Armed if you also want to arm or disarm its system. Enabling a camera alone does not arm the system.")
                    Text("4. Use the shortcut’s menu to Add to Home Screen, or assign it to your Action Button or Back Tap in Settings.")
                    Text("Use separate Enable and Disable shortcuts for predictable results. Actions verify the state with Blink before reporting success. Your iPhone must be unlocked and connected to the internet.")
                    Text("Status refreshes when you open the app, pull to refresh, or every 30 seconds while active. It is the last state reported by Blink, not a continuous live connection.")
                }.padding()
            }.navigationTitle("iPhone Shortcuts").navigationBarTitleDisplayMode(.inline)
        }.presentationDragIndicator(.visible)
    }
}
