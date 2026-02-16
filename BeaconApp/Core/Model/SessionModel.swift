import Foundation

public enum SourceConfidence: String, Codable, CaseIterable, Sendable {
    case high
    case medium
    case low
    case unknown

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = (try? container.decode(String.self))?.lowercased() ?? ""
        self = SourceConfidence(rawValue: raw) ?? .unknown
    }
}

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

public enum SessionLivenessState: String, Codable, CaseIterable, Sendable {
    case alive
    case suspectOffline
    case offline
    case terminated
}

public enum SessionTerminationReason: String, Codable, CaseIterable, Sendable {
    case sessionEndEvent
    case processMissing
    case ttyMissing
    case heartbeatTimeout
    case manual
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
    public var sourceApp: String?
    public var sourceBundleID: String?
    public var sourcePID: Int?
    public var sourceConfidence: SourceConfidence
    public var shellPID: Int?
    public var shellPPID: Int?
    public var terminalTTY: String?
    public var terminalSessionID: String?
    public var terminalWindowID: String?
    public var terminalPaneID: String?
    public var livenessState: SessionLivenessState
    public var lastSeenAliveAt: Date?
    public var offlineMarkedAt: Date?
    public var cleanupDeadline: Date?
    public var terminationReason: SessionTerminationReason?
    public var sourceFingerprint: String?

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
        notificationRepeatCount: Int = 0,
        sourceApp: String? = nil,
        sourceBundleID: String? = nil,
        sourcePID: Int? = nil,
        sourceConfidence: SourceConfidence = .unknown,
        shellPID: Int? = nil,
        shellPPID: Int? = nil,
        terminalTTY: String? = nil,
        terminalSessionID: String? = nil,
        terminalWindowID: String? = nil,
        terminalPaneID: String? = nil,
        livenessState: SessionLivenessState = .alive,
        lastSeenAliveAt: Date? = nil,
        offlineMarkedAt: Date? = nil,
        cleanupDeadline: Date? = nil,
        terminationReason: SessionTerminationReason? = nil,
        sourceFingerprint: String? = nil
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
        self.sourceApp = sourceApp
        self.sourceBundleID = sourceBundleID
        self.sourcePID = sourcePID
        self.sourceConfidence = sourceConfidence
        self.shellPID = shellPID
        self.shellPPID = shellPPID
        self.terminalTTY = terminalTTY
        self.terminalSessionID = terminalSessionID
        self.terminalWindowID = terminalWindowID
        self.terminalPaneID = terminalPaneID
        self.livenessState = livenessState
        self.lastSeenAliveAt = lastSeenAliveAt
        self.offlineMarkedAt = offlineMarkedAt
        self.cleanupDeadline = cleanupDeadline
        self.terminationReason = terminationReason
        self.sourceFingerprint = sourceFingerprint
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

    public var sourceDisplayLine: String? {
        guard sourceApp != nil || terminalTTY != nil || terminalSessionID != nil else {
            return nil
        }

        var pieces: [String] = []
        if let sourceApp, !sourceApp.isEmpty {
            pieces.append(sourceApp)
        }

        if let terminalTTY, !terminalTTY.isEmpty {
            pieces.append(terminalTTY)
        } else if let terminalSessionID, !terminalSessionID.isEmpty {
            pieces.append(terminalSessionID)
        }

        return pieces.joined(separator: " · ")
    }

    public static func buildSourceFingerprint(
        sourceBundleID: String?,
        terminalTTY: String?,
        shellPID: Int?,
        sourcePID: Int?
    ) -> String? {
        let bundle = sourceBundleID?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        let tty = terminalTTY?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        let pid = shellPID ?? sourcePID ?? 0
        guard !bundle.isEmpty || !tty.isEmpty || pid > 0 else {
            return nil
        }
        return "\(bundle)|\(tty)|\(pid)"
    }
}
