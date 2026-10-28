import CoreGraphics
import XCTest
@testable import GesturePadCore

final class StrokeRecognizerTests: XCTestCase {
    func testCardinalDirections() {
        XCTAssertEqual(recognize(line(0, 0, 220, 0))?.name, .arrowRight)
        XCTAssertEqual(recognize(line(220, 0, 0, 0))?.name, .arrowLeft)
        XCTAssertEqual(recognize(line(0, 0, 0, 220))?.name, .arrowUp)
        XCTAssertEqual(recognize(line(0, 220, 0, 0))?.name, .arrowDown)
    }

    func testDiagonals() {
        XCTAssertEqual(recognize(line(0, 0, 180, 180))?.name, .diagonalUpRight)
        XCTAssertEqual(recognize(line(180, 180, 0, 0))?.name, .diagonalDownLeft)
    }

    func testShortMovementIsIgnored() {
        XCTAssertNil(recognize(line(0, 0, 8, 3)))
        XCTAssertNil(recognize(line(0, 0, 90, 12)))
    }

    func testLettersMatchTheirTemplates() {
        let letters: [StrokeName] = [.w, .v, .l, .d, .p, .h, .j, .s, .q, .b]
        for letter in letters {
            let template = StrokeRecognizer.builtinTemplates(letter)[0]
            let result = StrokeRecognizer.recognize(template, options: .mouse)
            XCTAssertEqual(result?.name, letter, "\(letter.rawValue) score \(result?.score ?? -1)")
            XCTAssertGreaterThan(result?.score ?? 0, 0.9, letter.rawValue)
        }
    }

    func testWIsNotV() {
        let template = StrokeRecognizer.builtinTemplates(.w)[0]
        XCTAssertEqual(StrokeRecognizer.recognize(template)?.name, .w)
    }

    func testCloseShapesDoNotSwap() {
        let loose = RecognizeOptions(minChord: 20, minLetterPath: 40, letterThreshold: 0.72, minGestureLength: 0)
        let wideV = densify(StrokeRecognizer.polyline([(0, 100), (40, 0), (100, 78)]))
        XCTAssertEqual(StrokeRecognizer.recognize(wideV, options: loose)?.name, .v)
        let openD = densify(StrokeRecognizer.polyline([(20, 100), (20, 8), (72, 0), (100, 36), (96, 72), (64, 100), (28, 92)]))
        XCTAssertEqual(StrokeRecognizer.recognize(openD, options: loose)?.name, .d)
        let tiltedL = rotate(densify(StrokeRecognizer.builtinTemplates(.l)[0]), degrees: 18)
        XCTAssertEqual(StrokeRecognizer.recognize(tiltedL, options: loose)?.name, .l)
        let roundQ = densify(StrokeRecognizer.builtinTemplates(.q)[0])
        XCTAssertEqual(StrokeRecognizer.recognize(roundQ, options: loose)?.name, .q)
    }

    private func densify(_ points: [CGPoint]) -> [CGPoint] {
        guard points.count >= 2 else { return points }
        var result: [CGPoint] = []
        for index in 1..<points.count {
            let start = points[index - 1]
            let end = points[index]
            for step in 0..<12 {
                let t = CGFloat(step) / 12
                result.append(CGPoint(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t))
            }
        }
        result.append(points[points.count - 1])
        return result
    }

    private func rotate(_ points: [CGPoint], degrees: CGFloat) -> [CGPoint] {
        let radians = degrees * .pi / 180
        let cosR = cos(radians)
        let sinR = sin(radians)
        return points.map { CGPoint(x: $0.x * cosR - $0.y * sinR, y: $0.x * sinR + $0.y * cosR) }
    }

    func testStraightLineIsNotALetter() {
        let result = recognize(line(0, 40, 300, 48))
        XCTAssertEqual(result?.name, .arrowRight)
    }

    func testUserSampleOverridesAWeakMatch() {
        let custom = StrokeRecognizer.polyline([(0, 0), (10, 80), (20, 0), (30, 80), (40, 0), (50, 80)])
        let recognized = StrokeRecognizer.recognize(
            custom,
            extraTemplates: [.w: [custom]],
            options: RecognizeOptions(minChord: 20, minLetterPath: 40, letterThreshold: 0.72)
        )
        XCTAssertEqual(recognized?.name, .w)
    }

    func testRulesRoundTripKeepsEnabledFlagAndSamples() {
        var rules = BuiltinRules.all
        rules[0].enabled = false
        rules[0].userSamples = [[SamplePoint(CGPoint(x: 1, y: 2)), SamplePoint(CGPoint(x: 3, y: 4))]]
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("gesturepad-rules-\(UUID().uuidString).json")
        try? RuleStore.save(rules, to: url)
        let loaded = RuleStore.load(from: url)
        XCTAssertEqual(loaded.count, BuiltinRules.all.count)
        XCTAssertFalse(loaded[0].enabled)
        XCTAssertEqual(loaded[0].userSamples.count, 1)
        XCTAssertEqual(loaded[0].title, BuiltinRules.all[0].title)
        try? FileManager.default.removeItem(at: url)
    }

    private func line(_ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat) -> [CGPoint] {
        (0...16).map { step in
            let t = CGFloat(step) / 16
            return CGPoint(x: x1 + (x2 - x1) * t, y: y1 + (y2 - y1) * t)
        }
    }

    private func recognize(_ points: [CGPoint]) -> Recognition? {
        StrokeRecognizer.recognize(points, options: .mouse)
    }
}
