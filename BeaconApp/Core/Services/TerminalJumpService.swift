import AppKit
import Foundation

public final class TerminalJumpService {
    public enum Terminal: String, CaseIterable, Sendable {
        case terminalApp = "Terminal.app"
        case iTerm2 = "iTerm2"
        case warp = "Warp"
    }

    public init() {}

    @discardableResult
    public func jump(to session: SessionModel) -> Bool {
        let cwd = session.cwd ?? NSHomeDirectory()
        return jump(cwd: cwd, projectName: session.projectName)
    }

    @discardableResult
    public func jump(cwd: String, projectName: String) -> Bool {
        if executeTerminalApp(cwd: cwd) { return true }
        if executeITerm(cwd: cwd) { return true }
        if executeWarp(cwd: cwd, projectName: projectName) { return true }
        return false
    }

    private func executeTerminalApp(cwd: String) -> Bool {
        let script = """
        tell application "Terminal"
            activate
            do script "cd \(shellEscape(cwd))"
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
                write text "cd \(shellEscape(cwd))"
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

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", "Warp", cwd]

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
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

    private func shellEscape(_ string: String) -> String {
        string.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
