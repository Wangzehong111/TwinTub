import AppKit
import Foundation

public final class TerminalJumpService {
    public enum Terminal: String, CaseIterable, Sendable {
        case terminalApp = "Terminal.app"
        case iTerm2 = "iTerm2"
        case warp = "Warp"
        case ghostty = "Ghostty"
        case wezTerm = "WezTerm"
        case kitty = "Kitty"
        case alacritty = "Alacritty"
        case tabby = "Tabby"
        case hyper = "Hyper"
        case rio = "Rio"
        case kaku = "Kaku"
        case cursor = "Cursor"
        case visualStudioCode = "Visual Studio Code"
        case zed = "Zed"
    }

    public enum JumpTarget: String, CaseIterable, Identifiable, Sendable {
        case terminalApp
        case iTerm2
        case warp
        case ghostty
        case wezTerm
        case kitty
        case alacritty
        case tabby
        case hyper
        case rio
        case kaku
        case cursor
        case visualStudioCode
        case zed

        public var id: String { rawValue }

        public var displayName: String {
            switch self {
            case .terminalApp: return "Terminal.app"
            case .iTerm2: return "iTerm2"
            case .warp: return "Warp"
            case .ghostty: return "Ghostty"
            case .wezTerm: return "WezTerm"
            case .kitty: return "Kitty"
            case .alacritty: return "Alacritty"
            case .tabby: return "Tabby"
            case .hyper: return "Hyper"
            case .rio: return "Rio"
            case .kaku: return "Kaku"
            case .cursor: return "Cursor"
            case .visualStudioCode: return "VS Code"
            case .zed: return "Zed"
            }
        }
    }

    public enum JumpOutcome: Equatable, Sendable {
        case success
        case needsManualSelection([JumpTarget], reason: String)
    }

    enum OpenStrategy: Sendable {
        case cli(binary: String, argsTemplate: [String])
        case url(template: String)
        case openBundle(bundleID: String, passCwdAsPath: Bool)
        case openAppName(String, passCwdAsPath: Bool)
        case appleScript(String)
    }

    struct TerminalDescriptor: Sendable {
        let target: JumpTarget
        let displayName: String
        let bundleIDs: [String]
        let appNameAliases: [String]
        let executableAliases: [String]
        let urlSchemes: [String]
        let supportsTTYFocus: Bool
        let supportsWindowTabFocus: Bool
        let openStrategies: [OpenStrategy]
    }

    public init() {}

    /// Walks the process tree from `pid` upward and returns the first matching terminal's
    /// sourceApp + sourceBundleID. Suitable as `SessionStore.SourceResolver`.
    public func resolveSourceFromPID(_ pid: Int) -> (sourceApp: String, sourceBundleID: String)? {
        guard let target = walkProcessTreeForTerminal(startPID: pid),
              let descriptor = Self.registry[target] else {
            return nil
        }
        return (sourceApp: descriptor.displayName, sourceBundleID: descriptor.bundleIDs.first ?? "")
    }

    public func jump(
        to session: SessionModel,
        executeOverride: ((JumpTarget, String, String) -> Bool)? = nil
    ) -> JumpOutcome {
        let cwd = session.cwd ?? NSHomeDirectory()
        let reasonUnknown = "Unable to identify source terminal. Please choose a target."

        let executor: (JumpTarget, String, String) -> Bool = executeOverride ?? { target, targetCwd, projectName in
            self.execute(target: target, session: session, cwd: targetCwd, projectName: projectName)
        }

        guard let target = resolveTarget(sourceApp: session.sourceApp, sourceBundleID: session.sourceBundleID)
                ?? inferTargetFromProcessTree(session: session) else {
            if tryFocusKnownTerminalSessionWithoutSource(session) {
                return .success
            }
            return .needsManualSelection(manualTargets(), reason: reasonUnknown)
        }

        if executor(target, cwd, session.projectName) {
            return .success
        }

        let reasonKnown = "Recognized source as \(target.displayName), but could not focus/open it. Please choose a target."
        return .needsManualSelection(manualTargets(), reason: reasonKnown)
    }

