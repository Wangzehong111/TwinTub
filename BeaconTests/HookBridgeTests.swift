import Foundation
import XCTest
@testable import BeaconApp
import Darwin

final class HookBridgeTests: XCTestCase {
    @MainActor
    func testHookBridgeMapsAndPostsPayload() async throws {
        let exp = expectation(description: "hook forwarded event")
        var captured: BeaconEvent?
        let port = try freeLocalPort()

        let server = try LocalEventServer(port: port) { event in
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
        process.environment = ["BEACON_PORT": String(port)]

        let stdin = Pipe()
        let stderr = Pipe()
        process.standardInput = stdin
        process.standardError = stderr

        try process.run()
        let input = "{\"event\":\"PermissionRequest\",\"session_id\":\"s-hook\",\"tool_name\":\"git\",\"cwd\":\"/tmp/demo\",\"source_app\":\"Terminal.app\",\"source_bundle_id\":\"com.apple.Terminal\",\"source_pid\":101,\"source_confidence\":\"high\"}"
        stdin.fileHandleForWriting.write(Data(input.utf8))
        stdin.fileHandleForWriting.closeFile()
        process.waitUntilExit()

        XCTAssertEqual(process.terminationStatus, 0)
        XCTAssertEqual(String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8), "")

        await fulfillment(of: [exp], timeout: 2.0)
        XCTAssertEqual(captured?.event, .permissionRequest)
        XCTAssertEqual(captured?.sessionID, "s-hook")
        XCTAssertEqual(captured?.toolName, "git")
        XCTAssertEqual(captured?.sourceApp, "Terminal.app")
        XCTAssertEqual(captured?.sourceBundleID, "com.apple.Terminal")
        XCTAssertEqual(captured?.sourcePID, 101)
        XCTAssertEqual(captured?.sourceConfidence, .high)
    }

    @MainActor
    func testHookBridgeDetectsSourceFromEnvironment() async throws {
        let exp = expectation(description: "hook forwarded event with detected source")
        var captured: BeaconEvent?
        let port = try freeLocalPort()

        let server = try LocalEventServer(port: port) { event in
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
        process.environment = [
            "BEACON_PORT": String(port),
            "TERM_PROGRAM": "Apple_Terminal",
            "PPID": "1",
        ]

        let stdin = Pipe()
        let stderr = Pipe()
        process.standardInput = stdin
        process.standardError = stderr

        try process.run()
        let input = "{\"event\":\"UserPromptSubmit\",\"session_id\":\"s-env\",\"cwd\":\"/tmp/demo\"}"
        stdin.fileHandleForWriting.write(Data(input.utf8))
        stdin.fileHandleForWriting.closeFile()
        process.waitUntilExit()

        XCTAssertEqual(process.terminationStatus, 0)
        XCTAssertEqual(String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8), "")

        await fulfillment(of: [exp], timeout: 2.0)
        XCTAssertEqual(captured?.sourceApp, "Terminal.app")
        XCTAssertEqual(captured?.sourceBundleID, "com.apple.Terminal")
        XCTAssertEqual(captured?.sourceConfidence, .high)
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

    private func freeLocalPort() throws -> UInt16 {
        let sock = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard sock >= 0 else {
            throw NSError(domain: "HookBridgeTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "failed to create socket"])
        }
        defer { Darwin.close(sock) }

        var value: Int32 = 1
        Darwin.setsockopt(sock, SOL_SOCKET, SO_REUSEADDR, &value, socklen_t(MemoryLayout.size(ofValue: value)))

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(0).bigEndian
        addr.sin_addr = in_addr(s_addr: INADDR_LOOPBACK.bigEndian)

        let bindResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            throw NSError(domain: "HookBridgeTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "failed to bind ephemeral port"])
        }

        var assigned = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameResult = withUnsafeMutablePointer(to: &assigned) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.getsockname(sock, $0, &length)
            }
        }
        guard nameResult == 0 else {
            throw NSError(domain: "HookBridgeTests", code: 4, userInfo: [NSLocalizedDescriptionKey: "failed to read assigned port"])
        }

        return UInt16(bigEndian: assigned.sin_port)
    }
}
