import Foundation

struct DischargeDay: Codable, Equatable {
    var day: Int
    var seconds: Double = 0
    var milliampHours: Double = 0
}
struct RuntimeHistory: Codable, Equatable {
    var days: [DischargeDay] = []
    var fullCapacityMAh: Double?
    var seconds: Double { days.reduce(0) { $0 + $1.seconds } }
    var averageMA: Double? {
        let charge = days.reduce(0) { $0 + $1.milliampHours }
        return seconds > 0 ? charge * 3600 / seconds : nil
    }
    mutating func prune(day: Int) {
        days = days.filter { $0.day >= day - 6 && $0.day <= day && $0.seconds.isFinite && $0.seconds > 0 && $0.milliampHours.isFinite && $0.milliampHours >= 0 }.sorted { $0.day < $1.day }
    }
    mutating func add(day: Int, seconds: Double, averageMA: Double) {
        prune(day: day)
        if let index = days.firstIndex(where: { $0.day == day }) {
            days[index].seconds += seconds; days[index].milliampHours += averageMA * seconds / 3600
        } else { days.append(DischargeDay(day: day, seconds: seconds, milliampHours: averageMA * seconds / 3600)) }
    }
}
enum RuntimeState: Equatable { case learning, ready, adapter, unavailable }
struct RuntimeReading: Equatable {
    var state: RuntimeState = .learning
    var remainingHours: Double?
    var systemRemainingHours: Double?
    var typicalFullHours: Double?
    var watts: Double?
    var cpu: Double?
    var recentSeconds: Double = 0
    var learnedSeconds: Double = 0
    var remainingText: String {
        if let remainingHours { return runtimeLabel(remainingHours) }
        if let systemRemainingHours { return runtimeLabel(systemRemainingHours) + " · macOS" }
        switch state {
        case .adapter: return "On power adapter"
        case .learning: return "Learning · 2 min needed"
        case .unavailable: return "Unavailable"
        case .ready: return "—"
        }
    }
    var typicalText: String { typicalFullHours.map(runtimeLabel) ?? "Learning · 10 min of battery use" }
    var cpuText: String {
        guard let cpu else { return "—" }
        let label = cpu < 0.15 ? "Light" : cpu < 0.4 ? "Moderate" : "Heavy"
        return "\(label) · \(Int((cpu * 100).rounded()))%"
    }
}
func runtimeLabel(_ hours: Double) -> String {
    guard hours.isFinite, hours >= 0 else { return "—" }
    if hours > 48 { return "Over 48h" }
    let minutes = Int((hours * 60 / 5).rounded()) * 5
    if minutes < 5 { return "Under 5 min" }
    return minutes < 60 ? "About \(minutes) min" : "About \(minutes / 60)h \(minutes % 60)m"
}

/// Time-weighted discharge measurements, never a guessed watts-per-CPU formula.
struct RuntimeEstimator {
    private(set) var history: RuntimeHistory
    private var previous: (time: Double, current: Double, lowPower: Bool)?
    private var smoothedMA: Double?
    private var smoothedWatts: Double?
    private var smoothedCPU: Double?
    private var observed: Double = 0
    init(history: RuntimeHistory = RuntimeHistory()) { self.history = history }
    mutating func breakContinuity() {
        previous = nil; smoothedMA = nil; smoothedWatts = nil; smoothedCPU = nil; observed = 0
    }
    mutating func sample(time: Double, date: Date, currentMA: Double?, remainingMAh: Double?, fullMAh: Double?, voltage: Double?, onAC: Bool, cpu: Double, lowPower: Bool, systemMinutes: Int? = nil) -> RuntimeReading {
        let day = Int(floor(date.timeIntervalSince1970 / 86400))
        history.prune(day: day)
        if let fullMAh, fullMAh.isFinite, fullMAh > 0 { history.fullCapacityMAh = fullMAh }
        var reading = RuntimeReading()
        reading.learnedSeconds = history.seconds
        if history.seconds >= 600, let capacity = history.fullCapacityMAh, let average = history.averageMA, average > 20 {
            reading.typicalFullHours = capacity / average
        }
        guard !onAC else { breakContinuity(); reading.state = .adapter; return reading }
        if let systemMinutes, systemMinutes > 0, systemMinutes < 65535 { reading.systemRemainingHours = Double(systemMinutes) / 60 }
        guard let currentMA, currentMA.isFinite, currentMA < -20,
              let remainingMAh, remainingMAh.isFinite, remainingMAh >= 0,
              let fullMAh, fullMAh.isFinite, fullMAh > 0, remainingMAh <= fullMAh * 1.1,
              let voltage, voltage.isFinite, voltage > 0 else {
            breakContinuity(); reading.state = .unavailable; return reading
        }
        let draw = -currentMA
        let watts = draw * voltage / 1000
        let load = cpu.isFinite ? min(1, max(0, cpu)) : 0
        if let old = previous, time > old.time, time - old.time <= 75, old.lowPower == lowPower {
            let dt = time - old.time
            let previousMA = smoothedMA ?? draw
            // React faster only when CPU and measured draw both change strongly.
            let workloadChanged = abs(load - (smoothedCPU ?? load)) > 0.15 && abs(draw / max(1, previousMA) - 1) > 0.25
            let alpha = 1 - exp(-dt / (workloadChanged ? 60 : 180))
            smoothedMA = previousMA + alpha * (draw - previousMA)
            smoothedWatts = (smoothedWatts ?? watts) + alpha * (watts - (smoothedWatts ?? watts))
            let cpuAlpha = 1 - exp(-dt / 180)
            smoothedCPU = (smoothedCPU ?? load) + cpuAlpha * (load - (smoothedCPU ?? load))
            observed += dt
            history.add(day: day, seconds: dt, averageMA: (old.current + draw) / 2)
        } else {
            breakContinuity(); smoothedMA = draw; smoothedWatts = watts; smoothedCPU = load
        }
        previous = (time, draw, lowPower)
        reading.state = observed >= 120 ? .ready : .learning
        reading.recentSeconds = observed; reading.learnedSeconds = history.seconds
        reading.watts = smoothedWatts; reading.cpu = smoothedCPU
        if observed >= 120, let smoothedMA, smoothedMA > 20 { reading.remainingHours = min(remainingMAh, fullMAh) / smoothedMA }
        if history.seconds >= 600, let capacity = history.fullCapacityMAh, let average = history.averageMA, average > 20 {
            reading.typicalFullHours = capacity / average
        }
        return reading
    }
}
