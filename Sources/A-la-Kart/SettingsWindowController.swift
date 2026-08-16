import AppKit
import UniformTypeIdentifiers

final class SettingsWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    private let store: ConfigStore
    private let handler = DefaultHandlerManager()
    private let discovery = BrowserDiscovery()
    private var browsers: [BrowserOption] = []
    private let enabled = NSButton(checkboxWithTitle: "Enable URL routing", target: nil, action: nil)
    private let statusIcon = NSImageView()
    private let status = NSTextField(labelWithString: "")
    private let fallback = NSPopUpButton()
    private let table = NSTableView()
    private let emptyState = NSTextField(wrappingLabelWithString: "No domain rules yet. Add a rule to route a domain to a specific browser.")
    private let editButton = NSButton(title: "Edit", target: nil, action: nil)
    private let removeButton = NSButton(title: "Remove", target: nil, action: nil)
    private let toggleButton = NSButton(title: "Enable", target: nil, action: nil)
    private let moveUpButton = NSButton(title: "Move Up", target: nil, action: nil)
    private let moveDownButton = NSButton(title: "Move Down", target: nil, action: nil)
    private var defaultHandlerTimer: Timer?
    private var defaultHandlerChecks = 0
    private var hasPositionedWindow = false
    private var rules: [ALaKartConfig.Rule] { store.config.urlRouting.rules }
    private let noFallbackID = "__a_la_kart_no_fallback__"

    init(store: ConfigStore) {
        self.store = store
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 820, height: 700),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "URL Routing Settings"
        window.titleVisibility = .hidden
        window.minSize = NSSize(width: 700, height: 640)
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unified
        super.init(window: window)
        let content = NSView()
        content.translatesAutoresizingMaskIntoConstraints = false
        window.contentView = content
        build(in: content)
        reload()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func build(in view: NSView) {
        let headerIcon = NSImageView(image: NSImage(systemSymbolName: "arrow.triangle.branch", accessibilityDescription: "URL Routing") ?? NSImage())
        headerIcon.contentTintColor = .controlAccentColor
        headerIcon.symbolConfiguration = .init(pointSize: 28, weight: .medium)
        let title = NSTextField(labelWithString: "URL Routing")
        title.font = .systemFont(ofSize: 22, weight: .semibold)
        title.alignment = .center
        let subtitle = NSTextField(wrappingLabelWithString: "Route links to different browsers based on domain.")
        subtitle.textColor = .secondaryLabelColor
        subtitle.alignment = .center
        let header = NSStackView(views: [headerIcon, title, subtitle])
        header.orientation = .vertical
        header.alignment = .centerX
        header.spacing = 3
        header.setCustomSpacing(8, after: headerIcon)

        enabled.target = self; enabled.action = #selector(toggleEnabled)
        let defaultButton = button("Set as Default", symbol: "checkmark.shield", action: #selector(setDefault))
        let appsButton = button("Open System Settings", symbol: "gear", action: #selector(openApps))
        let statusRow = NSStackView(views: [statusIcon, status]); statusRow.spacing = 7; statusRow.alignment = .centerY
        statusIcon.imageScaling = .scaleProportionallyDown
        statusIcon.setContentHuggingPriority(.required, for: .horizontal)
        statusIcon.setContentCompressionResistancePriority(.required, for: .horizontal)
        fallback.translatesAutoresizingMaskIntoConstraints = false
        fallback.target = self; fallback.action = #selector(fallbackChanged)
        let fallbackLabel = NSTextField(labelWithString: "Fallback browser")
        fallbackLabel.textColor = .secondaryLabelColor
        let fallbackRow = NSStackView(views: [fallbackLabel, fallback]); fallbackRow.spacing = 10; fallbackRow.alignment = .centerY
        fallback.widthAnchor.constraint(greaterThanOrEqualToConstant: 280).isActive = true
        let defaultsContent = NSStackView(views: [enabled, statusRow, fallbackRow, NSStackView(views: [defaultButton, appsButton])])
        defaultsContent.orientation = .vertical; defaultsContent.spacing = 10
        let defaultsBox = card(title: "Default browser", content: defaultsContent)

        configureTable()
        let scroll = NSScrollView()
        scroll.documentView = table; scroll.hasVerticalScroller = true; scroll.drawsBackground = false
        scroll.borderType = .bezelBorder
        let tableHost = NSView(); tableHost.addSubview(scroll); tableHost.addSubview(emptyState)
        scroll.translatesAutoresizingMaskIntoConstraints = false; emptyState.translatesAutoresizingMaskIntoConstraints = false
        emptyState.alignment = .center; emptyState.textColor = .secondaryLabelColor
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: tableHost.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: tableHost.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: tableHost.topAnchor), scroll.bottomAnchor.constraint(equalTo: tableHost.bottomAnchor),
            emptyState.centerXAnchor.constraint(equalTo: tableHost.centerXAnchor), emptyState.centerYAnchor.constraint(equalTo: tableHost.centerYAnchor),
            emptyState.leadingAnchor.constraint(greaterThanOrEqualTo: tableHost.leadingAnchor, constant: 30), emptyState.trailingAnchor.constraint(lessThanOrEqualTo: tableHost.trailingAnchor, constant: -30)
        ])
        let add = button("Add", symbol: "plus", action: #selector(addRule))
        editButton.target = self; editButton.action = #selector(editRule)
        removeButton.target = self; removeButton.action = #selector(removeRule)
        toggleButton.target = self; toggleButton.action = #selector(toggleRule)
        moveUpButton.target = self; moveUpButton.action = #selector(moveRuleUp)
        moveDownButton.target = self; moveDownButton.action = #selector(moveRuleDown)
        configureButton(editButton, symbol: "pencil", tooltip: "Edit the selected rule")
        configureButton(removeButton, symbol: "trash", tooltip: "Remove the selected rule")
        configureButton(toggleButton, symbol: "checkmark.circle", tooltip: "Enable or disable the selected rule")
        configureButton(moveUpButton, symbol: "chevron.up", tooltip: "Move the selected rule up")
        configureButton(moveDownButton, symbol: "chevron.down", tooltip: "Move the selected rule down")
        let ruleActions = NSStackView(views: [add, editButton, removeButton, toggleButton, moveUpButton, moveDownButton]); ruleActions.spacing = 8
        let rulesContent = NSStackView(views: [tableHost, ruleActions]); rulesContent.orientation = .vertical; rulesContent.spacing = 10
        tableHost.heightAnchor.constraint(greaterThanOrEqualToConstant: 200).isActive = true
        let rulesBox = card(title: "Domain rules", content: rulesContent)

        let export = button("Export full config…", symbol: "square.and.arrow.up", action: #selector(exportConfig))
        let imp = button("Import full config…", symbol: "square.and.arrow.down", action: #selector(importConfig))
        let footer = NSStackView(views: [export, imp]); footer.spacing = 8
        [header, defaultsBox, rulesBox, footer].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; view.addSubview($0) }
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: view.topAnchor, constant: 22), header.centerXAnchor.constraint(equalTo: view.centerXAnchor), header.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24), header.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24),
            defaultsBox.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 20), defaultsBox.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24), defaultsBox.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            rulesBox.topAnchor.constraint(equalTo: defaultsBox.bottomAnchor, constant: 16), rulesBox.leadingAnchor.constraint(equalTo: defaultsBox.leadingAnchor), rulesBox.trailingAnchor.constraint(equalTo: defaultsBox.trailingAnchor),
            footer.topAnchor.constraint(equalTo: rulesBox.bottomAnchor, constant: 12), footer.leadingAnchor.constraint(equalTo: defaultsBox.leadingAnchor), footer.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -18)
        ])
        rulesBox.heightAnchor.constraint(greaterThanOrEqualToConstant: 280).isActive = true
    }

    private func card(title: String, content: NSView) -> NSBox {
        let box = NSBox(); box.boxType = .custom; box.cornerRadius = 10; box.borderWidth = 1; box.borderColor = .separatorColor; box.fillColor = .windowBackgroundColor
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .secondaryLabelColor
        let cardContent = NSStackView(views: [titleLabel, content])
        cardContent.orientation = .vertical
        cardContent.spacing = 8
        cardContent.alignment = .leading
        box.contentView?.addSubview(cardContent)
        cardContent.translatesAutoresizingMaskIntoConstraints = false
        content.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([cardContent.leadingAnchor.constraint(equalTo: box.contentView!.leadingAnchor, constant: 14), cardContent.trailingAnchor.constraint(equalTo: box.contentView!.trailingAnchor, constant: -14), cardContent.topAnchor.constraint(equalTo: box.contentView!.topAnchor, constant: 10), cardContent.bottomAnchor.constraint(equalTo: box.contentView!.bottomAnchor, constant: -12), content.trailingAnchor.constraint(equalTo: cardContent.trailingAnchor)])
        return box
    }

    private func button(_ title: String, symbol: String, action: Selector) -> NSButton { let result = NSButton(title: title, target: self, action: action); configureButton(result, symbol: symbol, tooltip: title); return result }
    private func configureButton(_ button: NSButton, symbol: String, tooltip: String) { button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip); button.imagePosition = .imageLeading; button.toolTip = tooltip; button.bezelStyle = .rounded }

    private func configureTable() {
        let columns: [(String, String, CGFloat)] = [("host", "Host pattern", 200), ("sub", "Subdomains", 95), ("target", "Browser", 175), ("state", "Enabled", 95)]
        for (id, title, width) in columns { let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id)); column.title = title; column.width = width; table.addTableColumn(column) }
        table.delegate = self; table.dataSource = self; table.usesAlternatingRowBackgroundColors = true; table.rowHeight = 32; table.headerView = NSTableHeaderView()
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.allowsEmptySelection = true
    }

    override func showWindow(_ sender: Any?) { reload(); if !hasPositionedWindow { window?.center(); hasPositionedWindow = true }; super.showWindow(sender) }

    private func reload() {
        browsers = discovery.browsers(); enabled.state = store.config.urlRouting.enabled ? .on : .off
        fallback.removeAllItems(); fallback.addItem(withTitle: "No fallback (do not open)"); fallback.lastItem?.representedObject = noFallbackID
        for option in browsers { fallback.addItem(withTitle: option.name); fallback.lastItem?.representedObject = option.id }
        if let id = store.config.urlRouting.fallbackBrowserBundleIdentifier {
            if fallback.itemArray.first(where: { $0.representedObject as? String == id }) == nil { fallback.addItem(withTitle: "Unavailable: \(id)"); fallback.lastItem?.representedObject = id }
            if let index = fallback.itemArray.firstIndex(where: { $0.representedObject as? String == id }) { fallback.selectItem(at: index) }
        } else { fallback.selectItem(at: 0) }
        status.stringValue = handler.ownsBoth ? "Default handler: A la Kart (HTTP + HTTPS)" : "Not the default handler for both HTTP and HTTPS"
        statusIcon.image = NSImage(systemSymbolName: handler.ownsBoth ? "checkmark.circle.fill" : "exclamationmark.circle.fill", accessibilityDescription: handler.ownsBoth ? "Default handler" : "Not the default handler")
        statusIcon.contentTintColor = handler.ownsBoth ? .systemGreen : .systemOrange
        table.reloadData(); emptyState.isHidden = !rules.isEmpty; updateRuleButtonStates()
    }

    private func save(_ update: (inout ALaKartConfig) -> Void) { var value = store.config; update(&value); do { try store.replace(value); reload() } catch { alert(error.localizedDescription) } }
    func numberOfRows(in tableView: NSTableView) -> Int { rules.count }
    func tableViewSelectionDidChange(_ notification: Notification) { updateRuleButtonStates() }
    private func updateRuleButtonStates() { let i = table.selectedRow; let selected = i >= 0 && i < rules.count; editButton.isEnabled = selected; removeButton.isEnabled = selected; toggleButton.isEnabled = selected; moveUpButton.isEnabled = selected && i > 0; moveDownButton.isEnabled = selected && i < rules.count - 1; toggleButton.title = selected && rules[i].enabled ? "Disable" : "Enable" }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = NSTableCellView(); let label = NSTextField(labelWithString: ""); label.alignment = .center; label.lineBreakMode = .byTruncatingTail; label.translatesAutoresizingMaskIntoConstraints = false
        let rule = rules[row]; switch tableColumn?.identifier.rawValue { case "host": label.stringValue = rule.host; case "sub": label.stringValue = rule.includeSubdomains ? "Yes" : "No"; case "target": label.stringValue = browsers.first(where: { $0.id == rule.browserBundleIdentifier })?.name ?? rule.browserBundleIdentifier; case "state": label.stringValue = rule.enabled ? "Yes" : "No"; default: break }
        cell.addSubview(label); cell.textField = label; NSLayoutConstraint.activate([label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8), label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8), label.centerYAnchor.constraint(equalTo: cell.centerYAnchor)]); return cell
    }

    @objc private func toggleEnabled() { save { $0.urlRouting.enabled = enabled.state == .on } }
    @objc private func fallbackChanged() { let selected = fallback.selectedItem?.representedObject as? String; save { $0.urlRouting.fallbackBrowserBundleIdentifier = selected == noFallbackID ? nil : selected } }
    @objc private func setDefault() { if store.config.urlRouting.fallbackBrowserBundleIdentifier == nil, let old = handler.handler(for: "https"), old != handler.bundleIdentifier { save { $0.urlRouting.fallbackBrowserBundleIdentifier = old } }; handler.requestDefaultHandlers(); waitForDefaultHandlerConfirmation() }
    private func waitForDefaultHandlerConfirmation() { defaultHandlerTimer?.invalidate(); defaultHandlerChecks = 0; status.stringValue = "Waiting for macOS confirmation…"; defaultHandlerTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] timer in guard let self else { timer.invalidate(); return }; if self.handler.ownsBoth { timer.invalidate(); self.defaultHandlerTimer = nil; self.reload(); return }; self.defaultHandlerChecks += 1; if self.defaultHandlerChecks >= 60 { timer.invalidate(); self.defaultHandlerTimer = nil; self.status.stringValue = "Not the default handler. You can retry or use System Settings." } } }
    @objc private func openApps() { handler.openDefaultApps() }
    @objc private func addRule() { edit(nil) }
    @objc private func editRule() { guard table.selectedRow >= 0 else { return }; edit(table.selectedRow) }

    private func edit(_ index: Int?) {
        let host = NSTextField(string: index.map { rules[$0].host } ?? ""); host.placeholderString = "example.com"
        let hostLabel = NSTextField(labelWithString: "Host pattern")
        let sub = NSButton(checkboxWithTitle: "Include subdomains", target: nil, action: nil); sub.state = index.map { rules[$0].includeSubdomains } == true ? .on : .off
        let popup = NSPopUpButton(); for option in browsers { popup.addItem(withTitle: option.name); popup.lastItem?.representedObject = option.id }
        if let i = index { let id = rules[i].browserBundleIdentifier; if popup.itemArray.first(where: { $0.representedObject as? String == id }) == nil { popup.addItem(withTitle: "Unavailable: \(id)"); popup.lastItem?.representedObject = id }; if let target = popup.itemArray.firstIndex(where: { $0.representedObject as? String == id }) { popup.selectItem(at: target) } }
        let editor = NSView(frame: NSRect(x: 0, y: 0, width: 380, height: 116)); [hostLabel, host, sub, popup].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; editor.addSubview($0) }
        NSLayoutConstraint.activate([hostLabel.topAnchor.constraint(equalTo: editor.topAnchor), hostLabel.leadingAnchor.constraint(equalTo: editor.leadingAnchor), hostLabel.trailingAnchor.constraint(equalTo: editor.trailingAnchor), host.topAnchor.constraint(equalTo: hostLabel.bottomAnchor, constant: 6), host.leadingAnchor.constraint(equalTo: editor.leadingAnchor), host.trailingAnchor.constraint(equalTo: editor.trailingAnchor), sub.topAnchor.constraint(equalTo: host.bottomAnchor, constant: 10), sub.leadingAnchor.constraint(equalTo: editor.leadingAnchor), popup.topAnchor.constraint(equalTo: sub.bottomAnchor, constant: 8), popup.leadingAnchor.constraint(equalTo: editor.leadingAnchor), popup.trailingAnchor.constraint(equalTo: editor.trailingAnchor), popup.bottomAnchor.constraint(equalTo: editor.bottomAnchor)])
        let alert = NSAlert(); alert.messageText = index == nil ? "Add URL Rule" : "Edit URL Rule"; alert.informativeText = "Choose which browser should open this domain."; alert.accessoryView = editor; alert.addButton(withTitle: "Save"); alert.addButton(withTitle: "Cancel"); alert.window.initialFirstResponder = host
        guard alert.runModal() == .alertFirstButtonReturn else { return }; guard let normalized = try? Hostname.normalize(host.stringValue) else { self.alert("Enter a valid hostname without a scheme or path."); return }; guard let browserID = popup.selectedItem?.representedObject as? String, !browserID.isEmpty else { self.alert("Select an installed browser for this rule."); return }
        save { config in if let i = index { config.urlRouting.rules[i] = ALaKartConfig.Rule(host: normalized, includeSubdomains: sub.state == .on, browserBundleIdentifier: browserID, enabled: config.urlRouting.rules[i].enabled, id: config.urlRouting.rules[i].id) } else { config.urlRouting.rules.append(ALaKartConfig.Rule(host: normalized, includeSubdomains: sub.state == .on, browserBundleIdentifier: browserID)) } }
    }

    @objc private func removeRule() { guard table.selectedRow >= 0 else { return }; save { $0.urlRouting.rules.remove(at: table.selectedRow) } }
    @objc private func toggleRule() { guard table.selectedRow >= 0 else { return }; save { $0.urlRouting.rules[table.selectedRow].enabled.toggle() } }
    @objc private func moveRuleUp() { move(-1) }; @objc private func moveRuleDown() { move(1) }
    private func move(_ delta: Int) { let i = table.selectedRow, j = i + delta; guard i >= 0, j >= 0, j < rules.count else { return }; save { $0.urlRouting.rules.swapAt(i, j) }; table.selectRowIndexes(IndexSet(integer: j), byExtendingSelection: false) }
    @objc private func exportConfig() { let panel = NSSavePanel(); panel.nameFieldStringValue = "a-la-kart-config.json"; guard panel.runModal() == .OK, let url = panel.url else { return }; do { try store.encoded().write(to: url, options: .atomic) } catch { alert(error.localizedDescription) } }
    @objc private func importConfig() { let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; guard panel.runModal() == .OK, let url = panel.url else { return }; do { let value = try JSONDecoder().decode(ALaKartConfig.self, from: Data(contentsOf: url)); try store.replace(value); reload() } catch { alert(error.localizedDescription) } }
    private func alert(_ message: String) { let a = NSAlert(); a.messageText = "A la Kart"; a.icon = NSApp.applicationIconImage; a.informativeText = message; a.runModal() }
}
