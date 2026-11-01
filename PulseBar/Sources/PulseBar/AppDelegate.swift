import AppKit
import SwiftUI

final class ControlPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    var dismiss: (() -> Void)?
    override func cancelOperation(_ sender: Any?) { dismiss?() }
}
final class InteractiveHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    let preferences: Preferences
    let model: Metrics
    private var item: NSStatusItem!
    private var panel: ControlPanel!
    private struct CachedPanel {
        let view: InteractiveHostingView<DashboardView>
        let refresh: PanelRefresh
    }
    private var panelViews: [PanelSection: CachedPanel] = [:]
    private var panelUseOrder: [PanelSection] = []
    private var outsideMonitor: Any?
    private var keyMonitor: Any?
    private var moduleItems: [BarModule: NSStatusItem] = [:]
    private var moduleKeys: [BarModule: String] = [:]
    private weak var activeAnchor: NSView?
    private let hotKeys = HotKeys()
    private var hotKeysEnabled = false
    private var lastRendered = ""
    private let snapshotPath: String?

    init(snapshotPath: String? = nil) {
        self.snapshotPath = snapshotPath
        preferences = Preferences(defaults: snapshotPath == nil ? .standard : UserDefaults(suiteName: "local.pulsebar.preview")!)
        model = Metrics(preferences: preferences)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(CommandLine.arguments.contains("--ui-test") ? .regular : .accessory)
        item = NSStatusBar.system.statusItem(withLength: PanelLayout.trafficWidth)
        item.autosaveName = "PulseBarNetwork"
        if let button = item.button {
            button.target = self; button.action = #selector(clicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.setAccessibilityLabel("PulseBar network monitor")
        }
        panel = ControlPanel(contentRect: NSRect(x: 0, y: 0, width: PanelLayout.width, height: model.panelHeight), styleMask: [.borderless], backing: .buffered, defer: false)
        panel.title = "PulseBar Control Center"
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.dismiss = { [weak self] in self?.hidePanel() }
        model.onDismiss = { [weak self] in self?.hidePanel() }
        model.onSectionChange = { [weak self] in self?.resizePanel() }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.panel.isVisible else { return event }
            if event.keyCode == 53 { self.hidePanel(); return nil }
            if event.modifierFlags.contains([.command, .control]), let key = event.charactersIgnoringModifiers {
                let sections: [String: PanelSection] = ["a": .audio, "n": .wifi, "d": .display, "p": .power]
                if let section = sections[key] { self.model.section = section; return nil }
            }
            return event
        }
        model.onSample = { [weak self] reading in self?.render(reading) }
        preferences.onChange = { [weak self] in
            guard let self else { return }
            self.lastRendered = ""
            self.syncBarItems()
            self.resizePanel()
            self.model.sample()
            self.updateHotKeys()
        }
        syncBarItems()
        model.start()
        hotKeys.onSelect = { [weak self] section in self?.model.section = section; self?.showPanel() }
        updateHotKeys()
        if snapshotPath == nil && CommandLine.arguments.contains("--relocate-login") {
            model.setLaunchAtLogin(false); model.setLaunchAtLogin(true)
        } else if snapshotPath == nil && CommandLine.arguments.contains("--enable-login") { model.setLaunchAtLogin(true) }
        if let path = snapshotPath { prepareSnapshot(path) }
        else if CommandLine.arguments.contains("--show") { showPanel() }
        let args = CommandLine.arguments
        if let index = args.firstIndex(of: "--geometry-report"), index + 1 < args.count {
            let path = args[index + 1]
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.reportGeometry(path) }
        }
    }

    @objc private func clicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = NSMenu()
            menu.addItem(withTitle: "Control Center", action: #selector(openCenter), keyEquivalent: "").target = self
            menu.addItem(withTitle: "Customize…", action: #selector(customize), keyEquivalent: ",").target = self
            menu.addItem(NSMenuItem.separator())
            menu.addItem(withTitle: "Quit PulseBar", action: #selector(quit), keyEquivalent: "q").target = self
            if let button = item.button { menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.minY), in: button) }
        } else {
            let target: PanelSection = .network
            if panel.isVisible && model.section == target { hidePanel() }
            else { if model.section != target { model.section = target }; activeAnchor = item.button; showPanel() }
        }
    }
    private func panelView(for section: PanelSection) -> CachedPanel {
        if let existing = panelViews[section] { return existing }
        let refresh = PanelRefresh(sources: [model.objectWillChange, model.controls.objectWillChange,
                                            model.health.objectWillChange, model.batteryHealth.objectWillChange,
                                            model.runtime.objectWillChange])
        let hosting = InteractiveHostingView(rootView: DashboardView(model: model, preferences: preferences, section: section, refresh: refresh))
        // AppKit already controls the exact frame; skip extra min/ideal/max probes.
        hosting.sizingOptions = []
        let cached = CachedPanel(view: hosting, refresh: refresh)
        panelViews[section] = cached
        return cached
    }
    private func positionPanel() {
        let anchor = activeAnchor ?? moduleItems[.center]?.button ?? item.button
        let visible = (anchor?.window?.screen ?? NSScreen.main)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        var right = visible.maxX - 8
        if let button = anchor, let window = button.window {
            right = window.convertToScreen(button.convert(button.bounds, to: nil)).maxX
        }
        let x = max(visible.minX + 8, min(right - PanelLayout.width, visible.maxX - PanelLayout.width - 8))
        let height = model.panelHeight
        let frame = NSRect(x: x, y: visible.maxY - height - 8, width: PanelLayout.width, height: height)
        let cached = panelView(for: model.section)
        let hosting = cached.view
        let refreshClock = [.home, .world, .calendar].contains(model.section)
        if panel.contentView !== hosting {
            // Resize the empty container instead of laying out the old page at
            // the new page's size. Reattaching restores the cached SwiftUI tree.
            for entry in panelViews.values { entry.refresh.setActive(false) }
            panel.contentView?.isHidden = true
            panel.contentView = nil
            if panel.frame != frame { panel.setFrame(frame, display: false) }
            hosting.isHidden = false
            cached.refresh.setActive(true, refreshClock: refreshClock)
            panel.contentView = hosting
        } else {
            cached.refresh.setActive(true, refreshClock: refreshClock)
            if panel.frame != frame { panel.setFrame(frame, display: false) }
        }
        panelUseOrder.removeAll { $0 == model.section }; panelUseOrder.append(model.section)
        while panelUseOrder.count > 4 {
            let oldest = panelUseOrder.removeFirst(); panelViews.removeValue(forKey: oldest)
        }
    }
    private func showPanel() {
        // Refresh data before layout, preventing an old-data/new-data double pass.
        model.panelVisible = true
        positionPanel()
        if !NSApp.isActive { NSApp.activate(ignoringOtherApps: true) }
        panel.makeKeyAndOrderFront(nil)
        if outsideMonitor == nil {
            outsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                DispatchQueue.main.async {
                    guard let self, !self.panel.frame.contains(NSEvent.mouseLocation) else { return }
                    self.hidePanel()
                }
            }
        }
    }
    private func hidePanel() {
        for entry in panelViews.values { entry.refresh.setActive(false) }
        panel.orderOut(nil); model.panelVisible = false
        if let monitor = outsideMonitor { NSEvent.removeMonitor(monitor); outsideMonitor = nil }
    }
    private func resizePanel() {
        guard let panel, panel.isVisible else { return }
        positionPanel()
    }
    @objc private func openCenter() { if model.section != .home { model.section = .home }; showPanel() }
    @objc private func customize() { if model.section != .settings { model.section = .settings }; showPanel() }
    @objc private func quit() { NSApp.terminate(nil) }
    private func updateHotKeys() {
        guard preferences.hotKeys != hotKeysEnabled else { return }
        hotKeysEnabled = preferences.hotKeys
        if !hotKeys.enable(preferences.hotKeys) { model.controls.message = "A keyboard shortcut is already in use by another app. Panel-local shortcuts still work." }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showPanel(); return true }
    func applicationWillTerminate(_ notification: Notification) {
        hotKeys.stop()
        model.stop()
        model.controls.stopWatching()
        model.health.stop()
        model.controls.setAwake(false)
        if let monitor = outsideMonitor { NSEvent.removeMonitor(monitor) }
        if let monitor = keyMonitor { NSEvent.removeMonitor(monitor) }
    }

    private func render(_ reading: Reading) {
        renderModules(reading)
        let key = moduleKey(.traffic, reading)
        guard key != lastRendered else { return }; lastRendered = key
        item.length = moduleWidth(.traffic)
        item.button?.effectiveAppearance.performAsCurrentDrawingAppearance {
            item.button?.image = moduleImage(.traffic, reading)
        }
        item.button?.toolTip = "Traffic · ↓ \(preferences.unit.string(reading.download)) · ↑ \(preferences.unit.string(reading.upload))"
    }
    private func moduleWidth(_ module: BarModule) -> CGFloat {
        switch module {
        case .traffic: return preferences.inline ? 138 : PanelLayout.trafficWidth
        case .battery: return NSStatusItem.variableLength
        case .cpu, .memory: return 32
        default: return 16
        }
    }
    private func moduleKey(_ module: BarModule, _ reading: Reading) -> String {
        switch module {
        case .traffic: return "\(preferences.unit.string(reading.download))|\(preferences.unit.string(reading.upload))|\(preferences.inline)|\(preferences.colorArrows)|\(preferences.theme)"
        case .battery: return "\(reading.battery.map { Int(($0.fraction * 100).rounded()) } ?? -1)|\(reading.battery?.charging ?? false)|\(reading.battery?.onAC ?? false)"
        case .wifi: return "\(reading.wifiPowered)|\(model.health.warning)"
        case .cpu: return "\(Int(reading.cpu * 100))"
        case .memory: return "\(Int(reading.memoryFraction * 100))"
        case .audio: return "\(model.controls.audio.outputMuted)"
        default: return module.rawValue
        }
    }
    private func moduleImage(_ module: BarModule, _ reading: Reading) -> NSImage? {
        switch module {
        case .traffic: return StatusImages.traffic(preferences.unit.string(reading.download), preferences.unit.string(reading.upload), preferences: preferences)
        case .center: return StatusImages.symbol("slider.horizontal.3")
        case .wifi: return StatusImages.symbol(reading.wifiPowered ? (model.health.warning ? "wifi.exclamationmark" : "wifi") : "wifi.slash")
        case .battery:
            guard let battery = reading.battery else { return StatusImages.symbol("powerplug") }
            return StatusImages.symbol(battery.statusSymbol)
        case .audio: return StatusImages.symbol(model.controls.audio.outputMuted ? "speaker.slash" : "speaker.wave.2")
        case .display: return StatusImages.symbol("display")
        case .cpu: return StatusImages.text("C \(Int(reading.cpu * 100))%")
        case .memory: return StatusImages.text("M \(Int(reading.memoryFraction * 100))%")
        }
    }
    private func syncBarItems() {
        moduleKeys.removeAll()
        item.isVisible = preferences.shows(.traffic)
        for module in BarModule.allCases where module != .traffic {
            if preferences.shows(module) {
                if moduleItems[module] == nil {
                    let status = NSStatusBar.system.statusItem(withLength: moduleWidth(module))
                    status.autosaveName = "PulseBar-" + module.rawValue
                    status.button?.identifier = NSUserInterfaceItemIdentifier(module.rawValue)
                    status.button?.target = self; status.button?.action = #selector(moduleClicked(_:))
                    status.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
                    status.button?.setAccessibilityLabel("PulseBar " + module.title)
                    moduleItems[module] = status
                }
            } else if let old = moduleItems.removeValue(forKey: module) { NSStatusBar.system.removeStatusItem(old) }
        }
        render(model.current)
    }
    @objc private func moduleClicked(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue, let module = BarModule(rawValue: id) else { return }
        activeAnchor = sender
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = NSMenu()
            menu.addItem(withTitle: "Open " + module.title, action: #selector(openSelectedModule(_:)), keyEquivalent: "").representedObject = module.rawValue
            menu.items.last?.target = self
            menu.addItem(withTitle: "Customize…", action: #selector(customize), keyEquivalent: ",").target = self
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.minY), in: sender)
        } else if panel.isVisible && model.section == module.section { hidePanel() }
        else { if model.section != module.section { model.section = module.section }; showPanel() }
    }
    @objc private func openSelectedModule(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let module = BarModule(rawValue: raw) else { return }
        if model.section != module.section { model.section = module.section }; showPanel()
    }
    private func renderModules(_ reading: Reading) {
        for (module, status) in moduleItems {
            let key = moduleKey(module, reading)
            guard moduleKeys[module] != key else { continue }; moduleKeys[module] = key
            status.button?.effectiveAppearance.performAsCurrentDrawingAppearance { status.button?.image = moduleImage(module, reading) }
            if module == .battery, let button = status.button {
                button.imagePosition = .imageLeft
                button.imageHugsTitle = true
                let text = reading.battery.map { " \(Int(($0.fraction * 100).rounded()))%" } ?? " AC"
                button.attributedTitle = NSAttributedString(string: text, attributes: [.font: NSFont.menuBarFont(ofSize: 0), .foregroundColor: NSColor.labelColor])
                status.length = NSStatusItem.variableLength
            }
            status.button?.toolTip = module == .battery ? (reading.battery.map { "\(Int(($0.fraction * 100).rounded()))% · \($0.label)" } ?? "AC power") : "PulseBar " + module.title
        }
    }
    private func reportGeometry(_ path: String) {
        var rows: [[String: Any]] = []
        for (name, status) in [("traffic", item!)] + moduleItems.map({ ($0.key.rawValue, $0.value) }) {
            guard let button = status.button, let window = button.window else { continue }
            let rect = window.convertToScreen(button.convert(button.bounds, to: nil))
            let imageRect = button.cell?.imageRect(forBounds: button.bounds) ?? .zero
            rows.append(["module": name, "requested_width": status.length, "actual_width": rect.width,
                         "x": rect.minX, "max_x": rect.maxX, "image_width": imageRect.width])
        }
        rows.sort { ($0["x"] as? Double ?? 0) < ($1["x"] as? Double ?? 0) }
        if let data = try? JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted, .sortedKeys]) { try? data.write(to: URL(fileURLWithPath: path)) }
    }

    // Uses the same interactive panel as production with separate preferences.
    private func prepareSnapshot(_ path: String) {
        let args = CommandLine.arguments
        if let index = args.firstIndex(of: "--section"), index + 1 < args.count,
           let section = PanelSection(rawValue: args[index + 1]) { model.section = section }
        if args.contains("--settings") { model.section = .settings }
        showPanel()
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self, let view = self.panel.contentView else { NSApp.terminate(nil); return }
            view.layoutSubtreeIfNeeded()
            guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { NSApp.terminate(nil); return }
            view.cacheDisplay(in: view.bounds, to: bitmap)
            if let data = bitmap.representation(using: .png, properties: [:]) { try? data.write(to: URL(fileURLWithPath: path)) }
            NSApp.terminate(nil)
        }
    }
}
