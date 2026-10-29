import AppKit
import GesturePadCore
import SwiftUI

extension Color {
    static let brand = Color(nsColor: .gestureBrand)
}

// MARK: - Labels for groups and actions

extension RuleGroup {
    var shortTitle: String {
        switch self {
        case .mouse: return "鼠标右键"
        case .middle: return "鼠标中键"
        case .corner: return "屏幕四角"
        case .key: return "键盘"
        }
    }

    var symbol: String {
        switch self {
        case .mouse: return "computermouse"
        case .middle: return "computermouse.fill"
        case .corner: return "rectangle.inset.topleft.filled"
        case .key: return "keyboard"
        }
    }

    var hint: String {
        switch self {
        case .mouse:
            return "按住右键画一笔，松开才执行。只动一小段仍是普通右键。这一类全部关掉后，右键完全不经过快捷手势。"
        case .middle:
            return "按住中键画，或按住中键滚动。"
        case .corner:
            return "把指针推到屏幕角落，再单击右键或滚动鼠标滚轮。触控板双指滑动不会触发。"
        case .key:
            return "全局快捷键。⌥ 加方向键会占掉系统里按词移动光标，不需要就关掉。"
        }
    }
}

extension WindowAction {
    var symbol: String {
        switch self {
        case .leftHalf: return "rectangle.lefthalf.inset.filled"
        case .rightHalf: return "rectangle.righthalf.inset.filled"
        case .topHalf: return "rectangle.tophalf.inset.filled"
        case .bottomHalf: return "rectangle.bottomhalf.inset.filled"
        case .topLeft: return "rectangle.inset.topleft.filled"
        case .topRight: return "rectangle.inset.topright.filled"
        case .bottomLeft: return "rectangle.inset.bottomleft.filled"
        case .bottomRight: return "rectangle.inset.bottomright.filled"
        case .maximize: return "arrow.up.left.and.arrow.down.right"
        case .minimize: return "arrow.down.right.and.arrow.up.left"
        case .center: return "rectangle.center.inset.filled"
        }
    }
}

// MARK: - Glyphs

/// Draws a stroke with a dot where the pen goes down, like the app icon.
struct StrokeGlyph: View {
    let points: [CGPoint]
    var arrow = false
    var color: Color = .brand
    var lineWidth: CGFloat = 2.4

    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: lineWidth + 3, dy: lineWidth + 3)
            let fitted = StrokeSmoothing.chaikin(Self.fit(points, in: rect), iterations: 3)
            guard fitted.count >= 2 else { return }
            var path = Path()
            path.addLines(fitted)
            let style = StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
            context.stroke(path, with: .color(color), style: style)
            let start = fitted[0]
            let r = lineWidth * 1.35
            context.fill(Path(ellipseIn: CGRect(x: start.x - r, y: start.y - r, width: r * 2, height: r * 2)), with: .color(color))
            if arrow, let end = fitted.last {
                let before = fitted[fitted.count - 2]
                let angle = atan2(end.y - before.y, end.x - before.x)
                let length = lineWidth * 3
                var head = Path()
                head.move(to: CGPoint(x: end.x - length * cos(angle - .pi / 5), y: end.y - length * sin(angle - .pi / 5)))
                head.addLine(to: end)
                head.addLine(to: CGPoint(x: end.x - length * cos(angle + .pi / 5), y: end.y - length * sin(angle + .pi / 5)))
                context.stroke(head, with: .color(color), style: style)
            }
        }
    }

    /// Scales points into the rect, keeps their aspect ratio and flips y for drawing.
    static func fit(_ points: [CGPoint], in rect: CGRect) -> [CGPoint] {
        guard let first = points.first else { return [] }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        for p in points {
            minX = min(minX, p.x); maxX = max(maxX, p.x)
            minY = min(minY, p.y); maxY = max(maxY, p.y)
        }
        let width = maxX - minX
        let height = maxY - minY
        guard max(width, height) > 0.001 else { return [] }
        let scale = min(rect.width / max(width, 0.001), rect.height / max(height, 0.001))
        let offsetX = rect.minX + (rect.width - width * scale) / 2
        let offsetY = rect.minY + (rect.height - height * scale) / 2
        return points.map { p in
            CGPoint(x: offsetX + (p.x - minX) * scale, y: offsetY + (maxY - p.y) * scale)
        }
    }
}

/// A small screen outline with one corner lit.
struct CornerGlyph: View {
    let corner: Corner
    var color: Color = .brand

    var body: some View {
        ZStack(alignment: corner.alignment) {
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(color.opacity(0.55), lineWidth: 1.5)
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
                .padding(3.5)
        }
        .frame(width: 28, height: 20)
    }
}

extension Corner {
    var alignment: Alignment {
        switch self {
        case .topLeft: return .topLeading
        case .topRight: return .topTrailing
        case .bottomLeft: return .bottomLeading
        case .bottomRight: return .bottomTrailing
        }
    }
}

/// The left-hand thumbnail of a rule row: what you do.
struct TriggerGlyph: View {
    let rule: GestureRule
    var active = true

