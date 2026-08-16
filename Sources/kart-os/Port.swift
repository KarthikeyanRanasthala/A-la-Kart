import Foundation

enum PortProtocol: String, Comparable {
    case tcp = "TCP"
    case udp = "UDP"

    static func < (lhs: PortProtocol, rhs: PortProtocol) -> Bool { lhs.rawValue < rhs.rawValue }
}

struct Port: Hashable {
    let number: Int
    let proto: PortProtocol
    let processName: String
    let pid: Int32
    let endpoint: String

    var title: String { "\(number) · \(proto.rawValue) — \(processName) (PID \(pid))" }
}
