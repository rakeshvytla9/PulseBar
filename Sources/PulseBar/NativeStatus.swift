import AppKit
@preconcurrency import CoreWLAN

@MainActor enum RadioState {
    static func wifi() -> Bool { CWWiFiClient.shared().interface()?.powerOn() ?? false }
}

@MainActor enum StatusImages {
    private static var symbols: [String: NSImage] = [:]
    static func symbol(_ name: String) -> NSImage? {
        if let image = symbols[name] { return image }
        guard let source = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return nil }
        let configured = source.withSymbolConfiguration(.init(pointSize: 13, weight: .regular)) ?? source
        configured.isTemplate = true
        let image = raster(configured); symbols[name] = image
        return image
    }
    static func raster(_ source: NSImage) -> NSImage {
        let size = source.size
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(ceil(size.width * 2)), pixelsHigh: Int(ceil(size.height * 2)), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return source }
        bitmap.size = size
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
        context.cgContext.scaleBy(x: 2, y: 2)
        source.draw(in: NSRect(origin: .zero, size: size))
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: size); image.addRepresentation(bitmap); image.isTemplate = source.isTemplate
        return image
    }
    static func traffic(_ down: String, _ up: String, preferences: Preferences) -> NSImage {
        let width = preferences.inline ? 138.0 : PanelLayout.trafficWidth
        let source = NSImage(size: NSSize(width: width, height: 22), flipped: false) { _ in
            let font = AppFonts.native(9)
            let normal: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.labelColor]
            let alignment = NSMutableParagraphStyle(); alignment.alignment = .right
            var rate = normal; rate[.paragraphStyle] = alignment
            let downColor = preferences.colorArrows ? NSColor(preferences.theme.palette.down) : NSColor.labelColor
            let upColor = preferences.colorArrows ? NSColor(preferences.theme.palette.up) : NSColor.labelColor
            if preferences.inline {
                ("↓ " + down as NSString).draw(at: NSPoint(x: 2, y: 5), withAttributes: [.font: font, .foregroundColor: downColor])
                ("↑ " + up as NSString).draw(at: NSPoint(x: 71, y: 5), withAttributes: [.font: font, .foregroundColor: upColor])
            } else {
                ("↓" as NSString).draw(at: NSPoint(x: 1, y: 11), withAttributes: [.font: font, .foregroundColor: downColor])
                ("↑" as NSString).draw(at: NSPoint(x: 1, y: 1), withAttributes: [.font: font, .foregroundColor: upColor])
                (down as NSString).draw(in: NSRect(x: 9, y: 11, width: 50, height: 11), withAttributes: rate)
                (up as NSString).draw(in: NSRect(x: 9, y: 1, width: 50, height: 11), withAttributes: rate)
            }
            return true
        }
        source.isTemplate = !preferences.colorArrows
        return raster(source)
    }
    static func text(_ text: String, symbol: String? = nil) -> NSImage {
        let width: CGFloat = symbol == nil ? 32 : 38
        let image = NSImage(size: NSSize(width: width, height: 22), flipped: false) { _ in
            if let symbol, let icon = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) {
                icon.draw(in: NSRect(x: 0, y: 4, width: 16, height: 14))
            }
            (text as NSString).draw(at: NSPoint(x: symbol == nil ? 1 : 17, y: 5), withAttributes: [.font: AppFonts.native(8.5), .foregroundColor: NSColor.labelColor])
            return true
        }
        image.isTemplate = true; return raster(image)
    }
}
