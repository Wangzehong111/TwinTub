import SwiftUI

@main
struct BeaconMenuBarApp: App {
    @StateObject private var store: SessionStore
    private let jumpService: TerminalJumpService
    private let server: LocalEventServer?

    init() {
        let notification = NotificationService()
        let store = SessionStore(notificationService: notification)
        _store = StateObject(wrappedValue: store)

        let jump = TerminalJumpService()
        self.jumpService = jump

        do {
            let server = try LocalEventServer(port: 55771) { event in
                store.handle(event: event)
            }
            self.server = server
            server.start()
        } catch {
            self.server = nil
            assertionFailure("Beacon server failed to start on 55771: \(error)")
        }
    }

    var body: some Scene {
        MenuBarExtra {
            BeaconPanelView(store: store, jumpService: jumpService)
        } label: {
            PillStatusView(status: store.globalStatus)
        }
        .menuBarExtraStyle(.window)
    }
}
