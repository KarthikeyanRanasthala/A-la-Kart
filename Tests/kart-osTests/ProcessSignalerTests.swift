import XCTest
@testable import kart_os

final class ProcessSignalerTests: XCTestCase {
    func testPermissionCheckUsesSignalZeroForExistingProcess() throws {
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/bin/sleep")
        child.arguments = ["10"]
        try child.run()
        defer { if child.isRunning { child.terminate() } }

        let signaler = ProcessSignaler()
        XCTAssertTrue(signaler.canSignal(child.processIdentifier))
        XCTAssertFalse(signaler.canSignal(ProcessInfo.processInfo.processIdentifier))
        XCTAssertFalse(signaler.canSignal(Int32.max))
        XCTAssertFalse(signaler.canSignal(1))
        XCTAssertFalse(signaler.canSignal(0))
    }
}
