import CoreGraphics
import Foundation

public enum ModifierKey: String, Codable, Equatable, CaseIterable {
    case command
    case option
    case control
    case shift

    public var symbol: String {
        switch self {
        case .command: return "⌘"
        case .option: return "⌥"
        case .control: return "⌃"
        case .shift: return "⇧"
        }
    }
}

public enum WindowAction: String, Codable, Equatable, CaseIterable {
    case leftHalf
    case rightHalf
    case topHalf
    case bottomHalf
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight
    case maximize
    case minimize
    case center

    public var title: String {
        switch self {
        case .leftHalf: return "窗口靠左半屏"
        case .rightHalf: return "窗口靠右半屏"
        case .topHalf: return "窗口靠上半屏"
        case .bottomHalf: return "窗口靠下半屏"
        case .topLeft: return "窗口左上四分之一"
        case .topRight: return "窗口右上四分之一"
        case .bottomLeft: return "窗口左下四分之一"
        case .bottomRight: return "窗口右下四分之一"
        case .maximize: return "窗口最大化"
        case .minimize: return "窗口最小化"
        case .center: return "窗口居中"
        }
    }
}

public enum GestureAction: Codable, Equatable {
    case openApp(path: String, bundleID: String?)
    case openURL(String)
    case openFolder(String)
    case shortcut(keyCode: Int, modifiers: [ModifierKey], title: String)
    case window(WindowAction)
    case lockScreen
    case screensaver
    case brightness(Int)
    case volume(Int)
    case newFinderWindow

    public var title: String {
        switch self {
        case .openApp(let path, _):
            return "打开 \(URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent)"
        case .openURL(let url):
            return "打开 \(url)"
        case .openFolder(let path):
            return "打开 \(URL(fileURLWithPath: path).lastPathComponent)"
        case .shortcut(_, _, let title):
            return title
        case .window(let action):
            return action.title
        case .lockScreen:
            return "锁定屏幕"
        case .screensaver:
            return "启动屏保"
        case .brightness(let delta):
            return delta > 0 ? "提高亮度" : "降低亮度"
        case .volume(let delta):
            return delta > 0 ? "提高音量" : "降低音量"
        case .newFinderWindow:
            return "新建访达窗口"
        }
    }
}

public enum Corner: String, Codable, Equatable, CaseIterable {
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight

    public var title: String {
        switch self {
        case .topLeft: return "左上角"
        case .topRight: return "右上角"
        case .bottomLeft: return "左下角"
        case .bottomRight: return "右下角"
        }
    }

    /// The screen corner a point sits in. Frames and point use AppKit
    /// coordinates, where y grows upward.
    public static func at(_ point: CGPoint, in frames: [CGRect], inset: CGFloat = 28) -> Corner? {
        for frame in frames {
            let left = point.x <= frame.minX + inset
            let right = point.x >= frame.maxX - inset
            let bottom = point.y <= frame.minY + inset
            let top = point.y >= frame.maxY - inset
            if top && left { return .topLeft }
            if top && right { return .topRight }
            if bottom && left { return .bottomLeft }
            if bottom && right { return .bottomRight }
        }
        return nil
    }
}

public enum ScrollDirection: String, Codable, Equatable, CaseIterable {
    case up
    case down

    public var title: String {
        self == .up ? "向上滚" : "向下滚"
    }
}

public enum Trigger: Codable, Equatable {
    case rightStroke(StrokeName)
    case middleStroke(StrokeName)
    case rightScroll(ScrollDirection, bundleID: String?)
    case middleScroll(ScrollDirection)
    case hotCornerClick(Corner)
    case hotCornerScroll(Corner, ScrollDirection)
    case hotkey(keyCode: Int, modifiers: [ModifierKey])

    public var summary: String {
        switch self {
        case .rightStroke(let name):
            return "按住右键画\(name.title)"
        case .middleStroke(let name):
            return "按住中键画\(name.title)"
        case .rightScroll(let direction, let bundleID):
            let whereText = bundleID.map { "在 \(KnownApps.name(for: $0)) 里" } ?? ""
            return "\(whereText)按住右键\(direction.title)"
        case .middleScroll(let direction):
            return "按住中键\(direction.title)"
        case .hotCornerClick(let corner):
            return "在屏幕\(corner.title)右键单击"
        case .hotCornerScroll(let corner, let direction):
            return "指针在屏幕\(corner.title)时\(direction.title)"
        case .hotkey(let keyCode, let modifiers):
            return "按 " + KeyNames.combo(keyCode: keyCode, modifiers: modifiers)
        }
    }
}

