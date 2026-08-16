import AppKit

final class SettingsWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    private let store: ConfigStore
    private let handler = DefaultHandlerManager()
    private let discovery = BrowserDiscovery()
    private var browsers: [BrowserOption] = []
    private let enabled = NSButton(checkboxWithTitle: "Enable URL routing", target: nil, action: nil)
    private let status = NSTextField(labelWithString: "")
    private let fallback = NSPopUpButton()
    private let fallbackLabel = NSTextField(labelWithString: "Fallback browser:")
    private let table = NSTableView()
    private let editButton = NSButton(title: "Edit", target: nil, action: nil)
    private let removeButton = NSButton(title: "Remove", target: nil, action: nil)
    private let toggleButton = NSButton(title: "Enable/Disable", target: nil, action: nil)
    private let moveUpButton = NSButton(title: "Move Up", target: nil, action: nil)
    private let moveDownButton = NSButton(title: "Move Down", target: nil, action: nil)
    private var defaultHandlerTimer: Timer?
    private var defaultHandlerChecks = 0
    private var hasPositionedWindow = false
    private var rules: [KartOSConfig.Rule] { store.config.urlRouting.rules }

    init(store: ConfigStore) {
        self.store = store
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 700, height: 500))
        let window = NSWindow(contentRect: view.frame, styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "URL Routing Settings"
        super.init(window: window)
        window.contentView = view
        build(view)
        reload()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func build(_ view: NSView) {
        enabled.target = self; enabled.action = #selector(toggleEnabled)
        status.font = .systemFont(ofSize: 12); status.textColor = .secondaryLabelColor
        let defaultButton = NSButton(title: "Set kart-os as Default Browser", target: self, action: #selector(setDefault))
        let appsButton = NSButton(title: "Open Default Browser Settings", target: self, action: #selector(openApps))
        let intro = NSTextField(wrappingLabelWithString: "Route links to different browsers based on domain.")
        let host = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("host")); host.title = "Host pattern"; host.width = 220
        let sub = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("sub")); sub.title = "Subdomains"; sub.width = 100
        let target = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("target")); target.title = "Browser"; target.width = 200
        let state = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("state")); state.title = "Enabled"; state.width = 80
        [host, sub, target, state].forEach { table.addTableColumn($0) }; table.delegate = self; table.dataSource = self; table.usesAlternatingRowBackgroundColors = true
        let scroll = NSScrollView(); scroll.documentView = table; scroll.hasVerticalScroller = true
        let add = NSButton(title: "Add", target: self, action: #selector(addRule))
        editButton.target = self; editButton.action = #selector(editRule)
        removeButton.target = self; removeButton.action = #selector(removeRule)
        toggleButton.target = self; toggleButton.action = #selector(toggleRule)
        moveUpButton.target = self; moveUpButton.action = #selector(moveRuleUp)
        moveDownButton.target = self; moveDownButton.action = #selector(moveRuleDown)
        let export = NSButton(title: "Export Config…", target: self, action: #selector(exportConfig)); let imp = NSButton(title: "Import Config…", target: self, action: #selector(importConfig))
        let controls = NSStackView(views: [add, editButton, removeButton, toggleButton, moveUpButton, moveDownButton]); controls.spacing = 8
        let io = NSStackView(views: [export, imp]); io.spacing = 8
        fallback.target = self; fallback.action = #selector(fallbackChanged)
        updateRuleButtonStates()
        [intro, enabled, status, defaultButton, appsButton, fallbackLabel, fallback, scroll, controls, io].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; view.addSubview($0) }
        NSLayoutConstraint.activate([
            intro.topAnchor.constraint(equalTo: view.topAnchor, constant: 18), intro.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 18), intro.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -18),
            enabled.topAnchor.constraint(equalTo: intro.bottomAnchor, constant: 12), enabled.leadingAnchor.constraint(equalTo: intro.leadingAnchor), status.centerYAnchor.constraint(equalTo: enabled.centerYAnchor), status.leadingAnchor.constraint(equalTo: enabled.trailingAnchor, constant: 18),
            defaultButton.topAnchor.constraint(equalTo: enabled.bottomAnchor, constant: 10), defaultButton.leadingAnchor.constraint(equalTo: intro.leadingAnchor), appsButton.centerYAnchor.constraint(equalTo: defaultButton.centerYAnchor), appsButton.leadingAnchor.constraint(equalTo: defaultButton.trailingAnchor, constant: 10),
            fallbackLabel.centerYAnchor.constraint(equalTo: fallback.centerYAnchor), fallbackLabel.leadingAnchor.constraint(equalTo: intro.leadingAnchor), fallback.topAnchor.constraint(equalTo: defaultButton.bottomAnchor, constant: 10), fallback.leadingAnchor.constraint(equalTo: fallbackLabel.trailingAnchor, constant: 8), fallback.widthAnchor.constraint(equalToConstant: 300),
            scroll.topAnchor.constraint(equalTo: fallback.bottomAnchor, constant: 12), scroll.leadingAnchor.constraint(equalTo: intro.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: intro.trailingAnchor), scroll.heightAnchor.constraint(equalToConstant: 250),
            controls.topAnchor.constraint(equalTo: scroll.bottomAnchor, constant: 8), controls.leadingAnchor.constraint(equalTo: intro.leadingAnchor), io.topAnchor.constraint(equalTo: controls.bottomAnchor, constant: 12), io.leadingAnchor.constraint(equalTo: intro.leadingAnchor), io.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -15)
        ])
    }
    override func showWindow(_ sender: Any?) {
        reload()
        if !hasPositionedWindow {
            window?.center()
            hasPositionedWindow = true
        }
        super.showWindow(sender)
    }
    private let noFallbackID = "__kart_os_no_fallback__"
    private func reload() {
        browsers = discovery.browsers()
        enabled.state = store.config.urlRouting.enabled ? .on : .off
        fallback.removeAllItems()
        fallback.addItem(withTitle: "No fallback (do not open)")
        fallback.lastItem?.representedObject = noFallbackID
        browsers.forEach { option in
            fallback.addItem(withTitle: option.name)
            fallback.lastItem?.representedObject = option.id
        }
        if let id = store.config.urlRouting.fallbackBrowserBundleIdentifier {
            if fallback.itemArray.first(where: { $0.representedObject as? String == id }) == nil {
                fallback.addItem(withTitle: "Unavailable: \(id)")
                fallback.lastItem?.representedObject = id
            }
            if let index = fallback.itemArray.firstIndex(where: { $0.representedObject as? String == id }) { fallback.selectItem(at: index) }
        } else if let index = fallback.itemArray.firstIndex(where: { $0.representedObject as? String == noFallbackID }) { fallback.selectItem(at: index) }
        status.stringValue = handler.ownsBoth ? "Default handler: kart-os (HTTP + HTTPS)" : "Not the default handler for both HTTP and HTTPS"
        table.reloadData()
        updateRuleButtonStates()
    }
    private func save(_ update: (inout KartOSConfig) -> Void) { var value = store.config; update(&value); do { try store.replace(value); reload() } catch { alert(error.localizedDescription) } }
    func numberOfRows(in tableView: NSTableView) -> Int { rules.count }
    func tableViewSelectionDidChange(_ notification: Notification) { updateRuleButtonStates() }
    private func updateRuleButtonStates() {
        let hasSelection = table.selectedRow >= 0
        editButton.isEnabled = hasSelection
        removeButton.isEnabled = hasSelection
        toggleButton.isEnabled = hasSelection
        moveUpButton.isEnabled = hasSelection
        moveDownButton.isEnabled = hasSelection
    }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let container = NSTableCellView()
        let label = NSTextField(labelWithString: "")
        let rule = rules[row]
        switch tableColumn?.identifier.rawValue {
        case "host": label.stringValue = rule.host
        case "sub": label.stringValue = rule.includeSubdomains ? "Yes" : "No"
        case "target": label.stringValue = browsers.first(where: { $0.id == rule.browserBundleIdentifier })?.name ?? rule.browserBundleIdentifier
        case "state": label.stringValue = rule.enabled ? "Yes" : "No"
        default: break
        }
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)
        container.textField = label
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 4),
            label.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -4),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])
        return container
    }
    @objc private func toggleEnabled() { save { $0.urlRouting.enabled = enabled.state == .on } }
    @objc private func fallbackChanged() { let selected = fallback.selectedItem?.representedObject as? String; save { $0.urlRouting.fallbackBrowserBundleIdentifier = selected == noFallbackID ? nil : selected } }
    @objc private func setDefault() { if store.config.urlRouting.fallbackBrowserBundleIdentifier == nil, let old = handler.handler(for: "https"), old != handler.bundleIdentifier { var value = store.config; value.urlRouting.fallbackBrowserBundleIdentifier = old; do { try store.replace(value) } catch { alert(error.localizedDescription); return } }; handler.requestDefaultHandlers(); waitForDefaultHandlerConfirmation() }
    private func waitForDefaultHandlerConfirmation() { defaultHandlerTimer?.invalidate(); defaultHandlerChecks = 0; status.stringValue = "Waiting for macOS confirmation…"; defaultHandlerTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] timer in guard let self else { timer.invalidate(); return }; if self.handler.ownsBoth { timer.invalidate(); self.defaultHandlerTimer = nil; self.reload(); return }; self.defaultHandlerChecks += 1; if self.defaultHandlerChecks >= 60 { timer.invalidate(); self.defaultHandlerTimer = nil; self.status.stringValue = "Not the default handler. You can retry or use Default Apps Settings." } } }
    @objc private func openApps() { handler.openDefaultApps() }
    @objc private func addRule() { edit(nil) }
    @objc private func editRule() { guard table.selectedRow >= 0 else { return }; edit(table.selectedRow) }
    private func edit(_ index: Int?) {
        let host = NSTextField(string: index.map { rules[$0].host } ?? "")
        let hostLabel = NSTextField(labelWithString: "Host (for example, example.com)")
        let sub = NSButton(checkboxWithTitle: "Include subdomains", target: nil, action: nil)
        sub.state = index.map { rules[$0].includeSubdomains } == true ? .on : .off
        let popup = NSPopUpButton()
        browsers.forEach { option in popup.addItem(withTitle: option.name); popup.lastItem?.representedObject = option.id }
        if let i = index {
            let targetID = rules[i].browserBundleIdentifier
            if popup.itemArray.first(where: { $0.representedObject as? String == targetID }) == nil { popup.addItem(withTitle: "Unavailable: \(targetID)"); popup.lastItem?.representedObject = targetID }
            if let targetIndex = popup.itemArray.firstIndex(where: { $0.representedObject as? String == targetID }) { popup.selectItem(at: targetIndex) }
        }

        let editor = NSView(frame: NSRect(x: 0, y: 0, width: 380, height: 116))
        [hostLabel, host, sub, popup].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            editor.addSubview($0)
        }
        NSLayoutConstraint.activate([
            hostLabel.topAnchor.constraint(equalTo: editor.topAnchor),
            hostLabel.leadingAnchor.constraint(equalTo: editor.leadingAnchor),
            hostLabel.trailingAnchor.constraint(equalTo: editor.trailingAnchor),
            host.topAnchor.constraint(equalTo: hostLabel.bottomAnchor, constant: 6),
            host.leadingAnchor.constraint(equalTo: editor.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: editor.trailingAnchor),
            sub.topAnchor.constraint(equalTo: host.bottomAnchor, constant: 10),
            sub.leadingAnchor.constraint(equalTo: editor.leadingAnchor),
            popup.topAnchor.constraint(equalTo: sub.bottomAnchor, constant: 8),
            popup.leadingAnchor.constraint(equalTo: editor.leadingAnchor),
            popup.trailingAnchor.constraint(equalTo: editor.trailingAnchor),
            popup.bottomAnchor.constraint(equalTo: editor.bottomAnchor)
        ])

        let alert = NSAlert()
        alert.messageText = index == nil ? "Add URL Rule" : "Edit URL Rule"
        alert.accessoryView = editor
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = host
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        guard let normalized = try? Hostname.normalize(host.stringValue) else { self.alert("Enter a valid hostname without a scheme or path."); return }
        guard let browserID = popup.selectedItem?.representedObject as? String, !browserID.isEmpty else { self.alert("Select an installed browser for this rule."); return }
        save { config in
            let rule = KartOSConfig.Rule(host: normalized, includeSubdomains: sub.state == .on, browserBundleIdentifier: browserID)
            if let i = index {
                config.urlRouting.rules[i] = KartOSConfig.Rule(host: normalized, includeSubdomains: sub.state == .on, browserBundleIdentifier: browserID, enabled: config.urlRouting.rules[i].enabled, id: config.urlRouting.rules[i].id)
            } else {
                config.urlRouting.rules.append(rule)
            }
        }
    }
    @objc private func removeRule() { guard table.selectedRow >= 0 else { return }; save { $0.urlRouting.rules.remove(at: table.selectedRow) } }
    @objc private func toggleRule() { guard table.selectedRow >= 0 else { return }; save { $0.urlRouting.rules[table.selectedRow].enabled.toggle() } }
    @objc private func moveRuleUp() { move(-1) }; @objc private func moveRuleDown() { move(1) }
    private func move(_ delta: Int) { let i = table.selectedRow, j = i + delta; guard i >= 0, j >= 0, j < rules.count else { return }; save { $0.urlRouting.rules.swapAt(i, j) }; table.selectRowIndexes(IndexSet(integer: j), byExtendingSelection: false) }
    @objc private func exportConfig() { let panel = NSSavePanel(); panel.nameFieldStringValue = "kart-os-config.json"; guard panel.runModal() == .OK, let url = panel.url else { return }; do { try store.encoded().write(to: url, options: .atomic) } catch { alert(error.localizedDescription) } }
    @objc private func importConfig() { let panel = NSOpenPanel(); panel.allowedFileTypes = ["json"]; guard panel.runModal() == .OK, let url = panel.url else { return }; do { let value = try JSONDecoder().decode(KartOSConfig.self, from: Data(contentsOf: url)); try store.replace(value); reload() } catch { alert(error.localizedDescription) } }
    private func alert(_ message: String) { let a = NSAlert(); a.messageText = "kart-os"; a.informativeText = message; a.runModal() }
}
private extension Array { subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil } }
