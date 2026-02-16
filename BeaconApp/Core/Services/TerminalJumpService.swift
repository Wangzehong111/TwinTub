import AppKit
import Foundation

public final class TerminalJumpService {
    public enum Terminal: String, CaseIterable, Sendable {
        case terminalApp = "Terminal.app"
        case iTerm2 = "iTerm2"
        case warp = "Warp"
        case kaku = "Kaku"
        case cursor = "Cursor"
        case visualStudioCode = "Visual Studio Code"
    }

    public enum JumpTarget: String, CaseIterable, Identifiable, Sendable {
        case terminalApp
        case iTerm2
        case warp
        case kaku
        case cursor
        case visualStudioCode

        public var id: String { rawValue }

        public var displayName: String {
            switch self {
            case .terminalApp: return "Terminal.app"
            case .iTerm2: return "iTerm2"
            case .warp: return "Warp"
            case .kaku: return "Kaku"
            case .cursor: return "Cursor"
            case .visualStudioCode: return "VS Code"
            }
        }
    }

    public enum JumpOutcome: Equatable, Sendable {
        case success
        case needsManualSelection([JumpTarget], reason: String)
    }

    public init() {}

    public func jump(
        to session: SessionModel,
        executeOverride: ((JumpTarget, String, String) -> Bool)? = nil
    ) -> JumpOutcome {
        let cwd = session.cwd ?? NSHomeDirectory()
        let reason = "Source terminal unavailable. Please choose a target."
        let executor: (JumpTarget, String, String) -> Bool = executeOverride ?? { target, targetCwd, projectName in
            self.execute(target: target, cwd: targetCwd, projectName: projectName)
        }

        guard let target = resolveTarget(
            sourceApp: session.sourceApp,
            sourceBundleID: session.sourceBundleID
        ) else {
            return .needsManualSelection(Self.manualTargets, reason: reason)
        }

        if executor(target, cwd, session.projectName) {
            return .success
        }

        return .needsManualSelection(Self.manualTargets, reason: reason)
    }

    @discardableResult
    public func jump(cwd: String, projectName: String, forcedTarget: JumpTarget) -> Bool {
        execute(target: forcedTarget, cwd: cwd, projectName: projectName)
    }

    public func resolveTarget(sourceApp: String?, sourceBundleID: String?) -> JumpTarget? {
        if let sourceBundleID {
            let normalizedBundle = sourceBundleID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if let target = bundleMap[normalizedBundle] {
                return target
            }
        }

        if let sourceApp {
            let normalizedName = sourceApp.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if let target = appNameMap[normalizedName] {
                return target
            }
        }

        return nil
    }

    private static let manualTargets: [JumpTarget] = JumpTarget.allCases

    private let bundleMap: [String: JumpTarget] = [
        "com.apple.terminal": .terminalApp,
        "com.googlecode.iterm2": .iTerm2,
        "dev.warp.warp-stable": .warp,
        "dev.warp.warp": .warp,
        "com.kaku.app": .kaku,
        "com.todesktop.230313mzl4w4u92": .cursor,
        "com.microsoft.vscode": .visualStudioCode,
    ]

    private let appNameMap: [String: JumpTarget] = [
        "terminal.app": .terminalApp,
        "terminal": .terminalApp,
        "iterm2": .iTerm2,
        "warp": .warp,
        "kaku": .kaku,
        "cursor": .cursor,
        "visual studio code": .visualStudioCode,
        "code": .visualStudioCode,
    ]

    private func execute(target: JumpTarget, cwd: String, projectName: String) -> Bool {
        switch target {
        case .terminalApp:
            return executeTerminalApp(cwd: cwd)
        case .iTerm2:
            return executeITerm(cwd: cwd)
        case .warp:
            return executeWarp(cwd: cwd, projectName: projectName)
        case .kaku:
            return executeKaku(cwd: cwd)
        case .cursor:
            return executeCursorIDE(cwd: cwd)
        case .visualStudioCode:
            return executeVSCodeIDE(cwd: cwd)
        }
    }

    private func executeTerminalApp(cwd: String) -> Bool {
        let script = """
        tell application "Terminal"
            activate
            do script "cd \(shellQuote(cwd))"
        end tell
        """
        return runAppleScript(script)
    }

    private func executeITerm(cwd: String) -> Bool {
        let script = """
        tell application "iTerm2"
            activate
            if (count of windows) = 0 then
                create window with default profile
            end if
            tell current session of current window
                write text "cd \(shellQuote(cwd))"
            end tell
        end tell
        """
        return runAppleScript(script)
    }

    private func executeWarp(cwd: String, projectName: String) -> Bool {
        let encodedPath = cwd.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? cwd
        if let url = URL(string: "warp://open?path=\(encodedPath)&name=\(projectName)") {
            if NSWorkspace.shared.open(url) {
                return true
            }
        }
        return openApp(named: "Warp", cwd: cwd)
    }

    private func executeKaku(cwd: String) -> Bool {
        if runCommand(executable: "/usr/bin/env", arguments: ["kaku", cwd]) == 0 {
            return true
        }
        return openApp(named: "Kaku", cwd: cwd) || openApp(named: "kaku", cwd: cwd)
    }

    private func executeCursorIDE(cwd: String) -> Bool {
        if runCommand(executable: "/usr/bin/env", arguments: ["cursor", "--reuse-window", cwd]) == 0 {
            _ = sendCDCommandToIDE(appName: "Cursor", cwd: cwd)
            return true
        }

        if openApp(named: "Cursor", cwd: cwd) {
            _ = sendCDCommandToIDE(appName: "Cursor", cwd: cwd)
            return true
        }
        return false
    }

    private func executeVSCodeIDE(cwd: String) -> Bool {
        if runCommand(executable: "/usr/bin/env", arguments: ["code", "--reuse-window", cwd]) == 0 {
            _ = sendCDCommandToIDE(appName: "Visual Studio Code", cwd: cwd)
            return true
        }

        if openApp(named: "Visual Studio Code", cwd: cwd) {
            _ = sendCDCommandToIDE(appName: "Visual Studio Code", cwd: cwd)
            return true
        }
        return false
    }

    @discardableResult
    private func runAppleScript(_ source: String) -> Bool {
        guard let script = NSAppleScript(source: source) else {
            return false
        }
        var error: NSDictionary?
        script.executeAndReturnError(&error)
        return error == nil
    }

    @discardableResult
    private func runCommand(executable: String, arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        } catch {
            return -1
        }
    }

    private func openApp(named app: String, cwd: String) -> Bool {
        runCommand(executable: "/usr/bin/open", arguments: ["-a", app, cwd]) == 0
    }

    private func sendCDCommandToIDE(appName: String, cwd: String) -> Bool {
        let escapedPath = appleScriptEscape(shellQuote(cwd))
        let escapedAppName = appleScriptEscape(appName)

        let script = """
        tell application "\(escapedAppName)"
            activate
        end tell
        delay 0.2
        tell application "System Events"
            keystroke "`" using control down
            delay 0.08
            keystroke "cd \(escapedPath)"
            key code 36
        end tell
        """
        return runAppleScript(script)
    }

    private func appleScriptEscape(_ string: String) -> String {
        string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private func shellQuote(_ string: String) -> String {
        "'" + string.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }
}
