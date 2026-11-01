import AppKit
@preconcurrency import CoreWLAN
import CoreLocation
import CoreAudio
import IOKit.pwr_mgt
import SystemConfiguration

struct WiFiReading: Equatable {
    var present = false, powered = false, connected = false
    var name = "Wi-Fi", signal = 0, noise = 0, rate: Double = 0, channel = 0
    var addresses: [String] = [], dns: [String] = []
    var gateway = "—"
}
struct WiFiChoice: Identifiable, Equatable {
    let id: String, name: String, signal: Int, secure: Bool
}
struct ScreenChoice: Identifiable, Equatable {
    let id: CGDirectDisplayID, name: String, pixels: String, scale: String, refresh: Double
    var brightness: Double?
}

/// No helper processes, installed packages, or periodic work of its own.
/// The shared metrics timer calls refresh only while the panel is visible.
@MainActor final class SystemControls: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var audio = AudioReading()
    @Published var wifi = WiFiReading()
    @Published var wifiChoices: [WiFiChoice] = []
    @Published var screens: [ScreenChoice] = []
    @Published var busy = false
    @Published var message: String?
    @Published var awake = false
    private var wifiNetworks: [String: CWNetwork] = [:]
    private let location = CLLocationManager()
    private var assertion: IOPMAssertionID = 0
    private var wifiPanelRequested = false
    private var audioWatcher: AudioWatcher?
    private var lastAutomaticWiFiScan: TimeInterval = -100
    var messageSection: PanelSection?
    func report(_ text: String?, section: PanelSection) { messageSection = section; message = text }
    func visibleMessage(in section: PanelSection) -> String? {
        guard messageSection == nil || messageSection == section || (messageSection == .wifi && section == .network) else { return nil }
        return message
    }
    func stopWatching() { audioWatcher?.stop(); audioWatcher = nil }
    func watchAudio() {
        guard audioWatcher == nil else { return }
        let watcher = AudioWatcher()
        watcher.changed = { [weak self] devices in
            guard let self else { return }
            let result = devices ? AudioControl.snapshot() : AudioControl.levels(self.audio)
            if result != self.audio { self.audio = result }
        }
        let result = watcher.start(); audioWatcher = watcher
        if result != audio { audio = result }
    }

    override init() { super.init(); location.delegate = self }

    func closePanel() { wifiPanelRequested = false; stopWatching() }
    func refresh(section: PanelSection, opening: Bool = false) {
        let now = ProcessInfo.processInfo.systemUptime
        wifiPanelRequested = section == .wifi
        if section == .home || section == .audio { watchAudio() } else { stopWatching() }
        if section == .wifi && opening { openWiFi() }
        else if section == .home || section == .network || section == .wifi { readWiFi() }
        // Scans are asynchronous and can occupy the radio for several seconds.
        // Refresh every opening, plus periodically while the Wi-Fi list is visible.
        if section == .wifi && !opening && wifi.powered && now - lastAutomaticWiFiScan >= 10 { scanWiFi() }
        if section == .display || section == .home { readDisplays() }
    }

    func readWiFi() {
        var result = WiFiReading()
        if let interface = CWWiFiClient.shared().interface() {
            result.present = true; result.powered = interface.powerOn()
            result.name = interface.ssid() ?? (result.powered ? "Wi-Fi connected / names hidden" : "Wi-Fi off")
            result.signal = interface.rssiValue(); result.noise = interface.noiseMeasurement()
            result.rate = interface.transmitRate(); result.channel = interface.wlanChannel()?.channelNumber ?? 0
            result.connected = result.powered && result.rate > 0 && result.signal != 0
        }
        let name = NetworkReader.primaryInterface() ?? ""
        var addresses: UnsafeMutablePointer<ifaddrs>?
        if getifaddrs(&addresses) == 0 {
            defer { freeifaddrs(addresses) }
            var p = addresses
            while let current = p {
                defer { p = current.pointee.ifa_next }
                guard String(cString: current.pointee.ifa_name) == name, let address = current.pointee.ifa_addr,
                      [UInt8(AF_INET), UInt8(AF_INET6)].contains(address.pointee.sa_family) else { continue }
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                    result.addresses.append(String(cString: host))
                }
            }
        }
        if let dns = SCDynamicStoreCopyValue(nil, "State:/Network/Global/DNS" as CFString) as? [String: Any] { result.dns = dns["ServerAddresses"] as? [String] ?? [] }
        if let ipv4 = SCDynamicStoreCopyValue(nil, "State:/Network/Global/IPv4" as CFString) as? [String: Any] { result.gateway = ipv4["Router"] as? String ?? "—" }
        if wifi != result { wifi = result }
    }

    func setWiFi(_ enabled: Bool) {
        do {
            guard let interface = CWWiFiClient.shared().interface() else { return }
            try interface.setPower(enabled)
            messageSection = .wifi; message = nil; readWiFi()
        } catch { messageSection = .wifi; message = error.localizedDescription }
    }

    func requestWiFiNames() { location.requestWhenInUseAuthorization() }
    func openWiFi() {
        wifiPanelRequested = true
        readWiFi()
        if wifi.powered { scanWiFi() }
    }
    func disconnectWiFi() { CWWiFiClient.shared().interface()?.disassociate(); readWiFi() }
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.readWiFi()
            if self.wifiPanelRequested && self.location.authorizationStatus == .authorizedAlways { self.scanWiFi() }
        }
    }

    func scanWiFi() {
        guard !busy else { return }; busy = true; messageSection = .wifi; message = nil
        lastAutomaticWiFiScan = ProcessInfo.processInfo.systemUptime
        DispatchQueue.global(qos: .utility).async {
            do {
                let networks = try CWWiFiClient.shared().interface()?.scanForNetworks(withName: nil) ?? []
                DispatchQueue.main.async {
                    self.wifiNetworks.removeAll()
                    var choices: [String: WiFiChoice] = [:]
                    for network in networks {
                        guard let name = network.ssid, !name.isEmpty else { continue }
                        if let old = choices[name], old.signal >= network.rssiValue { continue }
                        choices[name] = WiFiChoice(id: name, name: name, signal: network.rssiValue, secure: !network.supportsSecurity(.none))
                        self.wifiNetworks[name] = network
                    }
                    self.wifiChoices = choices.values.sorted { $0.signal > $1.signal }
                    self.busy = false
                    if choices.isEmpty { self.messageSection = .wifi; self.message = "No named networks returned. macOS may require Location access for Wi-Fi names." }
                }
            } catch { DispatchQueue.main.async { self.messageSection = .wifi; self.message = error.localizedDescription; self.busy = false } }
        }
    }

    func joinWiFi(_ id: String, password: String) {
        guard let network = wifiNetworks[id], !busy else { return }; busy = true; messageSection = .wifi; message = nil
        DispatchQueue.global(qos: .utility).async {
            do {
                guard let interface = CWWiFiClient.shared().interface() else {
                    DispatchQueue.main.async { self.busy = false; self.messageSection = .wifi; self.message = "No Wi-Fi interface is available." }
                    return
                }
                try interface.associate(to: network, password: password.isEmpty ? nil : password)
                DispatchQueue.main.async { self.busy = false; self.messageSection = .wifi; self.message = "Connected to \(id)."; self.readWiFi() }
            } catch { DispatchQueue.main.async { self.busy = false; self.messageSection = .wifi; self.message = error.localizedDescription } }
        }
    }

    func setVolume(_ value: Double, input: Bool = false) {
        let device = input ? audio.input : audio.output
        let status = AudioControl.setVolume(value, device: device, input: input)
        guard status == noErr else { messageSection = .audio; message = "This audio device does not expose software volume (\(status))."; return }
        if input { audio.inputVolume = value } else { audio.outputVolume = value }
    }
    func toggleMute(input: Bool = false) {
        let muted = input ? audio.inputMuted : audio.outputMuted
        let id = input ? audio.input : audio.output
        let status = AudioControl.set(id, AudioControl.address(kAudioDevicePropertyMute, input: input), value: UInt32(muted ? 0 : 1))
        guard status == noErr else { messageSection = .audio; message = "This device does not expose a mute switch (\(status))."; return }
        if input { audio.inputMuted.toggle() } else { audio.outputMuted.toggle() }
    }
    func selectAudio(_ id: AudioObjectID, input: Bool) {
        let status = AudioControl.set(AudioObjectID(kAudioObjectSystemObject), AudioControl.global(input ? kAudioHardwarePropertyDefaultInputDevice : kAudioHardwarePropertyDefaultOutputDevice), value: id)
        if status != noErr { messageSection = .audio; message = "Unable to select audio device (\(status))." }
        audio = AudioControl.snapshot()
    }

    func readDisplays() {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(UInt32(ids.count), &ids, &count) == .success else { return }
        let native = NSScreen.screens
        let result: [ScreenChoice] = ids.prefix(Int(count)).map { id in
            let screen = native.first { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == id }
            let mode = CGDisplayCopyDisplayMode(id)
            let scale = screen.map { "\(Int($0.frame.width)) × \(Int($0.frame.height)) logical · \(Int($0.backingScaleFactor))×" } ?? (CGDisplayMirrorsDisplay(id) != 0 ? "Mirroring" : "System managed")
            return ScreenChoice(id: id, name: screen?.localizedName ?? "Display \(id)",
                                pixels: "\(mode?.pixelWidth ?? 0) × \(mode?.pixelHeight ?? 0)", scale: scale,
                                refresh: mode?.refreshRate ?? 0, brightness: DisplayBrightness.get(id))
        }
        if screens != result { screens = result }
    }
    func setBrightness(_ value: Double, id: CGDirectDisplayID) {
        guard DisplayBrightness.set(id, value: value) else { messageSection = .display; message = "Brightness control is unavailable for this display. Use macOS Display settings."; return }
        if let index = screens.firstIndex(where: { $0.id == id }) { screens[index].brightness = value }
    }
    func setAwake(_ enabled: Bool) {
        if enabled {
            let result = IOPMAssertionCreateWithName(kIOPMAssertionTypeNoIdleSleep as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn), "PulseBar: stay awake" as CFString, &assertion)
            awake = result == kIOReturnSuccess
        } else { if assertion != 0 { IOPMAssertionRelease(assertion); assertion = 0 }; awake = false }
    }
    func sleepMac() {
        let connection = IOPMFindPowerManagement(0)
        guard connection != 0 else { return }
        let result = IOPMSleepSystem(connection); IOServiceClose(connection)
        if result != kIOReturnSuccess { messageSection = .power; message = "macOS could not enter sleep (\(result))." }
    }

}

/// Uses the macOS-provided DisplayServices framework if present. This optional
/// private API is runtime checked; unsupported displays retain a settings link.
enum DisplayBrightness {
    typealias Get = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
    typealias Set = @convention(c) (UInt32, Float) -> Int32
    static let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY)
    static func get(_ id: UInt32) -> Double? {
        guard let handle, let symbol = dlsym(handle, "DisplayServicesGetBrightness") else { return nil }
        var value: Float = 0
        return unsafeBitCast(symbol, to: Get.self)(id, &value) == 0 ? Double(value) : nil
    }
    static func set(_ id: UInt32, value: Double) -> Bool {
        guard let handle, let symbol = dlsym(handle, "DisplayServicesSetBrightness") else { return false }
        return unsafeBitCast(symbol, to: Set.self)(id, Float(max(0, min(1, value)))) == 0
    }
}
