import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import GesturePadCore

enum ActionRunner {
    static func perform(_ action: GestureAction, postKey: (Int, [ModifierKey]) -> Void) -> String {
        switch action {
        case .openApp(let path, let bundleID):
            return openApp(path: path, bundleID: bundleID)
        case .openURL(let string):
            guard let url = URL(string: string) else { return "链接无效" }
            NSWorkspace.shared.open(url)
            return "打开 \(string)"
        case .openFolder(let path):
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
            return "打开 \(path)"
        case .shortcut(let keyCode, let modifiers, let title):
            postKey(keyCode, modifiers)
            return title
        case .window(let placement):
            return placeWindow(placement)
        case .lockScreen:
            postKey(12, [.command, .control])
            return "锁定屏幕"
        case .screensaver:
            let url = URL(fileURLWithPath: "/System/Library/CoreServices/ScreenSaverEngine.app")
            if FileManager.default.fileExists(atPath: url.path) {
                NSWorkspace.shared.open(url)
                return "启动屏保"
            }
            return "没有找到屏保程序"
        case .brightness(let delta):
            postMediaKey(delta > 0 ? 2 : 3)
            return delta > 0 ? "提高亮度" : "降低亮度"
        case .volume(let delta):
            postMediaKey(delta > 0 ? 0 : 1)
            return delta > 0 ? "提高音量" : "降低音量"
        case .newFinderWindow:
            NSWorkspace.shared.open(FileManager.default.homeDirectoryForCurrentUser)
            return "新建访达窗口"
        }
    }

    static func openApp(path: String, bundleID: String?) -> String {
        let fileURL = URL(fileURLWithPath: path)
        if FileManager.default.fileExists(atPath: path) {
            NSWorkspace.shared.open(fileURL)
            return "打开 \(displayName(fileURL))"
        }
        if let bundleID, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            NSWorkspace.shared.open(url)
            return "打开 \(displayName(url))"
        }
        let name = fileURL.deletingPathExtension().lastPathComponent
        return "没有找到 \(name)"
    }

    private static func displayName(_ url: URL) -> String {
        let name = FileManager.default.displayName(atPath: url.path)
        return name.hasSuffix(".app") ? String(name.dropLast(4)) : name
    }

    static func placeWindow(_ placement: WindowAction) -> String {
        guard AXIsProcessTrusted() else { return "移动窗口需要辅助功能权限" }
        guard let element = focusedWindow() else { return "没有可移动的窗口" }
        if placement == .minimize {
            let error = AXUIElementSetAttributeValue(element, kAXMinimizedAttribute as CFString, kCFBooleanTrue)
            return error == .success ? placement.title : "最小化失败"
        }
        guard let screen = screenUnderMouse() else { return "没有找到屏幕" }
        let frame = frame(for: placement, on: screen, window: element)
        guard setFrame(frame, on: element) else { return "窗口拒绝调整大小" }
        return placement.title
    }

    private static func focusedWindow() -> AXUIElement? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, kAXFocusedWindowAttribute as CFString, &value)
        guard error == .success, let value else { return nil }
        return (value as! AXUIElement)
    }

    private static func screenUnderMouse() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
    }

    private static func frame(for placement: WindowAction, on screen: NSScreen, window: AXUIElement) -> CGRect {
        let visible = screen.visibleFrame
        let halfWidth = visible.width / 2
        let halfHeight = visible.height / 2
        switch placement {
        case .leftHalf:
            return CGRect(x: visible.minX, y: visible.minY, width: halfWidth, height: visible.height)
        case .rightHalf:
            return CGRect(x: visible.midX, y: visible.minY, width: halfWidth, height: visible.height)
        case .topHalf:
            return CGRect(x: visible.minX, y: visible.midY, width: visible.width, height: halfHeight)
        case .bottomHalf:
            return CGRect(x: visible.minX, y: visible.minY, width: visible.width, height: halfHeight)
        case .topLeft:
            return CGRect(x: visible.minX, y: visible.midY, width: halfWidth, height: halfHeight)
        case .topRight:
            return CGRect(x: visible.midX, y: visible.midY, width: halfWidth, height: halfHeight)
        case .bottomLeft:
            return CGRect(x: visible.minX, y: visible.minY, width: halfWidth, height: halfHeight)
        case .bottomRight:
            return CGRect(x: visible.midX, y: visible.minY, width: halfWidth, height: halfHeight)
        case .maximize:
            return visible
        case .center:
            var size = currentSize(window) ?? CGSize(width: visible.width * 0.62, height: visible.height * 0.7)
            if size.width > visible.width * 0.92 || size.height > visible.height * 0.92 {
                size = CGSize(width: visible.width * 0.62, height: visible.height * 0.7)
            }
            return CGRect(
                x: visible.midX - size.width / 2,
                y: visible.midY - size.height / 2,
                width: size.width,
                height: size.height
            )
        case .minimize:
            return visible
        }
    }

    private static func currentSize(_ window: AXUIElement) -> CGSize? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &value) == .success,
              let value else { return nil }
        var size = CGSize.zero
        let ax = value as! AXValue
        guard AXValueGetType(ax) == .cgSize, AXValueGetValue(ax, .cgSize, &size) else { return nil }
        return size
    }

    /// Accessibility window coordinates start at the top-left of the primary display.
    private static func setFrame(_ appKit: CGRect, on window: AXUIElement) -> Bool {
        let primary = NSScreen.screens.first?.frame ?? appKit
        var position = CGPoint(x: appKit.origin.x, y: primary.maxY - appKit.maxY)
        var size = appKit.size
        guard let positionValue = AXValueCreate(.cgPoint, &position),
              let sizeValue = AXValueCreate(.cgSize, &size) else { return false }
        let sizeError = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        let positionError = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, positionValue)
        _ = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        return sizeError == .success && positionError == .success
    }

    /// System-defined media keys. 0 sound up, 1 sound down, 2 brightness up, 3 brightness down.
    private static func postMediaKey(_ key: Int32) {
        func post(_ down: Bool) {
            let flags = NSEvent.ModifierFlags(rawValue: UInt(down ? 0xA00 : 0xB00))
            let data1 = Int((key << 16) | Int32(down ? 0xA00 : 0xB00))
            guard let event = NSEvent.otherEvent(
                with: .systemDefined,
                location: .zero,
                modifierFlags: flags,
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: 0,
                context: nil,
                subtype: 8,
                data1: data1,
                data2: -1
            ) else { return }
            event.cgEvent?.post(tap: .cghidEventTap)
        }
        post(true)
        post(false)
    }
}
