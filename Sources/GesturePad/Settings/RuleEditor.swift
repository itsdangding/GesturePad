import AppKit
import GesturePadCore
import SwiftUI
import UniformTypeIdentifiers

struct KeyCombo: Equatable {
    var keyCode: Int
    var modifiers: [ModifierKey]

    var text: String { KeyNames.combo(keyCode: keyCode, modifiers: modifiers) }
}

enum TriggerKind: String, CaseIterable, Identifiable {
    case rightStroke, middleStroke
    case rightScroll, middleScroll, hotCornerClick, hotCornerScroll, hotkey

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rightStroke: return "按住右键画"
        case .middleStroke: return "按住中键画"
        case .rightScroll: return "按住右键滚动滚轮"
        case .middleScroll: return "按住中键滚动滚轮"
        case .hotCornerClick: return "在屏幕角落单击右键"
        case .hotCornerScroll: return "在屏幕角落滚动滚轮"
        case .hotkey: return "键盘快捷键"
        }
    }

    static func defaultKind(for group: RuleGroup) -> TriggerKind {
        switch group {
        case .mouse: return .rightStroke
        case .middle: return .middleStroke
        case .corner: return .hotCornerClick
        case .key: return .hotkey
        }
    }
}

enum ActionKind: String, CaseIterable, Identifiable {
    case openApp, openURL, openFolder, shortcut, window
    case lockScreen, screensaver, brightness, volume, newFinderWindow

    var id: String { rawValue }

    var title: String {
        switch self {
        case .openApp: return "打开应用"
        case .openURL: return "打开网址"
        case .openFolder: return "打开文件夹"
        case .shortcut: return "发送快捷键"
        case .window: return "摆放当前窗口"
        case .lockScreen: return "锁定屏幕"
        case .screensaver: return "启动屏保"
        case .brightness: return "调节亮度"
        case .volume: return "调节音量"
        case .newFinderWindow: return "新建访达窗口"
        }
    }
}

/// Every field the editor can show, so switching kinds back and forth keeps what was typed.
struct RuleDraft {
    var id: String
    var title: String
    var enabled: Bool
    var userSamples: [[SamplePoint]]

    var triggerKind: TriggerKind
    var stroke: StrokeName = .arrowLeft
    var corner: Corner = .topLeft
    var scroll: ScrollDirection = .up
    var scrollBundleID: String?
    var hotkey: KeyCombo?

    var actionKind: ActionKind = .openApp
    var appPath: String?
    var appBundleID: String?
    var url = "https://"
    var folder: String?
    var shortcut: KeyCombo?
    var window: WindowAction = .leftHalf
    var increase = true

    /// A blank rule for a group. Picks a stroke or corner nothing else uses yet.
    init(newIn group: RuleGroup, existing: [GestureRule]) {
        id = RuleStore.newID()
        title = ""
        enabled = true
        userSamples = []
        triggerKind = TriggerKind.defaultKind(for: group)
        let used = Set(existing.filter(\.enabled).map { RuleDraft(rule: $0) }
            .filter { $0.triggerKind == triggerKind }
            .map { "\($0.stroke.rawValue)|\($0.corner.rawValue)" })
        if let free = StrokeName.allCases.first(where: { !used.contains("\($0.rawValue)|\(Corner.topLeft.rawValue)") }) {
            stroke = free
        }
        if triggerKind == .hotCornerClick,
           let free = Corner.allCases.first(where: { !used.contains("\(StrokeName.arrowLeft.rawValue)|\($0.rawValue)") }) {
            corner = free
        }
    }

    init(rule: GestureRule) {
        id = rule.id
        title = rule.title
        enabled = rule.enabled
        userSamples = rule.userSamples
        switch rule.trigger {
        case .rightStroke(let name): triggerKind = .rightStroke; stroke = name
        case .middleStroke(let name): triggerKind = .middleStroke; stroke = name
        case .rightScroll(let d, let bundle): triggerKind = .rightScroll; scroll = d; scrollBundleID = bundle
        case .middleScroll(let d): triggerKind = .middleScroll; scroll = d
        case .hotCornerClick(let c): triggerKind = .hotCornerClick; corner = c
        case .hotCornerScroll(let c, let d): triggerKind = .hotCornerScroll; corner = c; scroll = d
        case .hotkey(let code, let mods): triggerKind = .hotkey; hotkey = KeyCombo(keyCode: code, modifiers: mods)
        }
        switch rule.action {
        case .openApp(let path, let bundle): actionKind = .openApp; appPath = path; appBundleID = bundle
        case .openURL(let string): actionKind = .openURL; url = string
        case .openFolder(let path): actionKind = .openFolder; folder = path
        case .shortcut(let code, let mods, _): actionKind = .shortcut; shortcut = KeyCombo(keyCode: code, modifiers: mods)
        case .window(let w): actionKind = .window; window = w
        case .lockScreen: actionKind = .lockScreen
        case .screensaver: actionKind = .screensaver
        case .brightness(let delta): actionKind = .brightness; increase = delta > 0
        case .volume(let delta): actionKind = .volume; increase = delta > 0
        case .newFinderWindow: actionKind = .newFinderWindow
        }
    }

