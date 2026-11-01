import SwiftUI
import AppKit

struct Palette {
    let background: String, surface: String, foreground: String, muted: String
    let accent: String, green: String, purple: String, yellow: String
    var native = false
    var corner: CGFloat { native ? 14 : 2 }
    var bg: Color { native ? .clear : Color(hex: background) }
    var card: Color { native ? Color.primary.opacity(0.07) : Color(hex: surface) }
    var text: Color { native ? .primary : Color(hex: foreground) }
    var secondary: Color { native ? .secondary : Color(hex: muted) }
    var blue: Color { Color(hex: accent) }
    var down: Color { Color(hex: green) }
    var up: Color { Color(hex: purple) }
}

enum BarTheme: String, CaseIterable, Identifiable {
    case system = "macOS Glass", tokyo = "Tokyo Night", gruvbox = "Gruvbox", everforest = "Everforest", catppuccin = "Catppuccin"
    var id: String { rawValue }
    var palette: Palette {
        switch self {
        case .system: return Palette(background: "202024", surface: "303034", foreground: "F5F5F7", muted: "A0A0AA", accent: "0A84FF", green: "30A46C", purple: "0A84FF", yellow: "FF9F0A", native: true)
        case .tokyo: return Palette(background: "1a1b26", surface: "24283b", foreground: "c0caf5", muted: "9aa5ce", accent: "7aa2f7", green: "9ece6a", purple: "bb9af7", yellow: "e0af68")
        case .gruvbox: return Palette(background: "282828", surface: "3c3836", foreground: "d4be98", muted: "bdae93", accent: "7daea3", green: "a9b665", purple: "d3869b", yellow: "d8a657")
        case .everforest: return Palette(background: "2d353b", surface: "343f44", foreground: "d3c6aa", muted: "9da9a0", accent: "7fbbb3", green: "a7c080", purple: "d699b6", yellow: "dbbc7f")
        case .catppuccin: return Palette(background: "1e1e2e", surface: "313244", foreground: "cdd6f4", muted: "bac2de", accent: "89b4fa", green: "a6e3a1", purple: "f5c2e7", yellow: "f9e2af")
        }
    }
}

extension Color {
    init(hex: String) {
        let n = UInt64(hex, radix: 16) ?? 0
        self.init(red: Double((n >> 16) & 255) / 255, green: Double((n >> 8) & 255) / 255, blue: Double(n & 255) / 255)
    }
}

@MainActor final class Preferences: ObservableObject {
    private let defaults: UserDefaults
    @Published var theme: BarTheme { didSet { save() } }
    @Published var unit: RateUnit { didSet { save() } }
    @Published var interface: String { didSet { save() } }
    @Published var inline: Bool { didSet { save() } }
    @Published var showCPU: Bool { didSet { save() } }
    @Published var showMemory: Bool { didSet { save() } }
    @Published var showBattery: Bool { didSet { save() } }
    @Published var colorArrows: Bool { didSet { save() } }
    @Published var hotKeys: Bool { didSet { save() } }
    @Published var barModules: [String] { didSet { save() } }
    @Published var hiddenPanels: [String] { didSet { save() } }
    var onChange: (() -> Void)?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        theme = defaults.bool(forKey: "appearanceV3") ? BarTheme(rawValue: defaults.string(forKey: "theme") ?? "") ?? .system : .system
        unit = RateUnit(rawValue: defaults.string(forKey: "unit") ?? "") ?? .bytes
        interface = defaults.string(forKey: "interface") ?? "auto"
        inline = defaults.bool(forKey: "inline")
        showCPU = defaults.bool(forKey: "showCPU")
        showMemory = defaults.bool(forKey: "showMemory")
        showBattery = defaults.bool(forKey: "showBattery")
        colorArrows = defaults.object(forKey: "colorArrows") as? Bool ?? false
        hotKeys = defaults.bool(forKey: "hotKeys")
        let savedModules = (defaults.stringArray(forKey: "barModulesV3") ?? ["center", "traffic", "wifi", "battery"]).filter { BarModule(rawValue: $0) != nil }
        barModules = savedModules.isEmpty ? ["center"] : savedModules
        hiddenPanels = defaults.stringArray(forKey: "hiddenPanelsV3") ?? ["media", "world", "weather"]
        defaults.set(true, forKey: "appearanceV3")
        defaults.set(theme.rawValue, forKey: "theme")
    }

    func shows(_ module: BarModule) -> Bool { barModules.contains(module.rawValue) }
    var homeSections: [PanelSection] {
        [PanelSection.wifi, .power, .system, .network, .media, .world, .weather].filter(showsPanel)
    }
    func setModule(_ module: BarModule, enabled: Bool) {
        var values = Set(barModules)
        if enabled { values.insert(module.rawValue) } else { values.remove(module.rawValue) }
        if values.isEmpty { values.insert(BarModule.center.rawValue) }
        barModules = BarModule.allCases.map(\.rawValue).filter(values.contains)
    }
    func showsPanel(_ section: PanelSection) -> Bool { !hiddenPanels.contains(section.rawValue) }
    func setPanel(_ section: PanelSection, enabled: Bool) {
        var hidden = Set(hiddenPanels)
        if enabled { hidden.remove(section.rawValue) } else { hidden.insert(section.rawValue) }
        hiddenPanels = hidden.sorted()
    }

    private func save() {
        defaults.set(theme.rawValue, forKey: "theme")
        defaults.set(unit.rawValue, forKey: "unit")
        defaults.set(interface, forKey: "interface")
        defaults.set(inline, forKey: "inline")
        defaults.set(showCPU, forKey: "showCPU")
        defaults.set(showMemory, forKey: "showMemory")
        defaults.set(showBattery, forKey: "showBattery")
        defaults.set(colorArrows, forKey: "colorArrows")
        defaults.set(hotKeys, forKey: "hotKeys")
        defaults.set(barModules, forKey: "barModulesV3")
        defaults.set(hiddenPanels, forKey: "hiddenPanelsV3")
        onChange?()
    }
}
