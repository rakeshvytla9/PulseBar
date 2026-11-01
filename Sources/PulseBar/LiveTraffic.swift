import SwiftUI

@MainActor final class LiveTraffic: ObservableObject {
    @Published private(set) var reading = Reading()
    func update(_ value: Reading) { reading = value }
}

/// One-second updates stay in the cards/graph instead of rebuilding the panel.
@MainActor struct LiveTrafficView: View {
    @ObservedObject var stats: LiveTraffic
    @ObservedObject var preferences: Preferences
    @ObservedObject var health: NetworkHealth
    var copy: (String) -> Void
    var openQuality: () -> Void
    var reset: () -> Void
    private var palette: Palette { preferences.theme.palette }
    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 8) {
                speed("DOWNLOAD", arrow: "↓", rate: stats.reading.download, color: palette.down)
                speed("UPLOAD", arrow: "↑", rate: stats.reading.upload, color: palette.up)
                Button(action: openQuality) {
                    card("⌁ PING", value: !health.enabled ? "Off" : health.warning ? "Offline" : health.ping.map { String(format: "%.0f", $0) } ?? "—", unit: health.enabled && !health.warning && health.ping != nil ? "ms" : "", color: health.warning ? .orange : palette.blue)
                }.buttonStyle(.plain).help("Open Connection Quality: jitter, packet loss and outage details")
            }
            SectionBlock(title: "Traffic · last 60 seconds", palette: palette) {
                TrafficGraph(points: stats.reading.history, down: palette.down, up: palette.up, grid: palette.secondary).frame(height: 75)
                HStack { Text("60s ago"); Spacer(); Text("now") }.font(AppFonts.ui(9)).foregroundStyle(palette.secondary)
                total("Downloaded", value: byteTotal(stats.reading.received), color: palette.down)
                total("Uploaded", value: byteTotal(stats.reading.sent), color: palette.up)
                Button(action: reset) {
                    HStack { Text("Reset session totals"); Spacer(); Text("→") }.font(AppFonts.ui(11)).padding(10)
                        .frame(maxWidth: .infinity).background(palette.text.opacity(0.05), in: RoundedRectangle(cornerRadius: palette.corner))
                }.buttonStyle(FlatButtonStyle(color: palette.blue))
            }
        }
    }
    private func speed(_ label: String, arrow: String, rate: Double, color: Color) -> some View {
        let parts = preferences.unit.parts(rate)
        return Button { copy("\(label): \(preferences.unit.string(rate))") } label: {
            card("\(arrow) \(label)", value: parts.value, unit: parts.unit, color: color)
        }.buttonStyle(.plain).help("Click to copy")
    }
    private func card(_ label: String, value: String, unit: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(AppFonts.ui(8, bold: true)).tracking(0.5).foregroundStyle(color).lineLimit(1)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).font(AppFonts.ui(20, bold: true)).lineLimit(1).minimumScaleFactor(0.55)
                if !unit.isEmpty { Text(unit).font(AppFonts.ui(8)).foregroundStyle(palette.secondary).lineLimit(1) }
            }
        }.padding(10).frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
            .background(palette.native ? palette.card : color.opacity(0.06), in: RoundedRectangle(cornerRadius: palette.corner))
            .overlay(RoundedRectangle(cornerRadius: palette.corner).stroke(palette.text.opacity(palette.native ? 0.05 : 0.2), lineWidth: 1)).contentShape(Rectangle())
    }
    private func total(_ label: String, value: String, color: Color) -> some View {
        HStack {
            Text(label).foregroundStyle(palette.secondary); Spacer()
            Button { copy(value) } label: { Text(value).foregroundStyle(color) }.buttonStyle(.plain).help("Copy \(label)")
        }.font(AppFonts.ui(11))
    }
}
