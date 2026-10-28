import AppKit

enum MenuGlyph {
    static func image(side: CGFloat = 18) -> NSImage {
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            NSColor.black.setStroke()
            let path = NSBezierPath()
            path.move(to: Self.point(74, 76, in: rect))
            path.curve(
                to: Self.point(22, 28, in: rect),
                controlPoint1: Self.point(72, 44, in: rect),
                controlPoint2: Self.point(40, 26, in: rect)
            )
            path.lineWidth = rect.width * 0.16
            path.lineCapStyle = .round
            path.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }

    static func point(_ x: CGFloat, _ y: CGFloat, in rect: CGRect) -> CGPoint {
        CGPoint(
            x: rect.minX + x / 100 * rect.width,
            y: rect.minY + y / 100 * rect.height
        )
    }
}
