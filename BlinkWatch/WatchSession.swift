import Foundation
import WatchConnectivity
import BlinkCore

@MainActor
final class WatchModel: NSObject, ObservableObject, WCSessionDelegate {
    @Published private(set) var snapshot: WatchSnapshot?
    @Published private(set) var busy = false
    @Published private(set) var reachable = false
    @Published private(set) var error: String?
    @Published private(set) var confirmation: String?
    private var pendingID: UUID?
    private var timeout: Task<Void, Never>?
    override init() {
        super.init()
        guard WCSession.isSupported() else { error = "Watch connectivity is unavailable."; return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }
    func refresh() { send(.refresh) }
    func setSystem(_ system: WatchSystem, armed: Bool) { send(.setSystem(id: system.id, armed: armed)) }
    private func send(_ command: WatchCommand) {
        guard !busy else { return }
        confirmation = nil
        let session = WCSession.default
        guard session.activationState == .activated, session.isReachable else {
            reachable = false
            error = "iPhone unavailable. Keep it nearby, connected, and open Blink Control, then refresh."
            return
        }
        let data: Data
        do { data = try JSONEncoder().encode(command) }
        catch { self.error = error.localizedDescription; return }
        reachable = true; busy = true; error = nil
        let id = UUID(); pendingID = id
        // No retry: a command may have completed even if its reply was lost.
        timeout = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(75)) } catch { return }
            self?.fail(id, message: "No confirmation from iPhone. The change may have completed. Refresh before trying again.")
        }
        session.sendMessageData(data) { [weak self] response in
            Task { @MainActor in
                guard let self, self.pendingID == id else { return }
                self.timeout?.cancel(); self.pendingID = nil; self.busy = false
                do {
                    let reply = try JSONDecoder().decode(WatchReply.self, from: response)
                    self.snapshot = reply.snapshot; self.error = reply.error
                    if reply.error == nil, case .setSystem(_, let armed) = command {
                        self.confirmation = armed ? "System armed" : "System disarmed"
                    }
                } catch { self.error = "Could not read iPhone’s response. Update both apps and refresh." }
            }
        } errorHandler: { [weak self] _ in
            Task { @MainActor in
                self?.fail(id, message: "Connection lost. The change may have completed. Refresh to check before trying again.")
            }
        }
    }
    private func fail(_ id: UUID, message: String) {
        guard pendingID == id else { return }
        timeout?.cancel(); pendingID = nil; busy = false; error = message
        reachable = WCSession.default.isReachable
    }
    private func receive(_ context: [String: Any]) {
        guard !busy, let data = context["snapshot"] as? Data,
              let incoming = try? JSONDecoder().decode(WatchSnapshot.self, from: data) else { return }
        // A sign-out always clears the view, otherwise don't overwrite newer status.
        if !incoming.signedIn || snapshot?.updated == nil || (incoming.updated ?? .distantPast) >= (snapshot?.updated ?? .distantPast) {
            snapshot = incoming
        }
    }
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in
            reachable = session.isReachable
            receive(session.receivedApplicationContext)
            if error != nil { self.error = "Could not connect to iPhone. Open both apps and try again." }
            else if session.isReachable { refresh() }
        }
    }
    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in reachable = session.isReachable }
    }
    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in receive(applicationContext) }
    }
}
