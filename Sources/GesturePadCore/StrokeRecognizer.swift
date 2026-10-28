import CoreGraphics
import Foundation

/// Names produced by the recognizer. Straight strokes use the eight directions.
/// Letters are one-stroke shapes matched with a $1-style unistroke distance.
public enum StrokeName: String, Codable, CaseIterable, Equatable {
    case arrowLeft
    case arrowRight
    case arrowUp
    case arrowDown
    case diagonalUpRight
    case diagonalUpLeft
    case diagonalDownRight
    case diagonalDownLeft
    case w, h, l, p, v, d, q, b, j, s

    public var title: String {
        switch self {
        case .arrowLeft: return "向左直线"
        case .arrowRight: return "向右直线"
        case .arrowUp: return "向上直线"
        case .arrowDown: return "向下直线"
        case .diagonalUpRight: return "向右上"
        case .diagonalUpLeft: return "向左上"
        case .diagonalDownRight: return "向右下"
        case .diagonalDownLeft: return "向左下"
        case .w: return "字母 W"
        case .h: return "字母 H"
        case .l: return "字母 L"
        case .p: return "字母 P"
        case .v: return "字母 V"
        case .d: return "字母 D"
        case .q: return "字母 Q"
        case .b: return "字母 B"
        case .j: return "字母 J"
        case .s: return "字母 S"
        }
    }

    public var isLetter: Bool {
        switch self {
        case .w, .h, .l, .p, .v, .d, .q, .b, .j, .s:
            return true
        default:
            return false
        }
    }
}

public struct Recognition: Equatable {
    public var name: StrokeName
    public var score: Double

    public init(name: StrokeName, score: Double) {
        self.name = name
        self.score = score
    }
}

public struct RecognizeOptions: Equatable {
    /// Minimum start-to-end distance before a straight stroke counts.
    public var minChord: CGFloat
    /// Minimum path length before a letter counts.
    public var minLetterPath: CGFloat
    /// Unistroke score from 0 to 1. Lower scores are rejected.
    public var letterThreshold: Double
    /// Path length below this stays a normal click. Zero means every stroke is eligible.
    public var minGestureLength: CGFloat

    public init(
        minChord: CGFloat = 48,
        minLetterPath: CGFloat = 80,
        letterThreshold: Double = 0.72,
        minGestureLength: CGFloat = 0
    ) {
        self.minChord = minChord
        self.minLetterPath = minLetterPath
        self.letterThreshold = letterThreshold
        self.minGestureLength = minGestureLength
    }

    public static let mouse = RecognizeOptions(minChord: 48, minLetterPath: 80, letterThreshold: 0.72, minGestureLength: 150)
    public static let trackpad = RecognizeOptions(minChord: 180, minLetterPath: 220, letterThreshold: 0.72, minGestureLength: 180)
}

public enum StrokeRecognizer {
    public static func recognize(
        _ raw: [CGPoint],
        extraTemplates: [StrokeName: [[CGPoint]]] = [:],
        options: RecognizeOptions = .mouse
    ) -> Recognition? {
        let points = cleanup(raw)
        guard points.count >= 2 else { return nil }
        if options.minGestureLength > 0, pathLength(points) < options.minGestureLength {
            return nil
        }
        let length = pathLength(points)
        let chord = distance(points[0], points[points.count - 1])

        if let straight = straightRecognition(points, chord: chord, minimum: options.minChord) {
            return straight
        }

        guard length >= options.minLetterPath else { return nil }

        let drawn = shapeFacts(points)
        var ranked: [(name: StrokeName, score: Double)] = []
        for name in StrokeName.allCases where name.isLetter {
            var builtinDistance = CGFloat.greatestFiniteMagnitude
            for template in builtinTemplates(name) {
                builtinDistance = min(builtinDistance, pairDistance(points, template))
            }
            var userDistance = CGFloat.greatestFiniteMagnitude
            for template in extraTemplates[name] ?? [] {
                userDistance = min(userDistance, pairDistance(points, template))
            }
            let bestDistance = min(builtinDistance, userDistance)
            guard bestDistance < .greatestFiniteMagnitude else { continue }
            let cloud = scoreFromDistance(bestDistance)
            let trustsRecording = userDistance + 12 < builtinDistance
            let damp = cloud >= 0.90 ? 0.35 : 1
            let rawPenalty = structurePenalty(drawn, expected: letterFacts[name] ?? drawn)
            let penalty = trustsRecording ? 0 : min(0.28, rawPenalty * damp)
            let score = cloud - penalty
            if score >= options.letterThreshold {
                ranked.append((name, score))
            }
        }
        ranked.sort { $0.score > $1.score }
        guard let best = ranked.first else { return nil }
        if ranked.count > 1, best.score - ranked[1].score < 0.03 {
            return nil
        }
        return Recognition(name: best.name, score: min(1, best.score))
    }

