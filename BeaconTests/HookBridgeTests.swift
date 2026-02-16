import Foundation
import XCTest
@testable import BeaconApp
import Darwin

private final class EventBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: BeaconEvent?

    func set(_ event: BeaconEvent) {
        lock.lock()
        value = event
        lock.unlock()
    }

    func get() -> BeaconEvent? {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

final class HookBridgeTests: XCTestCase {
    @MainActor
    func testHookBridgeMapsAndPostsPayload() async throws {
        let exp = expectation(description: "hook forwarded event")
        let captured = EventBox()
        let port = try freeLocalPort()

        let server = try LocalEventServer(port: port) { event in
            captured.set(event)
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
        let input = "{\"event\":\"PermissionRequest\",\"session_id\":\"s-hook\",\"tool_name\":\"git\",\"cwd\":\"/tmp/demo\",\"source_app\":\"Terminal.app\",\"source_bundle_id\":\"com.apple.Terminal\",\"source_pid\":101,\"source_confidence\":\"high\",\"shell_pid\":202,\"shell_ppid\":101,\"terminal_tty\":\"/dev/ttys001\",\"terminal_session_id\":\"w0t0p0\"}"
        stdin.fileHandleForWriting.write(Data(input.utf8))
        stdin.fileHandleForWriting.closeFile()
        process.waitUntilExit()

        XCTAssertEqual(process.terminationStatus, 0)
        XCTAssertEqual(String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8), "")

        await fulfillment(of: [exp], timeout: 2.0)
        let event = captured.get()
        XCTAssertEqual(event?.event, .permissionRequest)
        XCTAssertEqual(event?.sessionID, "s-hook")
        XCTAssertEqual(event?.toolName, "git")
        XCTAssertEqual(event?.sourceApp, "Terminal.app")
        XCTAssertEqual(event?.sourceBundleID, "com.apple.Terminal")
        XCTAssertEqual(event?.sourcePID, 101)
        XCTAssertEqual(event?.sourceConfidence, .high)
        XCTAssertEqual(event?.shellPID, 202)
        XCTAssertEqual(event?.shellPPID, 101)
        XCTAssertEqual(event?.terminalTTY, "/dev/ttys001")
        XCTAssertEqual(event?.terminalSessionID, "w0t0p0")
    }

    @MainActor
    func testHookBridgeDetectsSourceFromEnvironment() async throws {
        let exp = expectation(description: "hook forwarded event with detected source")
        let captured = EventBox()
        let port = try freeLocalPort()

        let server = try LocalEventServer(port: port) { event in
            captured.set(event)
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
            "TERM_SESSION_ID": "w9t2p0",
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
        let event = captured.get()
        XCTAssertEqual(event?.sourceApp, "Terminal.app")
        XCTAssertEqual(event?.sourceBundleID, "com.apple.Terminal")
        XCTAssertEqual(event?.sourceConfidence, .high)
        XCTAssertNotNil(event?.shellPID)
        XCTAssertNotNil(event?.shellPPID)
        XCTAssertTrue((event?.shellPPID ?? 0) > 1)
        XCTAssertEqual(event?.terminalSessionID, "w9t2p0")
    }

    @MainActor
    func testHookBridgeDetectsGhosttyFromEnvironment() async throws {
        let exp = expectation(description: "hook forwarded event with ghostty source")
        let captured = EventBox()
        let port = try freeLocalPort()

        let server = try LocalEventServer(port: port) { event in
            captured.set(event)
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
            "TERM_PROGRAM": "ghostty",
            "PPID": "1",
        ]

        let stdin = Pipe()
        let stderr = Pipe()
        process.standardInput = stdin
        process.standardError = stderr

        try process.run()
        let input = "{\"event\":\"UserPromptSubmit\",\"session_id\":\"s-ghostty\",\"cwd\":\"/tmp/demo\"}"
        stdin.fileHandleForWriting.write(Data(input.utf8))
        stdin.fileHandleForWriting.closeFile()
        process.waitUntilExit()

        XCTAssertEqual(process.terminationStatus, 0)
        XCTAssertEqual(String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8), "")

        await fulfillment(of: [exp], timeout: 2.0)
        let event = captured.get()
        XCTAssertEqual(event?.sourceApp, "Ghostty")
        XCTAssertEqual(event?.sourceBundleID, "com.mitchellh.ghostty")
        XCTAssertEqual(event?.sourceConfidence, .high)
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
