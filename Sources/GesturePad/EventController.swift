import AppKit
import CoreGraphics
import Foundation
import GesturePadCore

struct ConfigSnapshot {
    var enabled = true
    var showTrail = true
    var mouseScroll: ScrollStyle = .standard
    var trackpadScroll: ScrollStyle = .system
    /// The system "natural scrolling" switch. On unless turned off.
    var systemNatural = true
    /// Height of the primary display. CGEvent locations start at its top-left,
    /// AppKit points start at its bottom-left, so y is always `primaryMaxY - y`.
    var primaryMaxY: CGFloat = 0
    var screenFrames: [CGRect] = []
    var rules: [GestureRule] = []
    var recordingRuleID: String?
    var frontBundleID: String?
    /// The settings window is recording a shortcut. Hotkeys pass through untouched.
    var capturingKeys = false

    /// Right-button down events are only held back when something can use them.
    var usesRightButton: Bool {
        recordingRuleID != nil || rules.contains { rule in
            guard rule.enabled else { return false }
            switch rule.trigger {
            case .rightStroke, .rightScroll, .hotCornerClick: return true
            default: return false
            }
        }
    }

    var usesMiddleButton: Bool {
        recordingRuleID != nil || rules.contains { rule in
            guard rule.enabled else { return false }
            switch rule.trigger {
            case .middleStroke, .middleScroll: return true
            default: return false
            }
        }
    }
}

final class ConfigBox {
    private let lock = NSLock()
    private var value = ConfigSnapshot()

    func update(_ body: (inout ConfigSnapshot) -> Void) {
        lock.lock()
        body(&value)
        lock.unlock()
    }

    func snapshot() -> ConfigSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

final class EventController {
    let box = ConfigBox()
    let overlay = StrokeOverlay()
    let trackpad = TrackpadMonitor()
    weak var model: AppModel?

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var thread: Thread?
    private var runLoop: CFRunLoop?
    private var right: Stroke?
    private var middle: Stroke?
    /// Written into every event this app posts, so the tap can let them through.
    static let syntheticMarker: Int64 = 0x4750_6164
    private var lastShortcut = Date.distantPast
    private var lastMedia = Date.distantPast
    /// Where the last non-momentum scroll came from. Momentum keeps that source.
    private var lastScrollSource: ScrollSource = .wheel
    /// A trackpad right click in a screen corner ran a rule; drop its up event.
    private var swallowRightUp = false
    private let performLock = NSLock()
    private var lastStroke = Date.distantPast
    private var lastStrokeID = ""
    private var installed = false

    struct Stroke {
        /// AppKit coordinates, used for recognition, corners and the trail.
        var origin: CGPoint
        /// The original CGEvent location, used when the click is replayed.
        var rawOrigin: CGPoint
        /// Modifier keys held at mouse down, so a replayed ⌃-click stays a ⌃-click.
        var flags: CGEventFlags
        var points: [CGPoint]
        var scrolled = false
    }

    func ensureRunning() {
        if installed { return }
        if thread == nil {
            start()
            return
        }
        guard let runLoop else { return }
        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.commonModes.rawValue) { [weak self] in
            self?.installTap()
        }
        CFRunLoopWakeUp(runLoop)
    }

    func start() {
        guard thread == nil else { return }
        // Only tells trackpad scrolling and clicks apart from the mouse.
        // Without it the app guesses from event fields, so a failure is fine.
        _ = trackpad.start()

        thread = Thread { [weak self] in
            self?.runLoop = CFRunLoopGetCurrent()
            self?.installTap()
            CFRunLoopRun()
        }
        thread?.name = "GesturePadEventTap"
        thread?.start()
    }

