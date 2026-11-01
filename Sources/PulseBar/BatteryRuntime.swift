import Foundation
import Combine

@MainActor final class BatteryRuntime: ObservableObject {
    @Published private(set) var reading = RuntimeReading()
    private var estimator: RuntimeEstimator
    private var dirty = false
    private var lastSave: Double = -1000
    init() {
        let data = UserDefaults.standard.data(forKey: "batteryRuntimeHistoryV1")
        let history = data.flatMap { try? JSONDecoder().decode(RuntimeHistory.self, from: $0) } ?? RuntimeHistory()
        estimator = RuntimeEstimator(history: history)
    }
    func sample(power: PowerDetails, battery: BatteryReading?, cpu: Double, time: Double) {
        let old = estimator.history
        let result = estimator.sample(time: time, date: Date(), currentMA: power.currentMA,
                                      remainingMAh: power.remainingCapacityMAh, fullMAh: power.fullCapacityMAh,
                                      voltage: power.voltage, onAC: battery?.onAC ?? true, cpu: cpu, lowPower: power.lowPower, systemMinutes: power.minutesRemaining)
        if result != reading { reading = result }
        dirty = dirty || old != estimator.history
        if time - lastSave >= 300 { flush(); lastSave = time }
    }
    func suspend() { estimator.breakContinuity(); flush() }
    func flush() {
        guard dirty, let data = try? JSONEncoder().encode(estimator.history) else { return }
        UserDefaults.standard.set(data, forKey: "batteryRuntimeHistoryV1"); dirty = false
    }
}
