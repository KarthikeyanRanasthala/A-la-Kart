import XCTest
@testable import A_la_Kart

final class LsofParserTests: XCTestCase {
    func testParsesRealStyleListeningTCPAndUDPAndSorts() {
        let input = "p20\0ctcp-app\0f3\0PTCP\0n*:80\0TST=LISTEN\0f4\0PTCP\0n*:80\0TST=LISTEN\0p21\0ctcp-at-53\0f5\0PTCP\0n*:53\0TST=LISTEN\0p11\0cudp-app\0f1\0PUDP\0n*:53\0p12\0calpha\0f2\0PUDP\0n[::1]:53\0"
        let ports = LsofParser.parse(input)
        XCTAssertEqual(ports.map { "\($0.number)-\($0.proto.rawValue)-\($0.processName)" }, ["53-TCP-tcp-at-53", "53-UDP-alpha", "53-UDP-udp-app", "80-TCP-tcp-app"])
    }

    func testNonListeningTCPAndMalformedRecordsAreIgnored() {
        let input = "p1\0cclosed\0f1\0PTCP\0n*:81\0TST=CLOSED\0f2\0PTCP\0n*:82\0TST=ESTABLISHED\0p2\0cbad\0f3\0PTCP\0n*:abc\0TST=LISTEN\0p3\0cmissing\0f4\0PTCP\0n*:22\0"
        XCTAssertTrue(LsofParser.parse(input).isEmpty)
    }

    func testExactProcessProtocolPortTupleIsDeduplicatedAcrossFiles() {
        let input = "p7\0cworker\0f1\0PUDP\0n*:9000\0f2\0PUDP\0n127.0.0.1:9000\0"
        XCTAssertEqual(LsofParser.parse(input).count, 1)
    }
}
