import Foundation

struct TrafficCounter: Equatable {
    var received: UInt64
    var sent: UInt64
}

struct TrafficPoint: Identifiable, Equatable {
    let id: TimeInterval
    let download: Double
    let upload: Double
}

/// Tracks one interface at a time. Reconnects, sleep and resets establish a
/// fresh baseline instead of displaying a burst from an unrelated counter.
struct TrafficTracker {
    private var previous: (name: String, counter: TrafficCounter, time: TimeInterval)?
    private(set) var received: UInt64 = 0
    private(set) var sent: UInt64 = 0

    mutating func sample(name: String, counter: TrafficCounter?, time: TimeInterval) -> (Double, Double) {
        defer { previous = counter.map { (name, $0, time) } }
        guard let counter, let old = previous, old.name == name,
              time > old.time, time - old.time <= 5,
              counter.received >= old.counter.received,
              counter.sent >= old.counter.sent else { return (0, 0) }
        let down = counter.received - old.counter.received
        let up = counter.sent - old.counter.sent
        received &+= down
        sent &+= up
        return (Double(down) / (time - old.time), Double(up) / (time - old.time))
    }

    mutating func rebaseline() { previous = nil }
    mutating func reset() { received = 0; sent = 0; previous = nil }
}

enum RateUnit: String, CaseIterable, Identifiable {
    case bytes = "Bytes", bits = "Bits"
    var id: String { rawValue }
    func parts(_ bytes: Double) -> (value: String, unit: String) {
        let suffixes = self == .bytes ? ["B/s", "KB/s", "MB/s", "GB/s", "TB/s"] : ["b/s", "Kb/s", "Mb/s", "Gb/s", "Tb/s"]
        var amount = max(0, bytes.isFinite ? bytes : 0) * (self == .bits ? 8 : 1)
        var index = 0
        while amount >= 999.5 && index < suffixes.count - 1 { amount /= 1000; index += 1 }
        let value = amount >= 100 || index == 0 ? String(format: "%.0f", amount) : String(format: "%.1f", amount)
        return (value, suffixes[index])
    }
    func string(_ bytes: Double) -> String {
        let p = parts(bytes)
        return "\(p.value) \(p.unit)"
    }
}

func byteTotal(_ bytes: UInt64) -> String {
    ByteCountFormatter.string(fromByteCount: Int64(clamping: bytes), countStyle: .decimal)
}

struct BatteryReading: Equatable {
    var fraction: Double
    var charging: Bool
    var onAC: Bool
    var label: String { charging ? "Charging" : onAC ? "Plugged in" : "On battery" }
    var statusSymbol: String {
        if charging || onAC { return "battery.100.bolt" }
        let value = fraction.isFinite ? min(1, max(0, fraction)) : 0
        return "battery.\(Int((value * 4).rounded()) * 25)"
    }
}

struct Reading: Equatable {
    var download: Double = 0
    var upload: Double = 0
    var received: UInt64 = 0
    var sent: UInt64 = 0
    var interface: String = ""
    var interfaceLabel: String = "No active interface"
    var connected = false
    var wifiPowered = false
    var cpu: Double = 0
    var memory: UInt64 = 0
    var physicalMemory: UInt64 = ProcessInfo.processInfo.physicalMemory
    var battery: BatteryReading?
    var cpuDetails = CPUDetails()
    var memoryDetails = MemoryDetails()
    var powerDetails = PowerDetails()
    var history: [TrafficPoint] = []
    var since = Date()
    var memoryFraction: Double { Double(memory) / Double(max(1, physicalMemory)) }
    var panelDetails: Reading {
        var copy = self
        copy.download = 0; copy.upload = 0; copy.received = 0; copy.sent = 0; copy.history = []
        return copy
    }
}

struct CPUDetails: Equatable {
    var user: Double = 0, system: Double = 0, idle: Double = 1
    var cores: [Double] = []
    var load: [Double] = []
    var thermal = "Nominal"
    var model = "Mac"
    var logicalCores = ProcessInfo.processInfo.processorCount
    var physicalCores = 0
}

