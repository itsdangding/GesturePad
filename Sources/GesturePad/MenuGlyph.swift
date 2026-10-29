import AppKit

enum MenuGlyph {
    /// Menu-bar mark: the app icon's stroke with its pen-down dot.
    /// Drawn on demand, so it stays sharp on every display.
    static func image(side: CGFloat = 18) -> NSImage {
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            draw(in: rect)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "快捷手势"
        return image
    }

    private static func draw(in rect: NSRect) {
        NSColor.black.set()
        let start = point(74, 76, in: rect)
        let path = NSBezierPath()
        path.move(to: start)
        path.curve(
            to: point(22, 28, in: rect),
            controlPoint1: point(72, 44, in: rect),
            controlPoint2: point(40, 26, in: rect)
        )
        path.lineWidth = rect.width * 0.15
        path.lineCapStyle = .round
        path.stroke()

        let radius = rect.width * 0.13
        NSBezierPath(ovalIn: NSRect(x: start.x - radius, y: start.y - radius, width: radius * 2, height: radius * 2)).fill()
    }

    /// Maps the app icon's 0–100 grid to the image. The mark sits in the
    /// middle of the icon, so this stretches it to fill the menu-bar slot.
    static func point(_ x: CGFloat, _ y: CGFloat, in rect: CGRect) -> CGPoint {
        CGPoint(
            x: rect.minX + (x - 14) / 72 * rect.width,
            y: rect.minY + (y - 16) / 72 * rect.height
        )
    }
}
