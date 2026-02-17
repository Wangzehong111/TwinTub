import Combine
import Foundation

@MainActor
public final class SessionStore: ObservableObject {
    @Published public private(set) var sessions: [SessionModel] = []
    @Published public private(set) var globalStatus: GlobalStatus = .idle

    public enum GlobalStatus: Equatable {
        case idle
        case processing(hasWaiting: Bool)
        case waiting(count: Int)
        case done
    }

    public typealias SourceResolver = @Sendable (Int) -> (sourceApp: String, sourceBundleID: String)?

    private var sessionMap: [String: SessionModel] = [:]
    private var doneVisibleUntil: Date?
    private let notificationService: NotificationDispatching
    private let livenessMonitor: SessionLivenessMonitor
    private let sourceResolver: SourceResolver?
    private let clock: () -> Date
    private let throttleInterval: TimeInterval
    private let livenessCheckInterval: TimeInterval
    private let livenessQueue = DispatchQueue(label: "twintub.liveness.queue", qos: .utility)
    private var livenessRevision: UInt64 = 0
    private var cancellables = Set<AnyCancellable>()
    private let sessionSubject = PassthroughSubject<[SessionModel], Never>()

    public init(
        notificationService: NotificationDispatching,
        livenessMonitor: SessionLivenessMonitor = SessionLivenessMonitor(),
        sourceResolver: SourceResolver? = nil,
        clock: @escaping () -> Date = Date.init,
        throttleInterval: TimeInterval = TwinTubConfig.sessionStoreThrottleInterval,
        livenessCheckInterval: TimeInterval = TwinTubConfig.livenessCheckInterval
    ) {
        self.notificationService = notificationService
        self.livenessMonitor = livenessMonitor
        self.sourceResolver = sourceResolver
        self.clock = clock
        self.throttleInterval = throttleInterval
        self.livenessCheckInterval = livenessCheckInterval

        if throttleInterval <= 0 {
            sessionSubject
                .sink { [weak self] values in
                    self?.sessions = values
                }
                .store(in: &cancellables)
        } else {
            sessionSubject
                .throttle(for: .seconds(throttleInterval), scheduler: RunLoop.main, latest: true)
                .sink { [weak self] values in
                    self?.sessions = values
                }
                .store(in: &cancellables)
        }

        notificationService.requestAuthorizationIfNeeded()

        if livenessCheckInterval > 0 {
            Timer.publish(every: livenessCheckInterval, tolerance: min(1.0, max(0.1, livenessCheckInterval * 0.2)), on: .main, in: .common)
                .autoconnect()
                .sink { [weak self] _ in
                    self?.reconcileLiveness()
                }
                .store(in: &cancellables)
        }
    }

    public func handle(event: TwinTubEvent) {
        handle(events: [event])
    }

    public func handle(events: [TwinTubEvent]) {
        guard !events.isEmpty else { return }

        var lastNow = clock()
        for event in events {
            let now = event.timestamp ?? clock()
            lastNow = now

            let current = sessionMap[event.sessionID]
            let mutation = SessionReducer.reduce(
                current: current,
                event: event,
                now: now,
                terminatedHistoryRetention: livenessMonitor.config.terminatedHistoryRetention
            )

            switch mutation {
            case let .upsert(next, decision):
                var finalModel: SessionModel
                if let decision {
                    finalModel = decision.session
                    handle(notificationDecision: decision)
                } else {
                    finalModel = next
                }
                backfillSourceIfNeeded(&finalModel)
                sessionMap[finalModel.id] = finalModel
                if event.event == .stop {
                    doneVisibleUntil = now.addingTimeInterval(TwinTubConfig.doneVisibleDuration)
                }

            case let .remove(sessionID):
                sessionMap.removeValue(forKey: sessionID)

            case .none:
                break
            }
        }

        pruneExpiredProcessingSessions(now: lastNow)
        publishSessions(now: lastNow)
    }

    public func reconcileLiveness(now: Date = Date()) {
        let revision = livenessRevision &+ 1
        livenessRevision = revision
        let snapshot = sessionMap
        let monitor = livenessMonitor

        livenessQueue.async { [weak self] in
            let reconciled = monitor.reconcile(sessionMap: snapshot, now: now)
            Task { @MainActor [weak self] in
                guard let self, self.livenessRevision == revision else { return }
                self.applyLivenessReconciliation(snapshot: snapshot, reconciled: reconciled, now: now)
            }
        }
    }

