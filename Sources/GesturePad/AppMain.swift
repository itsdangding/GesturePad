import AppKit
import Combine
import SwiftUI

final class SettingsWindow {
    private var window: NSWindow?
    private let model: AppModel
    private let initialPane: Pane

    init(model: AppModel, initialPane: Pane = .overview) {
        self.model = model
        self.initialPane = initialPane
    }

    func show() {
        if window == nil {
            let host = NSHostingController(rootView: SettingsView(model: model, pane: initialPane))
            host.sceneBridgingOptions = [.toolbars, .title]
            let window = NSWindow(contentViewController: FrostedController(content: host))
            window.title = "快捷手势"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            window.toolbarStyle = .unified
            window.isReleasedWhenClosed = false
            // Clear so the frosted backdrop can show the desktop behind it.
            window.isOpaque = false
            window.backgroundColor = .clear
            window.titlebarAppearsTransparent = true
            window.setContentSize(NSSize(width: 880, height: 640))
            window.contentMinSize = NSSize(width: 760, height: 600)
            window.center()
            // Restores the last size and position, if there is one.
            window.setFrameAutosaveName("GesturePadSettings")
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    var windowNumber: Int { window?.windowNumber ?? 0 }
}

/// Puts a frosted, behind-window blur under the SwiftUI content,
/// so the desktop shows through softly. SwiftUI clears its own window
/// background (see `frostedWindow()`), and this view fills the gap.
final class FrostedController: NSViewController {
    private let content: NSViewController

    init(content: NSViewController) {
        self.content = content
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { nil }

    override func loadView() {
        let effect = NSVisualEffectView()
        effect.material = .underWindowBackground
        effect.blendingMode = .behindWindow
        effect.state = .followsWindowActiveState
        view = effect
        // Most of the window color comes from this layer; the blur only tints it.
        let calm = CalmTintView(frame: effect.bounds)
        calm.autoresizingMask = [.width, .height]
        effect.addSubview(calm)
        addChild(content)
        content.view.frame = effect.bounds
        content.view.autoresizingMask = [.width, .height]
        effect.addSubview(content.view)
    }

    override var title: String? {
        get { content.title }
        set { content.title = newValue }
    }

    override var preferredContentSize: NSSize {
        get { content.preferredContentSize }
        set { content.preferredContentSize = newValue }
    }
}

/// The window background color at partial opacity, redrawn when the
/// appearance changes, so the frosted window stays calm in light and dark.
final class CalmTintView: NSView {
    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.62).cgColor
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let model = AppModel()
    private var statusItem: NSStatusItem?
    private var enabledWatch: AnyCancellable?
    private var settings: SettingsWindow?
    #if DEBUG
    private var testBackdrop: NSWindow?
    #endif

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        if let name = ProcessInfo.processInfo.environment["GESTUREPAD_PREVIEW"] {
            startPreview(Pane(previewName: name) ?? .overview)
            return
        }
        #endif
        settings = SettingsWindow(model: model)
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = MenuGlyph.image()
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        item.menu = menu
        statusItem = item
        // A paused app shows a dimmed menu bar icon.
        enabledWatch = model.$enabled.sink { [weak item] enabled in
            item?.button?.appearsDisabled = !enabled
        }
        model.start()
        if !model.accessibilityTrusted {
            settings?.show()
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        menu.removeAllItems()
        let statusSymbol: String
        if !model.accessibilityTrusted {
            statusSymbol = "exclamationmark.triangle"
        } else {
            statusSymbol = model.enabled ? "checkmark.circle" : "pause.circle"
        }
        let status = NSMenuItem(title: model.status, action: nil, keyEquivalent: "")
        status.image = symbol(statusSymbol)
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())
        menu.addItem(item("打开设置…", "gearshape", #selector(openSettings), key: ","))
        menu.addItem(item(model.enabled ? "暂停手势" : "继续手势",
                          model.enabled ? "pause.fill" : "play.fill",
                          #selector(toggleEnabled)))
        menu.addItem(.separator())
        menu.addItem(item("退出快捷手势", "power", #selector(quit), key: "q"))
    }

    private func item(_ title: String, _ symbolName: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        item.image = symbol(symbolName)
        return item
    }

    private func symbol(_ name: String) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)
    }

    @objc private func openSettings() {
        settings?.show()
    }

    @objc private func toggleEnabled() {
        model.setEnabled(!model.enabled)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    #if DEBUG
    /// Opens the settings window with sample state and no event tap,
    /// so the UI can be screenshotted next to an installed copy.
    /// Usage: GESTUREPAD_PREVIEW=mouse swift run
    private func startPreview(_ pane: Pane) {
        model.loadPreviewState()
        if ProcessInfo.processInfo.environment["GESTUREPAD_PREVIEW_DARK"] != nil {
            NSApp.appearance = NSAppearance(named: .darkAqua)
        }
        if ProcessInfo.processInfo.environment["GESTUREPAD_PREVIEW_TRAIL"] != nil {
            showTestTrail()
        }
        if ProcessInfo.processInfo.environment["GESTUREPAD_PREVIEW_BACKDROP"] != nil {
            showTestBackdrop()
        }
        let window = SettingsWindow(model: model, initialPane: pane)
        settings = window
        window.show()
        print("GESTUREPAD_WINDOW \(window.windowNumber)")
        fflush(stdout)
    }
    /// Draws a hand-wobbly W on screen with the real overlay.
    private func showTestTrail() {
        guard let screen = NSScreen.main else { return }
        let origin = CGPoint(x: screen.frame.midX - 160, y: screen.frame.midY + 120)
        let corners: [CGPoint] = [(0, 0), (70, -220), (160, -70), (250, -220), (320, 0)].map { CGPoint(x: $0.0, y: $0.1) }
        var points: [CGPoint] = []
        for index in 0..<(corners.count - 1) {
            for step in 0..<24 {
                let t = CGFloat(step) / 24
                let a = corners[index], b = corners[index + 1]
                let wobble = sin(CGFloat(points.count) * 0.9) * 2.5
                points.append(CGPoint(x: origin.x + a.x + (b.x - a.x) * t + wobble, y: origin.y + a.y + (b.y - a.y) * t))
            }
        }
        points.append(CGPoint(x: origin.x + 320, y: origin.y))
        model.events.overlay.show(points)
    }

    /// A colorful window behind the settings window, to check the frosted look.
    private func showTestBackdrop() {
        guard let screen = NSScreen.main else { return }
        let frame = screen.frame
        let backdrop = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        backdrop.contentView = NSHostingView(rootView: TestBackdrop())
        backdrop.isReleasedWhenClosed = false
        backdrop.orderFront(nil)
        testBackdrop = backdrop
    }
    #endif
}

@main
struct GesturePadMain {
    static let delegate = AppDelegate()

    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.delegate = delegate
        app.run()
    }
}

#if DEBUG
private struct TestBackdrop: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.98, green: 0.62, blue: 0.42), Color(red: 0.86, green: 0.42, blue: 0.62),
                                    Color(red: 0.45, green: 0.45, blue: 0.86), Color(red: 0.35, green: 0.72, blue: 0.80)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            GeometryReader { proxy in
                let w = proxy.size.width, h = proxy.size.height
                Circle().fill(Color(red: 1, green: 0.85, blue: 0.4)).frame(width: w * 0.35).position(x: w * 0.22, y: h * 0.3)
                Circle().fill(Color(red: 0.95, green: 0.35, blue: 0.3)).frame(width: w * 0.28).position(x: w * 0.7, y: h * 0.25)
                Circle().fill(Color(red: 0.3, green: 0.8, blue: 0.6)).frame(width: w * 0.32).position(x: w * 0.6, y: h * 0.8)
                Circle().fill(Color(red: 0.4, green: 0.5, blue: 1)).frame(width: w * 0.25).position(x: w * 0.15, y: h * 0.85)
            }
            .blur(radius: 60)
        }
        .ignoresSafeArea()
    }
}
#endif