    var trigger: Trigger? {
        switch triggerKind {
        case .rightStroke: return .rightStroke(stroke)
        case .middleStroke: return .middleStroke(stroke)
        case .rightScroll: return .rightScroll(scroll, bundleID: scrollBundleID)
        case .middleScroll: return .middleScroll(scroll)
        case .hotCornerClick: return .hotCornerClick(corner)
        case .hotCornerScroll: return .hotCornerScroll(corner, scroll)
        case .hotkey:
            guard let hotkey, !hotkey.modifiers.isEmpty else { return nil }
            return .hotkey(keyCode: hotkey.keyCode, modifiers: hotkey.modifiers)
        }
    }

    var action: GestureAction? {
        switch actionKind {
        case .openApp:
            guard let appPath else { return nil }
            return .openApp(path: appPath, bundleID: appBundleID)
        case .openURL:
            guard let normalized = Self.normalizedURL(url) else { return nil }
            return .openURL(normalized)
        case .openFolder:
            guard let folder else { return nil }
            return .openFolder(folder)
        case .shortcut:
            guard let shortcut else { return nil }
            return .shortcut(keyCode: shortcut.keyCode, modifiers: shortcut.modifiers, title: "快捷键 \(shortcut.text)")
        case .window: return .window(window)
        case .lockScreen: return .lockScreen
        case .screensaver: return .screensaver
        case .brightness: return .brightness(increase ? 1 : -1)
        case .volume: return .volume(increase ? 1 : -1)
        case .newFinderWindow: return .newFinderWindow
        }
    }

    var rule: GestureRule? {
        guard let trigger, let action else { return nil }
        let name = title.trimmingCharacters(in: .whitespaces)
        return GestureRule(id: id, title: name.isEmpty ? action.title : name, enabled: enabled,
                           trigger: trigger, action: action, userSamples: userSamples)
    }

    /// A rule good enough to draw the thumbnail while fields are still empty.
    var previewRule: GestureRule {
        GestureRule(id: id, title: title, trigger: trigger ?? .hotkey(keyCode: 0, modifiers: []),
                    action: action ?? .lockScreen)
    }

    /// Why the rule cannot be saved yet.
    var problem: String? {
        if trigger == nil {
            return hotkey == nil ? "录一个快捷键作为触发方式。" : "快捷键至少要带一个 ⌘ ⌥ ⌃ ⇧，不然会挡住正常打字。"
        }
        if action == nil {
            switch actionKind {
            case .openApp: return "选一个要打开的应用。"
            case .openURL: return "填一个有效的网址。"
            case .openFolder: return "选一个要打开的文件夹。"
            case .shortcut: return "录一个要发送的快捷键。"
            default: return nil
            }
        }
        return nil
    }

    static func normalizedURL(_ text: String) -> String? {
        var string = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !string.isEmpty, string != "https://", string != "http://" else { return nil }
        if !string.contains("://") { string = "https://" + string }
        guard let url = URL(string: string), url.scheme != nil, url.host != nil || url.scheme != "https" else { return nil }
        return string
    }
}

struct EditorTarget: Identifiable {
    let id = UUID()
    var draft: RuleDraft
    var isNew: Bool
}

