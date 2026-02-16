import Foundation
import XCTest
@testable import BeaconApp

final class SessionReducerTests: XCTestCase {
    func testAllEventMappings() {
        let now = Date()
        let base = BeaconEvent(event: .userPromptSubmit, sessionID: "s1", cwd: "/tmp/a", prompt: "run")
        let processing = SessionReducer.reduce(current: nil, event: base, now: now)

        guard case let .upsert(processingModel, _) = processing else {
            return XCTFail("Expected upsert for UserPromptSubmit")
        }
        XCTAssertEqual(processingModel.status, .processing)

        let usage = BeaconEvent(event: .postToolUse, sessionID: "s1", usageBytes: 950_000)
        let processing2 = SessionReducer.reduce(current: processingModel, event: usage, now: now)
        guard case let .upsert(usageModel, _) = processing2 else {
            return XCTFail("Expected upsert for PostToolUse")
        }
        XCTAssertEqual(usageModel.status, .processing)
        XCTAssertEqual(usageModel.usageSegments, 10)

        let waiting = BeaconEvent(event: .permissionRequest, sessionID: "s1", toolName: "bash")
        let waitingMutation = SessionReducer.reduce(current: usageModel, event: waiting, now: now)
        guard case let .upsert(waitingModel, decision) = waitingMutation else {
            return XCTFail("Expected upsert for PermissionRequest")
        }
        XCTAssertEqual(waitingModel.status, .waiting)
        XCTAssertNotNil(decision)

        let done = BeaconEvent(event: .stop, sessionID: "s1")
        let doneMutation = SessionReducer.reduce(current: waitingModel, event: done, now: now)
        guard case let .upsert(doneModel, doneDecision) = doneMutation else {
            return XCTFail("Expected upsert for Stop")
        }
        XCTAssertEqual(doneModel.status, .completed)
        XCTAssertNotNil(doneDecision)

        let remove = BeaconEvent(event: .sessionEnd, sessionID: "s1")
        let removeMutation = SessionReducer.reduce(current: doneModel, event: remove, now: now)
        guard case let .upsert(endedModel, _) = removeMutation else {
            return XCTFail("Expected upsert for SessionEnd")
        }
        XCTAssertEqual(endedModel.id, "s1")
        XCTAssertEqual(endedModel.livenessState, .terminated)
        XCTAssertEqual(endedModel.terminationReason, .sessionEndEvent)
    }

    func testOutOfOrderWaitingThenUserPromptResumesProcessing() {
        let now = Date()
        let waiting = BeaconEvent(event: .permissionRequest, sessionID: "s2", toolName: "git")
        let waitingMutation = SessionReducer.reduce(current: nil, event: waiting, now: now)

        guard case let .upsert(waitingModel, _) = waitingMutation else {
            return XCTFail("Expected waiting upsert")
        }

        let resume = BeaconEvent(event: .userPromptSubmit, sessionID: "s2", prompt: "y")
        let resumed = SessionReducer.reduce(current: waitingModel, event: resume, now: now.addingTimeInterval(5))
        guard case let .upsert(resumedModel, _) = resumed else {
            return XCTFail("Expected resumed upsert")
        }

        XCTAssertEqual(resumedModel.status, .processing)
    }

    func testUsageSegmentsBoundaries() {
        XCTAssertEqual(SessionModel.segments(for: 0), 0)
        XCTAssertEqual(SessionModel.segments(for: 1), 1)
        XCTAssertEqual(SessionModel.segments(for: 500_000), 5)
        XCTAssertEqual(SessionModel.segments(for: 600_000), 6)
        XCTAssertEqual(SessionModel.segments(for: 800_000), 8)
        XCTAssertEqual(SessionModel.segments(for: 900_000), 9)
        XCTAssertEqual(SessionModel.segments(for: 1_000_000), 10)
    }

    func testSourceFieldsPropagateAndOverride() {
        let now = Date()
        let start = BeaconEvent(
            event: .userPromptSubmit,
            sessionID: "s3",
            sourceApp: "Terminal.app",
            sourceBundleID: "com.apple.Terminal",
            sourcePID: 1234,
            sourceConfidence: .high,
            shellPID: 2222,
            shellPPID: 1111,
            terminalTTY: "/dev/ttys009",
            terminalSessionID: "w0t0p0"
        )

        let first = SessionReducer.reduce(current: nil, event: start, now: now)
        guard case let .upsert(model1, _) = first else {
            return XCTFail("Expected first upsert")
        }
        XCTAssertEqual(model1.sourceApp, "Terminal.app")
        XCTAssertEqual(model1.sourceBundleID, "com.apple.Terminal")
        XCTAssertEqual(model1.sourcePID, 1234)
        XCTAssertEqual(model1.sourceConfidence, .high)
        XCTAssertEqual(model1.shellPID, 2222)
        XCTAssertEqual(model1.shellPPID, 1111)
        XCTAssertEqual(model1.terminalTTY, "/dev/ttys009")
        XCTAssertEqual(model1.terminalSessionID, "w0t0p0")
        XCTAssertEqual(model1.livenessState, .alive)
        XCTAssertNotNil(model1.lastSeenAliveAt)
        XCTAssertNotNil(model1.sourceFingerprint)

        let keepSource = BeaconEvent(event: .postToolUse, sessionID: "s3")
        let second = SessionReducer.reduce(current: model1, event: keepSource, now: now.addingTimeInterval(1))
        guard case let .upsert(model2, _) = second else {
            return XCTFail("Expected second upsert")
        }
        XCTAssertEqual(model2.sourceApp, "Terminal.app")
        XCTAssertEqual(model2.sourceBundleID, "com.apple.Terminal")
        XCTAssertEqual(model2.sourcePID, 1234)
        XCTAssertEqual(model2.sourceConfidence, .high)
        XCTAssertEqual(model2.shellPID, 2222)
        XCTAssertEqual(model2.shellPPID, 1111)
        XCTAssertEqual(model2.terminalTTY, "/dev/ttys009")
        XCTAssertEqual(model2.terminalSessionID, "w0t0p0")
        XCTAssertEqual(model2.livenessState, .alive)
        XCTAssertNotNil(model2.lastSeenAliveAt)
        XCTAssertNotNil(model2.sourceFingerprint)

        let overrideSource = BeaconEvent(
            event: .permissionRequest,
            sessionID: "s3",
            sourceApp: "iTerm2",
            sourceBundleID: "com.googlecode.iterm2",
            sourcePID: 5678,
            sourceConfidence: .medium,
            shellPID: 3333,
            shellPPID: 2222,
            terminalTTY: "/dev/ttys010",
            terminalSessionID: "w3t4p0"
        )
        let third = SessionReducer.reduce(current: model2, event: overrideSource, now: now.addingTimeInterval(2))
        guard case let .upsert(model3, _) = third else {
            return XCTFail("Expected third upsert")
        }
        XCTAssertEqual(model3.sourceApp, "iTerm2")
        XCTAssertEqual(model3.sourceBundleID, "com.googlecode.iterm2")
        XCTAssertEqual(model3.sourcePID, 5678)
        XCTAssertEqual(model3.sourceConfidence, .medium)
        XCTAssertEqual(model3.shellPID, 3333)
        XCTAssertEqual(model3.shellPPID, 2222)
        XCTAssertEqual(model3.terminalTTY, "/dev/ttys010")
        XCTAssertEqual(model3.terminalSessionID, "w3t4p0")
        XCTAssertEqual(model3.livenessState, .alive)
        XCTAssertNotNil(model3.lastSeenAliveAt)
        XCTAssertNotNil(model3.sourceFingerprint)
    }
}