    public static func builtinTemplates(_ name: StrokeName) -> [[CGPoint]] {
        switch name {
        case .w:
            return [
                polyline([(0, 100), (25, 0), (50, 62), (75, 0), (100, 100)]),
                polyline([(0, 90), (22, 8), (50, 55), (78, 8), (100, 92)])
            ]
        case .v:
            return [
                polyline([(0, 100), (50, 0), (100, 100)]),
                polyline([(8, 92), (50, 6), (92, 94)])
            ]
        case .l:
            return [
                polyline([(0, 100), (0, 0), (100, 0)]),
                polyline([(6, 100), (6, 8), (96, 8)])
            ]
        case .d:
            return [
                polyline([(20, 100), (20, 8), (72, 0), (100, 36), (96, 72), (64, 100), (20, 100)]),
                polyline([(16, 96), (16, 12), (68, 4), (98, 40), (90, 78), (58, 98), (16, 96)])
            ]
        case .p:
            return [
                polyline([(18, 0), (18, 100), (18, 58), (70, 58), (96, 76), (78, 100), (18, 100)]),
                polyline([(22, 4), (22, 98), (22, 52), (74, 50), (98, 72), (70, 98), (22, 98)])
            ]
        case .h:
            return [
                polyline([(8, 100), (8, 0), (8, 50), (92, 50), (92, 100), (92, 0)]),
                polyline([(12, 96), (12, 6), (12, 48), (88, 48), (88, 96), (88, 4)])
            ]
        case .j:
            return [
                polyline([(78, 100), (78, 28), (58, 6), (28, 12), (16, 32)]),
                polyline([(70, 98), (72, 36), (50, 8), (22, 22)])
            ]
        case .s:
            return [
                polyline([(82, 88), (48, 100), (14, 78), (28, 54), (72, 46), (90, 22), (58, 2), (18, 12)]),
                polyline([(78, 92), (40, 98), (12, 74), (32, 52), (74, 42), (86, 18), (48, 4), (16, 16)])
            ]
        case .q:
            return [circle(cx: 46, cy: 58, radius: 34, start: -.pi / 2, sweep: 2 * .pi, steps: 24, tail: (18, -16))]
        case .b:
            return [
                polyline([(16, 100), (16, 0), (16, 62), (58, 78), (78, 62), (58, 46), (16, 50), (16, 28), (62, 18), (80, 32), (60, 48)])
            ]
        default:
            return []
        }
    }

    // MARK: - Geometry

    public static func cleanup(_ points: [CGPoint]) -> [CGPoint] {
        var result: [CGPoint] = []
        for point in points {
            guard point.x.isFinite, point.y.isFinite else { continue }
            if let last = result.last, distance(last, point) < 1.2 {
                continue
            }
            result.append(point)
        }
        return result
    }

    public static func pathLength(_ points: [CGPoint]) -> CGFloat {
        guard points.count >= 2 else { return 0 }
        var total: CGFloat = 0
        for index in 1..<points.count {
            total += distance(points[index - 1], points[index])
        }
        return total
    }

