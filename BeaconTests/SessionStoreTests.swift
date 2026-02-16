import Foundation
import XCTest
@testable import BeaconApp

@MainActor
final class SessionStoreTests: XCTestCase {
    private final class ClockBox {
        var now: Date
        init(now: Date) { self.now = now }
    }

    private final class StubProcessSnapshotProvider: ProcessSnapshotProviding {
        var snapshotValue: ProcessSnapshot?
        func snapshot() -> ProcessSnapshot? { snapshotValue }
    }

    private func makeStore(
        clockBox: ClockBox,
        snapshotProvider: StubProcessSnapshotProvider? = nil
    ) -> SessionStore {
        let provider = snapshotProvider ?? StubProcessSnapshotProvider()
        let monitor = SessionLivenessMonitor(
            processSnapshotProvider: provider,
            config: .init(
                offlineGracePeriod: 20,
                terminatedHistoryRetention: 300,
                hardExpiry: 1800
            )
        )
        return SessionStore(
            notificationService: TestNotificationService(),
            livenessMonitor: monitor,
            clock: { clockBox.now },
            throttleInterval: 0,
            livenessCheckInterval: 0
        )
    }

    func testSortingWaitingProcessingCompleted() {
        let clockBox = ClockBox(now: Date())
        let store = makeStore(clockBox: clockBox)

        store.handle(event: BeaconEvent(event: .userPromptSubmit, sessionID: "processing", prompt: "run"))
        clockBox.now = clockBox.now.addingTimeInterval(2)
        store.handle(event: BeaconEvent(event: .stop, sessionID: "done"))
        clockBox.now = clockBox.now.addingTimeInterval(2)
        store.handle(event: BeaconEvent(event: .permissionRequest, sessionID: "waiting", toolName: "bash"))

        XCTAssertEqual(store.sessions.map(\.id), ["waiting", "processing", "done"])
    }

    func testTTLPrunesProcessingAfterThirtyMinutes() {
        let clockBox = ClockBox(now: Date())
        let store = makeStore(clockBox: clockBox)

        store.handle(event: BeaconEvent(event: .userPromptSubmit, sessionID: "old", prompt: "run"))
        clockBox.now = clockBox.now.addingTimeInterval(1801)
        store.pruneExpiredProcessingSessions(now: clockBox.now)
        store.handle(event: BeaconEvent(event: .notification, sessionID: "new", message: "need input", notificationType: "permission_prompt"))

        XCTAssertFalse(store.sessions.contains(where: { $0.id == "old" }))
        XCTAssertTrue(store.sessions.contains(where: { $0.id == "new" }))
    }

    func testWaitingNotificationSilenceAndEscalationWindows() {
        let notifications = TestNotificationService()
        let clockBox = ClockBox(now: Date())
        let monitor = SessionLivenessMonitor(
            processSnapshotProvider: StubProcessSnapshotProvider(),
            config: .init(offlineGracePeriod: 20, terminatedHistoryRetention: 300, hardExpiry: 1800)
        )
        let store = SessionStore(
            notificationService: notifications,
            livenessMonitor: monitor,
            clock: { clockBox.now },
            throttleInterval: 0,
            livenessCheckInterval: 0
        )

        store.handle(event: BeaconEvent(event: .permissionRequest, sessionID: "a", toolName: "bash"))
        clockBox.now = clockBox.now.addingTimeInterval(30)
        store.handle(event: BeaconEvent(event: .permissionRequest, sessionID: "a", toolName: "bash"))
        clockBox.now = clockBox.now.addingTimeInterval(181)
        store.handle(event: BeaconEvent(event: .permissionRequest, sessionID: "a", toolName: "bash"))

        XCTAssertEqual(notifications.waitingRecords.count, 2)
        XCTAssertEqual(notifications.waitingRecords.first?.escalated, false)
        XCTAssertEqual(notifications.waitingRecords.last?.escalated, true)
    }

    func testDoneStateVisibleAfterStop() {
        let clockBox = ClockBox(now: Date())
        let store = makeStore(clockBox: clockBox)

        store.handle(event: BeaconEvent(event: .stop, sessionID: "a"))
        XCTAssertEqual(store.globalStatus, .done)

        clockBox.now = clockBox.now.addingTimeInterval(6)
        store.handle(event: BeaconEvent(event: .sessionEnd, sessionID: "a"))
        XCTAssertEqual(store.globalStatus, .idle)
    }

