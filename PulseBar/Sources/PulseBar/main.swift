import AppKit

AppFonts.register()

if CommandLine.arguments.contains("--battery-health-check") {
    print(BatteryReportReader.read().map { "Maximum capacity (macOS): \($0.maximumCapacity)%" } ?? "System health unavailable")
} else if let index = CommandLine.arguments.firstIndex(of: "--ping-check"), index + 1 < CommandLine.arguments.count {
    let result = PingProbe.measure(CommandLine.arguments[index + 1])
    print(result.map { String(format: "%.3f ms", $0) } ?? "No echo reply")
} else if CommandLine.arguments.contains("--diagnose") {
    let system = SystemReader()
    _ = system.cpu()
    let args = CommandLine.arguments
    let interfaceIndex = args.firstIndex(of: "--interface")
    let explicitName = interfaceIndex.flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil }
    let name = explicitName ?? NetworkReader.primaryInterface() ?? ""
    var tracker = TrafficTracker()
    _ = tracker.sample(name: name, counter: NetworkReader.counter(interface: name), time: ProcessInfo.processInfo.systemUptime)
    if args.contains("--signal-ready") { FileHandle.standardError.write(Data("READY\n".utf8)) }
    Thread.sleep(forTimeInterval: 1)
    let rates = tracker.sample(name: name, counter: NetworkReader.counter(interface: name), time: ProcessInfo.processInfo.systemUptime)
    let info: [String: Any] = [
        "font": AppFonts.regular,
        "font_available": NSFont(name: AppFonts.regular, size: 12) != nil,
        "interface": name,
        "counter_available": NetworkReader.counter(interface: name) != nil,
        "interfaces": NetworkReader.interfaces().map { $0.label },
        "download_Bps": rates.0, "upload_Bps": rates.1,
        "cpu_percent": system.cpu() * 100,
        "memory_bytes": system.memory(),
        "physical_memory_bytes": ProcessInfo.processInfo.physicalMemory,
        "battery_percent": system.battery().map { $0.fraction * 100 } as Any? ?? NSNull()
    ]
    if let data = try? JSONSerialization.data(withJSONObject: info, options: [.prettyPrinted, .sortedKeys]),
       let text = String(data: data, encoding: .utf8) { print(text) }
} else {
    MainActor.assumeIsolated {
        let arguments = CommandLine.arguments
        let index = arguments.firstIndex(of: "--snapshot")
        let snapshotPath = index.flatMap { $0 + 1 < arguments.count ? arguments[$0 + 1] : nil }
        let app = NSApplication.shared
        let delegate = AppDelegate(snapshotPath: snapshotPath)
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
