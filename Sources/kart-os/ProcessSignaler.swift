import Foundation
import Darwin

struct ProcessSignaler {
    let currentPID: Int32 = ProcessInfo.processInfo.processIdentifier

    func canSignal(_ pid: Int32) -> Bool {
        guard pid > 1, pid != currentPID else { return false }
        guard kill(pid, 0) == 0 else {
            _ = errno // Consume only the result of this permission/existence check.
            return false
        }
        return true
    }
    func terminate(_ pid: Int32, force: Bool) throws {
        guard canSignal(pid) else { throw NSError(domain: "kart-os", code: Int(EPERM), userInfo: [NSLocalizedDescriptionKey: "This process cannot be signaled."]) }
        guard kill(pid, force ? SIGKILL : SIGTERM) == 0 else {
            let errorCode = errno
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errorCode), userInfo: [NSLocalizedDescriptionKey: String(cString: strerror(errorCode))])
        }
    }
}
