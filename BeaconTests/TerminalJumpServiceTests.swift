import XCTest
@testable import BeaconApp

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
            usageSegments: 0,
            updatedAt: Date()
        )

        let outcome = service.jump(to: session)
        guard case let .needsManualSelection(targets, _) = outcome else {
            return XCTFail("Expected manual selection outcome")
        }
        XCTAssertEqual(targets, TerminalJumpService.JumpTarget.allCases)
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
        XCTAssertEqual(targets, TerminalJumpService.JumpTarget.allCases)
    }
}