    func testLivenessMonitorRemovesSessionAfterGracePeriodWhenProcessMissing() {
        let snapshotProvider = StubProcessSnapshotProvider()
        let clockBox = ClockBox(now: Date())
        let store = makeStore(clockBox: clockBox, snapshotProvider: snapshotProvider)

        store.handle(event: BeaconEvent(event: .userPromptSubmit, sessionID: "s-live", shellPID: 111, terminalTTY: "/dev/ttys001"))
        snapshotProvider.snapshotValue = ProcessSnapshot(
            entriesByPID: [111: .init(pid: 111, ppid: 1, tty: "/dev/ttys001")],
            pidsByTTY: ["/dev/ttys001": [111]]
        )
        store.reconcileLiveness(now: clockBox.now)
        XCTAssertTrue(store.sessions.contains(where: { $0.id == "s-live" }))

        snapshotProvider.snapshotValue = ProcessSnapshot(entriesByPID: [:], pidsByTTY: [:])
        clockBox.now = clockBox.now.addingTimeInterval(10)
        store.reconcileLiveness(now: clockBox.now)
        XCTAssertTrue(store.sessions.contains(where: { $0.id == "s-live" }))

        clockBox.now = clockBox.now.addingTimeInterval(21)
        store.reconcileLiveness(now: clockBox.now)
        XCTAssertFalse(store.sessions.contains(where: { $0.id == "s-live" }))
    }

    func testLivenessMonitorKeepsSessionWhenRecoveredWithinGracePeriod() {
        let snapshotProvider = StubProcessSnapshotProvider()
        let clockBox = ClockBox(now: Date())
        let store = makeStore(clockBox: clockBox, snapshotProvider: snapshotProvider)

        store.handle(event: BeaconEvent(event: .userPromptSubmit, sessionID: "s-recover", shellPID: 222, terminalTTY: "/dev/ttys002"))
        snapshotProvider.snapshotValue = ProcessSnapshot(
            entriesByPID: [222: .init(pid: 222, ppid: 1, tty: "/dev/ttys002")],
            pidsByTTY: ["/dev/ttys002": [222]]
        )
        store.reconcileLiveness(now: clockBox.now)

        snapshotProvider.snapshotValue = ProcessSnapshot(entriesByPID: [:], pidsByTTY: [:])
        clockBox.now = clockBox.now.addingTimeInterval(10)
        store.reconcileLiveness(now: clockBox.now)

        snapshotProvider.snapshotValue = ProcessSnapshot(
            entriesByPID: [222: .init(pid: 222, ppid: 1, tty: "/dev/ttys002")],
            pidsByTTY: ["/dev/ttys002": [222]]
        )
        clockBox.now = clockBox.now.addingTimeInterval(5)
        store.reconcileLiveness(now: clockBox.now)

        XCTAssertTrue(store.sessions.contains(where: { $0.id == "s-recover" }))
    }

    func testTerminatedSessionsPurgedAfterRetention() {
        let snapshotProvider = StubProcessSnapshotProvider()
        let clockBox = ClockBox(now: Date())
        let notifications = TestNotificationService()
        let monitor = SessionLivenessMonitor(
            processSnapshotProvider: snapshotProvider,
            config: .init(offlineGracePeriod: 20, terminatedHistoryRetention: 5, hardExpiry: 1800)
        )
        let store = SessionStore(
            notificationService: notifications,
            livenessMonitor: monitor,
            clock: { clockBox.now },
            throttleInterval: 0,
            livenessCheckInterval: 0
        )

        store.handle(event: BeaconEvent(event: .userPromptSubmit, sessionID: "s-end"))
        store.handle(event: BeaconEvent(event: .sessionEnd, sessionID: "s-end"))
        XCTAssertFalse(store.sessions.contains(where: { $0.id == "s-end" }))
        XCTAssertNotNil(store.session(id: "s-end"))

        clockBox.now = clockBox.now.addingTimeInterval(6)
        store.reconcileLiveness(now: clockBox.now)
        XCTAssertNil(store.session(id: "s-end"))
    }
}
