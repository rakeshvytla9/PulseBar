import Foundation
import Combine

struct ReportedBatteryHealth {
    let maximumCapacity: Int
    let condition: String
}

enum BatteryReportReader {
    /// Query the same system report used by System Information, only on demand.
    static func read() -> ReportedBatteryHealth? {
        let process = Process(); let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["SPPowerDataType", "-json"]
        process.standardOutput = output; process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let timeout = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 5, execute: timeout)
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit(); timeout.cancel()
        guard process.terminationStatus == 0, let root = try? JSONSerialization.jsonObject(with: data) else { return nil }
        func find(_ object: Any) -> ReportedBatteryHealth? {
            if let dict = object as? [String: Any] {
                if let text = dict["sppower_battery_health_maximum_capacity"] as? String,
                   let percent = Int(text.filter { $0.isNumber }), (0...100).contains(percent) {
                    return ReportedBatteryHealth(maximumCapacity: percent, condition: dict["sppower_battery_health"] as? String ?? "—")
                }
                for value in dict.values { if let result = find(value) { return result } }
            } else if let list = object as? [Any] {
                for value in list { if let result = find(value) { return result } }
            }
            return nil
        }
        return find(root)
    }
}

@MainActor final class BatteryHealthReport: ObservableObject {
    @Published private(set) var reading: ReportedBatteryHealth?
    private var loadedAt: Date?
    private var inFlight = false
    private var lastAttempt: Date?
    init() {
        let defaults = UserDefaults.standard
        if let date = defaults.object(forKey: "batteryReportDate") as? Date,
           Date().timeIntervalSince(date) < 3600, let value = defaults.object(forKey: "batteryReportCapacity") as? Int {
            reading = ReportedBatteryHealth(maximumCapacity: value, condition: defaults.string(forKey: "batteryReportCondition") ?? "—")
            loadedAt = date
        }
    }
    func load() {
        let now = Date()
        guard !inFlight,
              loadedAt.map({ now.timeIntervalSince($0) >= 3600 }) ?? true,
              lastAttempt.map({ now.timeIntervalSince($0) >= 60 }) ?? true else { return }
        inFlight = true; lastAttempt = now
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let report = BatteryReportReader.read()
            Task { @MainActor in
                guard let self else { return }
                self.inFlight = false
                guard let report else { return }
                self.reading = report
                self.loadedAt = Date()
                let defaults = UserDefaults.standard
                defaults.set(report.maximumCapacity, forKey: "batteryReportCapacity")
                defaults.set(report.condition, forKey: "batteryReportCondition")
                defaults.set(Date(), forKey: "batteryReportDate")
            }
        }
    }
}
