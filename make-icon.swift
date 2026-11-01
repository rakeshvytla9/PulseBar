import AppKit

let size = NSSize(width: 1024, height: 1024)
let image = NSImage(size: size)
image.lockFocus()
NSColor(calibratedRed: 0.10, green: 0.11, blue: 0.16, alpha: 1).setFill()
NSBezierPath(roundedRect: NSRect(x: 48, y: 48, width: 928, height: 928), xRadius: 210, yRadius: 210).fill()
func arrow(x: CGFloat, upward: Bool, color: NSColor) {
    color.setStroke()
    let path = NSBezierPath(); path.lineWidth = 62; path.lineCapStyle = .round; path.lineJoinStyle = .round
    let top: CGFloat = 735, bottom: CGFloat = 289
    path.move(to: NSPoint(x: x, y: upward ? bottom : top))
    path.line(to: NSPoint(x: x, y: upward ? top : bottom))
    path.move(to: NSPoint(x: x - 110, y: upward ? top - 110 : bottom + 110))
    path.line(to: NSPoint(x: x, y: upward ? top : bottom))
    path.line(to: NSPoint(x: x + 110, y: upward ? top - 110 : bottom + 110))
    path.stroke()
}
arrow(x: 350, upward: false, color: NSColor(calibratedRed: 0.62, green: 0.81, blue: 0.42, alpha: 1))
arrow(x: 674, upward: true, color: NSColor(calibratedRed: 0.73, green: 0.60, blue: 0.97, alpha: 1))
image.unlockFocus()
let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
