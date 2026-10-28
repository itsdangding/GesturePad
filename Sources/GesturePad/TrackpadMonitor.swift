import CoreGraphics
import Darwin
import Foundation
import GesturePadCore

/// Layout of a contact reported by the private MultitouchSupport framework.
/// The size and the normalized-vector offset are the stable part of the ABI.
struct MTPoint {
    var x: Float
    var y: Float
}

struct MTVector {
    var position: MTPoint
    var velocity: MTPoint
}

struct MTTouch {
    var frame: Int32
    var timestamp: Double
    var pathIndex: Int32
    var state: UInt32
    var fingerID: Int32
    var handID: Int32
    var normalized: MTVector
    var zTotal: Float
    var reserved9: Int32
    var angle: Float
    var majorAxis: Float
    var minorAxis: Float
    var absolute: MTVector
    var reserved14: Int32
    var reserved15: Int32
    var zDensity: Float
}

typealias MTFrameCallback = @convention(c) (
    OpaquePointer?,
    UnsafeMutableRawPointer?,
    Int,
    Double,
    Int,
    UnsafeMutableRawPointer?
) -> Void

private let mtFrameCallback: MTFrameCallback = { _, touches, count, _, _, refcon in
    guard let refcon else { return }
    let monitor = Unmanaged<TrackpadMonitor>.fromOpaque(refcon).takeUnretainedValue()
    monitor.handle(touches: touches, count: count)
}

/// Reads one-finger paths from the built-in trackpad.
/// Mouse drawing does not depend on this. If the private framework is missing,
/// trackpad letters and corner taps stay off and the rest of the app still runs.
final class TrackpadMonitor {
    var onStroke: (([CGPoint]) -> Void)?
    var onCorner: ((Corner) -> Void)?
    var onMove: (([CGPoint]) -> Void)?
    var onEnd: (() -> Void)?
    var readConfig: () -> (fn: Bool, fnRequired: Bool, flipY: Bool, enabled: Bool) = { (false, true, false, true) }

    private var framework: UnsafeMutableRawPointer?
    private var device: OpaquePointer?
    private var running = false
    private var tracking = false
    private var fnAtStart = false
    private var startX = 0.0
    private var startY = 0.0
    private var stroke: [CGPoint] = []
    private let touchLock = NSLock()
    private var lastMultiTouch: TimeInterval = 0
    private(set) var isAvailable = false

    /// Two or more fingers were on the trackpad a moment ago, so a smooth
    /// scroll event right now comes from the trackpad and not a mouse.
    var fingersRecentlyDown: Bool {
        touchLock.lock()
        defer { touchLock.unlock() }
        return ProcessInfo.processInfo.systemUptime - lastMultiTouch < 0.25
    }

    func start() -> String? {
        if MemoryLayout<MTTouch>.size != 96 || MemoryLayout.offset(of: \MTTouch.normalized) != 32 {
            return "触控板数据布局和系统对不上"
        }
        let path = "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport"
        guard let handle = dlopen(path, RTLD_NOW | RTLD_LOCAL) else {
            return "没有找到触控板接口"
        }
        framework = handle

        typealias Create = @convention(c) () -> OpaquePointer?
        typealias Register = @convention(c) (OpaquePointer?, MTFrameCallback, UnsafeMutableRawPointer?) -> Void
        typealias Start = @convention(c) (OpaquePointer?, Int32) -> Void
        typealias Running = @convention(c) (OpaquePointer?) -> Bool

        guard
            let create: Create = symbol(handle, "MTDeviceCreateDefault"),
            let register: Register = symbol(handle, "MTRegisterContactFrameCallbackWithRefcon"),
            let startDevice: Start = symbol(handle, "MTDeviceStart"),
            let isRunning: Running = symbol(handle, "MTDeviceIsRunning")
        else {
            return "触控板接口缺了必要函数"
        }

        guard let created = create() else {
            return "这台机器没有可用的内置触控板"
        }
        device = created
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        register(created, mtFrameCallback, refcon)
        startDevice(created, 0)
        running = isRunning(created)
        if !running {
            return "触控板接口没有开始回报手指"
        }
        isAvailable = true
        return nil
    }

