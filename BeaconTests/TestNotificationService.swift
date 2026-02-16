import Foundation
@testable import BeaconApp

final class TestNotificationService: NotificationDispatching {
    struct WaitingRecord: Equatable {
        let sessionID: String
        let escalated: Bool
    }

    private(set) var waitingRecords: [WaitingRecord] = []
    private(set) var completedRecords: [String] = []

    func requestAuthorizationIfNeeded() {}

    func postWaiting(session: SessionModel, escalated: Bool) {
        waitingRecords.append(.init(sessionID: session.id, escalated: escalated))
    }

    func postCompleted(session: SessionModel) {
        completedRecords.append(session.id)
    }
}