    private var tint: Color { active ? .brand : .secondary }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(tint.opacity(active ? 0.11 : 0.08))
            content
        }
        .frame(width: 40, height: 40)
    }

    @ViewBuilder private var content: some View {
        switch rule.trigger {
        case .rightStroke(let name), .middleStroke(let name):
            if let sample = rule.userSamples.last?.map(\.point) {
                // The user's own way of writing it, smoothed.
                StrokeGlyph(points: sample, color: tint, lineWidth: 2.2)
                    .padding(3)
            } else {
                LetterGlyph(name: name, color: tint, lineWidth: 2.2)
                    .padding(3)
            }
        case .rightScroll(let direction, _), .middleScroll(let direction):
            HStack(spacing: 1) {
                Image(systemName: "computermouse")
                    .font(.system(size: 15, weight: .regular))
                Image(systemName: direction == .up ? "arrow.up" : "arrow.down")
                    .font(.system(size: 10, weight: .bold))
            }
            .foregroundStyle(tint)
        case .hotCornerClick(let corner):
            CornerGlyph(corner: corner, color: tint)
        case .hotCornerScroll(let corner, let direction):
            ZStack {
                CornerGlyph(corner: corner, color: tint)
                Image(systemName: direction == .up ? "arrow.up" : "arrow.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(tint)
            }
        case .hotkey(let keyCode, let modifiers):
            Text(KeyNames.combo(keyCode: keyCode, modifiers: modifiers))
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(tint)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .padding(.horizontal, 3)
        }
    }
}

/// The right-hand chip of a rule row: what happens.
struct ActionBadge: View {
    let action: GestureAction

    var body: some View {
        if case .shortcut(let keyCode, let modifiers, _) = action {
            KeyCap(text: KeyNames.combo(keyCode: keyCode, modifiers: modifiers))
                .help(action.title)
        } else {
            chip
        }
    }

    private var chip: some View {
        HStack(spacing: 6) {
            icon
            if !label.isEmpty {
                Text(label)
                    .lineLimit(1)
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .help(action.title)
    }

    private var label: String {
        switch action {
        case .shortcut(let keyCode, let modifiers, _):
            return KeyNames.combo(keyCode: keyCode, modifiers: modifiers)
        case .openApp(let path, let bundleID):
            return AppIcon.displayName(path: path, bundleID: bundleID)
        case .openURL(let string):
            return URL(string: string)?.host ?? string
        case .openFolder(let path):
            return URL(fileURLWithPath: path).lastPathComponent
        default:
            // The rule title already says it. The symbol is enough here.
            return ""
        }
    }

    @ViewBuilder private var icon: some View {
        switch action {
        case .openApp(let path, let bundleID):
            AppIcon(path: path, bundleID: bundleID)
        default:
            Image(systemName: symbol)
                .frame(width: 18)
        }
    }

    private var symbol: String {
        switch action {
        case .openURL: return "link"
        case .openFolder: return "folder"
        case .window(let placement): return placement.symbol
        case .lockScreen: return "lock"
        case .screensaver: return "sparkles.tv"
        case .brightness(let delta): return delta > 0 ? "sun.max" : "sun.min"
        case .volume(let delta): return delta > 0 ? "speaker.wave.3" : "speaker.wave.1"
        case .newFinderWindow: return "macwindow.badge.plus"
        case .openApp, .shortcut: return "app"
        }
    }
}

struct AppIcon: View {
    let path: String
    let bundleID: String?

    var body: some View {
        Image(nsImage: Self.icon(path: path, bundleID: bundleID))
            .resizable()
            .frame(width: 18, height: 18)
    }

    private static var cache: [String: NSImage] = [:]

    /// The name Finder shows, so 微信 rather than WeChat on a Chinese system.
    static func displayName(path: String, bundleID: String?) -> String {
        var target = path
        if !FileManager.default.fileExists(atPath: path),
           let bundleID, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            target = url.path
        }
        guard FileManager.default.fileExists(atPath: target) else {
            return URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        }
        let name = FileManager.default.displayName(atPath: target)
        return name.hasSuffix(".app") ? String(name.dropLast(4)) : name
    }

    static func icon(path: String, bundleID: String?) -> NSImage {
        if let cached = cache[path] { return cached }
        var image: NSImage
        if FileManager.default.fileExists(atPath: path) {
            image = NSWorkspace.shared.icon(forFile: path)
        } else if let bundleID, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            image = NSWorkspace.shared.icon(forFile: url.path)
        } else {
            image = NSWorkspace.shared.icon(for: .applicationBundle)
        }
        cache[path] = image
        return image
    }
}

/// A keyboard key, for shortcut actions.
struct KeyCap: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .shadow(color: .black.opacity(0.18), radius: 0, y: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.12))
            )
    }
}

/// A rounded pill used for short states such as "未安装".
struct Tag: View {
    let text: String
    var tint: Color = .secondary

    init(_ text: String, tint: Color = .secondary) {
        self.text = text
        self.tint = tint
    }

    var body: some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(tint.opacity(0.12), in: Capsule())
    }
}

struct StatusDot: View {
    let color: Color

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .overlay(Circle().stroke(color.opacity(0.3), lineWidth: 3))
    }
}

/// The brand mark drawn in code, for builds that run without an app bundle.
struct BrandMark: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
            Canvas { context, size in
                let s = size.width / 100
                var path = Path()
                path.move(to: CGPoint(x: 74 * s, y: 24 * s))
                path.addCurve(
                    to: CGPoint(x: 22 * s, y: 72 * s),
                    control1: CGPoint(x: 72 * s, y: 56 * s),
                    control2: CGPoint(x: 40 * s, y: 74 * s)
                )
                context.stroke(path, with: .color(.brand), style: StrokeStyle(lineWidth: 9 * s, lineCap: .round))
                context.fill(Path(ellipseIn: CGRect(x: 68.5 * s, y: 18.5 * s, width: 11 * s, height: 11 * s)), with: .color(.primary))
            }
            .padding(6)
        }
    }
}

struct AppIconView: View {
    var size: CGFloat = 56

    var body: some View {
        Group {
            if Bundle.main.bundleURL.pathExtension == "app" {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
            } else {
                BrandMark()
            }
        }
        .frame(width: size, height: size)
    }
}
