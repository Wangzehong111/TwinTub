import Foundation

public enum BeaconEventType: String, Codable, CaseIterable, Sendable {
    case userPromptSubmit = "UserPromptSubmit"
    case postToolUse = "PostToolUse"
    case permissionRequest = "PermissionRequest"
    case notification = "Notification"
    case stop = "Stop"
    case sessionEnd = "SessionEnd"
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
        projectName: String? = nil
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
    }
}

extension JSONDecoder {
    static let beaconEventDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
