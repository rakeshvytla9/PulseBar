import AppKit
import Network
import Darwin

/// One short, non-privileged IPv4 echo request. No process, helper or library.
enum PingProbe {
    static func measure(_ host: String, timeout: Double = 1.5) -> Double? {
        var destination = sockaddr_in()
        destination.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        destination.sin_family = sa_family_t(AF_INET)
        guard inet_pton(AF_INET, host, &destination.sin_addr) == 1 else { return nil }
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP)
        guard fd >= 0 else { return nil }; defer { close(fd) }
        let identifier = UInt16.random(in: 1...UInt16.max)
        let sequence = UInt16.random(in: 1...UInt16.max)
        let nonce = (0..<16).map { _ in UInt8.random(in: 0...255) }
        var packet: [UInt8] = [8, 0, 0, 0, UInt8(identifier >> 8), UInt8(identifier & 255), UInt8(sequence >> 8), UInt8(sequence & 255)] + nonce
        var sum: UInt32 = 0
        for i in stride(from: 0, to: packet.count, by: 2) { sum += UInt32(packet[i]) << 8 | UInt32(packet[i + 1]) }
        while sum >> 16 != 0 { sum = (sum & 0xffff) + (sum >> 16) }
        let checksum = ~UInt16(sum)
        packet[2] = UInt8(checksum >> 8); packet[3] = UInt8(checksum & 255)
        let start = ProcessInfo.processInfo.systemUptime
        let sent = withUnsafePointer(to: &destination) { address in
            address.withMemoryRebound(to: sockaddr.self, capacity: 1) { ptr in
                packet.withUnsafeBytes { sendto(fd, $0.baseAddress, $0.count, 0, ptr, socklen_t(MemoryLayout<sockaddr_in>.size)) }
            }
        }
        guard sent == packet.count else { return nil }
        var buffer = [UInt8](repeating: 0, count: 2048)
        while true {
            let remaining = timeout - (ProcessInfo.processInfo.systemUptime - start)
            guard remaining > 0 else { return nil }
            var poller = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            guard poll(&poller, 1, Int32(remaining * 1000)) > 0 else { return nil }
            var source = sockaddr_in(); var length = socklen_t(MemoryLayout<sockaddr_in>.size)
            let count = withUnsafeMutablePointer(to: &source) { address in
                address.withMemoryRebound(to: sockaddr.self, capacity: 1) { ptr in
                    buffer.withUnsafeMutableBytes { recvfrom(fd, $0.baseAddress, $0.count, 0, ptr, &length) }
                }
            }
            guard count >= 8 else { continue }
            let offset = buffer[0] >> 4 == 4 ? Int(buffer[0] & 15) * 4 : 0
            guard count >= offset + packet.count, source.sin_addr.s_addr == destination.sin_addr.s_addr,
                  buffer[offset] == 0, buffer[offset + 1] == 0,
                  Array(buffer[(offset + 4)..<(offset + 8)]) == Array(packet[4..<8]),
                  Array(buffer[(offset + 8)..<(offset + 24)]) == nonce else { continue }
            return (ProcessInfo.processInfo.systemUptime - start) * 1000
        }
    }
}

@MainActor final class NetworkHealth: ObservableObject {
    @Published private(set) var state: ConnectivityState = .checking
    @Published private(set) var ping: Double?
    @Published private(set) var pingAttempted = false
    @Published private(set) var busy = false
    @Published private(set) var lastCheck: Date?
    @Published private(set) var target = UserDefaults.standard.string(forKey: "pingTarget") ?? "1.1.1.1"
    @Published private(set) var enabled = UserDefaults.standard.object(forKey: "networkHealthEnabled") as? Bool ?? true
    @Published private(set) var samples: [PingSample] = []
    @Published private(set) var outageStarted: Date?
    @Published private(set) var lastOutageSeconds: TimeInterval?
    private var failedSince: Date?
    @Published var validation: String?
    private var tracker = ConnectivityTracker()
    private var monitor: NWPathMonitor?
    private let queue = DispatchQueue(label: "local.pulsebar.health", qos: .utility)
    private var hasRoute = false
    private var schedule = NetworkProbeSchedule()
    private var panelVisible = false
    private var generation = 0
    private var checking = false
    private var probe: NWConnection?
    private var pendingTimeout: DispatchWorkItem?
    var pingText: String { ping.map { String(format: "%.1f ms", $0) } ?? (pingAttempted ? "No echo reply" : "—") }
    var quality: ConnectionQuality { ConnectionQuality(samples: samples) }
    var lossText: String { samples.isEmpty ? "—" : "\(samples.filter { $0.milliseconds == nil }.count)/\(samples.count) unanswered" }
    var warning: Bool { state == .unreachable || state == .offline }

