import Foundation
import XCTest
@testable import BeaconApp

final class NotificationServiceTests: XCTestCase {
    private final class MockNotificationSender: NotificationSending {
        struct Record: Equatable {
            let title: String
            let body: String
            let sound: String
            let sessionID: String?
        }

        private(set) var records: [Record] = []

        func send(title: String, body: String, sound: String, sessionID: String?) {
            records.append(.init(title: title, body: body, sound: sound, sessionID: sessionID))
        }
    }

    private final class AuthorizingMockSender: NotificationSending, NotificationAuthorizationRequesting {
        private(set) var requestAuthorizationCount = 0

        func requestAuthorizationIfNeeded() {
            requestAuthorizationCount += 1
        }

        func send(title: String, body: String, sound: String, sessionID: String?) {}
    }

    private func makeSession(id: String = "s-1", projectName: String = "Beacon", statusReason: String? = "bash") -> SessionModel {
        SessionModel(
            id: id,
            projectName: projectName,
            cwd: nil,
            status: .waiting,
            statusReason: statusReason,
            usageBytes: 0,
            usageSegments: 0,
            updatedAt: Date()
        )
    }

    func testPostWaitingSendsCorrectContent() {
        let mock = MockNotificationSender()
        let service = NotificationService(sender: mock)

        service.postWaiting(session: makeSession(), escalated: false)
        XCTAssertEqual(mock.records.count, 1)
        XCTAssertEqual(mock.records[0].title, "Beacon Waiting")
        XCTAssertTrue(mock.records[0].body.contains("Beacon"))
        XCTAssertTrue(mock.records[0].body.contains("bash"))
    }

    func testPostWaitingEscalated() {
        let mock = MockNotificationSender()
        let service = NotificationService(sender: mock)

        service.postWaiting(session: makeSession(), escalated: true)
        XCTAssertEqual(mock.records[0].title, "Beacon Escalation")
    }

    func testPostCompletedSendsCorrectContent() {
        let mock = MockNotificationSender()
        let service = NotificationService(sender: mock)

        service.postCompleted(session: makeSession())
        XCTAssertEqual(mock.records.count, 1)
        XCTAssertEqual(mock.records[0].title, "Beacon Done")
    }

    func testPostTerminatedSendsCorrectContent() {
        let mock = MockNotificationSender()
        let service = NotificationService(sender: mock)

        service.postTerminated(session: makeSession(), reason: .processMissing)
        XCTAssertEqual(mock.records.count, 1)
        XCTAssertEqual(mock.records[0].title, "Beacon Session Ended")
        XCTAssertTrue(mock.records[0].body.contains("Process not found"))
    }

    func testAppleScriptEscaping() {
        XCTAssertEqual(
            InProcessAppleScriptSender.escape(#"He said "hello""#),
            #"He said \"hello\""#
        )
        XCTAssertEqual(
            InProcessAppleScriptSender.escape(#"path\to\file"#),
            #"path\\to\\file"#
        )
    }

    func testRequestAuthorizationDelegatesToSenderWhenSupported() {
        let sender = AuthorizingMockSender()
        let service = NotificationService(sender: sender)

        service.requestAuthorizationIfNeeded()
        XCTAssertEqual(sender.requestAuthorizationCount, 1)
    }
}