    @discardableResult
    public func jump(cwd: String, projectName: String, forcedTarget: JumpTarget) -> Bool {
        execute(target: forcedTarget, session: nil, cwd: cwd, projectName: projectName)
    }

    @discardableResult
    public func jump(session: SessionModel, forcedTarget: JumpTarget) -> Bool {
        let cwd = session.cwd ?? NSHomeDirectory()
        return execute(target: forcedTarget, session: session, cwd: cwd, projectName: session.projectName)
    }

    public func resolveTarget(sourceApp: String?, sourceBundleID: String?) -> JumpTarget? {
        if let sourceBundleID {
            let normalizedBundle = Self.normalizedLookupKey(sourceBundleID)
            if let target = Self.bundleLookup[normalizedBundle] {
                return target
            }
        }

        if let sourceApp {
            let normalizedName = Self.normalizedLookupKey(sourceApp)
            if let target = Self.appNameLookup[normalizedName] {
                return target
            }

            // Weak executable/path based matching, e.g. "/Applications/Ghostty.app/..."
            let leaf = URL(fileURLWithPath: sourceApp).lastPathComponent
            if !leaf.isEmpty {
                let normalizedLeaf = Self.normalizedLookupKey(leaf)
                if let target = Self.executableLookup[normalizedLeaf] {
                    return target
                }
            }
        }

        return nil
    }