struct RuleEditor: View {
    @ObservedObject var model: AppModel
    @State var draft: RuleDraft
    let isNew: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    HStack(spacing: 12) {
                        TriggerGlyph(rule: draft.previewRule, active: draft.trigger != nil)
                        TextField("名称", text: $draft.title, prompt: Text(draft.action?.title ?? "给这个手势起个名字"))
                            .textFieldStyle(.roundedBorder)
                            .labelsHidden()
                            .multilineTextAlignment(.leading)
                        Toggle("启用", isOn: $draft.enabled)
                            .toggleStyle(.switch)
                            .labelsHidden()
                    }
                }

                Section("怎么触发") {
                    Picker("方式", selection: $draft.triggerKind) {
                        ForEach([TriggerKind.rightStroke, .middleStroke]) { Text($0.title).tag($0) }
                        Divider()
                        ForEach([TriggerKind.rightScroll, .middleScroll]) { Text($0.title).tag($0) }
                        Divider()
                        ForEach([TriggerKind.hotCornerClick, .hotCornerScroll]) { Text($0.title).tag($0) }
                        Divider()
                        Text(TriggerKind.hotkey.title).tag(TriggerKind.hotkey)
                    }
                    triggerDetail
                }

                Section("做什么") {
                    Picker("动作", selection: $draft.actionKind) {
                        ForEach([ActionKind.openApp, .openURL, .openFolder, .shortcut]) { Text($0.title).tag($0) }
                        Divider()
                        Text(ActionKind.window.title).tag(ActionKind.window)
                        Divider()
                        ForEach([ActionKind.lockScreen, .screensaver, .brightness, .volume, .newFinderWindow]) { Text($0.title).tag($0) }
                    }
                    actionDetail
                }
            }
            .glassForm()

            Divider()
            HStack {
                if !isNew {
                    Button("删除", role: .destructive) { confirmDelete = true }
                }
                if let message = statusMessage {
                    Label(message.text, systemImage: message.warning ? "exclamationmark.triangle.fill" : "info.circle")
                        .font(.callout)
                        .foregroundStyle(message.warning ? Color.orange : Color.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isNew ? "添加" : "保存") {
                    if let rule = draft.rule {
                        model.saveRule(rule)
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(draft.rule == nil)
                .glassButton(prominent: true)
            }
            .glassButton()
            .padding(16)
        }
        .frame(width: 580, height: 540)
        .presentationBackground(.regularMaterial)
        .confirmationDialog("删除「\(draft.title)」？", isPresented: $confirmDelete) {
            Button("删除", role: .destructive) {
                model.deleteRule(draft.id)
                dismiss()
            }
        } message: {
            Text(RuleStore.isBuiltin(draft.id) ? "这是默认手势。删掉后可以在偏好设置里「恢复默认」找回。" : "删掉后不能撤销。")
        }
    }

    private var statusMessage: (text: String, warning: Bool)? {
        if let problem = draft.problem { return (problem, false) }
        guard let rule = draft.rule else { return nil }
        let others = RuleStore.conflicts(for: rule, in: model.rules)
        if rule.enabled, let other = others.first {
            return ("和「\(other.title)」的触发方式一样，只有排在前面的那条会生效。", true)
        }
        if case .hotkey = rule.trigger, !model.inputTrusted {
            return ("键盘快捷键需要「输入监控」权限，在概览里可以申请。", true)
        }
        return nil
    }

    // MARK: Trigger fields

    @ViewBuilder private var triggerDetail: some View {
        switch draft.triggerKind {
        case .rightStroke, .middleStroke:
            StrokePicker(selection: $draft.stroke)
        case .hotCornerClick:
            CornerPicker(selection: $draft.corner)
        case .hotCornerScroll:
            CornerPicker(selection: $draft.corner)
            scrollPicker
        case .middleScroll:
            scrollPicker
        case .rightScroll:
            scrollPicker
            LabeledContent("只在这个应用里") {
                HStack {
                    if let bundle = draft.scrollBundleID {
                        Text(Self.appName(bundleID: bundle))
                            .foregroundStyle(.secondary)
                        Button("所有应用") { draft.scrollBundleID = nil }
                    } else {
                        Text("所有应用")
                            .foregroundStyle(.secondary)
                    }
                    Button("选择…") {
                        if let app = Self.pickApp() { draft.scrollBundleID = app.bundleID }
                    }
                }
            }
        case .hotkey:
            LabeledContent("快捷键") {
                KeyRecorder(combo: $draft.hotkey, model: model)
            }
        }
    }

    private var scrollPicker: some View {
        Picker("方向", selection: $draft.scroll) {
            Text("向上滚").tag(ScrollDirection.up)
            Text("向下滚").tag(ScrollDirection.down)
        }
        .pickerStyle(.segmented)
    }

    // MARK: Action fields

    @ViewBuilder private var actionDetail: some View {
        switch draft.actionKind {
        case .openApp:
            LabeledContent("应用") {
                HStack(spacing: 8) {
                    if let path = draft.appPath {
                        AppIcon(path: path, bundleID: draft.appBundleID)
                        Text(AppIcon.displayName(path: path, bundleID: draft.appBundleID))
                    }
                    Button(draft.appPath == nil ? "选择应用…" : "更换…") {
                        if let app = Self.pickApp() {
                            draft.appPath = app.path
                            draft.appBundleID = app.bundleID
                        }
                    }
                }
            }
        case .openURL:
            TextField("网址", text: $draft.url, prompt: Text("https://example.com"))
        case .openFolder:
            LabeledContent("文件夹") {
                HStack(spacing: 8) {
                    if let folder = draft.folder {
                        Text(folder.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(.secondary)
                    }
                    Button(draft.folder == nil ? "选择文件夹…" : "更换…") {
                        if let folder = Self.pickFolder() { draft.folder = folder }
                    }
                }
            }
        case .shortcut:
            LabeledContent("要发送的快捷键") {
                KeyRecorder(combo: $draft.shortcut, model: model)
            }
        case .window:
            Picker("位置", selection: $draft.window) {
                ForEach(WindowAction.allCases, id: \.self) { action in
                    Label(action.title, systemImage: action.symbol).tag(action)
                }
            }
        case .brightness, .volume:
            Picker("方向", selection: $draft.increase) {
                Text("提高").tag(true)
                Text("降低").tag(false)
            }
            .pickerStyle(.segmented)
        case .lockScreen, .screensaver, .newFinderWindow:
            EmptyView()
        }
    }

    // MARK: Panels

    static func pickApp() -> (path: String, bundleID: String?)? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "选择"
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return (url.path, Bundle(url: url)?.bundleIdentifier)
    }

    static func pickFolder() -> String? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "选择"
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return url.path
    }

    static func appName(bundleID: String) -> String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return AppIcon.displayName(path: url.path, bundleID: bundleID)
        }
        return KnownApps.name(for: bundleID)
    }
}

