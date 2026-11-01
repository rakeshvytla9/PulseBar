import Foundation
import IOKit

enum SystemDetails {
    static func integer(_ name: String) -> Int {
        var value: Int32 = 0; var size = MemoryLayout<Int32>.size
        return sysctlbyname(name, &value, &size, nil, 0) == 0 ? Int(value) : 0
    }
    static func string(_ name: String) -> String {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return "" }
        var bytes = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &bytes, &size, nil, 0) == 0 else { return "" }
        return String(cString: bytes)
    }
    static func memory(host: mach_port_t) -> MemoryDetails {
        var info = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let status = withUnsafeMutablePointer(to: &info) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics64(host, HOST_VM_INFO64, $0, &count) }
        }
        guard status == KERN_SUCCESS else { return MemoryDetails() }
        var page: vm_size_t = 0; host_page_size(host, &page)
        let p = UInt64(page)
        var result = MemoryDetails(active: UInt64(info.active_count) * p, wired: UInt64(info.wire_count) * p,
                                   compressed: UInt64(info.compressor_page_count) * p,
                                   inactive: UInt64(info.inactive_count) * p,
                                   free: UInt64(info.free_count) * p, purgeable: UInt64(info.purgeable_count) * p)
        var swap = xsw_usage(); var size = MemoryLayout<xsw_usage>.size
        if sysctlbyname("vm.swapusage", &swap, &size, nil, 0) == 0 { result.swapUsed = swap.xsu_used; result.swapTotal = swap.xsu_total }
        switch integer("kern.memorystatus_vm_pressure_level") {
        case 2: result.pressure = "Warning"
        case 4: result.pressure = "Critical"
        default: result.pressure = "Normal"
        }
        return result
    }
    static func power() -> PowerDetails {
        var result = PowerDetails()
        result.lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return result }
        defer { IOObjectRelease(service) }
        var properties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dict = properties?.takeRetainedValue() as? [String: Any] else { return result }
        func number(_ key: String) -> Double? { (dict[key] as? NSNumber)?.doubleValue }
        result.cycles = number("CycleCount").map(Int.init)
        result.remainingCapacityMAh = number("AppleRawCurrentCapacity")
        result.fullCapacityMAh = number("AppleRawMaxCapacity") ?? number("NominalChargeCapacity")
        if let maximum = number("NominalChargeCapacity") ?? number("AppleRawMaxCapacity"),
           let design = number("DesignCapacity"), design > 0 { result.healthPercent = min(100, Int(maximum / design * 100)) }
        if let raw = number("Temperature") { result.temperature = raw / 10 - 273.15 }
        if let voltage = number("Voltage") {
            result.voltage = voltage / 1000
            if let value = dict["Amperage"] as? NSNumber {
                // Some battery firmware exposes a negative 16-bit current as
                // an unsigned registry integer. Normalize it before watts.
                let current = Double(Int16(truncatingIfNeeded: value.int64Value))
                result.currentMA = current
                result.watts = voltage * current / 1_000_000
            }
        }
        if let minutes = number("TimeRemaining"), minutes > 0, minutes < 65535 { result.minutesRemaining = Int(minutes) }
        return result
    }
}

final class CoreReader {
    private var previous: [UInt32] = []
    func sample(host: mach_port_t) -> [Double] {
        var cores: natural_t = 0, info: processor_info_array_t?
        var count: mach_msg_type_number_t = 0
        guard host_processor_info(host, PROCESSOR_CPU_LOAD_INFO, &cores, &info, &count) == KERN_SUCCESS, let info else { return [] }
        defer { vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: info)), vm_size_t(count) * vm_size_t(MemoryLayout<integer_t>.size)) }
        let ticks = (0..<Int(count)).map { UInt32(bitPattern: info[$0]) }
        defer { previous = ticks }
        guard previous.count == ticks.count else { return Array(repeating: 0, count: Int(cores)) }
        return (0..<Int(cores)).map { core in
            let i = core * 4
            let deltas = (0..<4).map { Double(ticks[i + $0] &- previous[i + $0]) }
            let total = deltas.reduce(0, +)
            return total > 0 ? max(0, min(1, (total - deltas[2]) / total)) : 0
        }
    }
}