    private static let registry: [JumpTarget: TerminalDescriptor] = {
        let commonFocusFreeStrategies: [OpenStrategy] = []

        func d(
            _ target: JumpTarget,
            _ displayName: String,
            bundleIDs: [String],
            appNames: [String],
            executables: [String],
            urlSchemes: [String] = [],
            ttyFocus: Bool = false,
            windowTabFocus: Bool = false,
            open: [OpenStrategy]
        ) -> TerminalDescriptor {
            TerminalDescriptor(
                target: target,
                displayName: displayName,
                bundleIDs: bundleIDs,
                appNameAliases: appNames,
                executableAliases: executables,
                urlSchemes: urlSchemes,
                supportsTTYFocus: ttyFocus,
                supportsWindowTabFocus: windowTabFocus,
                openStrategies: open
            )
        }

        return [
            .terminalApp: d(
                .terminalApp,
                "Terminal.app",
                bundleIDs: ["com.apple.terminal"],
                appNames: ["terminal", "terminal.app"],
                executables: ["terminal"],
                ttyFocus: true,
                windowTabFocus: true,
                open: commonFocusFreeStrategies
            ),
            .iTerm2: d(
                .iTerm2,
                "iTerm2",
                bundleIDs: ["com.googlecode.iterm2"],
                appNames: ["iterm2", "iterm", "iterm.app"],
                executables: ["iterm2", "iterm"],
                ttyFocus: true,
                windowTabFocus: true,
                open: commonFocusFreeStrategies
            ),
            .warp: d(
                .warp,
                "Warp",
                bundleIDs: ["dev.warp.warp-stable", "dev.warp.warp", "dev.warp.warpstable"],
                appNames: ["warp"],
                executables: ["warp", "stable"],
                urlSchemes: ["warp"],
                open: [
                    .url(template: "warp://open?path={{cwd_url}}&name={{project_url}}"),
                    .openBundle(bundleID: "dev.warp.warp-stable", passCwdAsPath: true),
                    .openBundle(bundleID: "dev.warp.warp", passCwdAsPath: true),
                    .openAppName("Warp", passCwdAsPath: true)
                ]
            ),
            .ghostty: d(
                .ghostty,
                "Ghostty",
                bundleIDs: ["com.mitchellh.ghostty"],
                appNames: ["ghostty"],
                executables: ["ghostty"],
                open: [
                    .cli(binary: "ghostty", argsTemplate: ["--working-directory={{cwd}}"]),
                    .openBundle(bundleID: "com.mitchellh.ghostty", passCwdAsPath: true),
                    .openAppName("Ghostty", passCwdAsPath: true)
                ]
            ),
            .wezTerm: d(
                .wezTerm,
                "WezTerm",
                bundleIDs: ["com.github.wez.wezterm"],
                appNames: ["wezterm"],
                executables: ["wezterm", "wezterm-gui"],
                open: [
                    .cli(binary: "wezterm", argsTemplate: ["start", "--cwd", "{{cwd}}"]),
                    .openBundle(bundleID: "com.github.wez.wezterm", passCwdAsPath: true),
                    .openAppName("WezTerm", passCwdAsPath: true)
                ]
            ),
            .kitty: d(
                .kitty,
                "Kitty",
                bundleIDs: ["net.kovidgoyal.kitty"],
                appNames: ["kitty"],
                executables: ["kitty"],
                open: [
                    .cli(binary: "kitty", argsTemplate: ["--directory", "{{cwd}}"]),
                    .openBundle(bundleID: "net.kovidgoyal.kitty", passCwdAsPath: true),
                    .openAppName("kitty", passCwdAsPath: true),
                    .openAppName("Kitty", passCwdAsPath: true)
                ]
            ),
            .alacritty: d(
                .alacritty,
                "Alacritty",
                bundleIDs: ["org.alacritty", "io.alacritty"],
                appNames: ["alacritty"],
                executables: ["alacritty"],
                open: [
                    .cli(binary: "alacritty", argsTemplate: ["--working-directory", "{{cwd}}"]),
                    .openBundle(bundleID: "org.alacritty", passCwdAsPath: true),
                    .openBundle(bundleID: "io.alacritty", passCwdAsPath: true),
                    .openAppName("Alacritty", passCwdAsPath: true)
                ]
            ),
            .tabby: d(
                .tabby,
                "Tabby",
                bundleIDs: ["org.tabby", "org.tabby-terminal", "tabby"],
                appNames: ["tabby"],
                executables: ["tabby"],
                open: [
                    .openBundle(bundleID: "org.tabby", passCwdAsPath: true),
                    .openBundle(bundleID: "org.tabby-terminal", passCwdAsPath: true),
                    .openAppName("Tabby", passCwdAsPath: true)
                ]
            ),
            .hyper: d(
                .hyper,
                "Hyper",
                bundleIDs: ["co.zeit.hyper", "co.vercel.hyper"],
                appNames: ["hyper"],
                executables: ["hyper"],
                open: [
                    .openBundle(bundleID: "co.zeit.hyper", passCwdAsPath: true),
                    .openBundle(bundleID: "co.vercel.hyper", passCwdAsPath: true),
                    .openAppName("Hyper", passCwdAsPath: true)
                ]
            ),
            .rio: d(
                .rio,
                "Rio",
                bundleIDs: ["com.raphaelamorim.rio"],
                appNames: ["rio"],
                executables: ["rio"],
                open: [
                    .cli(binary: "rio", argsTemplate: ["--working-dir", "{{cwd}}"]),
                    .openBundle(bundleID: "com.raphaelamorim.rio", passCwdAsPath: true),
                    .openAppName("Rio", passCwdAsPath: true)
                ]
            ),
            .kaku: d(
                .kaku,
                "Kaku",
                bundleIDs: ["fun.tw93.kaku", "com.kaku.app"],
                appNames: ["kaku"],
                executables: ["kaku", "kaku-gui"],
                open: [
                    .cli(binary: "kaku", argsTemplate: ["{{cwd}}"]),
                    .openBundle(bundleID: "fun.tw93.kaku", passCwdAsPath: true),
                    .openBundle(bundleID: "com.kaku.app", passCwdAsPath: true),
                    .openAppName("Kaku", passCwdAsPath: true),
                    .openAppName("kaku", passCwdAsPath: true)
                ]
            ),
            .cursor: d(
                .cursor,
                "Cursor",
                bundleIDs: ["com.todesktop.230313mzl4w4u92"],
                appNames: ["cursor"],
                executables: ["cursor"],
                urlSchemes: ["cursor"],
                open: [
                    .cli(binary: "cursor", argsTemplate: ["--reuse-window", "{{cwd}}"]),
                    .openBundle(bundleID: "com.todesktop.230313mzl4w4u92", passCwdAsPath: true),
                    .openAppName("Cursor", passCwdAsPath: true)
                ]
            ),
            .visualStudioCode: d(
                .visualStudioCode,
                "VS Code",
                bundleIDs: ["com.microsoft.vscode", "com.microsoft.vscode-insiders", "com.microsoft.VSCode"],
                appNames: ["visual studio code", "code", "vscode"],
                executables: ["code", "visual studio code"],
                urlSchemes: ["vscode"],
                open: [
                    .cli(binary: "code", argsTemplate: ["--reuse-window", "{{cwd}}"]),
                    .openBundle(bundleID: "com.microsoft.vscode", passCwdAsPath: true),
                    .openBundle(bundleID: "com.microsoft.VSCode", passCwdAsPath: true),
                    .openAppName("Visual Studio Code", passCwdAsPath: true)
                ]
            ),
            .zed: d(
                .zed,
                "Zed",
                bundleIDs: ["dev.zed.Zed", "dev.zed.Zed-Preview"],
                appNames: ["zed", "zed preview", "zed code", "z code"],
                executables: ["zed", "zed-editor", "z-code"],
                urlSchemes: ["zed", "zcode"],
                open: [
                    .cli(binary: "zed", argsTemplate: ["{{cwd}}"]),
                    .openBundle(bundleID: "dev.zed.Zed", passCwdAsPath: true),
                    .openBundle(bundleID: "dev.zed.Zed-Preview", passCwdAsPath: true),
                    .openAppName("Zed", passCwdAsPath: true),
                    .openAppName("Z Code", passCwdAsPath: true)
                ]
            ),
        ]
    }()