    func handle(touches: UnsafeMutableRawPointer?, count: Int) {
        noteFingerCount(touches: touches, count: count)
        let config = readConfig()
        let armed = config.enabled && (config.fn || !config.fnRequired)
        guard config.enabled else {
            cancel()
            return
        }
        if !armed {
            if tracking { finish() }
            return
        }
        guard let touches, count > 0, count < 32 else {
            finish()
            return
        }

        var alive: [(x: Double, y: Double)] = []
        var sawLift = false
        for index in 0..<count {
            let touch = touches.advanced(by: index * MemoryLayout<MTTouch>.stride).load(as: MTTouch.self)
            guard touch.state == 3 || touch.state == 4 || touch.state == 5 else { continue }
            let x = Double(touch.normalized.position.x)
            var y = Double(touch.normalized.position.y)
            guard x.isFinite, y.isFinite, abs(x) < 4, abs(y) < 4 else { continue }
            if config.flipY {
                y = 1 - y
            }
            if touch.state == 5 {
                sawLift = true
                continue
            }
            alive.append((x, y))
        }

        if alive.count >= 2 {
            cancel()
            return
        }
        if let finger = alive.first {
            let point = CGPoint(x: finger.x * 1000, y: finger.y * 1000)
            if !tracking {
                tracking = true
                fnAtStart = config.fn
                startX = finger.x
                startY = finger.y
                stroke = [point]
            } else {
                stroke.append(point)
            }
            if stroke.count % 2 == 0 {
                onMove?(stroke)
            }
            return
        }
        if sawLift || alive.isEmpty {
            finish()
        }
    }

    /// Runs for every frame, whatever the gesture settings are.
    private func noteFingerCount(touches: UnsafeMutableRawPointer?, count: Int) {
        guard let touches, count >= 2, count < 32 else { return }
        var down = 0
        for index in 0..<count {
            let touch = touches.advanced(by: index * MemoryLayout<MTTouch>.stride).load(as: MTTouch.self)
            if touch.state == 3 || touch.state == 4 { down += 1 }
        }
        guard down >= 2 else { return }
        touchLock.lock()
        lastMultiTouch = ProcessInfo.processInfo.systemUptime
        touchLock.unlock()
    }

    private func finish() {
        guard tracking else { return }
        let points = stroke
        let fn = fnAtStart
        let origin = (x: startX, y: startY)
        tracking = false
        stroke = []

        let config = readConfig()
        let allowed = fn || !config.fnRequired
        guard allowed else {
            onEnd?()
            return
        }

        let dx = (points.last?.x ?? 0) - (points.first?.x ?? 0)
        let dy = (points.last?.y ?? 0) - (points.first?.y ?? 0)
        if hypot(dx, dy) < 80, fn, let corner = Self.corner(x: origin.x, y: origin.y) {
            onCorner?(corner)
            onEnd?()
            return
        }
        guard points.count >= 2 else {
            onEnd?()
            return
        }
        onStroke?(points)
        onEnd?()
    }

    private func cancel() {
        let wasTracking = tracking
        tracking = false
        stroke = []
        if wasTracking {
            onEnd?()
        }
    }

    static func corner(x: Double, y: Double) -> Corner? {
        let edge = 0.22
        let left = x < edge
        let right = x > 1 - edge
        let bottom = y < edge
        let top = y > 1 - edge
        if top && left { return .topLeft }
        if top && right { return .topRight }
        if bottom && left { return .bottomLeft }
        if bottom && right { return .bottomRight }
        return nil
    }

    private func symbol<T>(_ handle: UnsafeMutableRawPointer, _ name: String) -> T? {
        guard let pointer = dlsym(handle, name) else { return nil }
        return unsafeBitCast(pointer, to: T.self)
    }
}
