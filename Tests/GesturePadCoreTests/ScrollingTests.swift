import AppKit
import XCTest
@testable import GesturePadCore

final class ScrollingTests: XCTestCase {
    func testStyleFlipsOnlyWhenItDiffersFromTheSystem() {
        XCTAssertFalse(ScrollStyle.system.shouldInvert(systemNatural: true))
        XCTAssertFalse(ScrollStyle.system.shouldInvert(systemNatural: false))
        XCTAssertTrue(ScrollStyle.standard.shouldInvert(systemNatural: true))
        XCTAssertFalse(ScrollStyle.standard.shouldInvert(systemNatural: false))
        XCTAssertFalse(ScrollStyle.natural.shouldInvert(systemNatural: true))
        XCTAssertTrue(ScrollStyle.natural.shouldInvert(systemNatural: false))
    }

    func testNotchedWheelIsAlwaysAWheel() {
        let source = ScrollClassifier.source(continuous: false, momentum: false, hasPhase: false,
                                             fingersOnTrackpad: true, previous: .trackpad)
        XCTAssertEqual(source, .wheel)
    }

    func testSmoothScrollIsTrackpadOnlyWithFingersOnIt() {
        XCTAssertEqual(ScrollClassifier.source(continuous: true, momentum: false, hasPhase: true,
                                               fingersOnTrackpad: true, previous: .wheel), .trackpad)
        // A smooth-scrolling mouse or Magic Mouse while the trackpad is untouched.
        XCTAssertEqual(ScrollClassifier.source(continuous: true, momentum: false, hasPhase: true,
                                               fingersOnTrackpad: false, previous: .trackpad), .wheel)
    }

    func testMomentumKeepsItsSource() {
        XCTAssertEqual(ScrollClassifier.source(continuous: true, momentum: true, hasPhase: false,
                                               fingersOnTrackpad: false, previous: .trackpad), .trackpad)
        XCTAssertEqual(ScrollClassifier.source(continuous: true, momentum: true, hasPhase: false,
                                               fingersOnTrackpad: true, previous: .wheel), .wheel)
    }

    func testWithoutTrackpadReaderPhaseDecides() {
        XCTAssertEqual(ScrollClassifier.source(continuous: true, momentum: false, hasPhase: true,
                                               fingersOnTrackpad: nil, previous: .wheel), .trackpad)
        XCTAssertEqual(ScrollClassifier.source(continuous: true, momentum: false, hasPhase: false,
                                               fingersOnTrackpad: nil, previous: .trackpad), .wheel)
    }

    func testPhysicalDirectionIgnoresNaturalScrolling() {
        // Wheel turned away from you: positive without natural scrolling, negative with it.
        XCTAssertTrue(ScrollClassifier.movedUp(delta: 3, systemNatural: false))
        XCTAssertTrue(ScrollClassifier.movedUp(delta: -3, systemNatural: true))
        XCTAssertFalse(ScrollClassifier.movedUp(delta: -3, systemNatural: false))
        XCTAssertFalse(ScrollClassifier.movedUp(delta: 3, systemNatural: true))
    }

    // MARK: Inverting real events

    private func scrollEvent(_ unit: CGScrollEventUnit, continuous: Bool) -> CGEvent {
        let event = CGEvent(scrollWheelEvent2Source: nil, units: unit, wheelCount: 2, wheel1: -3, wheel2: 2, wheel3: 0)!
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: continuous ? 1 : 0)
        return event
    }

    /// Apps read NSEvent, so that is what has to change.
    func testInvertReversesWhatAppsSee() {
        for (unit, continuous) in [(CGScrollEventUnit.line, false), (.pixel, true)] {
            let event = scrollEvent(unit, continuous: continuous)
            // NSEvent reads the CGEvent lazily, so copy the numbers out before changing it.
            let before = NSEvent(cgEvent: event.copy()!)!
            let (dy, dx, deltaY) = (before.scrollingDeltaY, before.scrollingDeltaX, before.deltaY)
            ScrollInverter.invert(event)
            let after = NSEvent(cgEvent: event)!
            XCTAssertNotEqual(dy, 0)
            XCTAssertEqual(after.scrollingDeltaY, -dy, accuracy: 0.001, "\(unit.rawValue)")
            XCTAssertEqual(after.scrollingDeltaX, -dx, accuracy: 0.001, "\(unit.rawValue)")
            XCTAssertEqual(after.deltaY, -deltaY, accuracy: 0.001, "\(unit.rawValue)")
        }
    }

    func testInvertTwiceRestoresTheEvent() {
        let event = scrollEvent(.line, continuous: false)
        let before = NSEvent(cgEvent: event.copy()!)!.scrollingDeltaY
        ScrollInverter.invert(event)
        ScrollInverter.invert(event)
        XCTAssertEqual(NSEvent(cgEvent: event)!.scrollingDeltaY, before, accuracy: 0.001)
    }
}
