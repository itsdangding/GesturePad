import GesturePadCore
import SwiftUI

/// How each stroke is drawn in the interface. These are display shapes only:
/// the recognizer keeps its own templates and matches strokes in either direction,
/// so the start dot can sit wherever the letter is most natural to begin.
/// Coordinates are in a 100 × 100 box with y growing downward.
enum StrokeSegment {
    case move(CGFloat, CGFloat)
    case line(CGFloat, CGFloat)
    /// Cubic curve to (x, y) with two control points.
    case curve(CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat)
}

extension StrokeName {
    var displaySegments: [StrokeSegment] {
        switch self {
        case .arrowLeft: return [.move(90, 50), .line(10, 50)]
        case .arrowRight: return [.move(10, 50), .line(90, 50)]
        case .arrowUp: return [.move(50, 90), .line(50, 10)]
        case .arrowDown: return [.move(50, 10), .line(50, 90)]
        case .diagonalUpRight: return [.move(16, 84), .line(84, 16)]
        case .diagonalUpLeft: return [.move(84, 84), .line(16, 16)]
        case .diagonalDownRight: return [.move(16, 16), .line(84, 84)]
        case .diagonalDownLeft: return [.move(84, 16), .line(16, 84)]
        case .w:
            return [.move(8, 16), .line(28, 86), .line(50, 36), .line(72, 86), .line(92, 16)]
        case .v:
            return [.move(16, 14), .line(50, 88), .line(84, 14)]
        case .l:
            return [.move(28, 10), .line(28, 88), .line(82, 88)]
        case .h:
            return [.move(24, 10), .line(24, 90), .line(24, 52), .line(76, 52), .line(76, 10), .line(76, 90)]
        case .d:
            return [.move(28, 10), .line(28, 90), .curve(28, 10, 98, 90, 98, 10)]
        case .p:
            return [.move(28, 92), .line(28, 10), .curve(28, 54, 92, 8, 92, 56)]
        case .b:
            return [.move(28, 90), .line(28, 10),
                    .curve(30, 48, 84, 10, 84, 48),
                    .curve(28, 90, 94, 48, 94, 90)]
        case .j:
            return [.move(64, 10), .line(64, 64), .curve(20, 70, 64, 96, 22, 98)]
        case .s:
            return [.move(76, 22),
                    .curve(26, 30, 66, 6, 26, 6),
                    .curve(74, 70, 26, 52, 74, 46),
                    .curve(22, 80, 74, 96, 32, 98)]
        case .q:
            return [.move(50, 12),
                    .curve(12, 50, 28, 12, 12, 28),
                    .curve(50, 88, 12, 72, 28, 88),
                    .curve(88, 50, 72, 88, 88, 72),
                    .curve(50, 12, 88, 28, 72, 12),
                    .move(60, 66), .line(88, 94)]
        }
    }

    /// Straight strokes get an arrowhead so the direction is clear.
    var showsArrow: Bool { !isLetter }

    func displayPath(in rect: CGRect) -> (path: Path, start: CGPoint, end: CGPoint, before: CGPoint) {
        let side = min(rect.width, rect.height)
        let scale = side / 100
        let ox = rect.midX - side / 2
        let oy = rect.midY - side / 2
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: ox + x * scale, y: oy + y * scale) }
        var path = Path()
        var start: CGPoint?
        var current = CGPoint.zero
        var before = CGPoint.zero
        for segment in displaySegments {
            switch segment {
            case .move(let x, let y):
                current = p(x, y)
                path.move(to: current)
                if start == nil { start = current }
            case .line(let x, let y):
                before = current
                current = p(x, y)
                path.addLine(to: current)
            case .curve(let x, let y, let c1x, let c1y, let c2x, let c2y):
                before = p(c2x, c2y)
                current = p(x, y)
                path.addCurve(to: current, control1: p(c1x, c1y), control2: before)
            }
        }
        return (path, start ?? current, current, before)
    }
}

/// A built-in stroke drawn from its display shape, with a dot where the pen goes down.
struct LetterGlyph: View {
    let name: StrokeName
    var color: Color = .brand
    var lineWidth: CGFloat = 2.4

    var body: some View {
        Canvas { context, size in
            let inset = lineWidth + 2
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: inset, dy: inset)
            let shape = name.displayPath(in: rect)
            let style = StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
            context.stroke(shape.path, with: .color(color), style: style)
            let r = lineWidth * 1.3
            context.fill(Path(ellipseIn: CGRect(x: shape.start.x - r, y: shape.start.y - r, width: r * 2, height: r * 2)),
                         with: .color(color))
            if name.showsArrow {
                let angle = atan2(shape.end.y - shape.before.y, shape.end.x - shape.before.x)
                let length = lineWidth * 3.2
                var head = Path()
                head.move(to: CGPoint(x: shape.end.x - length * cos(angle - .pi / 5), y: shape.end.y - length * sin(angle - .pi / 5)))
                head.addLine(to: shape.end)
                head.addLine(to: CGPoint(x: shape.end.x - length * cos(angle + .pi / 5), y: shape.end.y - length * sin(angle + .pi / 5)))
                context.stroke(head, with: .color(color), style: style)
            }
        }
    }
}

enum StrokeSmoothing {
    /// Chaikin corner cutting. Turns jittery pointer samples into a calm line
    /// while keeping the first and last points where they were.
    static func chaikin(_ points: [CGPoint], iterations: Int = 2) -> [CGPoint] {
        guard points.count > 2, iterations > 0 else { return points }
        var result = points
        for _ in 0..<iterations {
            var next = [result[0]]
            for index in 0..<(result.count - 1) {
                let a = result[index], b = result[index + 1]
                next.append(CGPoint(x: 0.75 * a.x + 0.25 * b.x, y: 0.75 * a.y + 0.25 * b.y))
                next.append(CGPoint(x: 0.25 * a.x + 0.75 * b.x, y: 0.25 * a.y + 0.75 * b.y))
            }
            next.append(result[result.count - 1])
            result = next
        }
        return result
    }

    /// Drops points closer than `spacing` to the previous kept point.
    static func thin(_ points: [CGPoint], spacing: CGFloat) -> [CGPoint] {
        guard var last = points.first else { return [] }
        var result = [last]
        for point in points.dropFirst() where hypot(point.x - last.x, point.y - last.y) >= spacing {
            result.append(point)
            last = point
        }
        if let end = points.last, result.last != end { result.append(end) }
        return result
    }
}
