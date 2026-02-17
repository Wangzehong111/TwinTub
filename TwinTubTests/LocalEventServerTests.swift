import Foundation
import XCTest
@testable import TwinTubApp

final class LocalEventServerTests: XCTestCase {
    @MainActor
    func testHealthAndEventEndpoint() async throws {
        let eventExpectation = expectation(description: "event received")
        let server = try LocalEventServer(port: 55871) { event in
            if event.sessionID == "s-http" {
                eventExpectation.fulfill()
            }
        }
        let healthResponse = server.processRawRequest(httpRequest(method: "GET", path: "/health", body: nil))
        XCTAssertEqual(statusCode(from: healthResponse), 200)

        let payload = "{\"event\":\"UserPromptSubmit\",\"session_id\":\"s-http\",\"prompt\":\"run\"}"
        let response = server.processRawRequest(httpRequest(method: "POST", path: "/event", body: payload))
        XCTAssertEqual(statusCode(from: response), 202)

        await fulfillment(of: [eventExpectation], timeout: 2.0)
    }

    @MainActor
    func testInvalidPayloadReturns400() async throws {
        let server = try LocalEventServer(port: 55872) { _ in }
        let response = server.processRawRequest(httpRequest(method: "POST", path: "/event", body: "{\"event\":\"Stop\"}"))
        XCTAssertEqual(statusCode(from: response), 400)
    }

    private func httpRequest(method: String, path: String, body: String?) -> Data {
        let bodyValue = body ?? ""
        var request = "\(method) \(path) HTTP/1.1\r\nHost: 127.0.0.1\r\n"
        if !bodyValue.isEmpty {
            request += "Content-Type: application/json\r\n"
        }
        request += "Content-Length: \(bodyValue.utf8.count)\r\n\r\n"
        request += bodyValue
        return Data(request.utf8)
    }

    private func statusCode(from response: Data) -> Int? {
        guard let text = String(data: response, encoding: .utf8),
              let line = text.split(separator: "\r\n").first else {
            return nil
        }
        let parts = line.split(separator: " ")
        guard parts.count >= 2 else { return nil }
        return Int(parts[1])
    }
}
