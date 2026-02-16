import Foundation
import XCTest
@testable import BeaconApp

final class HookBridgeTests: XCTestCase {
    @MainActor
    func testHookBridgeMapsAndPostsPayload() async throws {
        let exp = expectation(description: "hook forwarded event")
        var captured: BeaconEvent?

        let server = try LocalEventServer(port: 55901) { event in
            captured = event
            exp.fulfill()
        }
        server.start()
        defer { server.stop() }

        try await Task.sleep(nanoseconds: 150_000_000)

        let scriptPath = try bridgePath()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [scriptPath]
        process.environment = ["BEACON_PORT": "55901"]

        let stdin = Pipe()
        let stderr = Pipe()
        process.standardInput = stdin
        process.standardError = stderr

        try process.run()
        let input = "{\"event\":\"PermissionRequest\",\"session_id\":\"s-hook\",\"tool_name\":\"git\",\"cwd\":\"/tmp/demo\"}"
        stdin.fileHandleForWriting.write(Data(input.utf8))
        stdin.fileHandleForWriting.closeFile()
        process.waitUntilExit()

        XCTAssertEqual(process.terminationStatus, 0)
        XCTAssertEqual(String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8), "")

        await fulfillment(of: [exp], timeout: 2.0)
        XCTAssertEqual(captured?.event, .permissionRequest)
        XCTAssertEqual(captured?.sessionID, "s-hook")
        XCTAssertEqual(captured?.toolName, "git")
    }

    func testHookBridgeSilentFailureWhenAppOffline() throws {
        let scriptPath = try bridgePath()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [scriptPath]
        process.environment = ["BEACON_PORT": "59999"]

        let stdin = Pipe()
        let stderr = Pipe()
        process.standardInput = stdin
        process.standardError = stderr

        try process.run()
        let input = "{\"event\":\"Stop\",\"session_id\":\"s-offline\"}"
        stdin.fileHandleForWriting.write(Data(input.utf8))
        stdin.fileHandleForWriting.closeFile()
        process.waitUntilExit()

        XCTAssertEqual(process.terminationStatus, 0)
        XCTAssertEqual(String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8), "")
    }

    private func bridgePath() throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let repoRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let script = repoRoot.appendingPathComponent("hooks/beacon_hook_bridge.sh")

        guard FileManager.default.isExecutableFile(atPath: script.path) else {
            throw NSError(domain: "HookBridgeTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "bridge script not executable: \(script.path)"])
        }

        return script.path
    }
}