/// Eight directions and the letters the recognizer knows, drawn as they are matched.
struct StrokePicker: View {
    @Binding var selection: StrokeName

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("画法")
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(42), spacing: 8), count: 9), alignment: .leading, spacing: 8) {
                ForEach(StrokeName.allCases, id: \.self) { name in
                    let selected = name == selection
                    Button { selection = name } label: {
                        LetterGlyph(name: name, color: selected ? .white : .brand, lineWidth: 2)
                            .padding(5)
                            .frame(width: 42, height: 42)
                            .background(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(selected ? Color.brand : Color.brand.opacity(0.1))
                            )
                    }
                    .buttonStyle(.plain)
                    .help(name.title)
                    .accessibilityLabel(name.title)
                }
            }
            Text(selection.title + (selection.isLetter ? "。认不准时，保存后点这一行的笔形按钮录下你的写法。" : ""))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

struct CornerPicker: View {
    @Binding var selection: Corner

    var body: some View {
        Picker("角落", selection: $selection) {
            ForEach(Corner.allCases, id: \.self) { Text($0.title).tag($0) }
        }
        .pickerStyle(.segmented)
    }
}

/// Click, then press a key combination. Esc cancels.
struct KeyRecorder: View {
    @Binding var combo: KeyCombo?
    let model: AppModel
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 8) {
            Button {
                recording ? stop() : start()
            } label: {
                Text(recording ? "请按下组合键…" : (combo?.text ?? "点击录制"))
                    .frame(minWidth: 110)
            }
            .tint(recording ? .red : nil)
            .glassButton()
            if combo != nil, !recording {
                Button {
                    combo = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.borderless)
                .help("清除")
            }
        }
        .onDisappear(perform: stop)
    }

    private func start() {
        recording = true
        model.setCapturingKeys(true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if event.keyCode == 53, flags.subtracting([.function, .numericPad]).isEmpty {
                stop()
                return nil
            }
            var modifiers: [ModifierKey] = []
            if flags.contains(.control) { modifiers.append(.control) }
            if flags.contains(.option) { modifiers.append(.option) }
            if flags.contains(.shift) { modifiers.append(.shift) }
            if flags.contains(.command) { modifiers.append(.command) }
            combo = KeyCombo(keyCode: Int(event.keyCode), modifiers: modifiers)
            stop()
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if recording { model.setCapturingKeys(false) }
        recording = false
    }
}
