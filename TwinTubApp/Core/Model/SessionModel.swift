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

    public var displayName: String {
        switch self {
        case .sessionEndEvent:
            return "Session ended normally"
        case .processMissing:
            return "Process not found"
        case .ttyMissing:
            return "Terminal disconnected"
        case .heartbeatTimeout:
            return "Session timed out"
        case .manual:
            return "Manually terminated"
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
    public var usageTokens: Int
    public var maxContextTokens: Int
    public var model: String?
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
    public var maxContextBytes: Int

    // 固定的上下文窗口大小（200K tokens，自动压缩阈值 95%）
    public static let defaultMaxContextTokens = 200_000

    public init(
        id: String,
        projectName: String,
        cwd: String?,
        status: SessionStatus,
        statusReason: String?,
        usageBytes: Int,
        usageTokens: Int,
        maxContextTokens: Int = defaultMaxContextTokens,
        model: String? = nil,
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
        sourceFingerprint: String? = nil,
        maxContextBytes: Int = 800_000
    ) {
        self.id = id
        self.projectName = projectName
        self.cwd = cwd
        self.status = status
        self.statusReason = statusReason
        self.usageBytes = usageBytes
        self.usageTokens = usageTokens
        self.maxContextTokens = maxContextTokens
        self.model = model
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
        self.maxContextBytes = maxContextBytes
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

    // 200K tokens ≈ 800,000 bytes (1 token ≈ 4 chars) - 保留用于向后兼容
    public static func segments(for usageBytes: Int, maxContextBytes: Int = 800_000) -> Int {
        guard usageBytes > 0 else { return 0 }
        let ratio = min(Double(usageBytes) / Double(maxContextBytes), 1.0)
        return min(10, max(1, Int(ceil(ratio * 10))))
    }

    /// 基于 token 数计算进度条段数（推荐使用）
    /// - Parameters:
    ///   - usageTokens: 当前使用的 token 数
    ///   - maxContextTokens: 上下文窗口最大 token 数（默认 200K）
    /// - Returns: 0-10 的段数
    public static func segmentsForTokens(_ usageTokens: Int, maxContextTokens: Int = defaultMaxContextTokens) -> Int {
        guard usageTokens > 0 else { return 0 }
        let ratio = min(Double(usageTokens) / Double(maxContextTokens), 1.0)
        return min(10, max(1, Int(ceil(ratio * 10))))
    }

    /// 根据模型名推断上下文窗口大小
    /// - Parameter modelName: 模型名称（如 "claude-opus-4-20250514", "claude-sonnet-4-20250514"）
    /// - Returns: 该模型的上下文窗口 token 数
    public static func maxContextTokens(for modelName: String?) -> Int {
        guard let modelName = modelName?.lowercased() else {
            return defaultMaxContextTokens
        }

        // Claude Opus 4 和 Sonnet 4 都是 200K
        if modelName.contains("opus") || modelName.contains("sonnet") {
            return 200_000
        }
        // Claude Haiku 3.5 约 128K
        if modelName.contains("haiku") {
            return 128_000
        }
        // 默认 200K
        return defaultMaxContextTokens
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