/// Display names for virtual key codes on an ANSI layout.
public enum KeyNames {
    private static let names: [Int: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
        11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T",
        18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9", 26: "7",
        27: "-", 28: "8", 29: "0", 30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P",
        36: "↩", 37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/",
        45: "N", 46: "M", 47: ".", 48: "⇥", 49: "空格", 50: "`", 51: "⌫", 53: "⎋",
        123: "←", 124: "→", 125: "↓", 126: "↑"
    ]

    public static func name(for keyCode: Int) -> String {
        names[keyCode] ?? "键 \(keyCode)"
    }

    /// Modifiers in the order macOS menus use: ⌃ ⌥ ⇧ ⌘.
    public static func combo(keyCode: Int, modifiers: [ModifierKey]) -> String {
        let order: [ModifierKey] = [.control, .option, .shift, .command]
        let symbols = order.filter(modifiers.contains).map(\.symbol).joined()
        return symbols + name(for: keyCode)
    }
}

/// Short names for apps that rules can be scoped to.
public enum KnownApps {
    public static func name(for bundleID: String) -> String {
        switch bundleID {
        case "company.thebrowser.dia": return "Dia"
        case "com.google.Chrome": return "Chrome"
        case "com.apple.Safari": return "Safari"
        default: return bundleID
        }
    }
}

public struct GestureRule: Codable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var enabled: Bool
    public var trigger: Trigger
    public var action: GestureAction
    public var userSamples: [[SamplePoint]]

    public init(
        id: String,
        title: String,
        enabled: Bool = true,
        trigger: Trigger,
        action: GestureAction,
        userSamples: [[SamplePoint]] = []
    ) {
        self.id = id
        self.title = title
        self.enabled = enabled
        self.trigger = trigger
        self.action = action
        self.userSamples = userSamples
    }

    public var strokeName: StrokeName? {
        switch trigger {
        case .rightStroke(let name), .middleStroke(let name):
            return name
        default:
            return nil
        }
    }
}

public struct SamplePoint: Codable, Equatable {
    public var x: Double
    public var y: Double

    public init(_ point: CGPoint) {
        x = Double(point.x)
        y = Double(point.y)
    }

    public var point: CGPoint {
        CGPoint(x: x, y: y)
    }
}

public enum RuleGroup: String, CaseIterable {
    case mouse = "鼠标右键"
    case middle = "鼠标中键"
    case corner = "屏幕四角"
    case key = "键盘"

    public static func group(of trigger: Trigger) -> RuleGroup {
        switch trigger {
        case .rightStroke, .rightScroll:
            return .mouse
        case .middleStroke, .middleScroll:
            return .middle
        case .hotCornerClick, .hotCornerScroll:
            return .corner
        case .hotkey:
            return .key
        }
    }
}

public enum BuiltinRules {
    public static let all: [GestureRule] = mouse + middle + corners + keys

    private static let wechat = "/Applications/WeChat.app"
    private static let vscode = "/Applications/Visual Studio Code.app"
    private static let activity = "/System/Applications/Utilities/Activity Monitor.app"
    private static let settings = "/System/Applications/System Settings.app"

