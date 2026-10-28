import AppKit
import QuartzCore

/// Draws the live stroke with Core Animation layers: a soft glow, the line
/// itself and a dot where it started. Points are smoothed into a curve so
/// pointer jitter does not show.
final class StrokeView: NSView {
    private let glow = CAShapeLayer()
    private let line = CAShapeLayer()
    private let dot = CAShapeLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = false
        let brand = NSColor.gestureBrand.cgColor

        glow.fillColor = nil
        glow.strokeColor = brand
        glow.opacity = 0.22
        glow.lineWidth = 14
        glow.lineCap = .round
        glow.lineJoin = .round

        line.fillColor = nil
        line.strokeColor = brand
        line.lineWidth = 4.5
        line.lineCap = .round
        line.lineJoin = .round
        line.shadowColor = NSColor.black.cgColor
        line.shadowOpacity = 0.18
        line.shadowRadius = 3
        line.shadowOffset = CGSize(width: 0, height: -1)

        dot.fillColor = brand
        dot.strokeColor = NSColor.white.cgColor
        dot.lineWidth = 2

        for sublayer in [glow, line, dot] {
            layer?.addSublayer(sublayer)
        }
    }

    required init?(coder: NSCoder) {
        nil
    }

    func update(_ points: [CGPoint]) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.removeAllAnimations()
        layer?.opacity = 1
        let path = Self.smoothPath(points)
        glow.path = path
        line.path = path
        if let start = points.first {
            dot.path = CGPath(ellipseIn: CGRect(x: start.x - 5.5, y: start.y - 5.5, width: 11, height: 11), transform: nil)
        } else {
            dot.path = nil
        }
        CATransaction.commit()
    }

    /// Fades the stroke out, then calls `done`.
    func fadeOut(_ done: @escaping () -> Void) {
        guard let layer, line.path != nil else {
            done()
            return
        }
        CATransaction.begin()
        CATransaction.setCompletionBlock(done)
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1
        fade.toValue = 0
        fade.duration = 0.22
        fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.opacity = 0
        layer.add(fade, forKey: "fade")
        CATransaction.commit()
    }

    func reset() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        glow.path = nil
        line.path = nil
        dot.path = nil
        layer?.removeAllAnimations()
        layer?.opacity = 1
        CATransaction.commit()
    }

    /// Catmull-Rom spline through thinned points, as cubic curves.
    static func smoothPath(_ raw: [CGPoint]) -> CGPath? {
        let points = StrokeSmoothing.thin(raw, spacing: 3)
        guard points.count >= 2 else { return nil }
        let path = CGMutablePath()
        path.move(to: points[0])
        guard points.count > 2 else {
            path.addLine(to: points[1])
            return path
        }
        for index in 0..<(points.count - 1) {
            let p0 = points[max(index - 1, 0)]
            let p1 = points[index]
            let p2 = points[index + 1]
            let p3 = points[min(index + 2, points.count - 1)]
            let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
            let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
            path.addCurve(to: p2, control1: c1, control2: c2)
        }
        return path
    }
}

/// A click-through window that draws the stroke on the screen under the pointer.
final class StrokeOverlay {
    private var window: NSWindow?
    private let canvas = StrokeView(frame: .zero)
    /// Bumped whenever a stroke starts, so a fade from the previous one
    /// does not hide the new one.
    private var generation = 0
    private var fading = false

    func show(_ screenPoints: [CGPoint]) {
        DispatchQueue.main.async {
            guard screenPoints.count >= 2, let screen = self.screen(containing: screenPoints[0]) else {
                self.clearNow()
                return
            }
            let window = self.window(for: screen)
            let local = screenPoints.map { CGPoint(x: $0.x - screen.frame.minX, y: $0.y - screen.frame.minY) }
            if self.fading {
                // A new stroke started while the last one was fading out.
                self.generation += 1
                self.fading = false
            }
            self.canvas.update(local)
            window.orderFrontRegardless()
        }
    }

    func clear() {
        DispatchQueue.main.async { self.clearNow() }
    }

    private func clearNow() {
        guard let window, window.isVisible else {
            canvas.reset()
            return
        }
        guard !fading else { return }
        fading = true
        let current = generation
        canvas.fadeOut { [weak self] in
            guard let self, self.generation == current else { return }
            self.fading = false
            self.canvas.reset()
            window.orderOut(nil)
        }
    }

    /// One window is reused and moved to whichever screen the stroke starts on.
    private func window(for screen: NSScreen) -> NSWindow {
        let panel = window ?? makeWindow(frame: screen.frame)
        if panel.frame != screen.frame {
            panel.setFrame(screen.frame, display: false)
            canvas.frame = NSRect(origin: .zero, size: screen.frame.size)
        }
        window = panel
        return panel
    }

    private func makeWindow(frame: NSRect) -> NSWindow {
        let panel = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.contentView = canvas
        canvas.frame = NSRect(origin: .zero, size: frame.size)
        return panel
    }

    private func screen(containing point: CGPoint) -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
    }
}

extension NSColor {
    /// The orange-red from the icon and the website.
    static let gestureBrand = NSColor(srgbRed: 0.83, green: 0.33, blue: 0.17, alpha: 1)
}
