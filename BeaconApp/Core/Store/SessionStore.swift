import Combine
import Foundation

@MainActor
public final class SessionStore: ObservableObject {
    @Published public private(set) var sessions: [SessionModel] = []
    @Published public private(set) var globalStatus: GlobalStatus = .idle

    public enum GlobalStatus: Equatable {
        case idle
        case processing
        case waiting(count: Int)
        case done
    }

    private var sessionMap: [String: SessionModel] = [:]
    private var doneVisibleUntil: Date?
    private let notificationService: NotificationDispatching
    private let clock: () -> Date
    private let throttleInterval: TimeInterval
    private var cancellables = Set<AnyCancellable>()
    private let sessionSubject = PassthroughSubject<[SessionModel], Never>()

    public init(
        notificationService: NotificationDispatching,
        clock: @escaping () -> Date = Date.init,
        throttleInterval: TimeInterval = 0.5
    ) {
        self.notificationService = notificationService
        self.clock = clock
        self.throttleInterval = throttleInterval

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
    }

    public func handle(event: BeaconEvent) {
        let now = event.timestamp ?? clock()
        let current = sessionMap[event.sessionID]
        let mutation = SessionReducer.reduce(current: current, event: event, now: now)

        switch mutation {
        case let .upsert(next, decision):
            let finalModel: SessionModel
            if let decision {
                finalModel = decision.session
                handle(notificationDecision: decision)
            } else {
                finalModel = next
            }
            sessionMap[finalModel.id] = finalModel
            if event.event == .stop {
                doneVisibleUntil = now.addingTimeInterval(5)
            }

        case let .remove(sessionID):
            sessionMap.removeValue(forKey: sessionID)

        case .none:
            break
        }

        pruneExpiredProcessingSessions(now: now)
        publishSessions(now: now)
    }

    public func pruneExpiredProcessingSessions(now: Date = Date()) {
        sessionMap = sessionMap.filter { _, session in
            !(session.status == .processing && now.timeIntervalSince(session.updatedAt) > 1800)
        }
    }

    public var lastActiveSession: SessionModel? {
        sessions.first(where: { $0.status == .waiting || $0.status == .processing }) ?? sessions.first
    }

    public func session(id: String) -> SessionModel? {
        sessionMap[id]
    }

    private func handle(notificationDecision: SessionReducer.NotificationDecision) {
        switch notificationDecision.kind {
        case let .waiting(escalated):
            notificationService.postWaiting(session: notificationDecision.session, escalated: escalated)
        case .completed:
            notificationService.postCompleted(session: notificationDecision.session)
        }
    }

    private func publishSessions(now: Date) {
        let sorted = sessionMap.values
            .filter { $0.status != .destroyed }
            .sorted(by: Self.sortPredicate)

        sessionSubject.send(sorted)

        let waitingCount = sorted.filter { $0.status == .waiting }.count
        if waitingCount > 0 {
            globalStatus = .waiting(count: waitingCount)
            return
        }

        if sorted.contains(where: { $0.status == .processing }) {
            globalStatus = .processing
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
