import AppKit
import Foundation
import UserNotifications

extension UNAuthorizationStatus {
    var name: String {
        switch self {
        case .notDetermined: return "notDetermined"
        case .denied: return "denied"
        case .authorized: return "authorized"
        case .provisional: return "provisional"
        case .ephemeral: return "ephemeral"
        @unknown default: return "unknown"
        }
    }
}

/// Notification click handler callback type
public typealias NotificationClickHandler = (String) -> Void

public protocol NotificationDispatching {
    func requestAuthorizationIfNeeded()
    func postWaiting(session: SessionModel, escalated: Bool)
    func postCompleted(session: SessionModel)
    func postTerminated(session: SessionModel, reason: SessionTerminationReason)
}

protocol NotificationSending {
    func send(title: String, body: String, sound: String, sessionID: String?)
}

protocol NotificationAuthorizationRequesting {
    func requestAuthorizationIfNeeded()
}

/// Delegate for handling notification clicks
final class NotificationCenterDelegate: NSObject, @unchecked Sendable, UNUserNotificationCenterDelegate {
    var onNotificationClick: NotificationClickHandler?

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        // Synchronously set activationPolicy to prevent Dock icon from appearing
        // This must be done synchronously because the app activation happens immediately
        if Thread.isMainThread {
            NSApp.setActivationPolicy(.accessory)
            NSApp.deactivate()
        } else {
            DispatchQueue.main.sync {
                NSApp.setActivationPolicy(.accessory)
                NSApp.deactivate()
            }
        }

        let userInfo = response.notification.request.content.userInfo
        if let sessionID = userInfo["session_id"] as? String {
            NSLog("[TwinTub] Notification clicked for session: \(sessionID)")
            onNotificationClick?(sessionID)
        }
        completionHandler()

        // Double-check to ensure Dock icon doesn't appear
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
    }
}

/// Uses UNUserNotificationCenter for first-class system notifications,
/// and falls back to AppleScript when permission is denied/unavailable.
final class UserNotificationCenterSender: @unchecked Sendable, NotificationSending, NotificationAuthorizationRequesting {
    private let center: UNUserNotificationCenter
    private let fallback: NotificationSending
    private let queue = DispatchQueue(label: "twintub.notification.center", qos: .utility)
    private var authorizationRequested = false

    init(
        center: UNUserNotificationCenter = .current(),
        fallback: NotificationSending
    ) {
        self.center = center
        self.fallback = fallback
    }

    func requestAuthorizationIfNeeded() {
        queue.async { [weak self] in
            guard let self, !self.authorizationRequested else { return }
            self.authorizationRequested = true
            self.center.getNotificationSettings { settings in
                guard settings.authorizationStatus == .notDetermined else { return }
                self.center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in
                    // Best effort: ignore failures and fallback when posting.
                }
            }
        }
    }

    func send(title: String, body: String, sound: String, sessionID: String?) {
        center.getNotificationSettings { [weak self] settings in
            guard let self else { return }
            let status = settings.authorizationStatus
            NSLog("[TwinTub] Notification authorization status: \(status.rawValue) (\(status.name))")
            switch status {
            case .authorized, .provisional, .ephemeral:
                NSLog("[TwinTub] Posting via UNUserNotificationCenter")
                self.postViaUserNotifications(title: title, body: body, sound: sound, sessionID: sessionID)
            case .notDetermined:
                NSLog("[TwinTub] Authorization not determined, requesting...")
                self.center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                    if granted {
                        NSLog("[TwinTub] Authorization granted, posting via UNUserNotificationCenter")
                        self.postViaUserNotifications(title: title, body: body, sound: sound, sessionID: sessionID)
                    } else {
                        NSLog("[TwinTub] Authorization denied, falling back to AppleScript")
                        self.fallback.send(title: title, body: body, sound: sound, sessionID: sessionID)
                    }
                }
            case .denied:
                NSLog("[TwinTub] Authorization denied, falling back to AppleScript")
                self.fallback.send(title: title, body: body, sound: sound, sessionID: sessionID)
            @unknown default:
                NSLog("[TwinTub] Unknown authorization status, falling back to AppleScript")
                self.fallback.send(title: title, body: body, sound: sound, sessionID: sessionID)
            }
        }
    }

    private func postViaUserNotifications(title: String, body: String, sound: String, sessionID: String?) {
        // Temporarily switch to .regular to ensure notification shows correct app icon
        // because LSUIElement = true apps may not display correct notification icon
        let shouldRestorePolicy = DispatchQueue.main.sync { () -> Bool in
            if NSApp.activationPolicy() == .accessory {
                NSApp.setActivationPolicy(.regular)
                return true
            }
            return false
        }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        if sound == "default" {
            content.sound = .default
        }
        // Store session ID in userInfo for click handling
        if let sessionID {
            content.userInfo = ["session_id": sessionID]
        }

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        center.add(request) { [weak self, shouldRestorePolicy] error in
            // Restore to .accessory after notification is sent
            if shouldRestorePolicy {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    NSApp.setActivationPolicy(.accessory)
                }
            }

            guard let self, let error else { return }
            NSLog("[TwinTub] UNUserNotificationCenter failed: \(error), falling back to AppleScript")
            self.fallback.send(title: title, body: body, sound: sound, sessionID: sessionID)
        }
    }
}

