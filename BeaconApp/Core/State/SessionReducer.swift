import Foundation

public struct SessionReducer {
    public struct NotificationDecision: Equatable, Sendable {
        public enum Kind: Equatable, Sendable {
            case waiting(escalated: Bool)
            case completed
        }

        public let kind: Kind
        public let session: SessionModel
    }

    public enum Mutation: Equatable, Sendable {
        case upsert(SessionModel, NotificationDecision?)
        case remove(String)
        case none
    }

    public static func reduce(
        current: SessionModel?,
        event: BeaconEvent,
        now: Date,
        notifySilenceWindow: TimeInterval = 120,
        notifyEscalationWindow: TimeInterval = 180
    ) -> Mutation {
        if event.event == .sessionEnd {
            return .remove(event.sessionID)
        }

        var model = current ?? SessionModel(
            id: event.sessionID,
            projectName: inferredProjectName(from: event),
            cwd: event.cwd,
            status: .processing,
            statusReason: nil,
            usageBytes: 0,
            usageSegments: 0,
            updatedAt: now
        )

        model.updatedAt = now
        model.projectName = event.projectName ?? model.projectName
        if let cwd = event.cwd, !cwd.isEmpty {
            model.cwd = cwd
        }

        switch event.event {
        case .userPromptSubmit:
            model.status = .processing
            model.statusReason = event.prompt.flatMap(inferStatusReason(from:))
            model.waitingSince = nil
            model.completedAt = nil
            return .upsert(model, nil)

        case .postToolUse:
            model.status = .processing
            model.waitingSince = nil
            model.completedAt = nil
            if let usageBytes = event.usageBytes, usageBytes >= 0 {
                model.usageBytes = usageBytes
                model.usageSegments = SessionModel.segments(for: usageBytes)
            }
            return .upsert(model, nil)

        case .permissionRequest:
            model.status = .waiting
            model.statusReason = event.toolName ?? "WAITING_FOR_INPUT"
            return .upsert(model, waitingDecision(for: model, now: now, silenceWindow: notifySilenceWindow, escalationWindow: notifyEscalationWindow))

        case .notification:
            if shouldEnterWaiting(from: event.notificationType) {
                model.status = .waiting
                model.statusReason = event.message ?? event.notificationType ?? "WAITING_FOR_INPUT"
                return .upsert(model, waitingDecision(for: model, now: now, silenceWindow: notifySilenceWindow, escalationWindow: notifyEscalationWindow))
            }
            return .upsert(model, nil)

        case .stop:
            model.status = .completed
            model.statusReason = "DONE"
            model.completedAt = now
            model.waitingSince = nil
            let decision = NotificationDecision(kind: .completed, session: model)
            return .upsert(model, decision)

        case .sessionEnd:
            return .remove(event.sessionID)
        }
    }

    private static func waitingDecision(
        for model: SessionModel,
        now: Date,
        silenceWindow: TimeInterval,
        escalationWindow: TimeInterval
    ) -> NotificationDecision? {
        var mutable = model
        if mutable.waitingSince == nil {
            mutable.waitingSince = now
        }

        let lastNotification = mutable.lastWaitingNotificationAt
        let waitingStarted = mutable.waitingSince ?? now
        let shouldEscalate = now.timeIntervalSince(waitingStarted) >= escalationWindow

        if let lastNotification, now.timeIntervalSince(lastNotification) < silenceWindow {
            return nil
        }

        mutable.lastWaitingNotificationAt = now
        if shouldEscalate {
            mutable.notificationRepeatCount += 1
        }

        return NotificationDecision(kind: .waiting(escalated: shouldEscalate), session: mutable)
    }

    private static func shouldEnterWaiting(from notificationType: String?) -> Bool {
        guard let notificationType else { return false }
        return notificationType == "permission_prompt" || notificationType == "idle_prompt"
    }

    private static func inferredProjectName(from event: BeaconEvent) -> String {
        if let projectName = event.projectName, !projectName.isEmpty {
            return projectName.uppercased()
        }
        if let cwd = event.cwd, let folder = cwd.split(separator: "/").last {
            return String(folder).uppercased()
        }
        return "UNKNOWN_SESSION"
    }

    private static func inferStatusReason(from prompt: String) -> String {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "PROCESSING" }
        return String(trimmed.prefix(24)).replacingOccurrences(of: " ", with: "_").uppercased()
    }
}
