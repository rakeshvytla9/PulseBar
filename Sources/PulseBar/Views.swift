import SwiftUI

@MainActor struct DashboardView: View {
    let model: Metrics
    @ObservedObject var refresh: PanelRefresh
    @ObservedObject var preferences: Preferences
    let controls: SystemControls
    let health: NetworkHealth
    let batteryHealth: BatteryHealthReport
    let runtime: BatteryRuntime
    @ObservedObject var weather: Weather
    @ObservedObject var media: Media
    let panelSection: PanelSection
    @State private var copied: String?
    @State private var selectedWiFi: String?
    @State private var password = ""
    @State private var zoneQuery = ""
    @State private var zones = UserDefaults.standard.stringArray(forKey: "worldZones") ?? [TimeZone.current.identifier, "Europe/London", "America/New_York", "Asia/Tokyo"]
    var palette: Palette { preferences.theme.palette }
    var reading: Reading { model.displayed }
    init(model: Metrics, preferences: Preferences, section: PanelSection, refresh: PanelRefresh) {
        self.refresh = refresh
        self.model = model; self.preferences = preferences; self.controls = model.controls; self.health = model.health
        self.batteryHealth = model.batteryHealth; self.runtime = model.runtime
        self.weather = model.weather; self.media = model.media; self.panelSection = section
    }
    var body: some View {
        let _ = refresh.revision
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                if panelSection != .home {
                    Button { model.section = .home } label: { Text("←").font(AppFonts.ui(22)).frame(width: 30, height: 38).contentShape(Rectangle()) }
                        .buttonStyle(FlatButtonStyle(color: palette.blue)).accessibilityLabel("Back to Control Center")
                } else { GlyphIcon(text: PanelSection.home.glyph, size: 24, color: palette.blue).frame(width: 30) }
                VStack(alignment: .leading, spacing: 4) {
                    Text(panelSection.title).font(AppFonts.ui(15, bold: true))
                    Text(palette.native ? "PULSEBAR" : "PULSEBAR / \(preferences.theme.rawValue)").font(AppFonts.ui(9)).tracking(0.7).foregroundStyle(palette.secondary)
                }
                Spacer(minLength: 0)
                NativeActionButton(title: panelSection == .settings ? "Done" : "Customize") {
                    model.section = panelSection == .settings ? .home : .settings
                }.frame(width: 82, height: 28)
            }.padding(14)
            Rectangle().fill(palette.text.opacity(0.15)).frame(height: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let message = controls.visibleMessage(in: panelSection) {
                        HStack(alignment: .top) {
                            Text(message).font(AppFonts.ui(10)).fixedSize(horizontal: false, vertical: true)
                            Spacer()
                            Button("×") { controls.message = nil }.buttonStyle(.plain)
                        }.padding(10).background(palette.blue.opacity(0.12))
                    }
                    sectionContent
                }.padding(14).frame(maxWidth: .infinity, alignment: .topLeading)
            }
            Rectangle().fill(palette.text.opacity(0.15)).frame(height: 1)
            HStack {
                TrafficFooter(stats: model.footer, health: health, copied: copied, openQuality: { model.section = .quality })
                Spacer()
                Button { copyStats() } label: { Image(systemName: "doc.on.doc").frame(width: 22, height: 22).contentShape(Rectangle()) }
                    .buttonStyle(.plain).help("Copy this panel's stats").accessibilityLabel("Copy panel stats")
                NativeActionButton(title: "Quit") { NSApplication.shared.terminate(nil) }.frame(width: 42, height: 22)
            }.padding(.horizontal, 14).padding(.vertical, 8)
        }.frame(width: PanelLayout.width, height: model.height(for: panelSection)).font(AppFonts.ui()).foregroundStyle(palette.text)
            .background { if palette.native { GlassBackground() } else { palette.bg } }
            .clipShape(RoundedRectangle(cornerRadius: palette.native ? 18 : 2))
            .overlay(RoundedRectangle(cornerRadius: palette.native ? 18 : 2).stroke(palette.text.opacity(0.15), lineWidth: 1))
            .preferredColorScheme(palette.native ? nil : .dark).onExitCommand { model.onDismiss?() }
    }

    @ViewBuilder private var sectionContent: some View {
        switch panelSection {
        case .home: home
        case .wifi: wifiPanel
        case .network: network
        case .quality: connectionQuality
        case .audio: audio
        case .display: display
        case .power: power
        case .system: system
        case .media: mediaPanel
        case .calendar: calendar
        case .world: world
        case .weather: weatherPanel
        case .settings: settings
        }
    }
    private func block<Content: View>(_ title: String, info: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        SectionBlock(title: title, palette: palette, info: info, content: content)
    }
    private func note(_ text: String) -> some View {
        Text(text).font(AppFonts.ui(10)).foregroundStyle(palette.secondary).fixedSize(horizontal: false, vertical: true)
    }
    private func row(_ name: String, _ value: String, color: Color? = nil) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(name).foregroundStyle(palette.secondary)
            Spacer(minLength: 4)
            Button { copy(value) } label: {
                Text(value).foregroundStyle(color ?? palette.text).multilineTextAlignment(.trailing).contentShape(Rectangle())
            }.buttonStyle(.plain).help("Click to copy \(name)").accessibilityLabel("Copy \(name): \(value)")
        }.font(AppFonts.ui(11))
    }
    private func action(_ title: String, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            HStack { Text(title); Spacer(); Text("→") }.font(AppFonts.ui(11)).padding(10)
                .frame(maxWidth: .infinity).background(palette.text.opacity(0.05), in: RoundedRectangle(cornerRadius: palette.corner)).contentShape(Rectangle())
        }.buttonStyle(FlatButtonStyle(color: palette.blue))
    }
    private func tile(_ section: PanelSection, _ subtitle: String) -> some View {
        Button { model.section = section } label: {
            HStack(spacing: 10) {
                GlyphIcon(text: section.glyph, size: 20, color: palette.native ? palette.text.opacity(0.85) : palette.blue).frame(width: 25)
                VStack(alignment: .leading, spacing: 5) {
                    Text(section.title).font(AppFonts.ui(12, bold: true))
                    Text(subtitle).font(AppFonts.ui(9)).foregroundStyle(palette.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                Text("›").foregroundStyle(palette.secondary)
            }.padding(10).frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
                .background(palette.card.opacity(palette.native ? 1 : 0.65), in: RoundedRectangle(cornerRadius: palette.corner)).overlay(RoundedRectangle(cornerRadius: palette.corner).stroke(palette.text.opacity(palette.native ? 0.06 : 0.15), lineWidth: 1)).contentShape(Rectangle())
        }.buttonStyle(FlatButtonStyle(color: palette.blue)).accessibilityLabel("\(section.title), \(subtitle)")
    }
    private var home: some View {
        VStack(spacing: 10) {
            HStack {
                Button { model.section = .calendar } label: { Text(Date(), format: .dateTime.weekday(.wide).day().month(.wide)) }.buttonStyle(.plain).disabled(!preferences.showsPanel(.calendar))
                Spacer(); Text(Date(), style: .time).foregroundStyle(palette.blue)
            }.font(AppFonts.ui(11))
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                ForEach(preferences.homeSections) { section in
                    tile(section, subtitle(section))
                }
            }
            if preferences.showsPanel(.audio) || preferences.showsPanel(.display) { quickControls }
        }
    }
    private var quickControls: some View {
        VStack(spacing: 6) {
            if preferences.showsPanel(.display) {
                HStack(spacing: 9) {
                    Button { model.section = .display } label: { Label("Display", systemImage: "sun.max").frame(width: 80, alignment: .leading).frame(height: 24).contentShape(Rectangle()) }.buttonStyle(.plain)
                    if let screen = controls.screens.first(where: { $0.brightness != nil }), let brightness = screen.brightness {
                        Slider(value: Binding(get: { controls.screens.first { $0.id == screen.id }?.brightness ?? brightness }, set: { controls.setBrightness($0, id: screen.id) }), in: 0...1)
                        Button("\(Int(brightness * 100))%") { copy("Brightness: \(Int(brightness * 100))%") }.buttonStyle(.plain).frame(width: 32)
                    } else { Spacer(); Button("Open controls") { model.section = .display }.buttonStyle(.plain) }
                }
            }
            if preferences.showsPanel(.audio) {
                HStack(spacing: 9) {
                    Button { model.section = .audio } label: { Label("Sound", systemImage: controls.audio.outputMuted ? "speaker.slash" : "speaker.wave.2").frame(width: 80, alignment: .leading).frame(height: 24).contentShape(Rectangle()) }.buttonStyle(.plain)
                    Slider(value: Binding(get: { controls.audio.outputVolume }, set: { controls.setVolume($0) }), in: 0...1).disabled(!controls.audio.canSetOutput)
                    Button("\(Int(controls.audio.outputVolume * 100))%") { copy("Volume: \(Int(controls.audio.outputVolume * 100))%") }.buttonStyle(.plain).frame(width: 32)
                }
            }
        }.font(AppFonts.ui(10)).controlSize(.small).padding(10)
            .background(palette.card, in: RoundedRectangle(cornerRadius: palette.corner))
    }
    private var wifiPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            block("Wi-Fi") {
                Toggle("Wi-Fi", isOn: Binding(get: { controls.wifi.powered }, set: { controls.setWiFi($0) })).toggleStyle(.switch).disabled(!controls.wifi.present)
                if controls.wifi.connected {
                    HStack { Image(systemName: "checkmark.circle.fill").foregroundStyle(palette.down); Text(controls.wifi.name).font(AppFonts.ui(12, bold: true)); Spacer() }
                    Button("Disconnect") { controls.disconnectWiFi() }.font(AppFonts.ui(11))
                    if health.warning { note(health.state.rawValue + " · the local connection can remain active when internet service is down.") }
                } else { note(controls.wifi.powered ? "Choose a network below to connect." : "Turn on Wi-Fi to find networks.") }
            }
            block("Nearby networks") {
                HStack {
                    Text(controls.busy ? "Finding networks…" : "Available networks").font(AppFonts.ui(11))
                    Spacer()
                    Button("Refresh") { controls.scanWiFi() }.disabled(controls.busy || !controls.wifi.powered)
                }
                if controls.wifiChoices.isEmpty && !controls.busy {
                    note("macOS requires Location access to show network names. Allow names, then choose a network.")
                    action("Allow Wi-Fi network names") { controls.requestWiFiNames() }
                }
                ForEach(controls.wifiChoices) { choice in
                    VStack(alignment: .leading, spacing: 8) {
                        Button { selectedWiFi = choice.id; password = "" } label: {
                            HStack {
                                Image(systemName: "wifi")
                                Text(choice.name).lineLimit(1)
                                Spacer()
                                if choice.secure { Image(systemName: "lock.fill").font(.system(size: 10)) }
                                Text("Connect").font(AppFonts.ui(10)).foregroundStyle(palette.blue)
                            }.padding(.vertical, 8).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        if selectedWiFi == choice.id {
                            if choice.secure { SecureField("Network password", text: $password).textFieldStyle(.roundedBorder).onSubmit { joinSelectedWiFi() } }
                            Button("Join \(choice.name)") { joinSelectedWiFi() }.disabled(controls.busy)
                        }
                    }
                }
            }
            action("Traffic & connection details") { model.section = .network }
            action("Other networks & advanced Wi-Fi settings") { openSettings("com.apple.wifi-settings-extension") }
        }
    }
    private func joinSelectedWiFi() {
        guard let selectedWiFi else { return }
        controls.joinWiFi(selectedWiFi, password: password); password = ""
    }
    private var network: some View {
        VStack(alignment: .leading, spacing: 14) {
            action("Manage Wi-Fi connections") { model.section = .wifi }
            LiveTrafficView(stats: model.traffic, preferences: preferences, health: health, copy: copy,
                            openQuality: { model.section = .quality }, reset: { model.resetTotals() })
            block("Connection details · click a value to copy") {
                row("Internet", health.state.rawValue, color: health.warning ? Color.orange : nil)
                action("Connection quality · ping, jitter & loss") { model.section = .quality }
                row("Interface", reading.interfaceLabel)
                row("Network", controls.wifi.name)
                if controls.wifi.signal != 0 {
                    row("Signal / noise", "\(controls.wifi.signal) / \(controls.wifi.noise) dBm")
                    row("Signal-to-noise", "\(controls.wifi.signal - controls.wifi.noise) dB")
                }
                row("Link rate", controls.wifi.rate > 0 ? String(format: "%.0f Mb/s", controls.wifi.rate) : "—")
                row("Channel", controls.wifi.channel > 0 ? "\(controls.wifi.channel)" : "—")
                ForEach(controls.wifi.addresses, id: \.self) { row($0.contains(":") ? "IPv6" : "IPv4", $0) }
                row("Gateway", controls.wifi.gateway)
                row("DNS", controls.wifi.dns.joined(separator: ", "))
                action("DNS & network settings") { openSettings("com.apple.Network-Settings.extension") }
            }
        }
    }
    private var connectionQuality: some View {
        VStack(alignment: .leading, spacing: 14) {
            block("Connection") {
                row("Internet", health.state.rawValue, color: health.warning ? Color.orange : nil)
                if let start = health.outageStarted {
                    HStack {
                        Text("Current observed outage").foregroundStyle(palette.secondary)
                        Spacer()
                        Button { copy(elapsedLabel(Date().timeIntervalSince(start))) } label: { Text(start, style: .timer).monospacedDigit() }.buttonStyle(.plain)
                    }.font(AppFonts.ui(11))
                }
                row("Last observed outage", health.lastOutageSeconds.map(elapsedLabel) ?? "None this session")
                if let checked = health.lastCheck { row("Last checked", checked.formatted(date: .omitted, time: .standard)) }
            }
            block("ICMP quality · last \(health.samples.count) \(health.samples.count == 1 ? "probe" : "probes")", info: "Ping updates every 2 seconds while a panel is open, or every 30 seconds in the background. Internet checks run every 5 seconds while open. ICMP can be blocked even when internet works. Jitter is the average change between consecutive successful pings; a lost ping breaks that pair. Internet outage detection uses separate TLS checks, rather than ICMP loss alone.") {
                row("Target", health.target)
                row("Latest ping", health.pingText)
                row("Average latency", health.quality.average.map { String(format: "%.1f ms", $0) } ?? "—")
                row("Jitter", health.quality.jitter.map { String(format: "%.1f ms", $0) } ?? "Collecting samples")
                row("Packet loss", health.quality.lossPercent.map { String(format: "%.0f%% · %@", $0, health.lossText) } ?? "—")
            }
        }
    }
    private var audio: some View {
        VStack(alignment: .leading, spacing: 14) {
            block("Output") {
                Picker("Device", selection: Binding(get: { controls.audio.output }, set: { controls.selectAudio($0, input: false) })) {
                    ForEach(controls.audio.devices.filter { !$0.input }) { Text($0.name).tag($0.id) }
                }
                HStack {
                    GlyphIcon(text: PanelSection.audio.glyph, size: 22, color: palette.text)
                    Slider(value: Binding(get: { controls.audio.outputVolume }, set: { controls.setVolume($0) }), in: 0...1).disabled(!controls.audio.canSetOutput)
                    Text("\(Int(controls.audio.outputVolume * 100))%").frame(width: 42)
                }
                Toggle("Mute output", isOn: Binding(get: { controls.audio.outputMuted }, set: { _ in controls.toggleMute() })).toggleStyle(.switch)
                row("Sample rate", controls.audio.sampleRate > 0 ? String(format: "%.1f kHz", controls.audio.sampleRate / 1000) : "—")
                if !controls.audio.canSetOutput { note("This output controls volume in hardware. Use its physical control.") }
            }
            block("Microphone") {
                Picker("Device", selection: Binding(get: { controls.audio.input }, set: { controls.selectAudio($0, input: true) })) {
                    ForEach(controls.audio.devices.filter(\.input)) { Text($0.name).tag($0.id) }
                }
                Slider(value: Binding(get: { controls.audio.inputVolume }, set: { controls.setVolume($0, input: true) }), in: 0...1).disabled(!controls.audio.canSetInput)
                row("Input level", "\(Int(controls.audio.inputVolume * 100))%")
                Toggle("Mute microphone", isOn: Binding(get: { controls.audio.inputMuted }, set: { _ in controls.toggleMute(input: true) })).toggleStyle(.switch)
            }
            note("Per-app audio mixing requires a separate macOS audio-routing engine; this build uses device controls without installing a driver.")
            action("Sound settings") { openSettings("com.apple.Sound-Settings.extension") }
        }
    }
    private var display: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(controls.screens) { screen in
                block(screen.name) {
                    row("Native pixels", screen.pixels)
                    row("Scaling", screen.scale)
                    row("Refresh rate", screen.refresh > 0 ? String(format: "%.0f Hz", screen.refresh) : "Variable / system managed")
                    if let brightness = screen.brightness {
                        HStack {
                            GlyphIcon(text: "\u{f185}", size: 20, color: palette.text)
                            Slider(value: Binding(get: { controls.screens.first { $0.id == screen.id }?.brightness ?? brightness }, set: { controls.setBrightness($0, id: screen.id) }), in: 0...1)
                            Text("\(Int(brightness * 100))%").frame(width: 42)
                        }
                    } else { note("Brightness is managed by the display's hardware or macOS.") }
                }
            }
            action("Resolution, Night Shift & display arrangement") { openSettings("com.apple.Displays-Settings.extension") }
            note("The font is the same JetBrainsMono Nerd Font used by Omarchy. It is loaded for PulseBar only.")
        }
    }
    private var power: some View {
        VStack(alignment: .leading, spacing: 14) {
            block("Battery") {
                HStack {
                    GlyphIcon(text: PanelSection.power.glyph, size: 30, color: palette.down)
                    Text(reading.battery.map { "\(Int($0.fraction * 100))%" } ?? "AC power").font(AppFonts.ui(28, bold: true))
                    Spacer()
                    Text(reading.battery?.label ?? "Desktop").font(AppFonts.ui(11)).foregroundStyle(palette.secondary)
                }
                row("Power flow", BatteryFlow.classify(watts: reading.powerDetails.watts, onAC: reading.battery?.onAC ?? false).rawValue)
                row("Battery power", reading.powerDetails.watts.map { String(format: "%.1f W", abs($0)) } ?? "—")
            }
            block("Battery runtime · estimated", info: "Time left at current use is remaining capacity divided by smoothed measured discharge current. Recent draw uses roughly three minutes of smoothing and adapts faster when CPU load and measured draw both change strongly. It needs two minutes of continuous battery use; a macOS estimate is used while learning when available. Typical full charge uses up to seven days of average battery use and needs ten minutes of observations. Charging and sleep are excluded. These estimates change with future workload.") {
                row("Time left · current use", runtime.reading.remainingText)
                row("Typical full charge", runtime.reading.typicalText)
                row("Smoothed battery draw", runtime.reading.watts.map { String(format: "%.1f W", $0) } ?? "Needs battery use")
                row("Recent CPU load", runtime.reading.cpuText)
            }
            block("Battery health & details", info: "Maximum capacity comes from the macOS system report. Raw capacity estimate is a separate nominal-to-design ratio and can differ. Watts measure net power at the battery, rather than the adapter's total consumption.") {
                row("Maximum capacity (macOS)", batteryHealth.reading.map { "\($0.maximumCapacity)%" } ?? "Loading / unavailable")
                row("Raw capacity estimate", reading.powerDetails.healthPercent.map { "\($0)% of design" } ?? "—")
                row("Cycle count", reading.powerDetails.cycles.map(String.init) ?? "—")
                row("Temperature", reading.powerDetails.temperature.map { String(format: "%.1f °C", $0) } ?? "—")
                row("Voltage", reading.powerDetails.voltage.map { String(format: "%.2f V", $0) } ?? "—")
                row("macOS time remaining", reading.powerDetails.minutesRemaining.map { "\($0 / 60)h \($0 % 60)m" } ?? "Estimating / AC")
                row("Low Power Mode", reading.powerDetails.lowPower ? "On" : "Off")
            }
            block("Power controls", info: "Stay awake prevents automatic idle sleep while PulseBar is running. Closing the lid still sleeps normally. The assertion is released when you turn it off or quit.") {
                Toggle("Stay awake", isOn: Binding(get: { controls.awake }, set: { controls.setAwake($0) })).toggleStyle(.switch)
                action("Energy mode & battery settings") { openSettings("com.apple.Battery-Settings.extension") }
                action("Sleep this Mac") { controls.sleepMac() }
            }
            block("System") {
                row("Processor", reading.cpuDetails.model)
                row("macOS", ProcessInfo.processInfo.operatingSystemVersionString)
                row("Uptime", "\(Int(ProcessInfo.processInfo.systemUptime / 3600))h \(Int(ProcessInfo.processInfo.systemUptime / 60) % 60)m")
            }
        }
    }
    private var system: some View {
        VStack(alignment: .leading, spacing: 14) {
            block("CPU · \(reading.cpuDetails.model)") {
                row("Total utilization", "\(Int(reading.cpu * 100))%", color: palette.blue)
                row("User / system / idle", String(format: "%.0f / %.0f / %.0f%%", reading.cpuDetails.user * 100, reading.cpuDetails.system * 100, reading.cpuDetails.idle * 100))
                row("Physical / logical cores", "\(reading.cpuDetails.physicalCores) / \(reading.cpuDetails.logicalCores)")
                row("Thermal state", reading.cpuDetails.thermal)
                row("Load · 1 / 5 / 15 min", reading.cpuDetails.load.map { String(format: "%.2f", $0) }.joined(separator: " / "))
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 10) {
                    ForEach(Array(reading.cpuDetails.cores.enumerated()), id: \.offset) { i, value in
                        VStack(spacing: 5) {
                            Text("C\(i + 1) \(Int(value * 100))%").font(AppFonts.ui(9))
                            ProgressView(value: value).tint(palette.blue)
                        }
                    }
                }
            }
            block("Memory") {
                row("Active + wired + compressed", "\(byteTotal(reading.memory)) / \(byteTotal(reading.physicalMemory))", color: palette.up)
                row("Pressure", reading.memoryDetails.pressure)
                row("Active", byteTotal(reading.memoryDetails.active))
                row("Wired", byteTotal(reading.memoryDetails.wired))
                row("Compressed", byteTotal(reading.memoryDetails.compressed))
                row("Inactive / cached", byteTotal(reading.memoryDetails.inactive))
                row("Free", byteTotal(reading.memoryDetails.free))
                row("Purgeable", byteTotal(reading.memoryDetails.purgeable))
                row("Swap used / total", "\(byteTotal(reading.memoryDetails.swapUsed)) / \(byteTotal(reading.memoryDetails.swapTotal))")
            }
            action("Open Activity Monitor") { NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app")) }
        }
    }
    private var calendar: some View {
        VStack(alignment: .leading, spacing: 14) {
            MonthCalendar(palette: palette)
            action("Open Calendar") { NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Calendar.app")) }
        }
    }
    private var world: some View {
        VStack(alignment: .leading, spacing: 14) {
            block("Across the day") {
                ForEach(zones, id: \.self) { id in
                    if let zone = TimeZone(identifier: id) {
                        HStack {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(id.split(separator: "/").last?.replacingOccurrences(of: "_", with: " ") ?? id).font(AppFonts.ui(12, bold: true))
                                Text(id).font(AppFonts.ui(9)).foregroundStyle(palette.secondary)
                            }
                            Spacer()
                            Text(zoneTime(zone)).font(AppFonts.ui(14))
                            Button("×") { zones.removeAll { $0 == id }; saveZones() }.buttonStyle(.plain)
                        }.padding(.vertical, 6)
                    }
                }
            }
            TextField("Search city or time zone", text: $zoneQuery).textFieldStyle(.roundedBorder)
            if !zoneQuery.isEmpty {
                ForEach(Array(TimeZone.knownTimeZoneIdentifiers.filter { $0.localizedCaseInsensitiveContains(zoneQuery.replacingOccurrences(of: " ", with: "_")) && !zones.contains($0) }.prefix(8)), id: \.self) { id in
                    action(id) { zones.append(id); saveZones(); zoneQuery = "" }
                }
            }
        }
    }
    private func saveZones() { UserDefaults.standard.set(zones, forKey: "worldZones") }
    private func zoneTime(_ zone: TimeZone) -> String {
        var format = Date.FormatStyle.dateTime.hour().minute().weekday(.abbreviated)
        format.timeZone = zone
        return Date().formatted(format)
    }
    private var weatherPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            TextField("City name", text: $weather.city).textFieldStyle(.roundedBorder).onSubmit { weather.fetch() }
            action(weather.busy ? "Loading…" : "Load forecast") { weather.fetch() }.disabled(weather.busy)
            if let error = weather.error { note(error) }
            if let forecast = weather.forecast {
                block("\(forecast.city), \(forecast.country)") {
                    Text(String(format: "%.0f °C", forecast.temperature)).font(AppFonts.ui(30, bold: true)).foregroundStyle(palette.blue)
                    row("Wind", String(format: "%.0f km/h", forecast.wind))
                    row("Humidity", String(format: "%.0f%%", forecast.humidity))
                    ForEach(forecast.days) { day in row(day.id, String(format: "%.0f / %.0f °C · %.0f%% rain", day.high, day.low, day.rain)) }
                }
            }
            note("Forecasts load only when requested. Your typed city is sent to Open-Meteo; device location is not used.")
            Link("Weather data by Open-Meteo.com · CC BY 4.0", destination: URL(string: "https://open-meteo.com/")!).font(AppFonts.ui(9))
        }
    }
    private var mediaPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("Player", selection: $media.player) { Text("Music").tag("Music"); Text("Spotify").tag("Spotify") }.pickerStyle(.segmented)
            block("Now playing") {
                Text(media.title).font(AppFonts.ui(16, bold: true))
                note(media.artist)
                note(media.state)
                HStack {
                    Button("Previous") { media.control("previous track") }
                    Spacer()
                    Button("Play / Pause") { media.control("playpause") }
                    Spacer()
                    Button("Next") { media.control("next track") }
                }.font(AppFonts.ui(10))
                action("Read current track") { media.read() }
                if let message = media.message { note(message) }
            }
            note("macOS asks for Automation access when you first control a player. Nothing is polled while this panel is closed.")
        }
    }
    private func subtitle(_ section: PanelSection) -> String {
        switch section {
        case .wifi: return health.warning && controls.wifi.connected ? "Internet unavailable" : controls.wifi.connected ? controls.wifi.name : "Choose a network"
        case .audio: return controls.audio.outputName
        case .display: return controls.screens.first?.name ?? "Displays"
        case .power: return reading.battery.map { "\(Int($0.fraction * 100))% · \($0.label)" } ?? "AC power"
        case .system: return "CPU \(Int(reading.cpu * 100))% · RAM \(Int(reading.memoryFraction * 100))%"
        case .network: return health.warning ? health.state.rawValue : "Traffic · " + health.pingText
        case .calendar: return "Date & month"
        case .world: return "Time zones"
        case .weather: return "City forecast"
        case .media: return "Music & Spotify"
        default: return ""
        }
    }
    private func copy(_ value: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        copied = pasteboard.setString(value, forType: .string) ? "Copied to clipboard" : "Could not copy"
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = nil }
    }
    private func copyStats() {
        let reading = model.current
        var lines = [panelSection.title]
        switch panelSection {
        case .quality:
            lines += ["Internet: \(health.state.rawValue)", "Ping \(health.target): \(health.pingText)", "Jitter: \(health.quality.jitter.map { String(format: "%.1f ms", $0) } ?? "Collecting")", "Loss: \(health.lossText)", "Last observed outage: \(health.lastOutageSeconds.map(elapsedLabel) ?? "None this session")"]
        case .wifi, .network:
            lines += ["Interface: \(reading.interfaceLabel)", "Network: \(controls.wifi.name)", "Internet: \(health.state.rawValue)", "Ping \(health.target): \(health.pingText)", "Download: \(preferences.unit.string(reading.download))", "Upload: \(preferences.unit.string(reading.upload))", "IP: \(controls.wifi.addresses.joined(separator: ", "))", "DNS: \(controls.wifi.dns.joined(separator: ", "))", "Signal: \(controls.wifi.signal) dBm"]
        case .power:
            lines += ["Runtime remaining: \(runtime.reading.remainingText)", "Typical full charge: \(runtime.reading.typicalText)"]
            lines += ["Power flow: \(BatteryFlow.classify(watts: reading.powerDetails.watts, onAC: reading.battery?.onAC ?? false).rawValue)", "Battery power: \(reading.powerDetails.watts.map { String(format: "%.1f W", abs($0)) } ?? "Unavailable")"]
            lines += ["Battery: \(reading.battery.map { Int($0.fraction * 100).description + "%" } ?? "AC")", "Maximum capacity (macOS): \(batteryHealth.reading.map { "\($0.maximumCapacity)%" } ?? "Unavailable")", "Raw capacity estimate: \(reading.powerDetails.healthPercent.map { "\($0)% of design" } ?? "Unavailable")", "Cycles: \(reading.powerDetails.cycles.map(String.init) ?? "Unavailable")"]
        default:
            lines += ["CPU: \(Int(reading.cpu * 100))%", "Memory: \(byteTotal(reading.memory)) / \(byteTotal(reading.physicalMemory))", "Download: \(preferences.unit.string(reading.download))", "Upload: \(preferences.unit.string(reading.upload))"]
        }
        copy(lines.joined(separator: "\n"))
    }
    private var settings: some View {
        VStack(alignment: .leading, spacing: 14) {
            block("Theme") {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                    ForEach(BarTheme.allCases) { theme in
                        Button { preferences.theme = theme } label: {
                            HStack {
                                Circle().fill(theme.palette.blue).frame(width: 8, height: 8)
                                Text(theme.rawValue).font(AppFonts.ui(10))
                                Spacer()
                                if preferences.theme == theme { Text("✓") }
                            }.padding(10).frame(maxWidth: .infinity).background(theme.palette.card).contentShape(Rectangle())
                                .overlay(Rectangle().stroke(preferences.theme == theme ? palette.blue : .clear, lineWidth: 1))
                        }.buttonStyle(FlatButtonStyle(color: palette.blue))
                    }
                }
                note("JetBrainsMono Nerd Font · bundled privately with this app")
            }
            block("Menu bar items") {
                ForEach(BarModule.allCases) { module in
                    HStack {
                        Toggle(module.title, isOn: Binding(get: { preferences.shows(module) }, set: { preferences.setModule(module, enabled: $0) }))
                            .disabled(preferences.barModules.count == 1 && preferences.shows(module))
                    }
                }
                note("Hold Command and drag items in the menu bar to reorder them. macOS manages the spacing.")
                action("Hide Apple's duplicate menu bar icons…") { openSettings("com.apple.ControlCenter-Settings.extension") }
            }
            block("Controls & modules") {
                ForEach([PanelSection.wifi, .audio, .display, .power, .system, .calendar, .network, .media, .world, .weather]) { section in
                    Toggle(section.title, isOn: Binding(get: { preferences.showsPanel(section) }, set: { preferences.setPanel(section, enabled: $0) }))
                }
                note("Hide modules or bottom sliders you don't use. You can add them back at any time.")
            }
            block("Traffic display") {
                Toggle("Single-line network speeds", isOn: $preferences.inline)
                Toggle("Colored arrows", isOn: $preferences.colorArrows)
                note("Two stacked speeds use 64 points. Wi-Fi and battery have separate native items.")
                Picker("Units", selection: $preferences.unit) { ForEach(RateUnit.allCases) { Text($0 == .bytes ? "MB/s" : "Mb/s").tag($0) } }.pickerStyle(.segmented)
            }
            block("Network source") {
                Toggle("Detect internet outages", isOn: Binding(get: { health.enabled }, set: { health.setEnabled($0) }))
                Picker("Interface", selection: $preferences.interface) {
                    Text("Automatic · primary physical").tag("auto")
                    ForEach(model.interfaces) { Text($0.label).tag($0.id) }
                }
                note("Automatic mode tracks the physical route, including when a VPN is active.")
            }
            block("Startup") {
                Toggle("Launch at login", isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }))
                Toggle("Omarchy global shortcuts", isOn: $preferences.hotKeys)
                note("⌘⌃A Audio · N Wi-Fi · D Display · P Power. Optional globally; always available while the panel is open.")
                if let message = model.loginMessage { note(message) }
            }
        }.toggleStyle(.switch).font(AppFonts.ui(11)).tint(palette.blue)
    }
}