    func start() {
        guard enabled, monitor == nil else { if !enabled { state = .disabled }; return }
        let monitor = NWPathMonitor(); self.monitor = monitor
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                guard let self, self.enabled, self.monitor != nil else { return }
                self.generation += 1
                self.probe?.stateUpdateHandler = nil; self.probe?.cancel(); self.probe = nil
                self.pendingTimeout?.cancel(); self.pendingTimeout = nil; self.checking = false
                self.hasRoute = path.status == .satisfied
                self.tracker.reset(); self.schedule.reset()
                self.state = self.hasRoute ? .checking : .offline
                self.failedSince = nil
                if !self.hasRoute && self.outageStarted == nil { self.outageStarted = Date() }
                self.tick()
            }
        }
        monitor.start(queue: queue)
    }
    func stop() {
        generation += 1; monitor?.cancel(); monitor = nil; schedule.reset()
        outageStarted = nil; failedSince = nil
        probe?.stateUpdateHandler = nil; probe?.cancel(); probe = nil
        pendingTimeout?.cancel(); pendingTimeout = nil; checking = false
    }
    func setEnabled(_ value: Bool) {
        enabled = value; UserDefaults.standard.set(value, forKey: "networkHealthEnabled")
        if value { start() } else { stop(); state = .disabled; outageStarted = nil; failedSince = nil }
    }
    func setPanelVisible(_ value: Bool) {
        guard panelVisible != value else { return }
        panelVisible = value
        if value { tick(force: true) }
    }
    func tick(force: Bool = false) {
        guard enabled, hasRoute else { return }
        let work = schedule.next(at: ProcessInfo.processInfo.systemUptime, visible: panelVisible,
                                 force: force, pingBusy: busy, connectivityBusy: checking)
        if work.connectivity {
            checking = true
            let token = generation
            checkTLS("one.one.one.one", token: token) { [weak self] success in
                guard let self, self.generation == token else { return }
                if success { self.record(true); return }
                self.checkTLS("dns.google", token: token) { [weak self] second in
                    guard let self, self.generation == token else { return }; self.record(second)
                }
            }
        }
        if work.ping { runPing(target) }
    }
    private func record(_ success: Bool) {
        checking = false; state = tracker.record(reachable: success); lastCheck = Date()
        if success {
            if let start = outageStarted { lastOutageSeconds = Date().timeIntervalSince(start); outageStarted = nil }
            failedSince = nil
        } else {
            if failedSince == nil { failedSince = Date() }
            if state == .unreachable && outageStarted == nil { outageStarted = failedSince }
        }
    }
    private func checkTLS(_ host: String, token: Int, completion: @escaping (Bool) -> Void) {
        let connection = NWConnection(host: NWEndpoint.Host(host), port: 443, using: .tls)
        probe = connection
        var finished = false
        let finish: (Bool) -> Void = { [weak self] result in
            guard let self, self.generation == token, !finished else { return }
            finished = true; self.pendingTimeout?.cancel(); connection.stateUpdateHandler = nil; connection.cancel(); self.probe = nil; completion(result)
        }
        connection.stateUpdateHandler = { status in
            Task { @MainActor in
                switch status { case .ready: finish(true); case .failed: finish(false); default: break }
            }
        }
        let timeout = DispatchWorkItem { finish(false) }
        pendingTimeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: timeout)
        connection.start(queue: queue)
    }
    func runPing(_ address: String) {
        guard !busy else { return }
        var parsed = in_addr()
        guard inet_pton(AF_INET, address, &parsed) == 1 else { validation = "Enter an IPv4 address, such as 1.1.1.1."; return }
        validation = nil
        if target != address {
            target = address; samples.removeAll(); ping = nil; pingAttempted = false
            UserDefaults.standard.set(address, forKey: "pingTarget")
        }
        busy = true
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let value = PingProbe.measure(address)
            Task { @MainActor in
                guard let self else { return }
                self.ping = value; self.pingAttempted = true; self.busy = false
                self.samples.append(PingSample(id: ProcessInfo.processInfo.systemUptime, milliseconds: value))
                if self.samples.count > 20 { self.samples.removeFirst(self.samples.count - 20) }
            }
        }
    }
}