    private static let mouse: [GestureRule] = [
        rule("mouse.w", "打开微信", .rightStroke(.w), .openApp(path: wechat, bundleID: "com.tencent.xinWeChat")),
        rule("mouse.h", "打开活动监视器", .rightStroke(.h), .openApp(path: activity, bundleID: "com.apple.ActivityMonitor")),
        rule("mouse.l", "关闭窗口", .rightStroke(.l), .shortcut(keyCode: 13, modifiers: [.command], title: "关闭窗口 ⌘W")),
        rule("mouse.p", "打开系统设置", .rightStroke(.p), .openApp(path: settings, bundleID: "com.apple.systempreferences")),
        rule("mouse.left", "后退", .rightStroke(.arrowLeft), .shortcut(keyCode: 33, modifiers: [.command], title: "后退 ⌘[")),
        rule("mouse.right", "前进", .rightStroke(.arrowRight), .shortcut(keyCode: 30, modifiers: [.command], title: "前进 ⌘]")),
        rule("mouse.v", "打开 Visual Studio Code", .rightStroke(.v), .openApp(path: vscode, bundleID: "com.microsoft.VSCode")),
        rule("mouse.up-right", "最大化", .rightStroke(.diagonalUpRight), .window(.maximize)),
        rule("mouse.down-left", "最小化", .rightStroke(.diagonalDownLeft), .window(.minimize)),
        rule("mouse.down", "复制", .rightStroke(.arrowDown), .shortcut(keyCode: 8, modifiers: [.command], title: "复制 ⌘C")),
        rule("mouse.up", "粘贴", .rightStroke(.arrowUp), .shortcut(keyCode: 9, modifiers: [.command], title: "粘贴 ⌘V")),
        rule("mouse.d", "新建访达窗口", .rightStroke(.d), .newFinderWindow),
        rule(
            "pad.dia.scroll-up",
            "Dia 上一标签",
            .rightScroll(.up, bundleID: "company.thebrowser.dia"),
            .shortcut(keyCode: 48, modifiers: [.control, .shift], title: "上一标签 ⌃⇧⇥")
        ),
        rule(
            "pad.dia.scroll-down",
            "Dia 下一标签",
            .rightScroll(.down, bundleID: "company.thebrowser.dia"),
            .shortcut(keyCode: 48, modifiers: [.control], title: "下一标签 ⌃⇥")
        )
    ]

    private static let middle: [GestureRule] = [
        rule("middle.s", "锁定屏幕", .middleStroke(.s), .lockScreen),
        rule("middle.scroll-up", "上一个标签", .middleScroll(.up), .shortcut(keyCode: 48, modifiers: [.control, .shift], title: "上一个标签 ⌃⇧⇥")),
        rule("middle.scroll-down", "下一个标签", .middleScroll(.down), .shortcut(keyCode: 48, modifiers: [.control], title: "下一个标签 ⌃⇥"))
    ]

    private static let corners: [GestureRule] = [
        rule("corner.tl", "屏保", .hotCornerClick(.topLeft), .screensaver),
        rule("corner.tr", "锁定屏幕", .hotCornerClick(.topRight), .lockScreen),
        rule("corner.bl.up", "提高亮度", .hotCornerScroll(.bottomLeft, .up), .brightness(1)),
        rule("corner.bl.down", "降低亮度", .hotCornerScroll(.bottomLeft, .down), .brightness(-1)),
        rule("corner.br.up", "提高音量", .hotCornerScroll(.bottomRight, .up), .volume(1)),
        rule("corner.br.down", "降低音量", .hotCornerScroll(.bottomRight, .down), .volume(-1))
    ]

    private static let keys: [GestureRule] = [
        rule("key.up", "窗口靠上", .hotkey(keyCode: 126, modifiers: [.option]), .window(.topHalf)),
        rule("key.right", "窗口靠右", .hotkey(keyCode: 124, modifiers: [.option]), .window(.rightHalf)),
        rule("key.down", "窗口靠下", .hotkey(keyCode: 125, modifiers: [.option]), .window(.bottomHalf)),
        rule("key.left", "窗口靠左", .hotkey(keyCode: 123, modifiers: [.option]), .window(.leftHalf)),
        rule("key.a", "打开应用程序文件夹", .hotkey(keyCode: 0, modifiers: [.control, .option]), .openFolder("/Applications"))
    ]

    private static func rule(_ id: String, _ title: String, _ trigger: Trigger, _ action: GestureAction) -> GestureRule {
        GestureRule(id: id, title: title, trigger: trigger, action: action)
    }
}

public struct RuleFile: Codable, Equatable {
    /// 1: only enabled flags and strokes were saved, titles and actions came from the builtins.
    /// 2: the file holds every rule in full, including edited and user-made ones.
    public static let currentVersion = 2

