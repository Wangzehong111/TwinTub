import Foundation

/// TwinTub global configuration center
///
/// This enum serves as a centralized configuration repository for all TwinTub components.
/// It provides type-safe access to network ports, timing intervals, and other constants.
///
/// ## Usage
///
/// ```swift
/// // Network configuration
/// let port = TwinTubConfig.serverPort
///
/// // Timing configuration
/// let interval = TwinTubConfig.livenessCheckInterval
///
/// // Environment variable override
/// // Set TWINTUB_PORT environment variable to override the default port
/// ```
public enum TwinTubConfig {
    // MARK: - Network Configuration

    /// Default HTTP server port for receiving hook events
    public static let defaultServerPort: UInt16 = 55771

    /// Actual server port to use (supports TWINTUB_PORT environment variable override)
    public static var serverPort: UInt16 {
        ProcessInfo.processInfo.environment["TWINTUB_PORT"].flatMap { UInt16($0) } ?? defaultServerPort
    }

    /// Timeout for hook bridge HTTP requests (seconds)
    public static let hookBridgeTimeout: TimeInterval = 0.2

    // MARK: - Event Processing Timing

    /// Interval for flushing coalesced events from EventBridge (seconds)
    public static let eventBridgeFlushInterval: TimeInterval = 0.1

    /// Throttle interval for SessionStore UI updates (seconds)
    public static let sessionStoreThrottleInterval: TimeInterval = 0.5

    /// Interval between liveness reconciliation checks (seconds)
    public static let livenessCheckInterval: TimeInterval = 5.0

    /// Duration to show "done" status before returning to idle (seconds)
    public static let doneVisibleDuration: TimeInterval = 5.0

    // MARK: - Session Liveness Configuration

    /// Grace period before marking a session as offline (seconds)
    ///
    /// This prevents false positives during short terminal jitter or
    /// temporary process table inconsistencies.
    public static let offlineGracePeriod: TimeInterval = 20

    /// Duration to retain terminated sessions in history (seconds)
    ///
    /// After this period, terminated sessions are permanently removed.
    public static let terminatedHistoryRetention: TimeInterval = 300

    /// Hard expiry time for sessions without heartbeat (seconds)
    ///
    /// Sessions that haven't received updates and have no liveness evidence
    /// are removed after this duration.
    public static let hardExpiry: TimeInterval = 1800

    // MARK: - Notification Configuration

    /// Silence window between duplicate waiting notifications (seconds)
    ///
    /// Prevents notification spam when a session is waiting for input.
    public static let notifySilenceWindow: TimeInterval = 120

    /// Time after which waiting notifications escalate (seconds)
    ///
    /// Notifications after this window are marked as "escalated" to indicate
    /// prolonged waiting time.
    public static let notifyEscalationWindow: TimeInterval = 180

    // MARK: - Context Window Configuration

    /// Default maximum context window size in tokens
    ///
    /// Claude Opus 4 and Sonnet 4 both support 200K token context windows.
    public static let defaultMaxContextTokens: Int = 200_000

    /// Default maximum context window size in bytes (for backward compatibility)
    ///
    /// Approximate conversion: 1 token ≈ 4 bytes.
    public static let defaultMaxContextBytes: Int = 800_000

    /// Ratio for converting tokens to bytes (1 token ≈ 4 chars)
    public static let tokenToBytesRatio: Int = 4

    // MARK: - UI Configuration

    /// Number of segments in the context usage progress bar
    public static let usageBarSegments: Int = 10

    /// Maximum characters to display in status reason
    public static let statusReasonMaxLength: Int = 24
}
