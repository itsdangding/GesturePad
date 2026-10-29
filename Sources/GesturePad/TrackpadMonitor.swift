import CoreGraphics
import Darwin
import Foundation

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

/// Watches whether fingers are on the built-in trackpad, so scroll events and
/// right clicks can be told apart from a mouse. It does not read gestures.
/// If the private framework is missing, the app falls back to event fields.
final class TrackpadMonitor {
    private var framework: UnsafeMutableRawPointer?
    private var device: OpaquePointer?
    private let touchLock = NSLock()
    private var lastMultiTouch: TimeInterval = 0
    private var lastTouch: TimeInterval = 0
    private(set) var isAvailable = false

    /// Two or more fingers were on the trackpad a moment ago, so a smooth
    /// scroll event right now comes from the trackpad and not a mouse.
    var fingersRecentlyDown: Bool {
        touchLock.lock()
        defer { touchLock.unlock() }
        return ProcessInfo.processInfo.systemUptime - lastMultiTouch < 0.25
    }

    /// A finger was on the trackpad a moment ago. A right click right now is a
    /// trackpad secondary click (two-finger click or tap, or a corner click).
    /// Tap-to-click fires after the fingers lift, hence the short grace period.
    var fingerRecentlyDown: Bool {
        touchLock.lock()
        defer { touchLock.unlock() }
        return ProcessInfo.processInfo.systemUptime - lastTouch < 0.3
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
        if !isRunning(created) {
            return "触控板接口没有开始回报手指"
        }
        isAvailable = true
        return nil
    }

    func handle(touches: UnsafeMutableRawPointer?, count: Int) {
        guard let touches, count >= 1, count < 32 else { return }
        var down = 0
        for index in 0..<count {
            let touch = touches.advanced(by: index * MemoryLayout<MTTouch>.stride).load(as: MTTouch.self)
            if touch.state == 3 || touch.state == 4 { down += 1 }
        }
        guard down >= 1 else { return }
        let now = ProcessInfo.processInfo.systemUptime
        touchLock.lock()
        lastTouch = now
        if down >= 2 { lastMultiTouch = now }
        touchLock.unlock()
    }

    private func symbol<T>(_ handle: UnsafeMutableRawPointer, _ name: String) -> T? {
        guard let pointer = dlsym(handle, name) else { return nil }
        return unsafeBitCast(pointer, to: T.self)
    }
}
