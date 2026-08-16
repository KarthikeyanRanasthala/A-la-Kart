import Foundation

struct LsofParser {
    /// Parses lsof's NUL-delimited fields. Each `f` starts a new socket record;
    /// TCP state is carried by a `TST=...` field after its `n` field.
    static func parse(_ output: String) -> [Port] {
        var result: [String: Port] = [:]
        var pid: Int32?
        var command = ""
        var proto: PortProtocol?
        var endpoint: String?
        var state: String?

        func finishSocket() {
            guard let pid, let proto, let endpoint, let port = portNumber(endpoint), port > 0, !command.isEmpty else { return }
            guard proto == .udp || state == "LISTEN" else { return }
            let portRecord = Port(number: port, proto: proto, processName: command, pid: pid, endpoint: endpoint)
            let key = "\(port)-\(proto.rawValue)-\(command)-\(pid)"
            result[key] = result[key] ?? portRecord
        }

        let fields = output.split { $0 == "\0" || $0 == "\n" }.map(String.init)
        for field in fields {
            guard let key = field.first else { continue }
            let value = String(field.dropFirst())
            switch key {
            case "p":
                finishSocket()
                pid = Int32(value); command = ""; proto = nil; endpoint = nil; state = nil
            case "c": command = value
            case "f": finishSocket(); proto = nil; endpoint = nil; state = nil
            case "P": proto = PortProtocol(rawValue: value)
            case "n": endpoint = value
            case "T": state = value.split(separator: "=", maxSplits: 1).last.map(String.init)
            default: break
            }
        }
        finishSocket()
        return result.values.sorted {
            if $0.number != $1.number { return $0.number < $1.number }
            if $0.proto != $1.proto { return $0.proto < $1.proto }
            let left = $0.processName.lowercased()
            let right = $1.processName.lowercased()
            if left != right { return left < right }
            return $0.pid < $1.pid
        }
    }

    private static func portNumber(_ endpoint: String) -> Int? {
        let value = endpoint.components(separatedBy: "->").first ?? endpoint
        guard let colon = value.lastIndex(of: ":") else { return nil }
        return Int(value[value.index(after: colon)...])
    }
}

protocol PortDiscovering { func discover() throws -> [Port] }

struct LsofService: PortDiscovering {
    func discover() throws -> [Port] {
        let task = Process()
        let pipe = Pipe()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        task.arguments = ["-nP", "-FpcfPTn0", "-iTCP", "-sTCP:LISTEN", "-iUDP"]
        task.standardOutput = pipe
        task.standardError = Pipe()
        try task.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        guard task.terminationStatus == 0 || !data.isEmpty else { throw NSError(domain: "lsof", code: Int(task.terminationStatus)) }
        return LsofParser.parse(String(decoding: data, as: UTF8.self))
    }
}
