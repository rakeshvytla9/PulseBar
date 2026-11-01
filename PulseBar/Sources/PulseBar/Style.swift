import AppKit
import SwiftUI
import CoreText

enum PanelLayout {
    static let width: CGFloat = 408
    static func height(for section: PanelSection) -> CGFloat {
        switch section {
        case .home: return 430
        case .wifi: return 540
        case .weather: return 480
        case .audio: return 470
        case .display, .media: return 360
        case .power: return 560
        case .quality: return 440
        case .calendar: return 500
        case .world: return 450
        default: return 580
        }
    }
    static let trafficWidth: CGFloat = 64
}

enum AppFonts {
    static var regular = "JetBrainsMonoNF-Regular"
    static var bold = "JetBrainsMonoNF-Bold"
    static func register() {
        for (file, isBold) in [("JetBrainsMonoNerdFont-Regular", false), ("JetBrainsMonoNerdFont-Bold", true)] {
            guard let url = Bundle.main.resourceURL?.appendingPathComponent("Fonts/\(file).ttf"),
                  FileManager.default.fileExists(atPath: url.path) else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            if let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
               let descriptor = descriptors.first,
               let name = CTFontDescriptorCopyAttribute(descriptor, kCTFontNameAttribute) as? String {
                if isBold { bold = name } else { regular = name }
            }
        }
    }
    static func ui(_ size: CGFloat = 12, bold: Bool = false) -> Font { .custom(bold ? self.bold : regular, size: size) }
    static func native(_ size: CGFloat = 9) -> NSFont { NSFont(name: regular, size: size) ?? .monospacedSystemFont(ofSize: size, weight: .regular) }
}

@MainActor private enum GlyphShapes {
    static var cache: [String: CGPath] = [:]
    static func path(_ text: String) -> CGPath? {
        if let cached = cache[text] { return cached }
        let font = CTFontCreateWithName(AppFonts.regular as CFString, 64, nil)
        var characters = Array(text.utf16)
        var glyphs = [CGGlyph](repeating: 0, count: characters.count)
        guard !characters.isEmpty, CTFontGetGlyphsForCharacters(font, &characters, &glyphs, characters.count),
              let path = CTFontCreatePathForGlyph(font, glyphs[0], nil) else { return nil }
        cache[text] = path
        return path
    }
}

/// Fits the actual glyph bounds, like Omarchy's BarIconContent, rather than
/// clipping wide Nerd Font symbols to a text character's advance width.
@MainActor struct GlyphIcon: View {
    let text: String
    var size: CGFloat = 22
    var color: Color = .primary
    var body: some View {
        let shape = GlyphShapes.path(text)
        return Canvas { context, canvas in
            guard let shape else { return }
            let bounds = shape.boundingBoxOfPath
            guard bounds.width > 0, bounds.height > 0 else { return }
            let scale = min(canvas.width / bounds.width, canvas.height / bounds.height)
            let transform = CGAffineTransform(a: scale, b: 0, c: 0, d: -scale,
                                             tx: (canvas.width - bounds.width * scale) / 2 - bounds.minX * scale,
                                             ty: (canvas.height + bounds.height * scale) / 2 + bounds.minY * scale)
            context.fill(Path(shape).applying(transform), with: .color(color))
        }.frame(width: size, height: size).accessibilityHidden(true)
    }
}