struct TrafficGraph: View {
    let points: [TrafficPoint]
    let down: Color, up: Color, grid: Color
    var body: some View {
        Canvas { context, size in
            for y in [0.0, 0.5, 1.0] {
                var line = Path(); line.move(to: CGPoint(x: 0, y: size.height * y)); line.addLine(to: CGPoint(x: size.width, y: size.height * y))
                context.stroke(line, with: .color(grid.opacity(0.15)), style: StrokeStyle(lineWidth: 0.5, dash: [3, 4]))
            }
            guard let end = points.last?.id, points.count > 1 else { return }
            let peak = max(1024, points.map { max($0.download, $0.upload) }.max() ?? 0) * 1.12
            for (isDownload, color) in [(true, down), (false, up)] {
                var line = Path()
                for (i, point) in points.enumerated() {
                    let x = size.width * max(0, 1 - (end - point.id) / 60)
                    let value = isDownload ? point.download : point.upload
                    let p = CGPoint(x: x, y: size.height - max(0.8, size.height * value / peak))
                    if i == 0 { line.move(to: p) } else { line.addLine(to: p) }
                }
                context.stroke(line, with: .color(color), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            }
        }
    }
}

struct MonthCalendar: View {
    let palette: Palette
    @State private var month = Date()
    @State private var selected = Date()
    private var cal: Calendar { var c = Calendar.current; c.firstWeekday = 2; return c }
    private var first: Date { cal.date(from: cal.dateComponents([.year, .month], from: month))! }
    private var start: Date {
        let offset = (cal.component(.weekday, from: first) + 5) % 7
        return cal.date(byAdding: .day, value: -offset, to: first)!
    }
    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Button("←") { move(-1) }; Spacer()
                Text(month, format: .dateTime.month(.wide).year()).font(AppFonts.ui(16, bold: true))
                Spacer(); Button("→") { move(1) }
            }
            VStack(spacing: 10) {
                HStack(spacing: 0) {
                    Text("W").frame(width: 26)
                    ForEach(Array(["M", "T", "W", "T", "F", "S", "S"].enumerated()), id: \.offset) { _, label in
                        Text(label).frame(maxWidth: .infinity)
                    }
                }.font(AppFonts.ui(10)).foregroundStyle(palette.secondary)
                ForEach(0..<6, id: \.self) { week in
                    HStack(spacing: 0) {
                        Text("\(Calendar(identifier: .iso8601).component(.weekOfYear, from: cal.date(byAdding: .day, value: week * 7, to: start)!))")
                            .font(AppFonts.ui(9)).foregroundStyle(palette.secondary).frame(width: 26)
                        ForEach(0..<7, id: \.self) { day in
                            let date = cal.date(byAdding: .day, value: week * 7 + day, to: start)!
                            Button { selected = date } label: {
                                Text("\(cal.component(.day, from: date))").font(AppFonts.ui(11)).frame(maxWidth: .infinity, minHeight: 28)
                                    .foregroundStyle(cal.isDate(date, equalTo: month, toGranularity: .month) ? palette.text : palette.secondary.opacity(0.5))
                                    .background(cal.isDate(date, inSameDayAs: selected) ? palette.blue.opacity(0.3) : .clear).contentShape(Rectangle())
                            }.buttonStyle(.plain).frame(maxWidth: .infinity)
                                .accessibilityLabel(date.formatted(.dateTime.day().month().year()))
                        }
                    }
                }
            }
            Text(selected, format: .dateTime.weekday(.wide).day().month(.wide).year()).font(AppFonts.ui(12))
            Button("Today") { month = Date(); selected = Date() }.font(AppFonts.ui(11))
        }.padding(14).background(palette.card.opacity(0.6), in: RoundedRectangle(cornerRadius: palette.corner))
    }
    private func move(_ offset: Int) { month = cal.date(byAdding: .month, value: offset, to: month)! }
}