/// Runs `display notification` via NSAppleScript within the current process.
/// Because the script executes inside TwinTub's process, macOS attributes the
/// notification to TwinTub and shows TwinTub's app icon.
final class InProcessAppleScriptSender: NotificationSending {
    private let fallbackQueue = DispatchQueue(label: "twintub.notification.fallback", qos: .utility)

    func send(title: String, body: String, sound: String, sessionID: String?) {
        let escaped = (
            title: Self.escape(title),
            body: Self.escape(body),
            sound: Self.escape(sound)
        )
        let source = "display notification \"\(escaped.body)\" with title \"\(escaped.title)\" sound name \"\(escaped.sound)\""
        if !runInProcess(source: source) {
            runFallbackViaOSAScript(source: source)
        }
    }

    static func escape(_ string: String) -> String {
        string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private func runInProcess(source: String) -> Bool {
        var succeeded = false
        let executeBlock = {
            var error: NSDictionary?
            _ = NSAppleScript(source: source)?.executeAndReturnError(&error)
            succeeded = (error == nil)
        }

        if Thread.isMainThread {
            executeBlock()
        } else {
            DispatchQueue.main.sync(execute: executeBlock)
        }

        return succeeded
    }

    private func runFallbackViaOSAScript(source: String) {
        fallbackQueue.async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", source]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                // Best-effort notification path.
            }
        }
    }
}

public final class NotificationService: NotificationDispatching {
    private let sender: NotificationSending
    private let notificationCenterDelegate: NotificationCenterDelegate

    /// Callback when a notification is clicked with the session ID
    public var onNotificationClick: NotificationClickHandler? {
        get { notificationCenterDelegate.onNotificationClick }
        set { notificationCenterDelegate.onNotificationClick = newValue }
    }

    public init() {
        let appleScriptFallback = InProcessAppleScriptSender()
        let delegate = NotificationCenterDelegate()
        self.notificationCenterDelegate = delegate

        // Set up the delegate for notification click handling
        let center = UNUserNotificationCenter.current()
        center.delegate = delegate

        self.sender = UserNotificationCenterSender(center: center, fallback: appleScriptFallback)
    }

    init(sender: NotificationSending, delegate: NotificationCenterDelegate = NotificationCenterDelegate()) {
        self.sender = sender
        self.notificationCenterDelegate = delegate
    }

    public func requestAuthorizationIfNeeded() {
        (sender as? NotificationAuthorizationRequesting)?.requestAuthorizationIfNeeded()
    }

    public func postWaiting(session: SessionModel, escalated: Bool) {
        let title = escalated ? "TwinTub Escalation" : "TwinTub Waiting"
        let body = "\(session.projectName) requires input: \(session.statusReason ?? "WAITING_FOR_INPUT")"
        sender.send(title: title, body: body, sound: "default", sessionID: session.id)
    }

    public func postCompleted(session: SessionModel) {
        sender.send(title: "TwinTub Done", body: "\(session.projectName) completed", sound: "default", sessionID: session.id)
    }

    public func postTerminated(session: SessionModel, reason: SessionTerminationReason) {
        sender.send(
            title: "TwinTub Session Ended",
            body: "\(session.projectName) session ended: \(reason.displayName)",
            sound: "default",
            sessionID: session.id
        )
    }
}

public final class NoopNotificationService: NotificationDispatching {
    public init() {}
    public func requestAuthorizationIfNeeded() {}
    public func postWaiting(session: SessionModel, escalated: Bool) {}
    public func postCompleted(session: SessionModel) {}
    public func postTerminated(session: SessionModel, reason: SessionTerminationReason) {}
}
