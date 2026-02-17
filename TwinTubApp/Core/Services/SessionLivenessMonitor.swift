import Foundation

public final class SessionLivenessMonitor: @unchecked Sendable {
    public struct Config: Sendable {
        public let offlineGracePeriod: TimeInterval
        public let terminatedHistoryRetention: TimeInterval
        public let hardExpiry: TimeInterval

        public init(
            offlineGracePeriod: TimeInterval = 20,
            terminatedHistoryRetention: TimeInterval = 300,
            hardExpiry: TimeInterval = 1800
        ) {
            self.offlineGracePeriod = offlineGracePeriod
            self.terminatedHistoryRetention = terminatedHistoryRetention
            self.hardExpiry = hardExpiry
        }
    }

    private enum Evidence {
        case alive
        case missing(SessionTerminationReason)
        case unknown
    }

    private let processSnapshotProvider: ProcessSnapshotProviding
    public let config: Config

    public init(
        processSnapshotProvider: ProcessSnapshotProviding = ProcessSnapshotProvider(),
        config: Config = .init()
    ) {
        self.processSnapshotProvider = processSnapshotProvider
        self.config = config
    }

    public func reconcile(sessionMap: [String: SessionModel], now: Date) -> [String: SessionModel] {
        let snapshot = processSnapshotProvider.snapshot()
        var nextMap: [String: SessionModel] = [:]

        for (sessionID, session) in sessionMap {
            if let next = reconcile(session: session, now: now, snapshot: snapshot) {
                nextMap[sessionID] = next
            }
        }

        return nextMap
    }

    private func reconcile(session: SessionModel, now: Date, snapshot: ProcessSnapshot?) -> SessionModel? {
        var mutable = session

        if mutable.livenessState == .terminated {
            if let deadline = mutable.cleanupDeadline, now >= deadline {
                return nil
            }
            return mutable
        }

        if now.timeIntervalSince(mutable.updatedAt) > config.hardExpiry,
           mutable.livenessState != .alive {
            return terminate(session: mutable, reason: .heartbeatTimeout, now: now)
        }

        guard let snapshot else {
            return mutable
        }

        switch evaluate(session: mutable, snapshot: snapshot) {
        case .alive:
            mutable.livenessState = .alive
            mutable.lastSeenAliveAt = now
            mutable.offlineMarkedAt = nil
            mutable.cleanupDeadline = nil
            mutable.terminationReason = nil
            return mutable

        case let .missing(reason):
            if mutable.offlineMarkedAt == nil {
                mutable.offlineMarkedAt = now
                mutable.livenessState = .suspectOffline
                return mutable
            }

            let offlineDuration = now.timeIntervalSince(mutable.offlineMarkedAt ?? now)
            if offlineDuration < config.offlineGracePeriod {
                mutable.livenessState = .suspectOffline
                return mutable
            }

            mutable.livenessState = .offline
            return terminate(session: mutable, reason: reason, now: now)

        case .unknown:
            return mutable
        }
    }

    private func terminate(session: SessionModel, reason: SessionTerminationReason, now: Date) -> SessionModel {
        var terminated = session
        terminated.livenessState = .terminated
        terminated.terminationReason = reason
        terminated.cleanupDeadline = now.addingTimeInterval(config.terminatedHistoryRetention)
        terminated.offlineMarkedAt = nil

        if terminated.status == .processing || terminated.status == .waiting {
            terminated.status = .completed
            terminated.statusReason = reason.rawValue.uppercased()
            terminated.completedAt = now
            terminated.waitingSince = nil
        }

        return terminated
    }

    private func evaluate(session: SessionModel, snapshot: ProcessSnapshot) -> Evidence {
        let normalizedTTY = ProcessSnapshotProvider.normalizeTTY(session.terminalTTY)

        // shellPPID is Claude's own process — the authoritative liveness signal.
        // shellPID is the user's shell which outlives Claude, so it must be secondary.
        let claudePID = session.shellPPID
        let shellPID = session.shellPID ?? session.sourcePID

        // 1. If we know Claude's PID, check it first — when it's gone, the session is dead.
        if let claudePID, claudePID > 1 {
            guard snapshot.entriesByPID[claudePID] != nil else {
                return .missing(.processMissing)
            }
        }

        // 2. Cross-check the shell/source PID and TTY for additional validation.
        if let shellPID, shellPID > 1 {
            guard let processEntry = snapshot.entriesByPID[shellPID] else {
                return .missing(.processMissing)
            }

            if let normalizedTTY {
                guard let processTTY = ProcessSnapshotProvider.normalizeTTY(processEntry.tty),
                      processTTY == normalizedTTY else {
                    return .missing(.ttyMissing)
                }
            }

            return .alive
        }

        // 3. Fallback: TTY-only check when no PIDs are available.
        if let normalizedTTY {
            if snapshot.pidsByTTY[normalizedTTY]?.isEmpty == false {
                return .alive
            }
            return .missing(.ttyMissing)
        }

        return .unknown
    }
}