    public var version: Int
    public var rules: [GestureRule]
    /// Builtin IDs this file has already seen. A builtin missing from `rules`
    /// but listed here was deleted on purpose. One not listed is new and gets added.
    public var knownBuiltinIDs: [String]?

    public init(version: Int = RuleFile.currentVersion, rules: [GestureRule], knownBuiltinIDs: [String]? = nil) {
        self.version = version
        self.rules = rules
        self.knownBuiltinIDs = knownBuiltinIDs
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        rules = try container.decode(LossyRules.self, forKey: .rules).rules
        knownBuiltinIDs = try container.decodeIfPresent([String].self, forKey: .knownBuiltinIDs)
    }
}

/// Decodes a rule list and skips rules this version no longer understands,
/// such as the trackpad gestures older versions saved.
struct LossyRules: Decodable {
    var rules: [GestureRule] = []

    private struct Skip: Decodable {}

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        while !container.isAtEnd {
            if let rule = try? container.decode(GestureRule.self) {
                rules.append(rule)
            } else {
                _ = try container.decode(Skip.self)
            }
        }
    }
}

public enum RuleStore {
    public static func fileURL(home: URL? = nil) -> URL {
        let base = home ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("GesturePad", isDirectory: true).appendingPathComponent("rules.json")
    }

    /// Reads a version 1 file: builtins stay in charge of titles and actions,
    /// the file only supplies enabled flags and recorded strokes.
    public static func merge(saved: [GestureRule], builtin: [GestureRule] = BuiltinRules.all) -> [GestureRule] {
        builtin.map { item in
            guard let previous = saved.first(where: { $0.id == item.id }) else { return item }
            var copy = item
            copy.enabled = previous.enabled
            copy.userSamples = Array(previous.userSamples.suffix(3))
            return copy
        }
    }

    /// Reads a version 2 file and appends builtins added since it was written.
    public static func upgrade(_ file: RuleFile, builtin: [GestureRule] = BuiltinRules.all) -> [GestureRule] {
        let known = Set(file.knownBuiltinIDs ?? file.rules.map(\.id))
        var rules = file.rules
        for item in builtin where !known.contains(item.id) && !rules.contains(where: { $0.id == item.id }) {
            rules.append(item)
        }
        for index in rules.indices {
            rules[index].userSamples = Array(rules[index].userSamples.suffix(3))
        }
        return rules
    }

    public static func load(from url: URL = fileURL()) -> [GestureRule] {
        guard let data = try? Data(contentsOf: url) else {
            return BuiltinRules.all
        }
        let decoder = JSONDecoder()
        if let file = try? decoder.decode(RuleFile.self, from: data) {
            return file.version >= 2 ? upgrade(file) : merge(saved: file.rules)
        }
        if let rules = try? decoder.decode(LossyRules.self, from: data).rules {
            return merge(saved: rules)
        }
        return BuiltinRules.all
    }

    public static func save(_ rules: [GestureRule], to url: URL = fileURL()) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = RuleFile(rules: rules, knownBuiltinIDs: BuiltinRules.all.map(\.id))
        let data = try JSONEncoder.pretty.encode(file)
        try data.write(to: url, options: .atomic)
    }

    /// Other enabled rules with the same trigger. Only the first one in the list runs.
    public static func conflicts(for rule: GestureRule, in rules: [GestureRule]) -> [GestureRule] {
        rules.filter { $0.id != rule.id && $0.enabled && $0.trigger == rule.trigger }
    }

    public static func newID() -> String {
        "custom." + UUID().uuidString.lowercased()
    }

    public static func isBuiltin(_ id: String) -> Bool {
        BuiltinRules.all.contains { $0.id == id }
    }

    public static func samples(in rules: [GestureRule]) -> [StrokeName: [[CGPoint]]] {
        var result: [StrokeName: [[CGPoint]]] = [:]
        for rule in rules {
            guard let name = rule.strokeName, name.isLetter else { continue }
            let samples = rule.userSamples.map { stroke in stroke.map(\.point) }
            result[name, default: []].append(contentsOf: samples)
        }
        return result
    }
}

private extension JSONEncoder {
    static let pretty: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()
}
