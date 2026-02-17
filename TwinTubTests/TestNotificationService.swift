import Foundation
@testable import TwinTubApp

final class TestNotificationService: NotificationDispatching {
    struct WaitingRecord: Equatable {
        let sessionID: String
        let escalated: Bool
    }

    struct TerminatedRecord: Equatable {
        let sessionID: String
        let reason: SessionTerminationReason
    }

    private(set) var waitingRecords: [WaitingRecord] = []
    private(set) var completedRecords: [String] = []
    private(set) var terminatedRecords: [TerminatedRecord] = []

    func requestAuthorizationIfNeeded() {}

    func postWaiting(session: SessionModel, escalated: Bool) {
        waitingRecords.append(.init(sessionID: session.id, escalated: escalated))
    }

    func postCompleted(session: SessionModel) {
        completedRecords.append(session.id)
    }

    func postTerminated(session: SessionModel, reason: SessionTerminationReason) {
        terminatedRecords.append(.init(sessionID: session.id, reason: reason))
    }
}
