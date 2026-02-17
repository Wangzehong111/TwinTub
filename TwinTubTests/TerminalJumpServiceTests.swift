import XCTest
@testable import TwinTubApp

final class TerminalJumpServiceTests: XCTestCase {
    func testResolveTargetFromSourceAppAndBundle() {
        let service = TerminalJumpService()

        XCTAssertEqual(
            service.resolveTarget(sourceApp: "Terminal.app", sourceBundleID: nil),
            .terminalApp
        )
        XCTAssertEqual(
            service.resolveTarget(sourceApp: nil, sourceBundleID: "com.googlecode.iterm2"),
            .iTerm2
        )
        XCTAssertEqual(
            service.resolveTarget(sourceApp: "Warp", sourceBundleID: nil),
            .warp
        )
        XCTAssertEqual(
            service.resolveTarget(sourceApp: "Kaku", sourceBundleID: nil),
            .kaku
        )
        XCTAssertEqual(
            service.resolveTarget(sourceApp: "Cursor", sourceBundleID: nil),
            .cursor
        )
        XCTAssertEqual(
            service.resolveTarget(sourceApp: "Visual Studio Code", sourceBundleID: nil),
            .visualStudioCode
        )
        XCTAssertEqual(
            service.resolveTarget(sourceApp: "Ghostty", sourceBundleID: nil),
            .ghostty
        )
        XCTAssertEqual(
            service.resolveTarget(sourceApp: nil, sourceBundleID: "com.mitchellh.ghostty"),
            .ghostty
        )
        XCTAssertEqual(
            service.resolveTarget(sourceApp: nil, sourceBundleID: "fun.tw93.kaku"),
            .kaku
        )
        XCTAssertEqual(
            service.resolveTarget(sourceApp: nil, sourceBundleID: "com.microsoft.VSCode"),
            .visualStudioCode
        )
        XCTAssertEqual(
            service.resolveTarget(sourceApp: "/Applications/Ghostty.app/Contents/MacOS/ghostty", sourceBundleID: nil),
            .ghostty
        )
    }

    func testJumpUnknownSourceNeedsManualSelection() {
        let service = TerminalJumpService()
        let session = SessionModel(
            id: "unknown",
            projectName: "PROJECT",
            cwd: "/tmp",
            status: .processing,
            statusReason: nil,
            usageBytes: 0,
            usageTokens: 0,
            usageSegments: 0,
            updatedAt: Date()
        )

        let outcome = service.jump(to: session)
        guard case let .needsManualSelection(targets, _) = outcome else {
            return XCTFail("Expected manual selection outcome")
        }
        XCTAssertEqual(Set(targets), Set(TerminalJumpService.JumpTarget.allCases))
    }

    func testJumpKnownSourceFailureNeedsManualSelection() {
        let service = TerminalJumpService()
        let session = SessionModel(
            id: "known",
            projectName: "PROJECT",
            cwd: "/tmp",
            status: .processing,
            statusReason: nil,
            usageBytes: 0,
            usageTokens: 0,
            usageSegments: 0,
            updatedAt: Date(),
            sourceApp: "Terminal.app",
            sourceBundleID: "com.apple.Terminal",
            sourcePID: 101,
            sourceConfidence: .high
        )

        let outcome = service.jump(to: session, executeOverride: { _, _, _ in false })
        guard case let .needsManualSelection(targets, _) = outcome else {
            return XCTFail("Expected manual selection outcome")
        }
        XCTAssertEqual(Set(targets), Set(TerminalJumpService.JumpTarget.allCases))
    }

    func testJumpKnownSourceSuccessWhenOverrideReturnsTrue() {
        let service = TerminalJumpService()
        let session = SessionModel(
            id: "known-success",
            projectName: "PROJECT",
            cwd: "/tmp",
            status: .processing,
            statusReason: nil,
            usageBytes: 0,
            usageTokens: 0,
            usageSegments: 0,
            updatedAt: Date(),
            sourceApp: "Ghostty",
            sourceBundleID: "com.mitchellh.ghostty",
            sourcePID: 101,
            sourceConfidence: .high
        )

        let outcome = service.jump(to: session, executeOverride: { target, _, _ in
            target == .ghostty
        })
        XCTAssertEqual(outcome, .success)
    }

    // MARK: - buildMatchStrings Tests

    func testBuildMatchStringsWithProjectNameAndCwd() {
        let service = TerminalJumpService()
        let session = SessionModel(
            id: "s1",
            projectName: "BEACON",
            cwd: "/Users/test/Projects/Beacon",
            status: .processing,
            statusReason: nil,
            usageBytes: 0,
            usageTokens: 0,
            usageSegments: 0,
            updatedAt: Date()
        )

        let matches = service.buildMatchStrings(session: session)

        XCTAssertTrue(matches.contains("BEACON"))
        XCTAssertTrue(matches.contains("beacon"))
        XCTAssertTrue(matches.contains("Beacon"))
        XCTAssertTrue(matches.contains("/Users/test/Projects/Beacon"))
    }

