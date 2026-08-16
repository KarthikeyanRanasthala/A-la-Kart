import AppKit
import Carbon

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var controller: MenuController!
    private var configStore: ConfigStore!
    private var receivesAppleEvents = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.isVisible = true
        statusItem.button?.title = "K"
        statusItem.button?.toolTip = "kart-os ports"
        configStore = ConfigStore()
        controller = MenuController(statusItem: statusItem, configStore: configStore)
        statusItem.menu = controller.menu
        NSAppleEventManager.shared().setEventHandler(self, andSelector: #selector(handleGetURL(_:withReplyEvent:)), forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
        receivesAppleEvents = true
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        controller.showURLRoutingSettings()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        if receivesAppleEvents { NSAppleEventManager.shared().removeEventHandler(forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL)); receivesAppleEvents = false }
    }

    @objc private func handleGetURL(_ event: NSAppleEventDescriptor, withReplyEvent replyEvent: NSAppleEventDescriptor) {
        guard let value = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: value) else { return }
        route([url])
    }

    private func route(_ urls: [URL]) {
        let router = URLRouter(config: configStore.config, ownBundleIdentifier: Bundle.main.bundleIdentifier ?? "sh.karthikeyan.kart-os")
        let opener = WorkspaceBrowserOpener()
        for url in urls {
            let result = router.route(url)
            switch result {
            case .browser(let id):
                if !opener.open(url, in: id) { showRoutingError("Could not open this link in \(id). The application may be unavailable.") }
            case .fallback(let id):
                if !opener.open(url, in: id) { showRoutingError("Could not open this link in the fallback browser (\(id)).") }
            case .noRoute:
                showRoutingError("No safe browser is configured. Open URL Routing Settings and choose a fallback browser.")
            case .nonWeb:
                break
            }
        }
    }

    private func showRoutingError(_ message: String) {
        let alert = NSAlert(); alert.messageText = "Could not route URL"; alert.informativeText = message; alert.runModal()
    }
}

@main
enum KartOSApplication {
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.run()
    }
}