struct MemoryDetails: Equatable {
    var active: UInt64 = 0, wired: UInt64 = 0, compressed: UInt64 = 0
    var inactive: UInt64 = 0, free: UInt64 = 0, purgeable: UInt64 = 0
    var swapUsed: UInt64 = 0, swapTotal: UInt64 = 0
    var pressure = "Normal"
    var used: UInt64 { active + wired + compressed }
}

struct PowerDetails: Equatable {
    var cycles: Int?, healthPercent: Int?, temperature: Double?, voltage: Double?, watts: Double?
    var currentMA: Double?, remainingCapacityMAh: Double?, fullCapacityMAh: Double?
    var minutesRemaining: Int?
    var lowPower = false
}

/// Failed ICMP echoes alone never establish an internet outage.
enum ConnectivityState: String {
    case checking = "Checking", online = "Internet reachable", uncertain = "Checking connection"
    case unreachable = "Internet not reachable", offline = "No network route", disabled = "Monitoring off"
}
struct ConnectivityTracker {
    private(set) var failures = 0
    mutating func reset() { failures = 0 }
    mutating func record(reachable: Bool) -> ConnectivityState {
        if reachable { failures = 0; return .online }
        failures += 1
        return failures >= 2 ? .unreachable : .uncertain
    }
}

struct PingSample: Identifiable {
    let id: TimeInterval
    let milliseconds: Double?
}
struct ConnectionQuality {
    let samples: [PingSample]
    var received: [Double] { samples.compactMap(\.milliseconds) }
    var lossPercent: Double? { samples.isEmpty ? nil : Double(samples.filter { $0.milliseconds == nil }.count) / Double(samples.count) * 100 }
    var average: Double? { received.isEmpty ? nil : received.reduce(0, +) / Double(received.count) }
    /// Mean absolute RTT difference between adjacent successful probes.
    /// A lost probe breaks the pair instead of manufacturing a jitter sample.
    var jitter: Double? {
        let changes = zip(samples, samples.dropFirst()).compactMap { a, b -> Double? in
            guard let a = a.milliseconds, let b = b.milliseconds else { return nil }; return abs(b - a)
        }
        return changes.isEmpty ? nil : changes.reduce(0, +) / Double(changes.count)
    }
}
enum BatteryFlow: String {
    case charging = "Charging", discharging = "Discharging", adapter = "Running on adapter", idle = "Battery idle", unknown = "Unavailable"
    static func classify(watts: Double?, onAC: Bool) -> BatteryFlow {
        guard let watts, watts.isFinite else { return onAC ? .adapter : .unknown }
        if watts > 0.3 { return .charging }
        if watts < -0.3 { return .discharging }
        return onAC ? .adapter : .idle
    }
}
func elapsedLabel(_ seconds: TimeInterval) -> String {
    let value = Int(max(0, seconds))
    if value >= 3600 { return "\(value / 3600)h \(value % 3600 / 60)m" }
    if value >= 60 { return "\(value / 60)m \(value % 60)s" }
    return "\(value)s"
}

/// Keep lightweight ping independent of slower connectivity timeouts. Opening a
/// panel requests fresh probes, without starting a second copy of in-flight work.
struct NetworkProbeSchedule {
    struct Work: Equatable { let ping: Bool; let connectivity: Bool }
    private var lastPing: TimeInterval?
    private var lastConnectivity: TimeInterval?
    mutating func reset() { lastPing = nil; lastConnectivity = nil }
    mutating func next(at time: TimeInterval, visible: Bool, force: Bool = false,
                       pingBusy: Bool, connectivityBusy: Bool) -> Work {
        let ping = !pingBusy && (force || lastPing == nil || time - lastPing! >= (visible ? 2 : 30))
        let connectivity = !connectivityBusy && (force || lastConnectivity == nil || time - lastConnectivity! >= (visible ? 5 : 30))
        if ping { lastPing = time }
        if connectivity { lastConnectivity = time }
        return Work(ping: ping, connectivity: connectivity)
    }
}