    static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }

    static func straightRecognition(_ points: [CGPoint], chord: CGFloat, minimum: CGFloat) -> Recognition? {
        guard chord >= minimum, chord > 1, let first = points.first, let last = points.last else { return nil }
        var maxDeviation: CGFloat = 0
        for point in points {
            maxDeviation = max(maxDeviation, distanceToSegment(point, first, last))
        }
        let allowance = max(16, chord * 0.16)
        guard maxDeviation <= allowance else { return nil }
        let score = 1 - 0.28 * Double(maxDeviation / allowance)
        return Recognition(name: directionName(from: first, to: last), score: score)
    }

    private struct ShapeFacts {
        var closure: Double
        var startHeight: Double
        var endHeight: Double
        var valleys: Int
    }

    private static let letterFacts: [StrokeName: ShapeFacts] = {
        var facts: [StrokeName: ShapeFacts] = [:]
        for name in StrokeName.allCases where name.isLetter {
            guard let template = builtinTemplates(name).first else { continue }
            facts[name] = shapeFacts(template)
        }
        return facts
    }()

    /// D and Q, or V and L, can sit close on pure outline distance.
    /// Closure, where the stroke starts and ends, and how many valleys it has
    /// pull those pairs apart so a high score means this letter and not the neighbor.
    private static func structurePenalty(_ drawn: ShapeFacts, expected: ShapeFacts) -> Double {
        let closure = abs(drawn.closure - expected.closure)
        let start = abs(drawn.startHeight - expected.startHeight)
        let end = abs(drawn.endHeight - expected.endHeight)
        let valleys = min(2, abs(drawn.valleys - expected.valleys))
        return 0.40 * closure + 0.20 * start + 0.50 * end + 0.12 * Double(valleys)
    }

    private static func shapeFacts(_ raw: [CGPoint]) -> ShapeFacts {
        let points = resample(cleanup(raw), count: 48)
        guard let first = points.first, let last = points.last, points.count >= 2 else {
            return ShapeFacts(closure: 1, startHeight: 0, endHeight: 0, valleys: 0)
        }
        let minY = points.map(\.y).min() ?? 0
        let maxY = points.map(\.y).max() ?? 0
        let minX = points.map(\.x).min() ?? 0
        let maxX = points.map(\.x).max() ?? 0
        let height = max(maxY - minY, 1)
        let width = max(maxX - minX, 1)
        let diagonal = max(hypot(width, height), 1)
        let gap = max(1, points.count / 6)
        var valleys = 0
        var lastValley = -gap * 2
        if points.count > gap * 2 {
            for index in gap..<(points.count - gap) {
                let y = points[index].y
                let before = points[index - gap].y
                let after = points[index + gap].y
                if y <= before - height * 0.15, y <= after - height * 0.15, index - lastValley > gap {
                    valleys += 1
                    lastValley = index
                }
            }
        }
        return ShapeFacts(
            closure: Double(min(1, distance(first, last) / diagonal)),
            startHeight: Double((first.y - minY) / height),
            endHeight: Double((last.y - minY) / height),
            valleys: valleys
        )
    }

    static func distanceToSegment(_ point: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        if lengthSquared < 0.01 {
            return distance(point, a)
        }
        var t = ((point.x - a.x) * dx + (point.y - a.y) * dy) / lengthSquared
        t = min(1, max(0, t))
        let projection = CGPoint(x: a.x + t * dx, y: a.y + t * dy)
        return distance(point, projection)
    }

    static func directionName(from start: CGPoint, to end: CGPoint) -> StrokeName {
        let degrees = atan2(end.y - start.y, end.x - start.x) * 180 / .pi
        switch degrees {
        case -22.5..<22.5:
            return .arrowRight
        case 22.5..<67.5:
            return .diagonalUpRight
        case 67.5..<112.5:
            return .arrowUp
        case 112.5..<157.5:
            return .diagonalUpLeft
        case -67.5..<(-22.5):
            return .diagonalDownRight
        case -112.5..<(-67.5):
            return .arrowDown
        case -157.5..<(-112.5):
            return .diagonalDownLeft
        default:
            return .arrowLeft
        }
    }

    static func scoreFromDistance(_ distance: CGFloat) -> Double {
        let halfDiagonal = 0.5 * sqrt(squareSize * squareSize + squareSize * squareSize)
        let score = 1 - Double(distance / halfDiagonal)
        return max(0, min(1, score))
    }

    // MARK: - $1 normalization

    private static let sampleCount = 64
    private static let squareSize: CGFloat = 250

    static func pairDistance(_ points: [CGPoint], _ template: [CGPoint]) -> CGFloat {
        min(
            cloudDistance(points, template),
            cloudDistance(Array(points.reversed()), template)
        )
    }

    static func cloudDistance(_ points: [CGPoint], _ template: [CGPoint]) -> CGFloat {
        let candidate = normalize(points)
        let reference = normalize(template)
        guard candidate.count == sampleCount, reference.count == sampleCount else {
            return .greatestFiniteMagnitude
        }
        var best = averageDistance(candidate, reference)
        for degrees in stride(from: -24, through: 24, by: 6) {
            let rotated = rotate(candidate, by: CGFloat(degrees) * .pi / 180)
            let translated = translateToOrigin(rotated)
            best = min(best, averageDistance(translated, reference))
        }
        return best
    }

    static func normalize(_ points: [CGPoint]) -> [CGPoint] {
        let sampled = resample(points, count: sampleCount)
        guard let first = sampled.first else { return [] }
        let angle = atan2(centroid(sampled).y - first.y, centroid(sampled).x - first.x)
        let rotated = rotate(sampled, by: -angle)
        let scaled = scaleToSquare(rotated, size: squareSize)
        return translateToOrigin(scaled)
    }

    static func resample(_ points: [CGPoint], count: Int) -> [CGPoint] {
        guard points.count >= 2, count >= 2 else { return points }
        let interval = pathLength(points) / CGFloat(count - 1)
        if interval < 0.001 {
            return Array(repeating: points[0], count: count)
        }
        var source = points
        var result = [source[0]]
        var accumulated: CGFloat = 0
        var index = 1
        var guardrail = 0
        while index < source.count && result.count < count && guardrail < count * 8 {
            guardrail += 1
            let step = distance(source[index - 1], source[index])
            if step < 0.001 {
                index += 1
                continue
            }
            if accumulated + step >= interval {
                let t = (interval - accumulated) / step
                let point = CGPoint(
                    x: source[index - 1].x + t * (source[index].x - source[index - 1].x),
                    y: source[index - 1].y + t * (source[index].y - source[index - 1].y)
                )
                result.append(point)
                source.insert(point, at: index)
                accumulated = 0
            } else {
                accumulated += step
            }
            index += 1
        }
        if result.count == count - 1, let last = source.last {
            result.append(last)
        }
        if result.count > count {
            result = Array(result.prefix(count))
        }
        while result.count < count {
            result.append(result.last ?? .zero)
        }
        return result
    }

    static func centroid(_ points: [CGPoint]) -> CGPoint {
        guard !points.isEmpty else { return .zero }
        var x: CGFloat = 0
        var y: CGFloat = 0
        for point in points {
            x += point.x
            y += point.y
        }
        let count = CGFloat(points.count)
        return CGPoint(x: x / count, y: y / count)
    }

    static func rotate(_ points: [CGPoint], by radians: CGFloat) -> [CGPoint] {
        let center = centroid(points)
        let cosR = cos(radians)
        let sinR = sin(radians)
        return points.map { point in
            let dx = point.x - center.x
            let dy = point.y - center.y
            return CGPoint(
                x: dx * cosR - dy * sinR + center.x,
                y: dx * sinR + dy * cosR + center.y
            )
        }
    }

    static func scaleToSquare(_ points: [CGPoint], size: CGFloat) -> [CGPoint] {
        let xs = points.map(\.x)
        let ys = points.map(\.y)
        let width = max(1, (xs.max() ?? 0) - (xs.min() ?? 0))
        let height = max(1, (ys.max() ?? 0) - (ys.min() ?? 0))
        let box = max(width, height)
        return points.map { CGPoint(x: $0.x * size / box, y: $0.y * size / box) }
    }

    static func translateToOrigin(_ points: [CGPoint]) -> [CGPoint] {
        let center = centroid(points)
        return points.map { CGPoint(x: $0.x - center.x, y: $0.y - center.y) }
    }

    static func averageDistance(_ a: [CGPoint], _ b: [CGPoint]) -> CGFloat {
        let count = min(a.count, b.count)
        guard count > 0 else { return .greatestFiniteMagnitude }
        var total: CGFloat = 0
        for index in 0..<count {
            total += distance(a[index], b[index])
        }
        return total / CGFloat(count)
    }

    static func polyline(_ pairs: [(CGFloat, CGFloat)]) -> [CGPoint] {
        pairs.map { CGPoint(x: $0.0, y: $0.1) }
    }

    static func circle(
        cx: CGFloat,
        cy: CGFloat,
        radius: CGFloat,
        start: CGFloat,
        sweep: CGFloat,
        steps: Int,
        tail: (CGFloat, CGFloat)
    ) -> [CGPoint] {
        var points: [CGPoint] = []
        for step in 0...steps {
            let t = start + sweep * CGFloat(step) / CGFloat(steps)
            points.append(CGPoint(x: cx + cos(t) * radius, y: cy + sin(t) * radius))
        }
        if let last = points.last {
            points.append(CGPoint(x: last.x + tail.0, y: last.y + tail.1))
        }
        return points
    }
}
