import Foundation

public enum SessionStatus: String, Codable, CaseIterable, Sendable {
    case waiting
    case processing
    case completed
    case destroyed

    var priority: Int {
        switch self {
        case .waiting: return 0
        case .processing: return 1
        case .completed: return 2
        case .destroyed: return 3
        }
    }
}

public struct SessionModel: Identifiable, Equatable, Sendable {
    public let id: String
    public var projectName: String
    public var cwd: String?
    public var status: SessionStatus
    public var statusReason: String?
    public var usageBytes: Int
    public var usageSegments: Int
    public var updatedAt: Date
    public var completedAt: Date?
    public var waitingSince: Date?
    public var lastWaitingNotificationAt: Date?
    public var notificationRepeatCount: Int

    public init(
        id: String,
        projectName: String,
        cwd: String?,
        status: SessionStatus,
        statusReason: String?,
        usageBytes: Int,
        usageSegments: Int,
        updatedAt: Date,
        completedAt: Date? = nil,
        waitingSince: Date? = nil,
        lastWaitingNotificationAt: Date? = nil,
        notificationRepeatCount: Int = 0
    ) {
        self.id = id
        self.projectName = projectName
        self.cwd = cwd
        self.status = status
        self.statusReason = statusReason
        self.usageBytes = usageBytes
        self.usageSegments = usageSegments
        self.updatedAt = updatedAt
        self.completedAt = completedAt
        self.waitingSince = waitingSince
        self.lastWaitingNotificationAt = lastWaitingNotificationAt
        self.notificationRepeatCount = notificationRepeatCount
    }

    public var displayStatusLine: String {
        switch status {
        case .processing:
            return "> \((statusReason ?? "PROCESSING").uppercased())"
        case .waiting:
            return "> \((statusReason ?? "WAITING_FOR_INPUT").uppercased())"
        case .completed:
            return "> DONE"
        case .destroyed:
            return "> DESTROYED"
        }
    }

    public static func segments(for usageBytes: Int, maxContextBytes: Int = 1_000_000) -> Int {
        guard usageBytes > 0 else { return 0 }
        let ratio = min(Double(usageBytes) / Double(maxContextBytes), 1.0)
        return min(10, max(1, Int(ceil(ratio * 10))))
    }
}
