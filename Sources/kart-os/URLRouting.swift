import AppKit
import CoreServices

struct KartOSConfig: Codable, Equatable {
    static let currentSchemaVersion = 1
    var schemaVersion: Int = 1
    var ports = PortsConfig()
    var urlRouting = URLRoutingConfig()

    struct PortsConfig: Codable, Equatable { var confirmBeforeKilling = true }
    struct URLRoutingConfig: Codable, Equatable {
        var enabled = true
        var fallbackBrowserBundleIdentifier: String?
        var rules: [Rule] = []
    }
    struct Rule: Codable, Equatable {
        var host: String
        var includeSubdomains = false
        var browserBundleIdentifier: String
        var enabled = true
        var id = UUID()
    }

    func validated() throws -> KartOSConfig {
        guard schemaVersion == Self.currentSchemaVersion else { throw ConfigError.unsupportedSchema }
        var copy = self
        var hosts = Set<String>()
        for index in copy.urlRouting.rules.indices {
            let normalized = try Hostname.normalize(copy.urlRouting.rules[index].host)
            guard hosts.insert(normalized).inserted else { throw ConfigError.duplicateHost }
            copy.urlRouting.rules[index].host = normalized
            guard !copy.urlRouting.rules[index].browserBundleIdentifier.isEmpty,
                  copy.urlRouting.rules[index].browserBundleIdentifier != Bundle.main.bundleIdentifier else { throw ConfigError.invalidBrowser }
        }
        if let fallback = copy.urlRouting.fallbackBrowserBundleIdentifier,
           fallback.isEmpty || fallback == Bundle.main.bundleIdentifier { throw ConfigError.invalidBrowser }
        return copy
    }
}

enum ConfigError: LocalizedError { case unsupportedSchema, duplicateHost, invalidHost, invalidBrowser
    var errorDescription: String? { switch self { case .unsupportedSchema: return "This configuration was created by a newer version of kart-os."; case .duplicateHost: return "Rules contain a duplicate host."; case .invalidHost: return "Enter a valid hostname without a scheme or path."; case .invalidBrowser: return "The selected browser is invalid." } }
}

enum Hostname {
    static func normalize(_ value: String) throws -> String {
        let host = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        // URL(string:) accepts many values which are not host patterns.
        guard !host.isEmpty, host.count <= 253, !host.contains("/"), !host.contains(":"), isValid(host) else { throw ConfigError.invalidHost }
        return host
    }
    private static func isValid(_ host: String) -> Bool {
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        return !labels.isEmpty && labels.allSatisfy { label in
            !label.isEmpty && label.first != "-" && label.last != "-" && label.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" }
        }
    }
}

final class ConfigStore {
    static let didChange = Notification.Name("KartOSConfigStoreDidChange")
    private(set) var config: KartOSConfig
    let fileURL: URL
    init(fileURL: URL? = nil, defaults: UserDefaults = .standard) {
        self.fileURL = fileURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("kart-os/config.json")
        if let data = try? Data(contentsOf: self.fileURL), let decoded = try? JSONDecoder().decode(KartOSConfig.self, from: data), let valid = try? decoded.validated() { config = valid }
        else { config = KartOSConfig(); if let old = defaults.object(forKey: "confirmBeforeKilling") as? Bool { config.ports.confirmBeforeKilling = old }; try? save(config) }
    }
    func replace(_ value: KartOSConfig) throws {
        let candidate = try value.validated()
        try save(candidate)
        config = candidate
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }
    func encoded() throws -> Data { let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; return try encoder.encode(config) }
    private func save(_ candidate: KartOSConfig) throws { let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; let data = try encoder.encode(candidate); let dir = fileURL.deletingLastPathComponent(); try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true); let temp = dir.appendingPathComponent(".config-\(UUID().uuidString)"); try data.write(to: temp, options: .atomic); if FileManager.default.fileExists(atPath: fileURL.path) { _ = try FileManager.default.replaceItemAt(fileURL, withItemAt: temp) } else { try FileManager.default.moveItem(at: temp, to: fileURL) } }
}

protocol BrowserOpening { func open(_ url: URL, in bundleIdentifier: String) -> Bool }
final class WorkspaceBrowserOpener: BrowserOpening {
    func open(_ url: URL, in bundleIdentifier: String) -> Bool { guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else { return false }; NSWorkspace.shared.open([url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration()); return true }
}

enum RouteResult: Equatable { case browser(String), fallback(String), nonWeb, noRoute }
struct URLRouter {
    let config: KartOSConfig
    let ownBundleIdentifier: String
    func route(_ url: URL) -> RouteResult {
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return .nonWeb }
        guard let raw = url.host, let host = try? Hostname.normalize(raw) else { return .noRoute }
        if config.urlRouting.enabled {
            for rule in config.urlRouting.rules where rule.enabled && (host == rule.host || (rule.includeSubdomains && host.hasSuffix("." + rule.host))) { return rule.browserBundleIdentifier == ownBundleIdentifier ? .noRoute : .browser(rule.browserBundleIdentifier) }
        }
        guard let fallback = config.urlRouting.fallbackBrowserBundleIdentifier, fallback != ownBundleIdentifier else { return .noRoute }
        return .fallback(fallback)
    }
    @discardableResult func open(_ url: URL, opener: BrowserOpening) -> Bool { switch route(url) { case .browser(let id), .fallback(let id): return opener.open(url, in: id); case .nonWeb, .noRoute: return false } }
}

struct BrowserOption: Equatable {
    let name: String
    let id: String
}

enum BrowserOptionList {
    static func deduplicated(_ options: [BrowserOption]) -> [BrowserOption] {
        var byID: [String: BrowserOption] = [:]
        for option in options {
            if let existing = byID[option.id] {
                if option.name.localizedCaseInsensitiveCompare(existing.name) == .orderedAscending { byID[option.id] = option }
            } else { byID[option.id] = option }
        }
        return byID.values.sorted {
            let left = $0.name.lowercased()
            let right = $1.name.lowercased()
            return left == right ? $0.id < $1.id : left < right
        }
    }
}

final class BrowserDiscovery {
    func browsers() -> [BrowserOption] {
        guard let url = URL(string: "https://example.com") else { return [] }
        let discovered = NSWorkspace.shared.urlsForApplications(toOpen: url).compactMap { (url: URL) -> BrowserOption? in
            guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier, id != Bundle.main.bundleIdentifier else { return nil }
            return BrowserOption(name: bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? url.deletingPathExtension().lastPathComponent, id: id)
        }
        return BrowserOptionList.deduplicated(discovered)
    }
}

final class DefaultHandlerManager {
    let bundleIdentifier: String
    init(bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "sh.karthikeyan.kart-os") { self.bundleIdentifier = bundleIdentifier }
    func handler(for scheme: String) -> String? { LSCopyDefaultHandlerForURLScheme(scheme as CFString)?.takeRetainedValue() as String? }
    var ownsBoth: Bool { handler(for: "http") == bundleIdentifier && handler(for: "https") == bundleIdentifier }
    func requestDefaultHandlers() {
        _ = LSSetDefaultHandlerForURLScheme("http" as CFString, bundleIdentifier as CFString)
        _ = LSSetDefaultHandlerForURLScheme("https" as CFString, bundleIdentifier as CFString)
    }
    func openDefaultApps() { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Desktop-Settings.extension?Widgets")!) }
}
