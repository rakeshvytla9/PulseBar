import Foundation
import Combine

/// Standalone regression checks: requires only the installed Swift toolchain,
/// not the XCTest framework shipped with full Xcode.
@main struct TrafficTests {
    static var checks = 0
    static func equal<T: Equatable>(_ actual: T, _ expected: T, _ message: String) {
        checks += 1
        guard actual == expected else {
            fputs("FAIL: \(message): got \(actual), expected \(expected)\n", stderr)
            exit(1)
        }
    }

    @MainActor static func main() {
        var tracker = TrafficTracker()
        let first = tracker.sample(name: "en0", counter: .init(received: 1_000, sent: 500), time: 1)
        equal(first.0, 0, "first sample establishes a baseline")
        let rate = tracker.sample(name: "en0", counter: .init(received: 5_000, sent: 1_500), time: 3)
        equal(rate.0, 2_000, "download divides by actual elapsed time")
        equal(rate.1, 500, "upload divides by actual elapsed time")
        equal(tracker.received, 4_000, "received session total")
        equal(tracker.sent, 1_000, "sent session total")

        tracker = TrafficTracker()
        let baseline = UInt64(UInt32.max) - 100
        _ = tracker.sample(name: "en0", counter: .init(received: baseline, sent: baseline), time: 1)
        let large = tracker.sample(name: "en0", counter: .init(received: baseline + 1_000_000_000, sent: baseline + 700), time: 2)
        equal(large.0, 1_000_000_000, "64-bit counters cross 4 GB")
        equal(large.1, 700, "64-bit sent counters cross 4 GB")

        tracker = TrafficTracker()
        _ = tracker.sample(name: "en0", counter: .init(received: 1_000, sent: 1_000), time: 1)
        equal(tracker.sample(name: "en1", counter: .init(received: 999_000, sent: 999_000), time: 2).0, 0, "interface change does not spike")
        equal(tracker.sample(name: "en1", counter: .init(received: 20, sent: 20), time: 3).0, 0, "counter reset does not underflow")
        equal(tracker.sample(name: "en1", counter: nil, time: 4).0, 0, "missing interface gives zero")
        equal(tracker.sample(name: "en1", counter: .init(received: 1_000_000, sent: 1_000_000), time: 5).0, 0, "reconnect establishes baseline")
        equal(tracker.received, 0, "no totals accumulated across discontinuities")

        tracker = TrafficTracker()
        _ = tracker.sample(name: "en0", counter: .init(received: 0, sent: 0), time: 1)
        equal(tracker.sample(name: "en0", counter: .init(received: 1_000_000, sent: 1_000), time: 100).0, 0, "sleep gap establishes baseline")
        _ = tracker.sample(name: "en0", counter: .init(received: 1_001_000, sent: 2_000), time: 101)
        equal(tracker.received, 1_000, "sampling resumes after sleep")
        tracker.reset()
        equal(tracker.received, 0, "explicit total reset")
        equal(tracker.sample(name: "en0", counter: .init(received: 9_000_000, sent: 9_000_000), time: 102).0, 0, "reset establishes fresh baseline")

        equal(RateUnit.bytes.string(1_000_000), "1.0 MB/s", "decimal bytes")
        equal(RateUnit.bits.string(1_000_000), "8.0 Mb/s", "bits conversion")
        equal(RateUnit.bytes.string(999_999), "1.0 MB/s", "rounding at unit boundary")
        equal(RateUnit.bytes.string(-100), "0 B/s", "negative rate")
        equal(RateUnit.bytes.string(.nan), "0 B/s", "nonfinite rate")
        var health = ConnectivityTracker()
        equal(health.record(reachable: true), .online, "successful TLS probe confirms reachability")
        equal(health.record(reachable: false), .uncertain, "one failed round does not declare an outage")
        equal(health.record(reachable: false), .unreachable, "two failed rounds report unreachable")
        equal(health.record(reachable: true), .online, "recovery clears an outage immediately")
        equal(health.failures, 0, "success resets consecutive failures")
        _ = health.record(reachable: false)
        health.reset()
        equal(health.record(reachable: false), .uncertain, "route changes discard previous failures")
        let quality = ConnectionQuality(samples: [10.0, 20.0, nil, 40.0, 50.0].enumerated().map { PingSample(id: Double($0.offset), milliseconds: $0.element) })
        equal(quality.average, 30, "average RTT excludes lost probes")
        equal(quality.jitter, 10, "loss breaks adjacent RTT pairs")
        equal(quality.lossPercent, 20, "loss counts all attempts")
        let lost = ConnectionQuality(samples: [PingSample(id: 0, milliseconds: nil)])
        equal(lost.average, nil, "all-lost samples have no fabricated RTT")
        equal(lost.jitter, nil, "one probe cannot establish jitter")
        equal(lost.lossPercent, 100, "all-lost window is 100 percent ICMP loss")
        equal(ConnectionQuality(samples: []).lossPercent, nil, "empty window has no fabricated loss percentage")
        equal(BatteryFlow.classify(watts: 12, onAC: true), .charging, "positive battery current is charging")
        equal(BatteryFlow.classify(watts: -7, onAC: false), .discharging, "negative battery current is discharge")
        equal(BatteryFlow.classify(watts: -4, onAC: true), .discharging, "adapter connection does not hide battery discharge")
        equal(BatteryFlow.classify(watts: 0.1, onAC: true), .adapter, "near-zero battery power on AC uses adapter")
        equal(BatteryFlow.classify(watts: nil, onAC: false), .unknown, "missing battery power is unavailable")
        equal(BatteryReading(fraction: 1, charging: false, onAC: true).statusSymbol, "battery.100.bolt", "full battery still shows adapter connection")
        equal(BatteryReading(fraction: 0.5, charging: false, onAC: false).statusSymbol, "battery.50", "unplugging restores charge-level symbol")
        equal(BatteryReading(fraction: 0.25, charging: true, onAC: true).statusSymbol, "battery.100.bolt", "charging uses native powered symbol")
        var runtime = RuntimeEstimator()
        var estimate = RuntimeReading()
        let day = Date(timeIntervalSince1970: 10 * 86400)
        for t in stride(from: 0.0, through: 120.0, by: 30.0) {
            estimate = runtime.sample(time: t, date: day, currentMA: -1000, remainingMAh: 2000, fullMAh: 4000, voltage: 12, onAC: false, cpu: 0.1, lowPower: false)
        }
        equal(estimate.state, .ready, "two minutes of continuous discharge enables estimate")
        equal(estimate.remainingHours, 2, "mAh divided by discharge mA gives remaining hours")
        equal(estimate.typicalFullHours, nil, "typical estimate needs ten minutes of observations")
        for t in stride(from: 150.0, through: 600.0, by: 30.0) {
            estimate = runtime.sample(time: t, date: day, currentMA: -1000, remainingMAh: 2000, fullMAh: 4000, voltage: 12, onAC: false, cpu: 0.1, lowPower: false)
        }
        equal(abs(estimate.typicalFullHours! - 4) < 0.000001, true, "full-charge estimate uses observed average draw")
        equal(runtime.history.seconds, 600, "observed time excludes the first instantaneous sample")
        var fixedCPU = runtime
        let spike = fixedCPU.sample(time: 630, date: day, currentMA: -3000, remainingMAh: 2000, fullMAh: 4000, voltage: 12, onAC: false, cpu: 0.1, lowPower: false)
        equal(spike.remainingHours! > 1.4 && spike.remainingHours! < 2, true, "one draw spike is smoothed instead of replacing the estimate")
        let changedCPU = runtime.sample(time: 630, date: day, currentMA: -3000, remainingMAh: 2000, fullMAh: 4000, voltage: 12, onAC: false, cpu: 0.8, lowPower: false)
        equal(changedCPU.remainingHours! < spike.remainingHours!, true, "confirmed CPU and draw change adapts faster")
        let oldSeconds = runtime.history.seconds
        estimate = runtime.sample(time: 1000, date: day, currentMA: -1000, remainingMAh: 2000, fullMAh: 4000, voltage: 12, onAC: false, cpu: 0.1, lowPower: false)
        equal(estimate.state, .learning, "sleep-sized gaps rebaseline recent estimate")
        equal(runtime.history.seconds, oldSeconds, "gaps never count as observed battery use")
        estimate = runtime.sample(time: 1030, date: day, currentMA: 1000, remainingMAh: 2000, fullMAh: 4000, voltage: 12, onAC: true, cpu: 0.1, lowPower: false)
        equal(estimate.remainingHours, nil, "AC operation does not present a drain forecast")
        equal(runtime.history.seconds, oldSeconds, "charging never trains the discharge average")
        equal(estimate.typicalFullHours != nil, true, "learned average remains available while plugged in")
        estimate = runtime.sample(time: 1060, date: day, currentMA: nil, remainingMAh: nil, fullMAh: nil, voltage: nil, onAC: false, cpu: 0.1, lowPower: false)
        equal(estimate.state, .unavailable, "missing hardware data does not fabricate a forecast")
        var history = RuntimeHistory()
        history.add(day: 0, seconds: 600, averageMA: 1000)
        history.add(day: 8, seconds: 300, averageMA: 500)
        equal(history.days.count, 1, "history is bounded to seven daily summaries")
        equal(abs(history.averageMA! - 500) < 0.000001, true, "expired observations do not skew typical draw")
        let persisted = try! JSONEncoder().encode(history)
        equal(try! JSONDecoder().decode(RuntimeHistory.self, from: persisted), history, "summary history survives local persistence")
        equal(persisted.count < 1024, true, "typical usage history stays small")
        var learningRuntime = RuntimeEstimator()
        let systemFallback = learningRuntime.sample(time: 0, date: day, currentMA: -1000, remainingMAh: 2000, fullMAh: 4000, voltage: 12, onAC: false, cpu: 0.1, lowPower: false, systemMinutes: 180)
        equal(systemFallback.systemRemainingHours, 3, "system estimate is available during initial learning")
        equal(systemFallback.remainingText.contains("macOS"), true, "fallback estimate identifies its source")
        let pluggedFallback = learningRuntime.sample(time: 30, date: day, currentMA: 1000, remainingMAh: 2000, fullMAh: 4000, voltage: 12, onAC: true, cpu: 0.1, lowPower: false, systemMinutes: 180)
        equal(pluggedFallback.systemRemainingHours, nil, "charging time is never displayed as battery runtime")
        let detailBase = Reading()
        var liveTick = detailBase
        liveTick.download = 2000; liveTick.upload = 500
        liveTick.received = 9000; liveTick.sent = 4000
        liveTick.history = [TrafficPoint(id: 1, download: 2000, upload: 500)]
        equal(liveTick.panelDetails, detailBase.panelDetails, "live traffic ticks do not invalidate cached panel details")
        liveTick.battery = BatteryReading(fraction: 0.5, charging: false, onAC: false)
        equal(liveTick.panelDetails != detailBase.panelDetails, true, "battery changes still update panel details")
        equal(liveTick.download, 2000, "separating detail snapshots preserves raw live rates")
        let publisher = ObservableObjectPublisher()
        let page = PanelRefresh(sources: [publisher])
        publisher.send(); publisher.send()
        equal(page.revision, 0, "hidden cached pages do not publish redraws")
        page.setActive(true)
        equal(page.revision, 1, "activating a dirty page refreshes once")
        publisher.send()
        equal(page.revision, 2, "visible pages still receive live updates")
        page.setActive(false)
        for _ in 0..<10 { publisher.send() }
        equal(page.revision, 2, "hidden updates coalesce without rendering")
        page.setActive(true)
        equal(page.revision, 3, "reopening applies accumulated changes once")
        page.setActive(true)
        equal(page.revision, 3, "unchanged repeated activation does not redraw")
        page.setActive(false); page.setActive(true, refreshClock: true)
        equal(page.revision, 4, "time-based pages refresh on reopen")
        var probes = NetworkProbeSchedule()
        equal(probes.next(at: 0, visible: false, pingBusy: false, connectivityBusy: false),
              .init(ping: true, connectivity: true), "startup probes without waiting for a background interval")
        equal(probes.next(at: 1, visible: false, pingBusy: false, connectivityBusy: false),
              .init(ping: false, connectivity: false), "closed panels retain light background sampling")
        equal(probes.next(at: 1, visible: true, force: true, pingBusy: false, connectivityBusy: false),
              .init(ping: true, connectivity: true), "opening bypasses old background freshness limits")
        equal(probes.next(at: 3, visible: true, pingBusy: false, connectivityBusy: true),
              .init(ping: true, connectivity: false), "slow TLS checks cannot stall visible ping updates")
        equal(probes.next(at: 6, visible: true, pingBusy: true, connectivityBusy: false),
              .init(ping: false, connectivity: true), "ping timeouts cannot stall connectivity checks")
        equal(probes.next(at: 7, visible: true, force: true, pingBusy: true, connectivityBusy: true),
              .init(ping: false, connectivity: false), "reopening never duplicates in-flight probes")
        equal(probes.next(at: 7, visible: true, force: true, pingBusy: false, connectivityBusy: false),
              .init(ping: true, connectivity: true), "fresh probes resume after in-flight work completes")
        equal(probes.next(at: 9, visible: true, pingBusy: false, connectivityBusy: false),
              .init(ping: true, connectivity: false), "visible ping refreshes on the two-second cadence")
        equal(probes.next(at: 12, visible: true, pingBusy: false, connectivityBusy: false),
              .init(ping: true, connectivity: true), "visible connectivity refreshes on the five-second cadence")
        equal(probes.next(at: 13, visible: false, pingBusy: false, connectivityBusy: false),
              .init(ping: false, connectivity: false), "closing immediately restores the background cadence")
        equal(probes.next(at: 42, visible: false, pingBusy: false, connectivityBusy: false),
              .init(ping: true, connectivity: true), "background checks continue after closing")
        probes.reset()
        equal(probes.next(at: 43, visible: false, pingBusy: false, connectivityBusy: false),
              .init(ping: true, connectivity: true), "route changes invalidate old probe deadlines")
        print("PASS: \(checks) traffic, connectivity, power, runtime and panel-cache checks")
    }
}
