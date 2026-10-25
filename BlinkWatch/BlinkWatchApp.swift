import SwiftUI
import BlinkCore

@main
struct BlinkWatchApp: App {
    @StateObject private var model = WatchModel()
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            WatchSystemsView(model: model)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { model.refresh() }
                }
        }
    }
}
struct WatchSystemsView: View {
    @ObservedObject var model: WatchModel
    @State private var disarming: WatchSystem?
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label(model.reachable ? "iPhone connected" : "iPhone unavailable",
                          systemImage: model.reachable ? "iphone" : "iphone.slash")
                        .font(.caption).foregroundStyle(.secondary)
                    if model.busy { ProgressView("Checking with Blink…") }
                    if let error = model.error { Text(error).font(.caption).foregroundStyle(.orange) }
                    if let confirmation = model.confirmation { Text(confirmation).font(.caption).foregroundStyle(.green) }
                    Button { model.refresh() } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                        .disabled(model.busy)
                }
                if let snapshot = model.snapshot, snapshot.signedIn {
                    if let date = snapshot.updated {
                        TimelineView(.periodic(from: .now, by: 15)) { context in
                            VStack(alignment: .leading) {
                                Text("Updated \(date.formatted(date: .omitted, time: .shortened))")
                                if context.date.timeIntervalSince(date) > 60 { Text("Status may be stale").foregroundStyle(.orange) }
                            }.font(.caption2)
                        }
                    }
                    if snapshot.systems.isEmpty { Text("No systems found. Refresh to check.").font(.caption) }
                    ForEach(snapshot.systems) { system in
                        Section {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(system.name).font(.headline)
                                if snapshot.systems.filter({ $0.name == system.name }).count > 1 {
                                    Text("System ID: \(system.id)").font(.caption2).foregroundStyle(.secondary)
                                }
                                Label(system.armLabel, systemImage: system.armed == true ? "shield.checkered" : "shield")
                                    .foregroundStyle(system.armed == true ? Color.teal : Color.secondary)
                                Text("\(system.cameraCount) cameras · \(system.status?.capitalized ?? "Connectivity unknown")")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            Button("Arm system") { model.setSystem(system, armed: true) }
                                .tint(.teal).disabled(model.busy || !model.reachable)
                            Button("Disarm system") { disarming = system }
                                .disabled(model.busy || !model.reachable)
                        }
                    }
                    Text("Arming keeps each camera’s motion setting. Cameras with motion disabled stay disabled.")
                        .font(.caption2).foregroundStyle(.secondary)
                } else {
                    Text("Sign in to Blink Control on your paired iPhone, then tap Refresh here.")
                        .font(.callout)
                }
            }
            .navigationTitle("Blink Control")
            .confirmationDialog("Disarm \(disarming?.name ?? "system")?", isPresented: Binding(
                get: { disarming != nil }, set: { if !$0 { disarming = nil } })) {
                    if let system = disarming {
                        Button("Disarm system", role: .destructive) { model.setSystem(system, armed: false); disarming = nil }
                    }
                    Button("Cancel", role: .cancel) { disarming = nil }
                } message: { Text("Motion detection will stop for this system.") }
        }
    }
}
