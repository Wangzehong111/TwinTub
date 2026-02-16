import Foundation
import Network

public final class LocalEventServer: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "beacon.event.server")
    private let eventHandler: @MainActor (BeaconEvent) -> Void

    public init(port: UInt16 = 55771, eventHandler: @escaping @MainActor (BeaconEvent) -> Void) throws {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw ServerError.invalidPort
        }
        self.listener = try NWListener(using: .tcp, on: nwPort)
        self.eventHandler = eventHandler
    }

    public func start() {
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection: connection)
        }
        listener.start(queue: queue)
    }

    public func stop() {
        listener.cancel()
    }

    private func handle(connection: NWConnection) {
        connection.start(queue: queue)
        receiveAllData(on: connection, buffer: Data())
    }

    private func receiveAllData(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }

            var nextBuffer = buffer
            if let data {
                nextBuffer.append(data)
            }

            if self.isRequestComplete(nextBuffer) || isComplete || error != nil {
                let response = self.processRawRequest(nextBuffer)
                connection.send(content: response, completion: .contentProcessed { _ in
                    connection.cancel()
                })
                return
            }

            self.receiveAllData(on: connection, buffer: nextBuffer)
        }
    }

    private func isRequestComplete(_ data: Data) -> Bool {
        guard let request = String(data: data, encoding: .utf8),
              let separatorRange = request.range(of: "\r\n\r\n") else {
            return false
        }

        let headerText = String(request[..<separatorRange.lowerBound])
        let body = request[separatorRange.upperBound...]

        if let lengthLine = headerText
            .split(separator: "\r\n")
            .first(where: { $0.lowercased().hasPrefix("content-length:") }),
           let value = lengthLine.split(separator: ":").last,
           let contentLength = Int(value.trimmingCharacters(in: .whitespaces)) {
            return body.utf8.count >= contentLength
        }

        return true
    }

    func processRawRequest(_ data: Data?) -> Data {
        guard let data,
              let rawRequest = String(data: data, encoding: .utf8) else {
            return httpResponse(status: 400, body: "invalid request")
        }

        let parts = rawRequest.components(separatedBy: "\r\n\r\n")
        guard let header = parts.first else {
            return httpResponse(status: 400, body: "missing headers")
        }

        let requestLine = header.split(separator: "\n").first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if requestLine.contains("GET /health") {
            return httpResponse(status: 200, body: "ok")
        }

        guard requestLine.contains("POST /event") else {
            return httpResponse(status: 404, body: "not found")
        }

        let body = parts.dropFirst().joined(separator: "\r\n\r\n")
        guard let bodyData = body.data(using: .utf8) else {
            return httpResponse(status: 400, body: "invalid body")
        }

        do {
            let event = try JSONDecoder.beaconEventDecoder.decode(BeaconEvent.self, from: bodyData)
            Task { @MainActor [eventHandler] in
                eventHandler(event)
            }
            return httpResponse(status: 202, body: "accepted")
        } catch {
            return httpResponse(status: 400, body: "invalid payload")
        }
    }

    private func httpResponse(status: Int, body: String) -> Data {
        let reason: String
        switch status {
        case 200: reason = "OK"
        case 202: reason = "Accepted"
        case 400: reason = "Bad Request"
        case 404: reason = "Not Found"
        default: reason = "Unknown"
        }

        let payload = body.data(using: .utf8) ?? Data()
        var response = "HTTP/1.1 \(status) \(reason)\r\n"
        response += "Content-Type: text/plain; charset=utf-8\r\n"
        response += "Content-Length: \(payload.count)\r\n"
        response += "Connection: close\r\n\r\n"

        var data = Data(response.utf8)
        data.append(payload)
        return data
    }

    public enum ServerError: Error {
        case invalidPort
    }
}
