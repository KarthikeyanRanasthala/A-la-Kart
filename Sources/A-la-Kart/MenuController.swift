import AppKit

final class MenuController: NSObject, NSMenuDelegate {
    let menu = NSMenu()
    private let portsMenu = NSMenu(title: "Ports")
    private let service: PortDiscovering
    private let signaler = ProcessSignaler()
    let configStore: ConfigStore
    private var settingsController: SettingsWindowController?
    private var configObserver: NSObjectProtocol?
    private weak var confirmationItem: NSMenuItem?
    private var timer: Timer?
    private var ports: [Port] = []
    private var refreshInFlight = false
    private var hasLoadedPorts = false
    private var rootMenuIsOpen = false
    private var discoveryFailed = false
    private var pendingRefresh: PendingRefresh?

    init(statusItem: NSStatusItem, service: PortDiscovering = LsofService(), configStore: ConfigStore = ConfigStore()) {
        self.service = service
        self.configStore = configStore
        super.init()
        configObserver = NotificationCenter.default.addObserver(forName: ConfigStore.didChange, object: configStore, queue: .main) { [weak self] _ in
            self?.confirmationItem?.state = self?.configStore.config.ports.confirmBeforeKilling == true ? .on : .off
        }
        portsMenu.autoenablesItems = false
        menu.delegate = self

        rebuildPortsMenu()
        let portsItem = NSMenuItem(); portsItem.title = "Ports"; portsItem.submenu = portsMenu; menu.addItem(portsItem)
        addStaticControls()
        refresh()
    }

    func menuWillOpen(_ menu: NSMenu) {
        guard menu === self.menu else { return }
        rootMenuIsOpen = true
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { [weak self] _ in self?.refresh() }
    }

    func menuDidClose(_ menu: NSMenu) {
        guard menu === self.menu else { return }
        rootMenuIsOpen = false
        timer?.invalidate(); timer = nil
        applyPendingRefreshIfSafe()
    }

    @objc func refresh() {
        guard !refreshInFlight else { return }
        refreshInFlight = true
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            do {
                let found = try self.service.discover()
                DispatchQueue.main.async {
                    self.refreshInFlight = false
                    if self.isMenuTracking {
                        self.pendingRefresh = .success(found)
                    } else {
                        self.applySuccess(found)
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.refreshInFlight = false
                    if self.isMenuTracking {
                        self.pendingRefresh = .failure
                    } else {
                        self.applyFailure()
                    }
                }
            }
        }
    }

    private var isMenuTracking: Bool { rootMenuIsOpen }

    private func applyPendingRefreshIfSafe() {
        guard !isMenuTracking, let pendingRefresh else { return }
        self.pendingRefresh = nil
        switch pendingRefresh {
        case .success(let found): applySuccess(found)
        case .failure: applyFailure()
        }
    }

    private func applySuccess(_ found: [Port]) {
        guard !isMenuTracking else { return }
        ports = found
        hasLoadedPorts = true
        discoveryFailed = false
        rebuildPortsMenu()
    }

    private func applyFailure() {
        guard !isMenuTracking, !hasLoadedPorts else { return }
        discoveryFailed = true
        rebuildPortsMenu()
    }

    private func rebuildPortsMenu() {
        guard !isMenuTracking else { return }
        portsMenu.removeAllItems()

        let refreshItem = NSMenuItem(title: "Refresh", action: #selector(refresh), keyEquivalent: "")
        refreshItem.target = self
        portsMenu.addItem(refreshItem)
        let confirm = NSMenuItem(title: "Confirm Before Killing", action: #selector(toggleConfirmation(_:)), keyEquivalent: "")
        confirm.target = self
        confirm.state = configStore.config.ports.confirmBeforeKilling ? .on : .off
        portsMenu.addItem(confirm)
        confirmationItem = confirm
        portsMenu.addItem(NSMenuItem.separator())

        if !hasLoadedPorts {
            let stateTitle = discoveryFailed ? "Unable to read ports" : "Loading…"
            let state = NSMenuItem(title: stateTitle, action: nil, keyEquivalent: "")
            state.isEnabled = false
            portsMenu.addItem(state)
            return
        }

        let hint = NSMenuItem(title: "Select a port for process actions", action: nil, keyEquivalent: "")
        hint.isEnabled = false
        portsMenu.addItem(hint)

        if ports.isEmpty {
            let empty = NSMenuItem(title: "No bound or listening ports", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            portsMenu.addItem(empty)
            return
        }

        for port in ports {
            let app = NSRunningApplication(processIdentifier: port.pid)
            let allowed = signaler.canSignal(port.pid)
            let detail = NSMenu(title: port.title)
            detail.autoenablesItems = false

            let friendly = app?.localizedName ?? port.processName
            let info = NSMenuItem(); info.title = "\(friendly) · \(port.endpoint)"; info.isEnabled = false
            detail.addItem(info)
            detail.addItem(NSMenuItem.separator())

            let term = NSMenuItem(); term.title = "Terminate (SIGTERM)"; term.action = #selector(terminate(_:)); term.target = self; term.representedObject = Action(port: port, force: false); term.isEnabled = allowed
            detail.addItem(term)
            let force = NSMenuItem(); force.title = "Force Kill (SIGKILL)"; force.action = #selector(terminate(_:)); force.target = self; force.representedObject = Action(port: port, force: true); force.isEnabled = allowed
            detail.addItem(force)

            let item = NSMenuItem(); item.title = port.title; item.submenu = detail; item.toolTip = port.endpoint
            portsMenu.addItem(item)
        }
    }

    private func addStaticControls() {
        let settings = NSMenuItem(title: "URL Routing Settings…", action: #selector(openSettings), keyEquivalent: "")
        settings.target = self
        settings.image = NSImage(systemSymbolName: "arrow.triangle.branch", accessibilityDescription: "URL Routing")
        menu.addItem(settings)
        menu.addItem(NSMenuItem.separator())
        let quit = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    @objc private func toggleConfirmation(_ item: NSMenuItem) {
        var updated = configStore.config
        updated.ports.confirmBeforeKilling = item.state != .on
        do { try configStore.replace(updated) } catch {
            let alert = NSAlert(); alert.messageText = "Could not save settings"; alert.informativeText = error.localizedDescription; alert.runModal()
        }
    }

    @objc private func terminate(_ item: NSMenuItem) {
        guard let action = item.representedObject as? Action else { return }
        if configStore.config.ports.confirmBeforeKilling {
            let alert = NSAlert()
            alert.messageText = action.force ? "Force kill process?" : "Terminate process?"
            alert.informativeText = "Send SIG\(action.force ? "KILL" : "TERM") to \(action.port.processName) (PID \(action.port.pid))?"
            alert.addButton(withTitle: action.force ? "Force Kill" : "Terminate")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        do {
            try signaler.terminate(action.port.pid, force: action.force)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { self.refresh() }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Could not signal process"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    @objc private func quit() { NSApplication.shared.terminate(nil) }

    deinit { if let configObserver { NotificationCenter.default.removeObserver(configObserver) } }

    func showURLRoutingSettings() {
        if settingsController == nil { settingsController = SettingsWindowController(store: configStore) }
        settingsController?.showWindow(nil)
        settingsController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func openSettings() { showURLRoutingSettings() }

    private final class Action {
        let port: Port
        let force: Bool
        init(port: Port, force: Bool) { self.port = port; self.force = force }
    }

    private enum PendingRefresh { case success([Port]); case failure }
}
