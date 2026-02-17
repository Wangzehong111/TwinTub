import Foundation
import XCTest
@testable import TwinTubApp

final class SessionLivenessMonitorTests: XCTestCase {
    private final class StubProcessSnapshotProvider: ProcessSnapshotProviding {
        var snapshotValue: ProcessSnapshot?
        func snapshot() -> ProcessSnapshot? { snapshotValue }
    }

    func testProcessMissingTransitionsToTerminatedAfterGrace() {
        let provider = StubProcessSnapshotProvider()
        let monitor = SessionLivenessMonitor(
            processSnapshotProvider: provider,
            config: .init(offlineGracePeriod: 20, terminatedHistoryRetention: 300, hardExpiry: 1800)
        )

        let now = Date()
        let session = SessionModel(
            id: "s1",
            projectName: "P",
            cwd: nil,
            status: .processing,
            statusReason: nil,
            usageBytes: 0,
            usageTokens: 0,
            usageSegments: 0,
            updatedAt: now,
            sourcePID: 500,
            livenessState: .alive
        )

        provider.snapshotValue = ProcessSnapshot(entriesByPID: [:], pidsByTTY: [:])

        let first = monitor.reconcile(sessionMap: [session.id: session], now: now)
        XCTAssertEqual(first[session.id]?.livenessState, .suspectOffline)

        let second = monitor.reconcile(sessionMap: first, now: now.addingTimeInterval(21))
        XCTAssertEqual(second[session.id]?.livenessState, .terminated)
        XCTAssertEqual(second[session.id]?.terminationReason, .processMissing)
    }

    func testTTYMismatchMarkedAsTTYMissing() {
        let provider = StubProcessSnapshotProvider()
        let monitor = SessionLivenessMonitor(
            processSnapshotProvider: provider,
            config: .init(offlineGracePeriod: 1, terminatedHistoryRetention: 300, hardExpiry: 1800)
        )

        let now = Date()
        let session = SessionModel(
            id: "s2",
            projectName: "P",
            cwd: nil,
            status: .processing,
            statusReason: nil,
            usageBytes: 0,
            usageTokens: 0,
            usageSegments: 0,
            updatedAt: now,
            shellPID: 123,
            terminalTTY: "/dev/ttys010",
            livenessState: .alive
        )

        provider.snapshotValue = ProcessSnapshot(
            entriesByPID: [123: .init(pid: 123, ppid: 1, tty: "/dev/ttys011")],
            pidsByTTY: ["/dev/ttys011": [123]]
        )

        let first = monitor.reconcile(sessionMap: [session.id: session], now: now)
        let second = monitor.reconcile(sessionMap: first, now: now.addingTimeInterval(2))

        XCTAssertEqual(second[session.id]?.livenessState, .terminated)
        XCTAssertEqual(second[session.id]?.terminationReason, .ttyMissing)
    }

    func testShellPPIDMissingTerminatesEvenIfShellPIDAlive() {
        let provider = StubProcessSnapshotProvider()
        let monitor = SessionLivenessMonitor(
            processSnapshotProvider: provider,
            config: .init(offlineGracePeriod: 1, terminatedHistoryRetention: 300, hardExpiry: 1800)
        )

        let now = Date()
        // shellPID 900 is the user's shell (stays alive), shellPPID 800 is Claude (will exit)
        let session = SessionModel(
            id: "s-ppid",
            projectName: "P",
            cwd: nil,
            status: .processing,
            statusReason: nil,
            usageBytes: 0,
            usageTokens: 0,
            usageSegments: 0,
            updatedAt: now,
            shellPID: 900,
            shellPPID: 800,
            terminalTTY: "/dev/ttys030",
            livenessState: .alive
        )

        // Shell alive, Claude gone
        provider.snapshotValue = ProcessSnapshot(
            entriesByPID: [900: .init(pid: 900, ppid: 1, tty: "/dev/ttys030")],
            pidsByTTY: ["/dev/ttys030": [900]]
        )

        let first = monitor.reconcile(sessionMap: [session.id: session], now: now)
        XCTAssertEqual(first[session.id]?.livenessState, .suspectOffline)

        let second = monitor.reconcile(sessionMap: first, now: now.addingTimeInterval(2))
        XCTAssertEqual(second[session.id]?.livenessState, .terminated)
        XCTAssertEqual(second[session.id]?.terminationReason, .processMissing)
    }

    func testShellPPIDAliveKeepsSessionAlive() {
        let provider = StubProcessSnapshotProvider()
        let monitor = SessionLivenessMonitor(
            processSnapshotProvider: provider,
            config: .init(offlineGracePeriod: 20, terminatedHistoryRetention: 300, hardExpiry: 1800)
        )

        let now = Date()
        let session = SessionModel(
            id: "s-ppid-alive",
            projectName: "P",
            cwd: nil,
            status: .processing,
            statusReason: nil,
            usageBytes: 0,
            usageTokens: 0,
            usageSegments: 0,
            updatedAt: now,
            shellPID: 900,
            shellPPID: 800,
            terminalTTY: "/dev/ttys030",
            livenessState: .alive
        )

        // Both shell and Claude alive
        provider.snapshotValue = ProcessSnapshot(
            entriesByPID: [
                900: .init(pid: 900, ppid: 1, tty: "/dev/ttys030"),
                800: .init(pid: 800, ppid: 900, tty: "/dev/ttys030")
            ],
            pidsByTTY: ["/dev/ttys030": [900, 800]]
        )

        let result = monitor.reconcile(sessionMap: [session.id: session], now: now)
        XCTAssertEqual(result[session.id]?.livenessState, .alive)
    }

    func testAliveSnapshotResetsSuspectState() {
        let provider = StubProcessSnapshotProvider()
        let monitor = SessionLivenessMonitor(
            processSnapshotProvider: provider,
            config: .init(offlineGracePeriod: 20, terminatedHistoryRetention: 300, hardExpiry: 1800)
        )

        let now = Date()
        let session = SessionModel(
            id: "s3",
            projectName: "P",
            cwd: nil,
            status: .processing,
            statusReason: nil,
            usageBytes: 0,
            usageTokens: 0,
            usageSegments: 0,
            updatedAt: now,
            shellPID: 900,
            terminalTTY: "/dev/ttys020",
            livenessState: .suspectOffline,
            offlineMarkedAt: now.addingTimeInterval(-5)
        )

        provider.snapshotValue = ProcessSnapshot(
            entriesByPID: [900: .init(pid: 900, ppid: 1, tty: "/dev/ttys020")],
            pidsByTTY: ["/dev/ttys020": [900]]
        )

        let reconciled = monitor.reconcile(sessionMap: [session.id: session], now: now)
        XCTAssertEqual(reconciled[session.id]?.livenessState, .alive)
        XCTAssertNil(reconciled[session.id]?.offlineMarkedAt)
        XCTAssertNil(reconciled[session.id]?.terminationReason)
    }
}
