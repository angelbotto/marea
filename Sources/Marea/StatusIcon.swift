import AppKit

/// Icono propio de la barra de menú: tres olas dibujadas a mano (template,
/// se tiñe solo para claro/oscuro). No depende de SF Symbols ni de recursos.
enum StatusIcon {
    static let image: NSImage = make()

    private static func make() -> NSImage {
        let w: CGFloat = 20, h: CGFloat = 15
        let img = NSImage(size: NSSize(width: w, height: h))
        img.lockFocus()
        NSColor.black.set()
        let path = NSBezierPath()
        path.lineWidth = 1.6
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        let amp: CGFloat = 2.1
        for y in [3.5, 7.5, 11.5] as [CGFloat] {
            path.move(to: NSPoint(x: 1.5, y: y))
            path.curve(to: NSPoint(x: w / 2, y: y),
                       controlPoint1: NSPoint(x: w * 0.20, y: y + amp),
                       controlPoint2: NSPoint(x: w * 0.30, y: y - amp))
            path.curve(to: NSPoint(x: w - 1.5, y: y),
                       controlPoint1: NSPoint(x: w * 0.70, y: y + amp),
                       controlPoint2: NSPoint(x: w * 0.80, y: y - amp))
        }
        path.stroke()
        img.unlockFocus()
        img.isTemplate = true   // macOS lo tiñe según el tema de la barra
        return img
    }
}
