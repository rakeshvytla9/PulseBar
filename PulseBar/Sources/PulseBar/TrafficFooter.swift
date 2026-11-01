import SwiftUI

@MainActor final class FooterStats: ObservableObject {
    @Published var text = "↓ 0 B/s   ↑ 0 B/s"
    func update(_ reading: Reading, unit: RateUnit) {
        let value = reading.interface.isEmpty ? "Offline" : "↓ \(unit.string(reading.download))   ↑ \(unit.string(reading.upload))"
        if value != text { text = value }
    }
}

/// Network ticks redraw this small label instead of every control in the panel.
@MainActor struct TrafficFooter: View {
    @ObservedObject var stats: FooterStats
    @ObservedObject var health: NetworkHealth
    var copied: String?
    var openQuality: () -> Void
    var body: some View {
        HStack(spacing: 7) {
            Text(copied ?? stats.text)
            if copied == nil && health.enabled {
                Button(action: openQuality) {
                    Text("Ping " + (health.warning ? "Offline" : health.ping.map { String(format: "%.0f ms", $0) } ?? "—"))
                        .foregroundStyle(health.warning ? Color.orange : Color.accentColor)
                        .padding(.horizontal, 5).padding(.vertical, 3)
                        .background((health.warning ? Color.orange : Color.accentColor).opacity(0.12), in: RoundedRectangle(cornerRadius: 5))
                }.buttonStyle(.plain).help("\(health.state.rawValue) · Ping \(health.target): \(health.pingText). Open connection quality, jitter, loss and outage details.")
            }
        }.font(AppFonts.ui(9)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
    }
}
