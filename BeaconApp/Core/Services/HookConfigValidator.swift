import Foundation

/// Validates that Claude Code settings.json has proper hooks configuration for Beacon
struct HookConfigValidator {

    // MARK: - Types

    struct ValidationResult {
        let isValid: Bool
        let missingHooks: [String]
        let hookScriptPath: String
        let hookScriptExists: Bool
        let settingsPath: String

        var hasIssues: Bool {
            return !missingHooks.isEmpty || !hookScriptExists
        }

        var summary: String {
            if !hookScriptExists {
                return "Hook script not found at \(hookScriptPath)"
            }
            if !missingHooks.isEmpty {
                return "Missing hooks: \(missingHooks.joined(separator: ", "))"
            }
            return "All hooks configured correctly"
        }
    }

    // MARK: - Constants

    /// Required hook event types for Beacon to function
    static let requiredHookEvents: Set<String> = [
        "UserPromptSubmit",
        "PostToolUse",
        "PermissionRequest",
        "Notification",
        "Stop",
        "SessionEnd"
    ]

    /// Path to the hook bridge script
    static var hookScriptPath: String {
        NSString(string: "~/.claude/hooks/beacon_hook_bridge.sh").expandingTildeInPath
    }

    /// Path to Claude Code settings.json
    static var settingsPath: String {
        NSString(string: "~/.claude/settings.json").expandingTildeInPath
    }

    // MARK: - Validation

    /// Validates the hooks configuration in settings.json
    static func validate() -> ValidationResult {
        let scriptPath = hookScriptPath
        let settingsURL = URL(fileURLWithPath: settingsPath)

        // Check if hook script exists
        let scriptExists = FileManager.default.fileExists(atPath: scriptPath)

        // Check settings.json
        guard let data = try? Data(contentsOf: settingsURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ValidationResult(
                isValid: false,
                missingHooks: Array(requiredHookEvents).sorted(),
                hookScriptPath: scriptPath,
                hookScriptExists: scriptExists,
                settingsPath: settingsPath
            )
        }

        // Extract hooks configuration
        guard let hooks = json["hooks"] as? [String: Any] else {
            return ValidationResult(
                isValid: false,
                missingHooks: Array(requiredHookEvents).sorted(),
                hookScriptPath: scriptPath,
                hookScriptExists: scriptExists,
                settingsPath: settingsPath
            )
        }

        // Check each required hook
        var missingHooks: [String] = []
        for event in requiredHookEvents {
            if !isHookConfigured(for: event, in: hooks, scriptPath: scriptPath) {
                missingHooks.append(event)
            }
        }

        return ValidationResult(
            isValid: missingHooks.isEmpty,
            missingHooks: missingHooks.sorted(),
            hookScriptPath: scriptPath,
            hookScriptExists: scriptExists,
            settingsPath: settingsPath
        )
    }

    /// Checks if a specific hook event is properly configured
    private static func isHookConfigured(for event: String, in hooks: [String: Any], scriptPath: String) -> Bool {
        guard let hookConfigs = hooks[event] as? [[String: Any]] else {
            return false
        }

        // Check if any hook config points to our script
        for config in hookConfigs {
            guard let hookList = config["hooks"] as? [[String: Any]] else {
                continue
            }
            for hook in hookList {
                if let type = hook["type"] as? String,
                   type == "command",
                   let command = hook["command"] as? String {
                    // Check if command references our script
                    if command.contains("beacon_hook_bridge.sh") {
                        return true
                    }
                }
            }
        }

        return false
    }

    // MARK: - Auto-Fix

    /// Attempts to automatically add missing hooks to settings.json
    /// Returns true if successful or no fix needed
    static func autoFix() -> Bool {
        let result = validate()

        // Nothing to fix
        if !result.hasIssues {
            return true
        }

        // Can't fix missing script
        if !result.hookScriptExists {
            NSLog("[Beacon] Cannot auto-fix: hook script not found at \(result.hookScriptPath)")
            return false
        }

        // Read current settings
        let settingsURL = URL(fileURLWithPath: result.settingsPath)
        guard let data = try? Data(contentsOf: settingsURL),
              var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            NSLog("[Beacon] Cannot auto-fix: failed to read settings.json")
            return false
        }

        // Build hooks configuration
        let hookCommand = "$HOME/.claude/hooks/beacon_hook_bridge.sh"
        var hooks = json["hooks"] as? [String: Any] ?? [:]

        // Add missing hooks
        for event in result.missingHooks {
            let hookConfig: [String: Any] = [
                "matcher": event == "UserPromptSubmit" ? "" : ".*",
                "hooks": [
                    ["type": "command", "command": hookCommand]
                ]
            ]
            hooks[event] = [hookConfig]
        }

        // Special case for Notification matcher
        if result.missingHooks.contains("Notification") {
            hooks["Notification"] = [
                [
                    "matcher": "permission_prompt|idle_prompt",
                    "hooks": [["type": "command", "command": hookCommand]]
                ]
            ]
        }

        // Special case for Stop (no matcher)
        if result.missingHooks.contains("Stop") {
            hooks["Stop"] = [
                ["hooks": [["type": "command", "command": hookCommand]]]
            ]
        }

        // Special case for UserPromptSubmit (empty matcher)
        if result.missingHooks.contains("UserPromptSubmit") {
            hooks["UserPromptSubmit"] = [
                ["matcher": "", "hooks": [["type": "command", "command": hookCommand]]]
            ]
        }

        json["hooks"] = hooks

        // Write back
        guard let updatedData = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]) else {
            NSLog("[Beacon] Cannot auto-fix: failed to serialize JSON")
            return false
        }

        do {
            try updatedData.write(to: settingsURL)
            NSLog("[Beacon] Auto-fixed settings.json: added hooks for \(result.missingHooks.joined(separator: ", "))")
            return true
        } catch {
            NSLog("[Beacon] Cannot auto-fix: failed to write settings.json: \(error)")
            return false
        }
    }
}
