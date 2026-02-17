import Foundation

public enum BeaconEventType: String, Codable, CaseIterable, Sendable {
    case userPromptSubmit = "UserPromptSubmit"
    case postToolUse = "PostToolUse"
    case permissionRequest = "PermissionRequest"
    case notification = "Notification"
    case stop = "Stop"
    case sessionEnd = "SessionEnd"

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        let normalized = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")

        switch normalized {
        case "userpromptsubmit", "user_prompt_submit":
            self = .userPromptSubmit
        case "posttooluse", "post_tool_use":
            self = .postToolUse
        case "pretooluse", "pre_tool_use":
            // Pre-tool callbacks also indicate active processing.
            self = .postToolUse
        case "permissionrequest", "permission_request":
            self = .permissionRequest
        case "notification":
            self = .notification
        case "stop":
            self = .stop
        case "sessionend", "session_end", "subagentstop", "subagent_stop":
            self = .sessionEnd
        default:
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported event type: \(raw)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct BeaconEvent: Codable, Equatable, Sendable {
    public let event: BeaconEventType
    public let sessionID: String
    public let timestamp: Date?
    public let cwd: String?
    public let prompt: String?
    public let toolName: String?
    public let message: String?
    public let notificationType: String?
    public let usageBytes: Int?
    public let projectName: String?
    public let sourceApp: String?
    public let sourceBundleID: String?
    public let sourcePID: Int?
    public let sourceConfidence: SourceConfidence?
    public let shellPID: Int?
    public let shellPPID: Int?
    public let terminalTTY: String?
    public let terminalSessionID: String?
    public let terminalWindowID: String?
    public let terminalPaneID: String?
    public let heartbeatID: String?
    public let eventSeq: Int?
    public let maxContextBytes: Int?

    enum CodingKeys: String, CodingKey {
        case event
        case sessionID = "session_id"
        case timestamp
        case cwd
        case prompt
        case toolName = "tool_name"
        case message
        case notificationType = "notification_type"
        case usageBytes = "usage_bytes"
        case projectName = "project_name"
        case sourceApp = "source_app"
        case sourceBundleID = "source_bundle_id"
        case sourcePID = "source_pid"
        case sourceConfidence = "source_confidence"
        case shellPID = "shell_pid"
        case shellPPID = "shell_ppid"
        case terminalTTY = "terminal_tty"
        case terminalSessionID = "terminal_session_id"
        case terminalWindowID = "terminal_window_id"
        case terminalPaneID = "terminal_pane_id"
        case heartbeatID = "heartbeat_id"
        case eventSeq = "event_seq"
        case maxContextBytes = "max_context_bytes"
    }

    public init(
        event: BeaconEventType,
        sessionID: String,
        timestamp: Date? = nil,
        cwd: String? = nil,
        prompt: String? = nil,
        toolName: String? = nil,
        message: String? = nil,
        notificationType: String? = nil,
        usageBytes: Int? = nil,
        projectName: String? = nil,
        sourceApp: String? = nil,
        sourceBundleID: String? = nil,
        sourcePID: Int? = nil,
        sourceConfidence: SourceConfidence? = nil,
        shellPID: Int? = nil,
        shellPPID: Int? = nil,
        terminalTTY: String? = nil,
        terminalSessionID: String? = nil,
        terminalWindowID: String? = nil,
        terminalPaneID: String? = nil,
        heartbeatID: String? = nil,
        eventSeq: Int? = nil,
        maxContextBytes: Int? = nil
    ) {
        self.event = event
        self.sessionID = sessionID
        self.timestamp = timestamp
        self.cwd = cwd
        self.prompt = prompt
        self.toolName = toolName
        self.message = message
        self.notificationType = notificationType
        self.usageBytes = usageBytes
        self.projectName = projectName
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
        self.heartbeatID = heartbeatID
        self.eventSeq = eventSeq
        self.maxContextBytes = maxContextBytes
    }
}

extension JSONDecoder {
    static let beaconEventDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
