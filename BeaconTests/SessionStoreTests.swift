import Foundation
import XCTest
@testable import BeaconApp

@MainActor
final class SessionStoreTests: XCTestCase {
    func testSortingWaitingProcessingCompleted() {
        let notifications = TestNotificationService()
        var now = Date()
        let store = SessionStore(notificationService: notifications, clock: { now }, throttleInterval: 0)

        store.handle(event: BeaconEvent(event: .userPromptSubmit, sessionID: "processing", prompt: "run"))
        now = now.addingTimeInterval(2)
        store.handle(event: BeaconEvent(event: .stop, sessionID: "done"))
        now = now.addingTimeInterval(2)
        store.handle(event: BeaconEvent(event: .permissionRequest, sessionID: "waiting", toolName: "bash"))

        XCTAssertEqual(store.sessions.map(\.id), ["waiting", "processing", "done"])
    }

    func testTTLPrunesProcessingAfterThirtyMinutes() {
        let notifications = TestNotificationService()
        var now = Date()
        let store = SessionStore(notificationService: notifications, clock: { now }, throttleInterval: 0)

        store.handle(event: BeaconEvent(event: .userPromptSubmit, sessionID: "old", prompt: "run"))
        now = now.addingTimeInterval(1801)
        store.pruneExpiredProcessingSessions(now: now)
        store.handle(event: BeaconEvent(event: .notification, sessionID: "new", message: "need input", notificationType: "permission_prompt"))

        XCTAssertFalse(store.sessions.contains(where: { $0.id == "old" }))
        XCTAssertTrue(store.sessions.contains(where: { $0.id == "new" }))
    }

    func testWaitingNotificationSilenceAndEscalationWindows() {
        let notifications = TestNotificationService()
        var now = Date()
        let store = SessionStore(notificationService: notifications, clock: { now }, throttleInterval: 0)

        store.handle(event: BeaconEvent(event: .permissionRequest, sessionID: "a", toolName: "bash"))
        now = now.addingTimeInterval(30)
        store.handle(event: BeaconEvent(event: .permissionRequest, sessionID: "a", toolName: "bash"))
        now = now.addingTimeInterval(181)
        store.handle(event: BeaconEvent(event: .permissionRequest, sessionID: "a", toolName: "bash"))

        XCTAssertEqual(notifications.waitingRecords.count, 2)
        XCTAssertEqual(notifications.waitingRecords.first?.escalated, false)
        XCTAssertEqual(notifications.waitingRecords.last?.escalated, true)
    }

    func testDoneStateVisibleAfterStop() {
        let notifications = TestNotificationService()
        var now = Date()
        let store = SessionStore(notificationService: notifications, clock: { now }, throttleInterval: 0)

        store.handle(event: BeaconEvent(event: .stop, sessionID: "a"))
        XCTAssertEqual(store.globalStatus, .done)

        now = now.addingTimeInterval(6)
        store.handle(event: BeaconEvent(event: .sessionEnd, sessionID: "a"))
        XCTAssertEqual(store.globalStatus, .idle)
    }
}