    /// Synchronous version for testing purposes
    public func reconcileLivenessSync(now: Date = Date()) {
        let snapshot = sessionMap
        let reconciled = livenessMonitor.reconcile(sessionMap: snapshot, now: now)
        applyLivenessReconciliation(snapshot: snapshot, reconciled: reconciled, now: now)
    }

    private func applyLivenessReconciliation(
        snapshot: [String: SessionModel],
        reconciled: [String: SessionModel],
        now: Date
    ) {
        // Detect newly terminated sessions and send notifications
        for (sessionID, nextModel) in reconciled {
            if let prevModel = snapshot[sessionID],
               prevModel.livenessState != .terminated,
               nextModel.livenessState == .terminated,
               let reason = nextModel.terminationReason {
                let decision = SessionReducer.NotificationDecision(
                    kind: .terminated(reason: reason),
                    session: nextModel
                )
                handle(notificationDecision: decision)
            }
        }

        sessionMap = reconciled
        pruneExpiredProcessingSessions(now: now)
        publishSessions(now: now)
    }

    public func pruneExpiredProcessingSessions(now: Date = Date()) {
        sessionMap = sessionMap.filter { _, session in
            if session.livenessState == .terminated {
                guard let deadline = session.cleanupDeadline else { return false }
                return deadline > now
            }

            if session.status == .processing &&
                now.timeIntervalSince(session.updatedAt) > livenessMonitor.config.hardExpiry {
                return false
            }

            if now.timeIntervalSince(session.updatedAt) > livenessMonitor.config.hardExpiry &&
                session.livenessState != .alive &&
                session.status != .waiting &&
                session.status != .processing {
                return false
            }

            return true
        }
    }

    public var lastActiveSession: SessionModel? {
        sessions.first(where: { $0.status == .waiting || $0.status == .processing }) ?? sessions.first
    }

    public func session(id: String) -> SessionModel? {
        sessionMap[id]
    }

    private func backfillSourceIfNeeded(_ model: inout SessionModel) {
        guard model.sourceApp == nil || model.sourceApp?.isEmpty == true else { return }
        guard let resolver = sourceResolver else { return }
        let pids = [model.shellPID, model.shellPPID, model.sourcePID].compactMap { $0 }
        for pid in pids {
            if let source = resolver(pid) {
                model.sourceApp = source.sourceApp
                model.sourceBundleID = source.sourceBundleID
                model.sourceFingerprint = SessionModel.buildSourceFingerprint(
                    sourceBundleID: model.sourceBundleID,
                    terminalTTY: model.terminalTTY,
                    shellPID: model.shellPID,
                    sourcePID: model.sourcePID
                )
                return
            }
        }
    }

    private func handle(notificationDecision: SessionReducer.NotificationDecision) {
        switch notificationDecision.kind {
        case let .waiting(escalated):
            notificationService.postWaiting(session: notificationDecision.session, escalated: escalated)
        case .completed:
            notificationService.postCompleted(session: notificationDecision.session)
        case let .terminated(reason):
            notificationService.postTerminated(session: notificationDecision.session, reason: reason)
        }
    }

    private func publishSessions(now: Date) {
        let sorted = sessionMap.values
            .filter { $0.status != .destroyed }
            .filter { $0.livenessState != .terminated }
            .sorted(by: Self.sortPredicate)

        sessionSubject.send(sorted)

        let waitingCount = sorted.filter { $0.status == .waiting }.count
        let hasProcessing = sorted.contains(where: { $0.status == .processing })

        // 新优先级：processing > waiting > done > idle
        if hasProcessing {
            globalStatus = .processing(hasWaiting: waitingCount > 0)
            return
        }

        if waitingCount > 0 {
            globalStatus = .waiting(count: waitingCount)
            return
        }

        if let doneVisibleUntil, doneVisibleUntil > now {
            globalStatus = .done
            return
        }

        globalStatus = .idle
    }

    private static func sortPredicate(lhs: SessionModel, rhs: SessionModel) -> Bool {
        if lhs.status.priority != rhs.status.priority {
            return lhs.status.priority < rhs.status.priority
        }

        if lhs.status == .completed, rhs.status == .completed {
            return (lhs.completedAt ?? lhs.updatedAt) > (rhs.completedAt ?? rhs.updatedAt)
        }

        return lhs.updatedAt > rhs.updatedAt
    }
}
