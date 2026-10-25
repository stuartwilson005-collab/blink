import Foundation
import WatchConnectivity
import BlinkCore

/// Active messages only: arm/disarm requests are never queued for later delivery.
final class WatchPhoneBridge: NSObject, WCSessionDelegate {
    static let shared = WatchPhoneBridge()
    private weak var dashboard: Dashboard?
    @MainActor
    func start(dashboard: Dashboard) {
        self.dashboard = dashboard
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }
    @MainActor
    func publish(_ snapshot: WatchSnapshot) {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated,
              WCSession.default.isPaired, WCSession.default.isWatchAppInstalled,
              let data = try? JSONEncoder().encode(snapshot) else { return }
        // Only the latest status is retained; no account secrets are transferred.
        try? WCSession.default.updateApplicationContext(["snapshot": data])
    }
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in
            if let dashboard { publish(dashboard.watchSnapshot) }
        }
    }
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    func session(_ session: WCSession, didReceiveMessageData messageData: Data,
                 replyHandler: @escaping (Data) -> Void) {
        Task { @MainActor in
            let empty = WatchSnapshot(signedIn: false, systems: [], updated: nil)
            let response: WatchReply
            if let dashboard {
                do {
                    let command = try JSONDecoder().decode(WatchCommand.self, from: messageData)
                    response = await dashboard.handleWatch(command)
                } catch {
                    response = WatchReply(snapshot: dashboard.watchSnapshot, error: "The Watch request was not recognised. Update both apps.")
                }
            } else {
                response = WatchReply(snapshot: empty, error: "Open Blink Control on your iPhone and sign in.")
            }
            if let data = try? JSONEncoder().encode(response) { replyHandler(data) }
        }
    }
}
