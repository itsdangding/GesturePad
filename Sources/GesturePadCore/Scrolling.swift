import CoreGraphics
import Foundation

/// Which way content moves when you scroll.
/// macOS has one "natural scrolling" switch for every device. This lets the
/// mouse wheel and the trackpad each go their own way.
public enum ScrollStyle: String, CaseIterable, Codable {
    /// Leave events as the system sends them.
    case system
    /// Wheel or fingers down shows what is further down, as on Windows.
    case standard
    /// Content follows the fingers, as on iPhone.
    case natural

    /// True when the event has to be flipped to get this style.
    public func shouldInvert(systemNatural: Bool) -> Bool {
        switch self {
        case .system: return false
        case .standard: return systemNatural
        case .natural: return !systemNatural
        }
    }
}

public enum ScrollSource: Equatable {
    case wheel
    case trackpad
}

public enum ScrollClassifier {
    /// Decides where a scroll event came from.
    /// - Line-based events always come from a wheel.
    /// - Momentum keeps the source of the scroll that started it.
    /// - Smooth events count as trackpad only while two fingers are on it. Without
    ///   a trackpad reader, events with a gesture phase are treated as trackpad.
    public static func source(
        continuous: Bool,
        momentum: Bool,
        hasPhase: Bool,
        fingersOnTrackpad: Bool?,
        previous: ScrollSource
    ) -> ScrollSource {
        if !continuous { return .wheel }
        if momentum { return previous }
        if let fingersOnTrackpad { return fingersOnTrackpad ? .trackpad : .wheel }
        return hasPhase ? .trackpad : .wheel
    }

    /// Direction the wheel or fingers physically moved, before any flipping.
    /// Positive delta means content scrolls up when natural scrolling is off.
    public static func movedUp(delta: Double, systemNatural: Bool) -> Bool {
        (delta > 0) != systemNatural
    }
}

public enum ScrollInverter {
    /// Reverses a scroll event on both axes.
    ///
    /// Setting one delta field makes CoreGraphics recompute the others, so
    /// flipping them one at a time undoes itself and the app sees no change.
    /// Read every value first, then write them back negated, line deltas first.
    public static func invert(_ event: CGEvent) {
        let lineFields: [CGEventField] = [.scrollWheelEventDeltaAxis1, .scrollWheelEventDeltaAxis2]
        let fixedFields: [CGEventField] = [.scrollWheelEventFixedPtDeltaAxis1, .scrollWheelEventFixedPtDeltaAxis2]
        // The accelerated fields are left alone: writing them recomputes the
        // point deltas and undoes the flip for smooth scrolling.
        let pointFields: [CGEventField] = [.scrollWheelEventPointDeltaAxis1, .scrollWheelEventPointDeltaAxis2]
        let lines = lineFields.map { event.getIntegerValueField($0) }
        let fixed = fixedFields.map { event.getDoubleValueField($0) }
        let points = pointFields.map { event.getIntegerValueField($0) }
        for (field, value) in zip(lineFields, lines) {
            event.setIntegerValueField(field, value: -value)
        }
        for (field, value) in zip(fixedFields, fixed) {
            event.setDoubleValueField(field, value: -value)
        }
        for (field, value) in zip(pointFields, points) where value != 0 {
            event.setIntegerValueField(field, value: -value)
        }
    }
}
