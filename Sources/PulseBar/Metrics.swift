import AppKit
import IOKit.ps
import Combine
import ServiceManagement

final class SystemReader {
    private let host = mach_host_self()
    private var oldTicks: (UInt32, UInt32, UInt32, UInt32)?
    private let cores = CoreReader()
    private(set) var details = CPUDetails()
    private(set) var memoryDetails = MemoryDetails()
    init() {
        details.model = SystemDetails.string("machdep.cpu.brand_string")
        if details.model.isEmpty { details.model = SystemDetails.string("hw.model") }
        details.physicalCores = SystemDetails.integer("hw.physicalcpu")
    }
    deinit { mach_port_deallocate(mach_task_self_, host) }

    func cpu() -> Double {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let status = withUnsafeMutablePointer(to: &info) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics(host, HOST_CPU_LOAD_INFO, $0, &count) }
        }
        guard status == KERN_SUCCESS else { return 0 }
        let ticks = info.cpu_ticks
        defer { oldTicks = ticks }
        guard let old = oldTicks else { return 0 }
        let user = Double(ticks.0 &- old.0), system = Double(ticks.1 &- old.1)
        let idle = Double(ticks.2 &- old.2), nice = Double(ticks.3 &- old.3)
        let total = user + system + idle + nice
        if total > 0 {
            details.user = (user + nice) / total
            details.system = system / total
            details.idle = idle / total
        }
        return total > 0 ? min(1, (total - idle) / total) : 0
    }

    func memory() -> UInt64 {
        memoryDetails = SystemDetails.memory(host: host)
        return memoryDetails.used
    }

    func detailedCPU() -> CPUDetails {
        details.cores = cores.sample(host: host)
        var load = [Double](repeating: 0, count: 3)
        if getloadavg(&load, 3) == 3 { details.load = load }
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: details.thermal = "Nominal"
        case .fair: details.thermal = "Fair"
        case .serious: details.thermal = "Serious"
        case .critical: details.thermal = "Critical"
        @unknown default: details.thermal = "Unknown"
        }
        return details
    }

    func battery() -> BatteryReading? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let current = description[kIOPSCurrentCapacityKey] as? Int,
                  let maximum = description[kIOPSMaxCapacityKey] as? Int, maximum > 0 else { continue }
            return BatteryReading(fraction: min(1, max(0, Double(current) / Double(maximum))),
                                  charging: description[kIOPSIsChargingKey] as? Bool ?? false,
                                  onAC: description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue)
        }
        return nil
    }
}

@MainActor final class Metrics: NSObject, ObservableObject {
    @Published var displayed = Reading()
    @Published var interfaces = NetworkReader.interfaces()
    @Published var section: PanelSection = .home {
        didSet {
            guard section != oldValue else { return }
            if section == .settings { refreshLoginStatus() }
            if panelVisible { refreshVisiblePanel() }
            onSectionChange?()
        }
    }
    var settingsVisible: Bool {
        get { section == .settings }
        set { section = newValue ? .settings : .home }
    }
    @Published var launchAtLogin = false
    @Published var loginMessage: String?
    private(set) var current = Reading()
    private var tracker = TrafficTracker()
    private let system = SystemReader()
    private let preferences: Preferences
    let controls = SystemControls()
    let footer = FooterStats()
    let traffic = LiveTraffic()
    let health = NetworkHealth()
    let batteryHealth = BatteryHealthReport()
    let runtime = BatteryRuntime()
    let weather = Weather()
    let media = Media()
    var panelHeight: CGFloat { height(for: section) }
    func height(for section: PanelSection) -> CGFloat {
        guard section == .home else { return PanelLayout.height(for: section) }
        let rows = (preferences.homeSections.count + 1) / 2
        let tiles = rows == 0 ? 0 : rows * 50 + (rows - 1) * 6
        let quickCount = (preferences.showsPanel(.audio) ? 1 : 0) + (preferences.showsPanel(.display) ? 1 : 0)
        let quick = quickCount == 0 ? 0 : quickCount * 24 + (quickCount - 1) * 6 + 20
        return CGFloat(min(580, max(240, 144 + tiles + quick + (rows > 0 ? 10 : 0) + (quickCount > 0 ? 10 : 0))))
    }
    var onDismiss: (() -> Void)?
    var onSectionChange: (() -> Void)?
    private var timer: Timer?
    private var powerNotifications: CFRunLoopSource?
    private var lastSystemRead: TimeInterval = -100
    private var lastInterfaceRead: TimeInterval = -100
    private var lastSelection = ""
    private var lastPowerRead: TimeInterval = -100
    var onSample: ((Reading) -> Void)?
    var panelVisible = false {
        didSet {
            guard panelVisible != oldValue else { return }
            health.setPanelVisible(panelVisible)
            if panelVisible { refreshVisiblePanel() }
            else { controls.closePanel() }
        }
    }

