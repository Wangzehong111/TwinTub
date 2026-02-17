import Foundation
import XCTest
@testable import TwinTubApp

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

        store.handle(event: TwinTubEvent(event: .userPromptSubmit, sessionID: "processing", prompt: "run"))
        clockBox.now = clockBox.now.addingTimeInterval(2)
        store.handle(event: TwinTubEvent(event: .stop, sessionID: "done"))
        clockBox.now = clockBox.now.addingTimeInterval(2)
        store.handle(event: TwinTubEvent(event: .permissionRequest, sessionID: "waiting", toolName: "bash"))

        XCTAssertEqual(store.sessions.map(\.id), ["waiting", "processing", "done"])
    }

    func testTTLPrunesProcessingAfterThirtyMinutes() {
        let clockBox = ClockBox(now: Date())
        let store = makeStore(clockBox: clockBox)

        store.handle(event: TwinTubEvent(event: .userPromptSubmit, sessionID: "old", prompt: "run"))
        clockBox.now = clockBox.now.addingTimeInterval(1801)
        store.pruneExpiredProcessingSessions(now: clockBox.now)
        store.handle(event: TwinTubEvent(event: .notification, sessionID: "new", message: "need input", notificationType: "permission_prompt"))

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

        store.handle(event: TwinTubEvent(event: .permissionRequest, sessionID: "a", toolName: "bash"))
        clockBox.now = clockBox.now.addingTimeInterval(30)
        store.handle(event: TwinTubEvent(event: .permissionRequest, sessionID: "a", toolName: "bash"))
        clockBox.now = clockBox.now.addingTimeInterval(181)
        store.handle(event: TwinTubEvent(event: .permissionRequest, sessionID: "a", toolName: "bash"))

        XCTAssertEqual(notifications.waitingRecords.count, 2)
        XCTAssertEqual(notifications.waitingRecords.first?.escalated, false)
        XCTAssertEqual(notifications.waitingRecords.last?.escalated, true)
    }

    func testDoneStateVisibleAfterStop() {
        let clockBox = ClockBox(now: Date())
        let store = makeStore(clockBox: clockBox)

        store.handle(event: TwinTubEvent(event: .stop, sessionID: "a"))
        XCTAssertEqual(store.globalStatus, .done)

        clockBox.now = clockBox.now.addingTimeInterval(6)
        store.handle(event: TwinTubEvent(event: .sessionEnd, sessionID: "a"))
        XCTAssertEqual(store.globalStatus, .idle)
    }

    func testLivenessMonitorRemovesSessionAfterGracePeriodWhenProcessMissing() {
        let snapshotProvider = StubProcessSnapshotProvider()
        let clockBox = ClockBox(now: Date())
        let store = makeStore(clockBox: clockBox, snapshotProvider: snapshotProvider)

        store.handle(event: TwinTubEvent(event: .userPromptSubmit, sessionID: "s-live", shellPID: 111, terminalTTY: "/dev/ttys001"))
        snapshotProvider.snapshotValue = ProcessSnapshot(
            entriesByPID: [111: .init(pid: 111, ppid: 1, tty: "/dev/ttys001")],
            pidsByTTY: ["/dev/ttys001": [111]]
        )
        store.reconcileLivenessSync(now: clockBox.now)
        XCTAssertTrue(store.sessions.contains(where: { $0.id == "s-live" }))

        snapshotProvider.snapshotValue = ProcessSnapshot(entriesByPID: [:], pidsByTTY: [:])
        clockBox.now = clockBox.now.addingTimeInterval(10)
        store.reconcileLivenessSync(now: clockBox.now)
        XCTAssertTrue(store.sessions.contains(where: { $0.id == "s-live" }))

        clockBox.now = clockBox.now.addingTimeInterval(21)
        store.reconcileLivenessSync(now: clockBox.now)
        XCTAssertFalse(store.sessions.contains(where: { $0.id == "s-live" }))
    }

    func testLivenessMonitorKeepsSessionWhenRecoveredWithinGracePeriod() {
        let snapshotProvider = StubProcessSnapshotProvider()
        let clockBox = ClockBox(now: Date())
        let store = makeStore(clockBox: clockBox, snapshotProvider: snapshotProvider)

        store.handle(event: TwinTubEvent(event: .userPromptSubmit, sessionID: "s-recover", shellPID: 222, terminalTTY: "/dev/ttys002"))
        snapshotProvider.snapshotValue = ProcessSnapshot(
            entriesByPID: [222: .init(pid: 222, ppid: 1, tty: "/dev/ttys002")],
            pidsByTTY: ["/dev/ttys002": [222]]
        )
        store.reconcileLivenessSync(now: clockBox.now)

        snapshotProvider.snapshotValue = ProcessSnapshot(entriesByPID: [:], pidsByTTY: [:])
        clockBox.now = clockBox.now.addingTimeInterval(10)
        store.reconcileLivenessSync(now: clockBox.now)

        snapshotProvider.snapshotValue = ProcessSnapshot(
            entriesByPID: [222: .init(pid: 222, ppid: 1, tty: "/dev/ttys002")],
            pidsByTTY: ["/dev/ttys002": [222]]
        )
        clockBox.now = clockBox.now.addingTimeInterval(5)
        store.reconcileLivenessSync(now: clockBox.now)

        XCTAssertTrue(store.sessions.contains(where: { $0.id == "s-recover" }))
    }

    func testSessionEndAfterStopTriggersTerminatedNotification() {
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

        store.handle(event: TwinTubEvent(event: .userPromptSubmit, sessionID: "s-term"))
        // Stop followed immediately by SessionEnd (simulates typical Claude Code lifecycle)
        store.handle(events: [
            TwinTubEvent(event: .stop, sessionID: "s-term"),
            TwinTubEvent(event: .sessionEnd, sessionID: "s-term")
        ])

        XCTAssertEqual(notifications.terminatedRecords.count, 1)
        XCTAssertEqual(notifications.terminatedRecords.first?.sessionID, "s-term")
        XCTAssertEqual(notifications.terminatedRecords.first?.reason, .sessionEndEvent)
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

        store.handle(event: TwinTubEvent(event: .userPromptSubmit, sessionID: "s-end"))
        store.handle(event: TwinTubEvent(event: .sessionEnd, sessionID: "s-end"))
        XCTAssertFalse(store.sessions.contains(where: { $0.id == "s-end" }))
        XCTAssertNotNil(store.session(id: "s-end"))

        clockBox.now = clockBox.now.addingTimeInterval(6)
        store.reconcileLivenessSync(now: clockBox.now)
        XCTAssertNil(store.session(id: "s-end"))
    }

    // MARK: - GlobalStatus Processing Priority Tests

    func testGlobalStatusProcessingTakesPriorityOverWaiting() {
        let clockBox = ClockBox(now: Date())
        let store = makeStore(clockBox: clockBox)

        // 创建一个 processing 会话
        store.handle(event: TwinTubEvent(event: .userPromptSubmit, sessionID: "proc1", prompt: "run"))

        // 创建一个 waiting 会话
        store.handle(event: TwinTubEvent(event: .permissionRequest, sessionID: "wait1", toolName: "bash"))

        // 验证：processing 优先级更高，显示 processing(hasWaiting: true)
        if case .processing(let hasWaiting) = store.globalStatus {
            XCTAssertTrue(hasWaiting, "当同时存在 processing 和 waiting 时，hasWaiting 应为 true")
        } else {
            XCTFail("期望 globalStatus 为 .processing(hasWaiting: true)，实际为 \(store.globalStatus)")
        }
    }

    func testGlobalStatusProcessingWithoutWaiting() {
        let clockBox = ClockBox(now: Date())
        let store = makeStore(clockBox: clockBox)

        // 只创建一个 processing 会话
        store.handle(event: TwinTubEvent(event: .userPromptSubmit, sessionID: "proc1", prompt: "run"))

        // 验证：processing(hasWaiting: false)
        if case .processing(let hasWaiting) = store.globalStatus {
            XCTAssertFalse(hasWaiting, "当只有 processing 没有 waiting 时，hasWaiting 应为 false")
        } else {
            XCTFail("期望 globalStatus 为 .processing(hasWaiting: false)，实际为 \(store.globalStatus)")
        }
    }

    func testGlobalStatusWaitingWhenNoProcessing() {
        let clockBox = ClockBox(now: Date())
        let store = makeStore(clockBox: clockBox)

        // 只创建 waiting 会话
        store.handle(event: TwinTubEvent(event: .permissionRequest, sessionID: "wait1", toolName: "bash"))
        store.handle(event: TwinTubEvent(event: .permissionRequest, sessionID: "wait2", toolName: "bash"))

        // 验证：waiting(count: 2)
        if case .waiting(let count) = store.globalStatus {
            XCTAssertEqual(count, 2, "当只有 waiting 会话时，count 应为 2")
        } else {
            XCTFail("期望 globalStatus 为 .waiting(count: 2)，实际为 \(store.globalStatus)")
        }
    }
}