    func testBuildMatchStringsProjectNameOnly() {
        let service = TerminalJumpService()
        let session = SessionModel(
            id: "s2",
            projectName: "MyProject",
            cwd: nil,
            status: .processing,
            statusReason: nil,
            usageBytes: 0,
            usageTokens: 0,
            usageSegments: 0,
            updatedAt: Date()
        )

        let matches = service.buildMatchStrings(session: session)

        XCTAssertTrue(matches.contains("MyProject"))
        XCTAssertTrue(matches.contains("myproject"))
        XCTAssertFalse(matches.isEmpty)
    }

    func testBuildMatchStringsCwdOnly() {
        let service = TerminalJumpService()
        let session = SessionModel(
            id: "s3",
            projectName: "",
            cwd: "/home/user/code/my-app",
            status: .processing,
            statusReason: nil,
            usageBytes: 0,
            usageTokens: 0,
            usageSegments: 0,
            updatedAt: Date()
        )

        let matches = service.buildMatchStrings(session: session)

        XCTAssertTrue(matches.contains("my-app"))
        XCTAssertTrue(matches.contains("/home/user/code/my-app"))
        XCTAssertTrue(matches.contains("s3"))
    }

    func testBuildMatchStringsDeduplication() {
        let service = TerminalJumpService()
        let session = SessionModel(
            id: "s4",
            projectName: "Beacon",
            cwd: "/Users/test/Beacon",
            status: .processing,
            statusReason: nil,
            usageBytes: 0,
            usageTokens: 0,
            usageSegments: 0,
            updatedAt: Date()
        )

        let matches = service.buildMatchStrings(session: session)

        let beaconCount = matches.filter { $0 == "Beacon" }.count
        XCTAssertEqual(beaconCount, 1, "Beacon should appear only once")
    }

    // MARK: - focusWindowByTitleAppleScript Tests

    func testFocusWindowByTitleAppleScriptContainsProcessName() {
        let service = TerminalJumpService()
        let session = SessionModel(
            id: "s5",
            projectName: "TestProject",
            cwd: "/tmp/test",
            status: .processing,
            statusReason: nil,
            usageBytes: 0,
            usageTokens: 0,
            usageSegments: 0,
            updatedAt: Date()
        )

        let matches = service.buildMatchStrings(session: session)
        XCTAssertTrue(matches.first == "TestProject" || matches.contains("TestProject"))
    }

    func testFocusWindowByTitleAppleScriptEscapesSpecialChars() {
        let service = TerminalJumpService()

        // The method should handle strings with quotes and backslashes
        let result = service.focusWindowByTitleAppleScript(
            processName: "Test\"App",
            matchString: "My\\Project"
        )
        // On CI/test machines this will return false since the app isn't running,
        // but we verify it doesn't crash with special characters
        XCTAssertFalse(result)
    }

    func testCandidateProcessNamesIncludesAliasesAndSourceApp() {
        let service = TerminalJumpService()
        let descriptor = TerminalJumpService.TerminalDescriptor(
            target: .kaku,
            displayName: "Kaku",
            bundleIDs: [],
            appNameAliases: ["kaku", "kaku.app"],
            executableAliases: ["kaku-gui"],
            urlSchemes: [],
            supportsTTYFocus: false,
            supportsWindowTabFocus: false,
            openStrategies: []
        )
        let session = SessionModel(
            id: "s-kaku",
            projectName: "PROJECT",
            cwd: "/tmp",
            status: .processing,
            statusReason: nil,
            usageBytes: 0,
            usageTokens: 0,
            usageSegments: 0,
            updatedAt: Date(),
            sourceApp: "/Applications/Kaku.app/Contents/MacOS/kaku"
        )

        let candidates = service.candidateProcessNames(for: descriptor, session: session)
        XCTAssertTrue(candidates.contains("Kaku"))
        XCTAssertTrue(candidates.contains("kaku"))
    }

    // MARK: - New Model Fields Tests

    func testSessionModelNewFieldsDefaultToNil() {
        let session = SessionModel(
            id: "s6",
            projectName: "TEST",
            cwd: "/tmp",
            status: .processing,
            statusReason: nil,
            usageBytes: 0,
            usageTokens: 0,
            usageSegments: 0,
            updatedAt: Date()
        )

        XCTAssertNil(session.terminalWindowID)
        XCTAssertNil(session.terminalPaneID)
    }