    private static let bundleLookup: [String: JumpTarget] = {
        var map: [String: JumpTarget] = [:]
        for (target, descriptor) in registry {
            for bundle in descriptor.bundleIDs {
                map[normalizedLookupKey(bundle)] = target
            }
        }
        return map
    }()

    private static let appNameLookup: [String: JumpTarget] = {
        var map: [String: JumpTarget] = [:]
        for (target, descriptor) in registry {
            for alias in descriptor.appNameAliases + [descriptor.displayName] {
                map[normalizedLookupKey(alias)] = target
            }
        }
        return map
    }()

    private static let executableLookup: [String: JumpTarget] = {
        var map: [String: JumpTarget] = [:]
        for (target, descriptor) in registry {
            for executable in descriptor.executableAliases {
                map[normalizedLookupKey(executable)] = target
            }
        }
        return map
    }()

    private static func normalizedLookupKey(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private func manualTargets() -> [JumpTarget] {
        JumpTarget.allCases.sorted { lhs, rhs in
            let lhsInstalled = isInstalled(target: lhs)
            let rhsInstalled = isInstalled(target: rhs)
            if lhsInstalled != rhsInstalled {
                return lhsInstalled && !rhsInstalled
            }
            return lhs.displayName < rhs.displayName
        }
    }

    private func isInstalled(target: JumpTarget) -> Bool {
        guard let descriptor = Self.registry[target] else { return false }

        for bundleID in descriptor.bundleIDs {
            if NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil {
                return true
            }
        }

        let appDirs = ["/Applications", NSHomeDirectory() + "/Applications"]
        for appName in Set(descriptor.appNameAliases + [descriptor.displayName]) {
            let normalizedName = appName.hasSuffix(".app") ? appName : appName + ".app"
            for dir in appDirs {
                let fullPath = (dir as NSString).appendingPathComponent(normalizedName)
                if FileManager.default.fileExists(atPath: fullPath) {
                    return true
                }
            }
        }

        return false
    }

    private func execute(target: JumpTarget, session: SessionModel?, cwd: String, projectName: String) -> Bool {
        guard let descriptor = Self.registry[target] else { return false }

        // Layer 1+2: TTY/WindowTab/Title matching
        if focusExistingSessionIfPossible(target: target, session: session) {
            return true
        }

        // Layer 2.5: If app is already running, just activate it (bring to front).
        // This prevents opening a NEW window for apps like Ghostty/Kaku whose
        // windows are invisible to System Events / CGWindowList.
        if activateRunningApp(for: descriptor) {
            return true
        }

        // Layer 3: App is not running — launch it
        if executeOpenStrategies(descriptor.openStrategies, cwd: cwd, projectName: projectName) {
            return true
        }

        return openAppOnly(descriptor: descriptor)
    }

    private func activateRunningApp(for descriptor: TerminalDescriptor) -> Bool {
        for bundleID in descriptor.bundleIDs {
            let apps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            if let app = apps.first {
                app.activate(options: [.activateIgnoringOtherApps])
                return true
            }
        }
        return false
    }

    private func focusExistingSessionIfPossible(target: JumpTarget, session: SessionModel?) -> Bool {
        guard let session else { return false }

        switch target {
        case .terminalApp:
            if let location = parseWindowTabLocation(from: session.terminalSessionID),
               focusTerminalSession(windowTab: location) {
                return true
            }
            if let tty = preferredTTY(for: session), focusTerminalSession(tty: tty) {
                return true
            }
            return false

        case .iTerm2:
            if let location = parseWindowTabLocation(from: session.terminalSessionID),
               focusITermSession(windowTab: location) {
                return true
            }
            if let tty = preferredTTY(for: session), focusITermSession(tty: tty) {
                return true
            }
            return false

        case .kitty:
            if focusKittyWindow(session: session) {
                return true
            }
            return focusWindowByTitle(target: target, session: session)

        case .wezTerm:
            if focusWezTermPane(session: session) {
                return true
            }
            return focusWindowByTitle(target: target, session: session)

        default:
            return focusWindowByTitle(target: target, session: session)
        }
    }

    // MARK: - Universal Window Title Matching (Layer 2)

    func focusWindowByTitle(target: JumpTarget, session: SessionModel) -> Bool {
        guard let descriptor = Self.registry[target] else { return false }

        let matchStrings = buildMatchStrings(session: session)
        for processName in candidateProcessNames(for: descriptor, session: session) {
            for matchString in matchStrings {
                if focusWindowByTitleAppleScript(processName: processName, matchString: matchString) {
                    return true
                }
            }
            if focusSingleWindowProcess(processName: processName) {
                return true
            }
        }

        return false
    }

    func buildMatchStrings(session: SessionModel) -> [String] {
        var candidates: [String] = []

        if !session.projectName.isEmpty {
            let name = session.projectName
            candidates.append(name)
            let lower = name.lowercased()
            if lower != name {
                candidates.append(lower)
            }
            let capitalized = name.prefix(1).uppercased() + name.dropFirst().lowercased()
            if capitalized != name && capitalized != lower {
                candidates.append(capitalized)
            }
        }

        if let cwd = session.cwd {
            let lastComponent = URL(fileURLWithPath: cwd).lastPathComponent
            if !lastComponent.isEmpty && !candidates.contains(lastComponent) {
                candidates.append(lastComponent)
            }
            if !candidates.contains(cwd) {
                candidates.append(cwd)
            }
        }
        if !session.id.isEmpty && !candidates.contains(session.id) {
            candidates.append(session.id)
        }

        return candidates
    }

    func focusWindowByTitleAppleScript(processName: String, matchString: String) -> Bool {
        let escapedProcess = appleScriptEscape(processName)
        let escapedMatch = appleScriptEscape(matchString)

        let script = """
        tell application "System Events"
            if not (exists process "\(escapedProcess)") then return 0
            tell process "\(escapedProcess)"
                set frontmost to true
                set windowList to every window
                repeat with w in windowList
                    try
                        set titleText to ""
                        try
                            set titleText to (name of w as text)
                        end try
                        if titleText is "" then
                            try
                                set titleText to (value of attribute "AXTitle" of w as text)
                            end try
                        end if
                        if titleText is "" then
                            try
                                set titleText to (value of attribute "AXDocument" of w as text)
                            end try
                        end if
                        if titleText contains "\(escapedMatch)" then
                            perform action "AXRaise" of w
                            return 1
                        end if
                    end try
                end repeat
            end tell
        end tell
        return 0
        """
        return runAppleScriptIntResult(script) == 1
    }

    private func focusSingleWindowProcess(processName: String) -> Bool {
        let escapedProcess = appleScriptEscape(processName)
        let script = """
        tell application "System Events"
            if not (exists process "\(escapedProcess)") then return 0
            tell process "\(escapedProcess)"
                set frontmost to true
                if (count of windows) is 1 then
                    try
                        perform action "AXRaise" of window 1
                    end try
                    return 1
                end if
            end tell
        end tell
        return 0
        """
        return runAppleScriptIntResult(script) == 1
    }

    func candidateProcessNames(for descriptor: TerminalDescriptor, session: SessionModel) -> [String] {
        var candidates: [String] = []

        func appendUnique(_ name: String?) {
            guard let name else { return }
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            if !candidates.contains(trimmed) {
                candidates.append(trimmed)
            }
        }

        for app in NSWorkspace.shared.runningApplications {
            let bundle = Self.normalizedLookupKey(app.bundleIdentifier ?? "")
            let executable = Self.normalizedLookupKey(app.executableURL?.lastPathComponent ?? "")
            let localized = Self.normalizedLookupKey(app.localizedName ?? "")

            let aliasSet = Set((descriptor.appNameAliases + descriptor.executableAliases + [descriptor.displayName]).map(Self.normalizedLookupKey))
            if descriptor.bundleIDs.map(Self.normalizedLookupKey).contains(bundle) || aliasSet.contains(executable) || aliasSet.contains(localized) {
                appendUnique(app.localizedName)
            }
        }

        for bundleID in descriptor.bundleIDs {
            let apps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            for app in apps {
                appendUnique(app.localizedName)
            }
        }

        appendUnique(descriptor.displayName)
        for alias in descriptor.appNameAliases {
            appendUnique(alias.replacingOccurrences(of: ".app", with: ""))
        }

        if let sourceApp = session.sourceApp {
            appendUnique(sourceApp)
            let leaf = URL(fileURLWithPath: sourceApp).lastPathComponent
            appendUnique(leaf.replacingOccurrences(of: ".app", with: ""))
        }

        return candidates
    }

    func runningProcessName(for descriptor: TerminalDescriptor) -> String? {
        for bundleID in descriptor.bundleIDs {
            let apps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            if let app = apps.first, let name = app.localizedName {
                return name
            }
        }
        return nil
    }

    // MARK: - Terminal-Specific Focusing (Layer 1 extensions)

    private func focusKittyWindow(session: SessionModel) -> Bool {
        guard let windowID = session.terminalWindowID, !windowID.isEmpty else {
            return false
        }

        let activateResult = runCommand(
            executable: "/usr/bin/env",
            arguments: ["kitty", "@", "focus-window", "--match", "id:\(windowID)"]
        )

        if activateResult == 0 {
            activateAppByBundleID("net.kovidgoyal.kitty")
            return true
        }
        return false
    }

    private func focusWezTermPane(session: SessionModel) -> Bool {
        guard let paneID = session.terminalPaneID, !paneID.isEmpty else {
            return false
        }

        let activateResult = runCommand(
            executable: "/usr/bin/env",
            arguments: ["wezterm", "cli", "activate-pane", "--pane-id", paneID]
        )

        if activateResult == 0 {
            activateAppByBundleID("com.github.wez.wezterm")
            return true
        }
        return false
    }

    private func activateAppByBundleID(_ bundleID: String) {
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        apps.first?.activate(options: [.activateIgnoringOtherApps])
    }

    // MARK: - Jump-time Process Tree Inference

    func inferTargetFromProcessTree(session: SessionModel) -> JumpTarget? {
        let pids = [session.shellPID, session.shellPPID, session.sourcePID].compactMap { $0 }
        for pid in pids {
            if let target = walkProcessTreeForTerminal(startPID: pid) {
                return target
            }
        }
        return nil
    }

    func walkProcessTreeForTerminal(startPID: Int) -> JumpTarget? {
        var currentPID = startPID
        var depth = 0
        while currentPID > 1 && depth < 12 {
            if let comm = runCommandCaptureOutput(
                executable: "/bin/ps",
                arguments: ["-p", String(currentPID), "-o", "comm="]
            ) {
                if let target = resolveTarget(sourceApp: comm, sourceBundleID: nil) {
                    return target
                }
            }
            guard let ppidStr = runCommandCaptureOutput(
                executable: "/bin/ps",
                arguments: ["-p", String(currentPID), "-o", "ppid="]
            ), let ppid = Int(ppidStr.trimmingCharacters(in: .whitespacesAndNewlines)),
                  ppid != currentPID else {
                break
            }
            currentPID = ppid
            depth += 1
        }
        return nil
    }

    private func executeOpenStrategies(_ strategies: [OpenStrategy], cwd: String, projectName: String) -> Bool {
        for strategy in strategies {
            if execute(strategy: strategy, cwd: cwd, projectName: projectName) {
                return true
            }
        }
        return false
    }

    private func execute(strategy: OpenStrategy, cwd: String, projectName: String) -> Bool {
        switch strategy {
        case let .cli(binary, argsTemplate):
            let args = argsTemplate.map { replacePlaceholders(in: $0, cwd: cwd, projectName: projectName) }
            return runCommand(executable: "/usr/bin/env", arguments: [binary] + args) == 0

        case let .url(template):
            let resolved = replacePlaceholders(in: template, cwd: cwd, projectName: projectName)
            guard let url = URL(string: resolved) else { return false }
            return NSWorkspace.shared.open(url)

        case let .openBundle(bundleID, passCwdAsPath):
            var args = ["-b", bundleID]
            if passCwdAsPath {
                args.append(cwd)
            }
            return runCommand(executable: "/usr/bin/open", arguments: args) == 0

        case let .openAppName(appName, passCwdAsPath):
            var args = ["-a", appName]
            if passCwdAsPath {
                args.append(cwd)
            }
            return runCommand(executable: "/usr/bin/open", arguments: args) == 0

        case let .appleScript(template):
            let resolved = replacePlaceholders(in: template, cwd: cwd, projectName: projectName)
            return runAppleScript(resolved)
        }
    }

    private func replacePlaceholders(in template: String, cwd: String, projectName: String) -> String {
        let cwdURL = cwd.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? cwd
        let projectURL = projectName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? projectName

        return template
            .replacingOccurrences(of: "{{cwd}}", with: cwd)
            .replacingOccurrences(of: "{{cwd_url}}", with: cwdURL)
            .replacingOccurrences(of: "{{project}}", with: projectName)
            .replacingOccurrences(of: "{{project_url}}", with: projectURL)
    }

    private func openAppOnly(descriptor: TerminalDescriptor) -> Bool {
        for bundleID in descriptor.bundleIDs {
            if execute(strategy: .openBundle(bundleID: bundleID, passCwdAsPath: false), cwd: "", projectName: "") {
                return true
            }
        }

        for alias in descriptor.appNameAliases + [descriptor.displayName] {
            if execute(strategy: .openAppName(alias, passCwdAsPath: false), cwd: "", projectName: "") {
                return true
            }
        }

        return false
    }

    private func tryFocusKnownTerminalSessionWithoutSource(_ session: SessionModel) -> Bool {
        if let location = parseWindowTabLocation(from: session.terminalSessionID) {
            if focusTerminalSession(windowTab: location) {
                return true
            }
            if focusITermSession(windowTab: location) {
                return true
            }
        }

        if let tty = preferredTTY(for: session) {
            if focusTerminalSession(tty: tty) {
                return true
            }
            if focusITermSession(tty: tty) {
                return true
            }
        }

        return false
    }

    private func preferredTTY(for session: SessionModel?) -> String? {
        guard let session else { return nil }

        if let tty = normalizedTTY(from: session.terminalTTY) {
            return tty
        }

        if let shellPID = session.shellPID,
           let ttyFromShellPID = ttyForProcess(pid: shellPID) {
            return ttyFromShellPID
        }

        if let sourcePID = session.sourcePID,
           let ttyFromSourcePID = ttyForProcess(pid: sourcePID) {
            return ttyFromSourcePID
        }

        return nil
    }

    private func focusTerminalSession(tty: String) -> Bool {
        let escapedTTY = appleScriptEscape(tty)
        let script = """
        tell application "Terminal"
            activate
            set targetTTY to "\(escapedTTY)"
            repeat with w in windows
                repeat with t in tabs of w
                    try
                        set tabTTY to tty of t
                    on error
                        set tabTTY to ""
                    end try
                    if tabTTY is targetTTY or ("/dev/" & tabTTY) is targetTTY then
                        set frontmost of w to true
                        set selected tab of w to t
                        return 1
                    end if
                end repeat
            end repeat
            return 0
        end tell
        """
        return runAppleScriptIntResult(script) == 1
    }

    private func focusTerminalSession(windowTab: WindowTabLocation) -> Bool {
        let script = """
        tell application "Terminal"
            activate
            if (count of windows) < \(windowTab.windowIndex) then return 0
            set targetWindow to window \(windowTab.windowIndex)
            if (count of tabs of targetWindow) < \(windowTab.tabIndex) then return 0
            set frontmost of targetWindow to true
            set selected tab of targetWindow to tab \(windowTab.tabIndex) of targetWindow
            return 1
        end tell
        """
        return runAppleScriptIntResult(script) == 1
    }

    private func focusITermSession(tty: String) -> Bool {
        let escapedTTY = appleScriptEscape(tty)
        let script = """
        tell application "iTerm2"
            activate
            set targetTTY to "\(escapedTTY)"
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        try
                            set sessionTTY to tty of s
                        on error
                            set sessionTTY to ""
                        end try
                        if sessionTTY is targetTTY or ("/dev/" & sessionTTY) is targetTTY then
                            tell w to set current tab to t
                            tell t to set current session to s
                            return 1
                        end if
                    end repeat
                end repeat
            end repeat
            return 0
        end tell
        """
        return runAppleScriptIntResult(script) == 1
    }

    private func focusITermSession(windowTab: WindowTabLocation) -> Bool {
        let script = """
        tell application "iTerm2"
            activate
            if (count of windows) < \(windowTab.windowIndex) then return 0
            set targetWindow to window \(windowTab.windowIndex)
            if (count of tabs of targetWindow) < \(windowTab.tabIndex) then return 0
            set targetTab to tab \(windowTab.tabIndex) of targetWindow
            tell targetWindow to set current tab to targetTab
            return 1
        end tell
        """
        return runAppleScriptIntResult(script) == 1
    }

    private struct WindowTabLocation {
        let windowIndex: Int
        let tabIndex: Int
    }

    private func parseWindowTabLocation(from terminalSessionID: String?) -> WindowTabLocation? {
        guard let raw = terminalSessionID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else {
            return nil
        }

        let pattern = #"w([0-9]+)t([0-9]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        let range = NSRange(raw.startIndex..<raw.endIndex, in: raw)
        guard let match = regex.firstMatch(in: raw, options: [], range: range),
              match.numberOfRanges >= 3,
              let windowRange = Range(match.range(at: 1), in: raw),
              let tabRange = Range(match.range(at: 2), in: raw),
              let zeroBasedWindow = Int(raw[windowRange]),
              let zeroBasedTab = Int(raw[tabRange]) else {
            return nil
        }

        return WindowTabLocation(windowIndex: zeroBasedWindow + 1, tabIndex: zeroBasedTab + 1)
    }

    private func normalizedTTY(from value: String?) -> String? {
        guard let raw = value?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        if raw == "not a tty" || raw == "?" {
            return nil
        }
        if raw.hasPrefix("/dev/") {
            return raw
        }
        return "/dev/\(raw)"
    }

    private func ttyForProcess(pid: Int) -> String? {
        guard pid > 1 else { return nil }

        let output = runCommandCaptureOutput(
            executable: "/bin/ps",
            arguments: ["-p", String(pid), "-o", "tty="]
        )

        return normalizedTTY(from: output)
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

    private func runAppleScriptIntResult(_ source: String) -> Int? {
        guard let script = NSAppleScript(source: source) else {
            return nil
        }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        guard error == nil else {
            return nil
        }
        return result.int32Value == 0 ? 0 : Int(result.int32Value)
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

    private func runCommandCaptureOutput(executable: String, arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
            guard var output = String(data: data, encoding: .utf8) else { return nil }
            output = output.trimmingCharacters(in: .whitespacesAndNewlines)
            return output.isEmpty ? nil : output
        } catch {
            return nil
        }
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
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
    }

    private func shellQuote(_ string: String) -> String {
        "'" + string.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }
}
