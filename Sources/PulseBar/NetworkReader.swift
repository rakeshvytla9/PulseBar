import Foundation
import SystemConfiguration
import Darwin

struct NetworkInterface: Identifiable {
    let id: String
    let label: String
}

enum NetworkReader {
    static func interfaces() -> [NetworkInterface] {
        (SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] ?? []).compactMap { item in
            guard let name = SCNetworkInterfaceGetBSDName(item) as String? else { return nil }
            let display = SCNetworkInterfaceGetLocalizedDisplayName(item) as String? ?? name
            return NetworkInterface(id: name, label: "\(display) · \(name)")
        }.sorted { $0.id < $1.id }
    }

    static func primaryInterface() -> String? {
        for family in ["IPv4", "IPv6"] {
            if let state = SCDynamicStoreCopyValue(nil, "State:/Network/Global/\(family)" as CFString) as? [String: Any],
               let name = state["PrimaryInterface"] as? String, !virtual(name) { return name }
        }
        // With a VPN, monitor its underlying physical route to avoid counting
        // the same traffic twice or losing the physical interface entirely.
        for family in ["IPv4", "IPv6"] {
            if let setup = SCDynamicStoreCopyValue(nil, "Setup:/Network/Global/\(family)" as CFString) as? [String: Any],
               let order = setup["ServiceOrder"] as? [String] {
                for service in order {
                    guard let state = SCDynamicStoreCopyValue(nil, "State:/Network/Service/\(service)/\(family)" as CFString) as? [String: Any],
                          state["Router"] != nil, let name = state["InterfaceName"] as? String, !virtual(name) else { continue }
                    return name
                }
            }
        }
        return nil
    }

    private static func virtual(_ name: String) -> Bool {
        ["utun", "ipsec", "ppp", "tun", "tap", "gif", "stf", "wg", "lo", "awdl", "llw"].contains { name.hasPrefix($0) }
    }

    // Adapted from getBytesInfo() in exelban/Stats, MIT license.
    // Copyright (c) 2019 Serhiy Mytrovtsiy. See THIRD-PARTY-NOTICES.md.
    // 64-bit NET_RT_IFLIST2 counters avoid the 4 GB rollover of if_data.
    static func counter(interface: String) -> TrafficCounter? {
        let index = if_nametoindex(interface)
        guard index != 0 else { return nil }
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, Int32(index)]
        var size: size_t = 0
        guard sysctl(&mib, u_int(mib.count), nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, u_int(mib.count), &buffer, &size, nil, 0) == 0 else { return nil }
        var offset = 0
        while offset + MemoryLayout<if_msghdr>.size <= size {
            let header = buffer.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: if_msghdr.self) }
            let length = Int(header.ifm_msglen)
            guard length >= 4, offset + length <= size else { return nil }
            if Int32(header.ifm_type) == RTM_IFINFO2, length >= MemoryLayout<if_msghdr2>.size {
                let full = buffer.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self) }
                if UInt32(full.ifm_index) == index {
                    guard full.ifm_flags & IFF_UP != 0, full.ifm_flags & IFF_RUNNING != 0 else { return nil }
                    return TrafficCounter(received: full.ifm_data.ifi_ibytes, sent: full.ifm_data.ifi_obytes)
                }
            }
            offset += length
        }
        return nil
    }
}
