import XCTest
@testable import A_la_Kart

final class URLRoutingTests: XCTestCase {
    private let browser = "com.example.Browser"
    func testConfigRoundTripAndValidation() throws {
        var config = ALaKartConfig(); config.ports.confirmBeforeKilling = false; config.urlRouting.fallbackBrowserBundleIdentifier = browser; config.urlRouting.rules = [.init(host: " X.COM. ", browserBundleIdentifier: browser)]
        let data = try JSONEncoder().encode(config); let decoded = try JSONDecoder().decode(ALaKartConfig.self, from: data).validated()
        XCTAssertEqual(decoded.ports.confirmBeforeKilling, false); XCTAssertEqual(decoded.urlRouting.rules[0].host, "x.com")
    }
    func testRejectsFutureSchemaAndInvalidOrDuplicateRules() {
        XCTAssertThrowsError(try ({ var c = ALaKartConfig(); c.schemaVersion = 2; return try c.validated() })())
        XCTAssertThrowsError(try ({ var c = ALaKartConfig(); c.schemaVersion = 0; return try c.validated() })())
        XCTAssertThrowsError(try ({ var c = ALaKartConfig(); c.urlRouting.rules = [.init(host: "https://x.com", browserBundleIdentifier: browser)]; return try c.validated() })())
        XCTAssertThrowsError(try ({ var c = ALaKartConfig(); c.urlRouting.rules = [.init(host: "x.com", browserBundleIdentifier: browser), .init(host: " X.COM ", browserBundleIdentifier: browser)]; return try c.validated() })())
    }
    func testExactSubdomainDisabledAndFirstMatch() throws {
        var c = ALaKartConfig(); c.urlRouting.rules = [.init(host: "example.com", includeSubdomains: true, browserBundleIdentifier: "broad"), .init(host: "child.example.com", browserBundleIdentifier: "exact")]
        let router = URLRouter(config: try c.validated(), ownBundleIdentifier: "self")
        XCTAssertEqual(router.route(URL(string: "https://child.example.com")!), .browser("broad"))
        c.urlRouting.rules.reverse()
        XCTAssertEqual(URLRouter(config: try c.validated(), ownBundleIdentifier: "self").route(URL(string: "https://child.example.com")!), .browser("exact"))
        var disabled = c; disabled.urlRouting.rules[0].enabled = false; disabled.urlRouting.fallbackBrowserBundleIdentifier = "fallback"
        XCTAssertEqual(URLRouter(config: disabled, ownBundleIdentifier: "self").route(URL(string: "https://child.example.com")!), .browser("broad"))
        disabled.urlRouting.rules[1].enabled = false
        XCTAssertEqual(URLRouter(config: disabled, ownBundleIdentifier: "self").route(URL(string: "https://child.example.com")!), .fallback("fallback"))
    }
    func testFallbackAndRecursionProtection() {
        var c = ALaKartConfig(); c.urlRouting.fallbackBrowserBundleIdentifier = browser
        let router = URLRouter(config: c, ownBundleIdentifier: "self")
        XCTAssertEqual(router.route(URL(string: "https://unknown.test/path")!), .fallback(browser))
        c.urlRouting.fallbackBrowserBundleIdentifier = "self"
        XCTAssertEqual(URLRouter(config: c, ownBundleIdentifier: "self").route(URL(string: "https://unknown.test")!), .noRoute)
        XCTAssertEqual(router.route(URL(string: "mailto:test@example.com")!), .nonWeb)
        c.urlRouting.fallbackBrowserBundleIdentifier = nil
        XCTAssertEqual(URLRouter(config: c, ownBundleIdentifier: "self").route(URL(string: "https://unknown.test")!), .noRoute)
    }

    func testConfigReplacementDoesNotMutateWhenPersistenceFails() {
        let store = ConfigStore(fileURL: URL(fileURLWithPath: "/dev/null/a-la-kart-config.json"))
        let original = store.config
        var candidate = original
        candidate.ports.confirmBeforeKilling = false
        XCTAssertThrowsError(try store.replace(candidate))
        XCTAssertEqual(store.config, original)
    }

    func testBrowserOptionsDeduplicateByBundleIDAndKeepStableIdentity() {
        let options = BrowserOptionList.deduplicated([
            BrowserOption(name: "Firefox", id: "org.mozilla.firefox"),
            BrowserOption(name: "Google Chrome", id: "com.google.Chrome"),
            BrowserOption(name: "Firefox", id: "org.mozilla.firefox"),
            BrowserOption(name: "Brave Browser", id: "com.brave.Browser")
        ])
        XCTAssertEqual(options.map(\.id), ["com.brave.Browser", "org.mozilla.firefox", "com.google.Chrome"])
        XCTAssertEqual(options.first(where: { $0.id == "com.google.Chrome" })?.id, "com.google.Chrome")
    }
}
