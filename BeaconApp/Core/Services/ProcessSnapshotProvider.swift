import Foundation

public struct ProcessSnapshot: Sendable {
    public struct Entry: Sendable {
        public let pid: Int
        public let ppid: Int
        public let tty: String?
    }

    public let entriesByPID: [Int: Entry]
    public let pidsByTTY: [String: Set<Int>]

    public init(entriesByPID: [Int: Entry], pidsByTTY: [String: Set<Int>]) {
        self.entriesByPID = entriesByPID
        self.pidsByTTY = pidsByTTY
    }
}

public protocol ProcessSnapshotProviding {
    func snapshot() -> ProcessSnapshot?
}

public final class ProcessSnapshotProvider: ProcessSnapshotProviding {
    public init() {}

    public func snapshot() -> ProcessSnapshot? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "pid=,ppid=,tty="]

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                return nil
            }

            let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
            guard let text = String(data: data, encoding: .utf8) else {
                return nil
            }

            return parseSnapshot(text)
        } catch {
            return nil
        }
    }

    private func parseSnapshot(_ text: String) -> ProcessSnapshot {
        var entriesByPID: [Int: ProcessSnapshot.Entry] = [:]
        var pidsByTTY: [String: Set<Int>] = [:]

        for rawLine in text.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            let components = line.split(maxSplits: 2, omittingEmptySubsequences: true, whereSeparator: { $0.isWhitespace })
            guard components.count >= 2,
                  let pid = Int(components[0]),
                  let ppid = Int(components[1]) else {
                continue
            }

            let ttyRaw = components.count >= 3 ? String(components[2]) : ""
            let tty = Self.normalizeTTY(ttyRaw)
            let entry = ProcessSnapshot.Entry(pid: pid, ppid: ppid, tty: tty)
            entriesByPID[pid] = entry

            if let tty {
                pidsByTTY[tty, default: []].insert(pid)
            }
        }

        return ProcessSnapshot(entriesByPID: entriesByPID, pidsByTTY: pidsByTTY)
    }

    static func normalizeTTY(_ value: String?) -> String? {
        guard let value else { return nil }
        let raw = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !raw.isEmpty, raw != "?", raw != "not a tty" else {
            return nil
        }
        if raw.hasPrefix("/dev/") {
            return raw
        }
        return "/dev/\(raw)"
    }
}