    init(preferences: Preferences) {
        self.preferences = preferences
        super.init()
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(sleeping), name: NSWorkspace.willSleepNotification, object: nil)
        center.addObserver(self, selector: #selector(waking), name: NSWorkspace.didWakeNotification, object: nil)
        powerNotifications = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            MainActor.assumeIsolated { Unmanaged<Metrics>.fromOpaque(context).takeUnretainedValue().powerSourceChanged() }
        }, Unmanaged.passUnretained(self).toOpaque())?.takeRetainedValue()
        if let source = powerNotifications { CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes) }
    }

    func start() {
        timer?.invalidate()
        health.start()
        sample()
        // One shared, coalescible timer. No polling subprocesses or network requests.
        let timer = Timer(timeInterval: 1, target: self, selector: #selector(tick), userInfo: nil, repeats: true)
        timer.tolerance = 0.05
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    @objc private func tick() { sample() }
    @objc private func sleeping() { timer?.invalidate(); timer = nil; tracker.rebaseline(); health.stop(); runtime.suspend() }
    @objc private func waking() { tracker.rebaseline(); current.history.removeAll(); lastSystemRead = -100; lastPowerRead = -100; start() }

    private func powerSourceChanged() {
        let battery = system.battery()
        guard battery != current.battery else { return }
        let changedSource = battery?.onAC != current.battery?.onAC || battery?.charging != current.battery?.charging
        current.battery = battery
        if changedSource { _ = readPower(now: ProcessInfo.processInfo.systemUptime) }
        if panelVisible { publishDetails() }
        onSample?(current)
    }
    func stop() {
        timer?.invalidate(); timer = nil; runtime.flush()
        if let source = powerNotifications { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        powerNotifications = nil
    }
    @discardableResult private func readPower(now: TimeInterval) -> Bool {
        let details = SystemDetails.power()
        let changed = details != current.powerDetails
        current.powerDetails = details; lastPowerRead = now
        runtime.sample(power: details, battery: current.battery, cpu: current.cpu, time: now)
        return changed
    }

    private func readSystem(now: TimeInterval) {
        current.cpu = system.cpu()
        current.memory = system.memory()
        let nextBattery = system.battery()
        let sourceChanged = nextBattery?.onAC != current.battery?.onAC || nextBattery?.charging != current.battery?.charging
        current.battery = nextBattery
        if sourceChanged { _ = readPower(now: now) }
        if preferences.shows(.wifi) { current.wifiPowered = RadioState.wifi() }
        current.cpuDetails.user = system.details.user
        current.cpuDetails.system = system.details.system
        current.cpuDetails.idle = system.details.idle
        current.cpuDetails.model = system.details.model
        current.cpuDetails.physicalCores = system.details.physicalCores
        current.memoryDetails = system.memoryDetails
        lastSystemRead = now
    }

    private func readInterfaces(now: TimeInterval) {
        let list = NetworkReader.interfaces()
        if list.map(\.id) != interfaces.map(\.id) { interfaces = list }
        lastInterfaceRead = now
    }

    private func refreshVisiblePanel() {
        let now = ProcessInfo.processInfo.systemUptime
        readSystem(now: now)
        readInterfaces(now: now)
        health.tick()
        refreshPanel(opening: true)
        publishDetails()
        footer.update(current, unit: preferences.unit)
        if section == .network { traffic.update(current) }
        onSample?(current)
    }

    func sample() {
        health.tick()
        let now = ProcessInfo.processInfo.systemUptime
        if preferences.interface != lastSelection {
            if !lastSelection.isEmpty { resetTotals() }
            lastSelection = preferences.interface
            tracker.rebaseline()
        }
        let name = preferences.interface == "auto" ? NetworkReader.primaryInterface() ?? "" : preferences.interface
        let count = name.isEmpty ? nil : NetworkReader.counter(interface: name)
        if current.interface != name { current.history.removeAll() }
        let rates = tracker.sample(name: name, counter: count, time: now)
        current.download = rates.0; current.upload = rates.1
        current.interface = name; current.connected = count != nil
        if panelVisible || now - lastInterfaceRead >= 10 { readInterfaces(now: now) }
        current.interfaceLabel = interfaces.first(where: { $0.id == name })?.label ?? (name.isEmpty ? "No active interface" : name)
        current.received = tracker.received; current.sent = tracker.sent
        let generalChanged = panelVisible || now - lastSystemRead >= 5
        if generalChanged { readSystem(now: now) }
        let powerChanged = now - lastPowerRead >= 30 ? readPower(now: now) : false
        let advancedChanged = panelVisible ? refreshPanel() : false
        current.history.append(TrafficPoint(id: now, download: rates.0, upload: rates.1))
        current.history.removeAll { $0.id < now - 60 }
        if panelVisible { footer.update(current, unit: preferences.unit) }
        if panelVisible && section == .network { traffic.update(current) }
        if panelVisible && (generalChanged || advancedChanged || powerChanged) { publishDetails() }
        onSample?(current)
    }

    @discardableResult private func refreshPanel(opening: Bool = false) -> Bool {
        let now = ProcessInfo.processInfo.systemUptime
        controls.refresh(section: section, opening: opening)
        if section == .power { batteryHealth.load() }
        var changed = false
        if section == .power {
            changed = readPower(now: now)
        }
        if section == .system {
            let details = system.detailedCPU()
            changed = changed || details != current.cpuDetails
            current.cpuDetails = details
        }
        return changed
    }

    func resetTotals() {
        tracker.reset()
        current.received = 0; current.sent = 0; current.since = Date()
        if panelVisible { publishDetails(); traffic.update(current) }
    }

    private func publishDetails() {
        let details = current.panelDetails
        if details != displayed { displayed = details }
    }

    func refreshLoginStatus() {
        let enabled = SMAppService.mainApp.status == .enabled
        if launchAtLogin != enabled { launchAtLogin = enabled }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        if enabled && SMAppService.mainApp.status == .enabled {
            loginMessage = nil; refreshLoginStatus(); return
        }
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            loginMessage = SMAppService.mainApp.status == .requiresApproval ? "Allow PulseBar in System Settings → Login Items." : nil
        } catch { loginMessage = error.localizedDescription }
        refreshLoginStatus()
    }
}
