import Foundation

public struct SessionReducer {
    public struct NotificationDecision: Equatable, Sendable {
        public enum Kind: Equatable, Sendable {
            case waiting(escalated: Bool)
            case completed
            case terminated(reason: SessionTerminationReason)
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
        event: TwinTubEvent,
        now: Date,
        terminatedHistoryRetention: TimeInterval = 300,
        notifySilenceWindow: TimeInterval = 120,
        notifyEscalationWindow: TimeInterval = 180
    ) -> Mutation {
        if event.event == .sessionEnd {
            guard var model = current else {
                return .none
            }
            model.status = .completed
            model.statusReason = "SESSION_ENDED"
            model.completedAt = now
            model.waitingSince = nil
            model.livenessState = .terminated
            model.terminationReason = .sessionEndEvent
            model.cleanupDeadline = now.addingTimeInterval(terminatedHistoryRetention)
            model.offlineMarkedAt = nil
            let decision = NotificationDecision(kind: .terminated(reason: .sessionEndEvent), session: model)
            return .upsert(model, decision)
        }

        var model = current ?? SessionModel(
            id: event.sessionID,
            projectName: inferredProjectName(from: event),
            cwd: event.cwd,
            status: .processing,
            statusReason: nil,
            usageBytes: 0,
            usageTokens: 0,
            maxContextTokens: SessionModel.maxContextTokens(for: event.model),
            model: event.model,
            usageSegments: 0,
            updatedAt: now,
            sourceApp: event.sourceApp,
            sourceBundleID: event.sourceBundleID,
            sourcePID: event.sourcePID,
            sourceConfidence: event.sourceConfidence ?? .unknown,
            shellPID: event.shellPID,
            shellPPID: event.shellPPID,
            terminalTTY: event.terminalTTY,
            terminalSessionID: event.terminalSessionID,
            terminalWindowID: event.terminalWindowID,
            terminalPaneID: event.terminalPaneID,
            livenessState: .alive,
            lastSeenAliveAt: now
        )

        model.updatedAt = now
        model.projectName = event.projectName ?? model.projectName
        if let cwd = event.cwd, !cwd.isEmpty {
            model.cwd = cwd
        }
        if let sourceApp = event.sourceApp, !sourceApp.isEmpty {
            model.sourceApp = sourceApp
        }
        if let sourceBundleID = event.sourceBundleID, !sourceBundleID.isEmpty {
            model.sourceBundleID = sourceBundleID
        }
        if let sourcePID = event.sourcePID {
            model.sourcePID = sourcePID
        }
        if let sourceConfidence = event.sourceConfidence {
            model.sourceConfidence = sourceConfidence
        }
        if let shellPID = event.shellPID {
            model.shellPID = shellPID
        }
        if let shellPPID = event.shellPPID {
            model.shellPPID = shellPPID
        }
        if let terminalTTY = event.terminalTTY, !terminalTTY.isEmpty {
            model.terminalTTY = terminalTTY
        }
        if let terminalSessionID = event.terminalSessionID, !terminalSessionID.isEmpty {
            model.terminalSessionID = terminalSessionID
        }
        if let terminalWindowID = event.terminalWindowID, !terminalWindowID.isEmpty {
            model.terminalWindowID = terminalWindowID
        }
        if let terminalPaneID = event.terminalPaneID, !terminalPaneID.isEmpty {
            model.terminalPaneID = terminalPaneID
        }
        model.sourceFingerprint = SessionModel.buildSourceFingerprint(
            sourceBundleID: model.sourceBundleID,
            terminalTTY: model.terminalTTY,
            shellPID: model.shellPID,
            sourcePID: model.sourcePID
        )
        model.livenessState = .alive
        model.lastSeenAliveAt = now
        model.offlineMarkedAt = nil
        model.cleanupDeadline = nil
        model.terminationReason = nil

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

            // 优先使用 token 数计算进度条
            if let usageTokens = event.usageTokens, usageTokens >= 0 {
                model.usageTokens = usageTokens
                // 如果有新的模型信息，更新 maxContextTokens
                if let model_name = event.model, !model_name.isEmpty {
                    model.model = model_name
                    model.maxContextTokens = SessionModel.maxContextTokens(for: model_name)
                }
                model.usageSegments = SessionModel.segmentsForTokens(usageTokens, maxContextTokens: model.maxContextTokens)
                // 为了向后兼容，也更新 usageBytes（如果需要）
                model.usageBytes = usageTokens * 4
            } else if let usageBytes = event.usageBytes, usageBytes >= 0 {
                // 回退到 bytes 计算（向后兼容）
                model.usageBytes = usageBytes
                let maxBytes = event.maxContextBytes ?? model.maxContextBytes
                model.usageSegments = SessionModel.segments(for: usageBytes, maxContextBytes: maxBytes)
            }

            // 更新 maxContextBytes（如果 Hook 提供了新值）
            if let maxContextBytes = event.maxContextBytes {
                model.maxContextBytes = maxContextBytes
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
        let normalized = notificationType
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")

        return normalized == "permission_prompt" ||
            normalized == "permission_request" ||
            normalized == "idle_prompt"
    }

    private static func inferredProjectName(from event: TwinTubEvent) -> String {
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