enum PanelSection: String, CaseIterable, Identifiable {
    case home, wifi, network, quality, audio, display, power, system, media, calendar, world, weather, settings
    var id: String { rawValue }
    var title: String {
        switch self {
        case .home: return "Control Center"
        case .wifi: return "Wi-Fi"
        case .network: return "Traffic"
        case .quality: return "Connection Quality"
        case .audio: return "Audio"
        case .display: return "Display"
        case .power: return "Power"
        case .system: return "System"
        case .media: return "Media"
        case .calendar: return "Calendar"
        case .world: return "World clocks"
        case .weather: return "Weather"
        case .settings: return "Customize"
        }
    }
    // Nerd Font glyphs, as used by Omarchy's own shell panels.
    var glyph: String {
        switch self {
        case .home: return "\u{f1de}"
        case .wifi: return "\u{f1eb}"
        case .network: return "\u{f0ec}"
        case .quality: return "\u{f0ec}"
        case .audio: return "\u{f028}"
        case .display: return "\u{f108}"
        case .power: return "\u{f240}"
        case .system: return "\u{f4bc}"
        case .media: return "\u{f001}"
        case .calendar: return "\u{f073}"
        case .world: return "\u{f0ac}"
        case .weather: return "\u{e30d}"
        case .settings: return "\u{f013}"
        }
    }
}

enum BarModule: String, CaseIterable, Identifiable {
    case center, traffic, wifi, battery, audio, display, cpu, memory
    var id: String { rawValue }
    var title: String {
        switch self {
        case .center: return "Control Center"
        case .traffic: return "Upload / download"
        case .wifi: return "Wi-Fi"
        case .battery: return "Battery"
        case .audio: return "Volume"
        case .display: return "Display"
        case .cpu: return "CPU"
        case .memory: return "Memory"
        }
    }
    var section: PanelSection {
        switch self {
        case .center: return .home
        case .traffic: return .network
        case .wifi: return .wifi
        case .battery: return .power
        case .audio: return .audio
        case .display: return .display
        case .cpu, .memory: return .system
        }
    }
}

struct GlassBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

struct NativeActionButton: NSViewRepresentable {
    let title: String
    var action: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(action) }
    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(title: title, target: context.coordinator, action: #selector(Coordinator.run))
        button.bezelStyle = .recessed
        button.font = AppFonts.native(11)
        if title == "Quit" { button.keyEquivalent = "q"; button.keyEquivalentModifierMask = .command }
        if title == "Customize" { button.keyEquivalent = ","; button.keyEquivalentModifierMask = .command }
        button.setAccessibilityIdentifier("pulsebar-\(title.lowercased())")
        return button
    }
    func updateNSView(_ button: NSButton, context: Context) { button.title = title; context.coordinator.action = action }
    final class Coordinator: NSObject {
        var action: () -> Void
        init(_ action: @escaping () -> Void) { self.action = action }
        @objc func run() { action() }
    }
}

struct FlatButtonStyle: ButtonStyle {
    let color: Color
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.contentShape(Rectangle()).opacity(configuration.isPressed ? 0.65 : 1)
    }
}

struct SectionBlock<Content: View>: View {
    let title: String
    let palette: Palette
    var info: String? = nil
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title.uppercased()).font(AppFonts.ui(10, bold: true)).tracking(1.2).foregroundStyle(palette.secondary)
                if let info { Spacer(minLength: 4); InfoButton(title: title, text: info).foregroundStyle(palette.secondary) }
            }
            content
        }.padding(11).frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.card.opacity(palette.native ? 1 : 0.6), in: RoundedRectangle(cornerRadius: palette.corner))
            .overlay(RoundedRectangle(cornerRadius: palette.corner).stroke(palette.text.opacity(palette.native ? 0.06 : 0.12), lineWidth: 1))
    }
}

private struct InfoButton: View {
    let title: String
    let text: String
    @State private var showing = false
    var body: some View {
        Button { showing.toggle() } label: {
            Image(systemName: "info.circle").font(.system(size: 12)).frame(width: 18, height: 18).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel("About " + title).help("About " + title)
            .popover(isPresented: $showing) {
                Text(text).font(AppFonts.ui(11)).textSelection(.enabled)
                    .frame(width: 290, alignment: .leading).fixedSize(horizontal: false, vertical: true).padding(14)
            }
    }
}

func openSettings(_ pane: String) {
    if let url = URL(string: "x-apple.systempreferences:\(pane)") { NSWorkspace.shared.open(url) }
}