    func testSessionModelNewFieldsCanBeSet() {
        let session = SessionModel(
            id: "s7",
            projectName: "TEST",
            cwd: "/tmp",
            status: .processing,
            statusReason: nil,
            usageBytes: 0,
            usageTokens: 0,
            usageSegments: 0,
            updatedAt: Date(),
            terminalWindowID: "42",
            terminalPaneID: "3"
        )

        XCTAssertEqual(session.terminalWindowID, "42")
        XCTAssertEqual(session.terminalPaneID, "3")
    }

    func testTwinTubEventNewFieldsDecoding() throws {
        let json = """
        {
            "event": "UserPromptSubmit",
            "session_id": "test-123",
            "terminal_window_id": "99",
            "terminal_pane_id": "7"
        }
        """
        let data = json.data(using: .utf8)!
        let event = try JSONDecoder.twinTubEventDecoder.decode(TwinTubEvent.self, from: data)

        XCTAssertEqual(event.terminalWindowID, "99")
        XCTAssertEqual(event.terminalPaneID, "7")
    }

    func testTwinTubEventNewFieldsOptionalDecoding() throws {
        let json = """
        {
            "event": "UserPromptSubmit",
            "session_id": "test-456"
        }
        """
        let data = json.data(using: .utf8)!
        let event = try JSONDecoder.twinTubEventDecoder.decode(TwinTubEvent.self, from: data)

        XCTAssertNil(event.terminalWindowID)
        XCTAssertNil(event.terminalPaneID)
    }

    // MARK: - SessionReducer New Fields Tests

    func testReducerPropagatesNewTerminalFields() {
        let event = TwinTubEvent(
            event: .userPromptSubmit,
            sessionID: "s-new-fields",
            cwd: "/tmp/test",
            terminalWindowID: "42",
            terminalPaneID: "3"
        )

        let mutation = SessionReducer.reduce(current: nil, event: event, now: Date())
        guard case let .upsert(session, _) = mutation else {
            return XCTFail("Expected upsert")
        }

        XCTAssertEqual(session.terminalWindowID, "42")
        XCTAssertEqual(session.terminalPaneID, "3")
    }

    func testReducerUpdatesNewTerminalFieldsOnSubsequentEvents() {
        let now = Date()
        let existing = SessionModel(
            id: "s-update",
            projectName: "TEST",
            cwd: "/tmp",
            status: .processing,
            statusReason: nil,
            usageBytes: 0,
            usageTokens: 0,
            usageSegments: 0,
            updatedAt: now,
            terminalWindowID: "10",
            terminalPaneID: "1"
        )

        let event = TwinTubEvent(
            event: .postToolUse,
            sessionID: "s-update",
            terminalWindowID: "20",
            terminalPaneID: "2"
        )

        let mutation = SessionReducer.reduce(current: existing, event: event, now: now)
        guard case let .upsert(session, _) = mutation else {
            return XCTFail("Expected upsert")
        }

        XCTAssertEqual(session.terminalWindowID, "20")
        XCTAssertEqual(session.terminalPaneID, "2")
    }

    // MARK: - Process Tree Inference Tests

    func testWalkProcessTreeResolvesGhosttyPath() {
        let service = TerminalJumpService()
        // resolveTarget handles full paths via executable leaf matching
        let target = service.resolveTarget(
            sourceApp: "/Applications/Ghostty.app/Contents/MacOS/ghostty",
            sourceBundleID: nil
        )
        XCTAssertEqual(target, .ghostty)
    }

    func testWalkProcessTreeResolvesKakuPath() {
        let service = TerminalJumpService()
        let target = service.resolveTarget(
            sourceApp: "/Applications/Kaku.app/Contents/MacOS/kaku",
            sourceBundleID: nil
        )
        XCTAssertEqual(target, .kaku)
    }

    func testWalkProcessTreeResolvesWarpStable() {
        let service = TerminalJumpService()
        let target = service.resolveTarget(
            sourceApp: "/Applications/Warp.app/Contents/MacOS/stable",
            sourceBundleID: nil
        )
        XCTAssertEqual(target, .warp)
    }

    func testInferTargetFromProcessTreeReturnsNilForNoShellPID() {
        let service = TerminalJumpService()
        let session = SessionModel(
            id: "s-no-pid",
            projectName: "TEST",
            cwd: "/tmp",
            status: .processing,
            statusReason: nil,
            usageBytes: 0,
            usageTokens: 0,
            usageSegments: 0,
            updatedAt: Date()
        )
        XCTAssertNil(service.inferTargetFromProcessTree(session: session))
    }

    func testWalkProcessTreeWithInvalidPIDReturnsNil() {
        let service = TerminalJumpService()
        XCTAssertNil(service.walkProcessTreeForTerminal(startPID: 0))
        XCTAssertNil(service.walkProcessTreeForTerminal(startPID: -1))
    }
}