    private func installTap() {
        if tap != nil { return }
        let mask = eventMask([
            .rightMouseDown, .rightMouseDragged, .rightMouseUp,
            .otherMouseDown, .otherMouseDragged, .otherMouseUp,
            .scrollWheel, .flagsChanged, .keyDown
        ])
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: eventTapCallback,
            userInfo: refcon
        ) else {
            DispatchQueue.main.async {
                self.model?.status = "事件监听没建起来。先在系统设置里打开辅助功能，再点重新检查。"
            }
            return
        }
        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.source = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        installed = true
        DispatchQueue.main.async {
            self.model?.status = "手势监听已开始"
        }
    }

    fileprivate func handle(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return nil
        }
        if event.getIntegerValueField(.eventSourceUserData) == Self.syntheticMarker {
            return Unmanaged.passUnretained(event)
        }
        let snap = box.snapshot()
        var scrollUp = false
        if type == .scrollWheel {
            scrollUp = ScrollClassifier.movedUp(
                delta: event.getDoubleValueField(.scrollWheelEventDeltaAxis1),
                systemNatural: snap.systemNatural
            )
            applyScrollStyle(event, snap: snap)
        }
        guard snap.enabled else {
            return releaseHeldButton(type, event)
        }

        switch type {
        case .flagsChanged:
            return Unmanaged.passUnretained(event)
        case .keyDown:
            if snap.capturingKeys || event.getIntegerValueField(.keyboardEventAutorepeat) != 0 {
                return Unmanaged.passUnretained(event)
            }
            let code = Int(event.getIntegerValueField(.keyboardEventKeycode))
            let modifiers = modifierKeys(event.flags)
            if let rule = snap.rules.first(where: { rule in
                guard rule.enabled, case .hotkey(let key, let required) = rule.trigger else { return false }
                return key == code && Set(required) == Set(modifiers)
            }) {
                perform(rule)
                return nil
            }
            return Unmanaged.passUnretained(event)
        case .scrollWheel:
            if consumeScroll(event, up: scrollUp, rules: snap.rules) {
                return nil
            }
            return Unmanaged.passUnretained(event)
        case .rightMouseDown:
            guard snap.usesRightButton else { return Unmanaged.passUnretained(event) }
            let point = location(of: event, snap: snap)
            // Trackpad secondary clicks go straight through, so the context
            // menu opens at once as usual. Only screen-corner rules apply to them.
            if snap.recordingRuleID == nil, trackpad.isAvailable, trackpad.fingerRecentlyDown {
                if let corner = screenCorner(point), let rule = snap.rules.first(where: { rule in
                    guard rule.enabled, case .hotCornerClick(let expected) = rule.trigger else { return false }
                    return expected == corner
                }) {
                    perform(rule)
                    swallowRightUp = true
                    return nil
                }
                return Unmanaged.passUnretained(event)
            }
            right = Stroke(origin: point, rawOrigin: event.location, flags: event.flags, points: [point])
            return nil
        case .rightMouseDragged:
            guard right != nil else { return Unmanaged.passUnretained(event) }
            right?.points.append(location(of: event, snap: snap))
            showMouseTrail(right?.points ?? [])
            return nil
        case .rightMouseUp:
            if swallowRightUp {
                swallowRightUp = false
                return nil
            }
            guard right != nil else { return Unmanaged.passUnretained(event) }
            finish(stroke: right, source: .right, rules: snap.rules, release: event)
            right = nil
            overlay.clear()
            return nil
        case .otherMouseDown:
            guard event.getIntegerValueField(.mouseEventButtonNumber) == 2, snap.usesMiddleButton else {
                return Unmanaged.passUnretained(event)
            }
            let point = location(of: event, snap: snap)
            middle = Stroke(origin: point, rawOrigin: event.location, flags: event.flags, points: [point])
            return nil
        case .otherMouseDragged:
            guard middle != nil else { return Unmanaged.passUnretained(event) }
            middle?.points.append(location(of: event, snap: snap))
            showMouseTrail(middle?.points ?? [])
            return nil
        case .otherMouseUp:
            guard middle != nil else { return Unmanaged.passUnretained(event) }
            finish(stroke: middle, source: .middle, rules: snap.rules, release: event)
            middle = nil
            overlay.clear()
            return nil
        default:
            return Unmanaged.passUnretained(event)
        }
    }

    private enum Source {
        case right
        case middle
    }

    /// Gestures were paused while a button was held. The down event was
    /// swallowed, so give the app a normal click instead of a stray up event.
    private func releaseHeldButton(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        let held: Stroke?
        let source: Source
        switch type {
        case .rightMouseUp:
            held = right
            right = nil
            source = .right
        case .otherMouseUp:
            held = middle
            middle = nil
            source = .middle
        case .rightMouseDragged where right != nil, .otherMouseDragged where middle != nil:
            return nil
        default:
            return Unmanaged.passUnretained(event)
        }
        guard let held else { return Unmanaged.passUnretained(event) }
        overlay.clear()
        if !held.scrolled { replay(held, source: source, release: event) }
        return nil
    }

    private func finish(stroke: Stroke?, source: Source, rules: [GestureRule], release: CGEvent) {
        guard let stroke else { return }
        let chord = hypot(stroke.points.last!.x - stroke.origin.x, stroke.points.last!.y - stroke.origin.y)
        let length = StrokeRecognizer.pathLength(StrokeRecognizer.cleanup(stroke.points))
        let minimum = RecognizeOptions.mouse.minGestureLength
        if length < 28, !stroke.scrolled, source == .right, let corner = screenCorner(stroke.origin) {
            if let rule = rules.first(where: { rule in
                guard rule.enabled, case .hotCornerClick(let expected) = rule.trigger else { return false }
                return expected == corner
            }) {
                perform(rule)
                return
            }
        }
        if length < minimum || (stroke.scrolled && chord < 30) {
            if !stroke.scrolled {
                replay(stroke, source: source, release: release)
            }
            return
        }
        if let recording = box.snapshot().recordingRuleID {
            let points = stroke.points
            DispatchQueue.main.async {
                self.model?.saveSample(ruleID: recording, points: points)
            }
            return
        }
        let options = RecognizeOptions.mouse
        let extras = RuleStore.samples(in: rules)
        guard let recognition = StrokeRecognizer.recognize(stroke.points, extraTemplates: extras, options: options) else {
            if !stroke.scrolled {
                replay(stroke, source: source, release: release)
            }
            return
        }
        let matched = rules.first { rule in
            guard rule.enabled else { return false }
            switch (source, rule.trigger) {
            case (.right, .rightStroke(let name)), (.middle, .middleStroke(let name)):
                return name == recognition.name
            default:
                return false
            }
        }
        if let matched {
            perform(matched, detail: recognition.name.title)
        } else if !stroke.scrolled {
            replay(stroke, source: source, release: release)
        }
    }

    /// Flips a scroll event when the chosen direction for its device differs
    /// from what the system does. Both axes flip, as the system switch does.
    private func applyScrollStyle(_ event: CGEvent, snap: ConfigSnapshot) {
        let continuous = event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0
        let momentum = event.getIntegerValueField(.scrollWheelEventMomentumPhase) != 0
        let phase = event.getIntegerValueField(.scrollWheelEventScrollPhase) != 0
        let source = ScrollClassifier.source(
            continuous: continuous,
            momentum: momentum,
            hasPhase: phase,
            fingersOnTrackpad: trackpad.isAvailable ? trackpad.fingersRecentlyDown : nil,
            previous: lastScrollSource
        )
        if !momentum { lastScrollSource = source }
        let style = source == .trackpad ? snap.trackpadScroll : snap.mouseScroll
        guard style.shouldInvert(systemNatural: snap.systemNatural) else { return }

        ScrollInverter.invert(event)
    }

    /// `up` is the way the wheel physically turned, so 「向上滚」 means the same
    /// thing whatever scroll direction is chosen.
    private func consumeScroll(_ event: CGEvent, up: Bool, rules: [GestureRule]) -> Bool {
        let delta = event.getDoubleValueField(.scrollWheelEventDeltaAxis1)
        if abs(delta) < 0.01 {
            return false
        }
        // Trackpad and Magic Mouse scrolling is continuous. Leave it alone so
        // two-finger scrolling near a corner, or during a two-finger click, works as usual.
        guard event.getIntegerValueField(.scrollWheelEventIsContinuous) == 0 else {
            return false
        }
        let direction: ScrollDirection = up ? .up : .down
        let point = location(of: event, snap: box.snapshot())
        if right == nil && middle == nil, let corner = screenCorner(point, inset: 36) {
            if let rule = rules.first(where: { rule in
                guard rule.enabled, case .hotCornerScroll(let expected, let scroll) = rule.trigger else { return false }
                return expected == corner && scroll == direction
            }) {
                let now = Date()
                if now.timeIntervalSince(lastMedia) < 0.09 { return true }
                lastMedia = now
                perform(rule, repeatable: true)
                return true
            }
        }
        if var stroke = right {
            stroke.scrolled = true
            right = stroke
            let movement = hypot(point.x - stroke.origin.x, point.y - stroke.origin.y)
            if movement < 28 {
                let bundle = box.snapshot().frontBundleID
                if let rule = rules.first(where: { rule in
                    guard rule.enabled, case .rightScroll(let scroll, let required) = rule.trigger else { return false }
                    if scroll != direction { return false }
                    if let required, required != bundle { return false }
                    return true
                }) {
                    let now = Date()
                    if now.timeIntervalSince(lastShortcut) < 0.12 { return true }
                    lastShortcut = now
                    perform(rule, repeatable: true)
                    return true
                }
            }
            return false
        }
        if var stroke = middle {
            stroke.scrolled = true
            middle = stroke
            let movement = hypot(point.x - stroke.origin.x, point.y - stroke.origin.y)
            if movement < 28, let rule = rules.first(where: { rule in
                guard rule.enabled, case .middleScroll(let scroll) = rule.trigger else { return false }
                return scroll == direction
            }) {
                let now = Date()
                if now.timeIntervalSince(lastShortcut) < 0.12 { return true }
                lastShortcut = now
                perform(rule, repeatable: true)
                return true
            }
            return true
        }
        return false
    }

    private func showMouseTrail(_ points: [CGPoint]) {
        guard box.snapshot().showTrail, points.count >= 2 else { return }
        let length = StrokeRecognizer.pathLength(StrokeRecognizer.cleanup(points))
        guard length >= RecognizeOptions.mouse.minGestureLength else {
            overlay.clear()
            return
        }
        overlay.show(points)
    }

    private func perform(_ rule: GestureRule, detail: String? = nil, repeatable: Bool = false) {
        if !repeatable {
            let now = Date()
            performLock.lock()
            let duplicate = rule.id == lastStrokeID && now.timeIntervalSince(lastStroke) < 0.4
            if !duplicate {
                lastStroke = now
                lastStrokeID = rule.id
            }
            performLock.unlock()
            if duplicate { return }
        }
        DispatchQueue.main.async {
            let message = ActionRunner.perform(rule.action) { keyCode, modifiers in
                self.postKey(keyCode, modifiers)
            }
            let prefix = detail.map { "\($0) → " } ?? ""
            self.model?.note("\(prefix)\(message)")
        }
    }

    private func postKey(_ keyCode: Int, _ modifiers: [ModifierKey]) {
        let source = CGEventSource(stateID: .hidSystemState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(keyCode), keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(keyCode), keyDown: false) else { return }
        let flags = cgFlags(modifiers)
        for event in [down, up] {
            event.flags = flags
            event.setIntegerValueField(.eventSourceUserData, value: Self.syntheticMarker)
            event.post(tap: .cghidEventTap)
        }
    }

    /// Sends the click that was held back. Down goes where the button was pressed,
    /// so a context menu opens in the right place. Up goes where it was released,
    /// so the pointer is not pulled back.
    private func replay(_ stroke: Stroke, source: Source, release: CGEvent) {
        let eventSource = CGEventSource(stateID: .hidSystemState)
        let downType: CGEventType = source == .right ? .rightMouseDown : .otherMouseDown
        let upType: CGEventType = source == .right ? .rightMouseUp : .otherMouseUp
        let button: CGMouseButton = source == .right ? .right : .center
        guard let down = CGEvent(mouseEventSource: eventSource, mouseType: downType, mouseCursorPosition: stroke.rawOrigin, mouseButton: button),
              let up = CGEvent(mouseEventSource: eventSource, mouseType: upType, mouseCursorPosition: release.location, mouseButton: button) else { return }
        for event in [down, up] {
            if source == .middle {
                event.setIntegerValueField(.mouseEventButtonNumber, value: 2)
            }
            event.flags = stroke.flags
            event.setIntegerValueField(.mouseEventClickState, value: 1)
            event.setIntegerValueField(.eventSourceUserData, value: Self.syntheticMarker)
            event.post(tap: .cgAnnotatedSessionEventTap)
        }
    }

    private func screenCorner(_ point: CGPoint, inset: CGFloat = 28) -> Corner? {
        Corner.at(point, in: box.snapshot().screenFrames, inset: inset)
    }

    private func location(of event: CGEvent, snap: ConfigSnapshot) -> CGPoint {
        let raw = event.location
        guard snap.primaryMaxY > 0 else { return raw }
        return CGPoint(x: raw.x, y: snap.primaryMaxY - raw.y)
    }

    private func modifierKeys(_ flags: CGEventFlags) -> [ModifierKey] {
        var keys: [ModifierKey] = []
        if flags.contains(.maskCommand) { keys.append(.command) }
        if flags.contains(.maskAlternate) { keys.append(.option) }
        if flags.contains(.maskControl) { keys.append(.control) }
        if flags.contains(.maskShift) { keys.append(.shift) }
        return keys
    }

    private func cgFlags(_ modifiers: [ModifierKey]) -> CGEventFlags {
        var flags = CGEventFlags()
        for modifier in modifiers {
            switch modifier {
            case .command: flags.insert(.maskCommand)
            case .option: flags.insert(.maskAlternate)
            case .control: flags.insert(.maskControl)
            case .shift: flags.insert(.maskShift)
            }
        }
        return flags
    }

    private func eventMask(_ types: [CGEventType]) -> CGEventMask {
        types.reduce(0) { $0 | (1 << $1.rawValue) }
    }
}

private func eventTapCallback(
    _ proxy: CGEventTapProxy,
    _ type: CGEventType,
    _ event: CGEvent,
    _ refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let controller = Unmanaged<EventController>.fromOpaque(refcon).takeUnretainedValue()
    return controller.handle(proxy: proxy, type: type, event: event)
}
