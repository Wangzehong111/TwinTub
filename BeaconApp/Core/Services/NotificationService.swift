import Foundation
import UserNotifications

public protocol NotificationDispatching {
    func requestAuthorizationIfNeeded()
    func postWaiting(session: SessionModel, escalated: Bool)
    func postCompleted(session: SessionModel)
}

public final class NotificationService: NotificationDispatching {
    private let center: UNUserNotificationCenter

    public init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    public func requestAuthorizationIfNeeded() {
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    public func postWaiting(session: SessionModel, escalated: Bool) {
        let content = UNMutableNotificationContent()
        content.title = escalated ? "Beacon Escalation" : "Beacon Waiting"
        content.body = "\(session.projectName) requires input: \(session.statusReason ?? "WAITING_FOR_INPUT")"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "beacon.waiting.\(session.id)",
            content: content,
            trigger: nil
        )
        center.add(request)
    }

    public func postCompleted(session: SessionModel) {
        let content = UNMutableNotificationContent()
        content.title = "Beacon Done"
        content.body = "\(session.projectName) completed"

        let request = UNNotificationRequest(
            identifier: "beacon.completed.\(session.id)",
            content: content,
            trigger: nil
        )
        center.add(request)
    }
}

public final class NoopNotificationService: NotificationDispatching {
    public init() {}
    public func requestAuthorizationIfNeeded() {}
    public func postWaiting(session: SessionModel, escalated: Bool) {}
    public func postCompleted(session: SessionModel) {}
}
