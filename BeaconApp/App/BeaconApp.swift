import SwiftUI
import AppKit

@main
struct BeaconMenuBarApp: App {
    @StateObject private var store: SessionStore
    @AppStorage("beacon.themePreference") private var themePreferenceRaw = ThemePreference.system.rawValue
    private let jumpService: TerminalJumpService
    private let server: LocalEventServer?
    private let eventBridge: EventBridge
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        let notification = NotificationService()
        let jump = TerminalJumpService()
        self.jumpService = jump

        let store = SessionStore(
            notificationService: notification,
            sourceResolver: { pid in jump.resolveSourceFromPID(pid) }
        )

        // Set up notification click handler to jump to terminal session (after store is created)
        notification.onNotificationClick = { [store, jump] sessionID in
            // Prevent App from activating when notification is clicked
            DispatchQueue.main.async {
                if let session = store.sessions.first(where: { $0.id == sessionID }) {
                    let outcome = jump.jump(to: session)
                    NSLog("[Beacon] Notification click jump outcome: \(outcome)")
                } else {
                    NSLog("[Beacon] Notification clicked but session not found: \(sessionID)")
                }
            }
        }

        _store = StateObject(wrappedValue: store)
        let bridge = EventBridge(store: store)
        self.eventBridge = bridge

        do {
            let server = try LocalEventServer(port: 55771, eventHandler: { event in
                bridge.enqueue(event)
            }, debugHandler: { [store] in
                var lines: [String] = []
                for s in store.sessions {
                    lines.append("id=\(s.id) src=\(s.sourceApp ?? "nil") bundle=\(s.sourceBundleID ?? "nil") shellPID=\(s.shellPID ?? 0) tty=\(s.terminalTTY ?? "nil") proj=\(s.projectName)")
                }
                return lines.joined(separator: "\n")
            })
            self.server = server
            server.start()
        } catch {
            self.server = nil
            assertionFailure("Beacon server failed to start on 55771: \(error)")
        }
    }

    var body: some Scene {
        MenuBarExtra {
            BeaconPanelView(
                store: store,
                jumpService: jumpService,
                themePreference: themePreference,
                onToggleTheme: toggleTheme
            )
            .beaconThemeOverride(themePreference.overrideColorScheme)
        } label: {
            PillStatusView(status: store.globalStatus)
        }
        .menuBarExtraStyle(.window)
    }

    private var themePreference: ThemePreference {
        ThemePreference(rawValue: themePreferenceRaw) ?? .system
    }

    private func toggleTheme() {
        var preference = themePreference
        preference.toggleDarkLight()
        themePreferenceRaw = preference.rawValue
    }
}

private final class EventBridge: @unchecked Sendable {
    private let store: SessionStore
    private let queue = DispatchQueue(label: "beacon.event.bridge", qos: .userInitiated)
    private let flushInterval: TimeInterval = 0.1
    private var pendingBySession: [String: BeaconEvent] = [:]
    private var pendingOrder: [String] = []
    private var flushScheduled = false
    private var deliveryInFlight = false

    init(store: SessionStore) {
        self.store = store
    }

    func enqueue(_ event: BeaconEvent) {
        queue.async { [weak self] in
            guard let self else { return }
            self.merge(event)
            self.scheduleFlushIfNeeded()
        }
    }

    private func scheduleFlushIfNeeded() {
        guard !flushScheduled else { return }
        flushScheduled = true
        queue.asyncAfter(deadline: .now() + flushInterval) { [weak self] in
            self?.flush()
        }
    }

    private func flush() {
        guard !pendingOrder.isEmpty else {
            flushScheduled = false
            return
        }
        guard !deliveryInFlight else {
            flushScheduled = false
            scheduleFlushIfNeeded()
            return
        }

        let order = pendingOrder
        let bySession = pendingBySession
        pendingOrder.removeAll(keepingCapacity: true)
        pendingBySession.removeAll(keepingCapacity: true)
        flushScheduled = false
        deliveryInFlight = true

        var compacted: [BeaconEvent] = []
        compacted.reserveCapacity(order.count)
        for sessionID in order {
            if let event = bySession[sessionID] {
                compacted.append(event)
            }
        }

        Task { @MainActor [store] in
            store.handle(events: compacted)
            self.queue.async { [weak self] in
                guard let self else { return }
                self.deliveryInFlight = false
                if !self.pendingOrder.isEmpty {
                    self.scheduleFlushIfNeeded()
                }
            }
        }
    }

    private func merge(_ event: BeaconEvent) {
        let sessionID = event.sessionID
        if pendingBySession[sessionID] == nil {
            pendingOrder.append(sessionID)
        }
        pendingBySession[sessionID] = coalesce(previous: pendingBySession[sessionID], incoming: event)
    }

    private func coalesce(previous: BeaconEvent?, incoming: BeaconEvent) -> BeaconEvent {
        guard let previous else { return incoming }

        // SessionEnd is the final lifecycle event — always takes precedence.
        if incoming.event == .sessionEnd { return incoming }
        if previous.event == .sessionEnd { return previous }

        // Stop beats non-terminal events but not SessionEnd.
        if previous.event == .stop { return previous }
        if incoming.event == .stop { return incoming }

        return incoming
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Ensure the app stays as agent (menu bar app)
        NSApp.setActivationPolicy(.accessory)

        // Validate hooks configuration on startup
        validateHooksConfiguration()
    }

    private func validateHooksConfiguration() {
        DispatchQueue.global(qos: .utility).async {
            let result = HookConfigValidator.validate()

            if result.hasIssues {
                NSLog("[Beacon] Hook configuration issue detected: \(result.summary)")

                // Attempt auto-fix
                if HookConfigValidator.autoFix() {
                    NSLog("[Beacon] Hooks configuration auto-fixed successfully")
                } else {
                    NSLog("[Beacon] Failed to auto-fix hooks configuration. Manual intervention required.")
                    // Could show a notification to user here if desired
                }
            } else {
                NSLog("[Beacon] Hooks configuration validated: \(result.summary)")
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Do not show dock icon when notification is clicked
        return false
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        // Prevent the app from activating fully
        DispatchQueue.main.async {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
