import AppKit
import ApplicationServices
import Foundation
import GesturePadCore
import ServiceManagement
import os

final class AppModel: ObservableObject {
    let events = EventController()

    @Published var rules: [GestureRule] = []
    @Published var enabled = true
    @Published var showTrail = true
    @Published var fnRequired = true
    @Published var flipTrackpadY = false
    @Published var mouseScroll: ScrollStyle = .standard
    @Published var trackpadScroll: ScrollStyle = .system
    @Published var systemNatural = true
    @Published var launchAtLogin = false
    @Published var accessibilityTrusted = false
    @Published var inputTrusted = false
    @Published var trackpadReady = false
    @Published var trackpadMessage = "正在检查触控板"
    @Published var recordingRuleID: String?
    @Published var status = "正在启动"
    @Published var pointerCorner: Corner?

    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var installedCache: [String: Bool] = [:]
    /// Preview mode shows sample data and must not overwrite the real rules file.
    private var savesRules = true

    init() {
        events.model = self
        let defaults = UserDefaults.standard
        if defaults.object(forKey: Keys.enabled) != nil {
            enabled = defaults.bool(forKey: Keys.enabled)
        }
        if defaults.object(forKey: Keys.showTrail) != nil {
            showTrail = defaults.bool(forKey: Keys.showTrail)
        }
        if defaults.object(forKey: Keys.fnRequired) != nil {
            fnRequired = defaults.bool(forKey: Keys.fnRequired)
        }
        flipTrackpadY = defaults.bool(forKey: Keys.flipY)
        if let raw = defaults.string(forKey: Keys.mouseScroll), let style = ScrollStyle(rawValue: raw) {
            mouseScroll = style
        } else if defaults.object(forKey: Keys.reverseMouseY) != nil {
            // Older versions had one switch: wheel like Windows, or leave it alone.
            mouseScroll = defaults.bool(forKey: Keys.reverseMouseY) ? .standard : .system
        }
        if let raw = defaults.string(forKey: Keys.trackpadScroll), let style = ScrollStyle(rawValue: raw) {
            trackpadScroll = style
        }
        systemNatural = Self.readSystemNatural()
        rules = RuleStore.load()
        push()
    }

    func start() {
        updateScreens()
        updateFrontApp()
        refreshTrust()
        refreshLoginItem()
        events.ensureRunning()
        refreshStatus()
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.updateScreens() })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.updateFrontApp() })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.installedCache = [:] })
        timer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    func tick() {
        let corner = Corner.at(NSEvent.mouseLocation, in: NSScreen.screens.map(\.frame))
        if corner != pointerCorner { pointerCorner = corner }
        let trusted = AXIsProcessTrusted()
        let input = CGPreflightListenEventAccess()
        let natural = Self.readSystemNatural()
        if natural != systemNatural {
            systemNatural = natural
            push()
        }
        if trusted != accessibilityTrusted { accessibilityTrusted = trusted }
        if input != inputTrusted { inputTrusted = input }
        if trusted {
            events.ensureRunning()
        }
        refreshStatus()
    }

    private func updateScreens() {
        let frames = NSScreen.screens.map(\.frame)
        events.box.update {
            $0.primaryMaxY = frames.first?.maxY ?? 0
            $0.screenFrames = frames
        }
    }

    private func updateFrontApp() {
        let bundle = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        events.box.update { $0.frontBundleID = bundle }
    }

    func refreshTrust() {
        accessibilityTrusted = AXIsProcessTrusted()
        inputTrusted = CGPreflightListenEventAccess()
    }

    func requestAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
        refreshTrust()
    }

    func requestInputMonitoring() {
        NSApp.activate(ignoringOtherApps: true)
        // Asking here is what puts the app into the 输入监控 list.
        // Opening Settings in the same instant covers the system prompt, so wait.
        CGRequestListenEventAccess()
        note("如果弹出系统提示，点允许。列表里的名字是「快捷手势」。")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            let candidates = [
                "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ListenEvent",
                "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
            ]
            for string in candidates {
                guard let url = URL(string: string) else { continue }
                if NSWorkspace.shared.open(url) { break }
            }
            self?.refreshTrust()
        }
    }

    func revealInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([Self.appURL])
    }

    static var appURL: URL {
        Bundle.main.bundleURL
    }

    func setEnabled(_ value: Bool) {
        enabled = value
        UserDefaults.standard.set(value, forKey: Keys.enabled)
        push()
        note(value ? "手势已开启" : "手势已暂停")
        refreshStatus()
    }

    func setShowTrail(_ value: Bool) {
        showTrail = value
        UserDefaults.standard.set(value, forKey: Keys.showTrail)
        push()
    }

    func setFnRequired(_ value: Bool) {
        fnRequired = value
        UserDefaults.standard.set(value, forKey: Keys.fnRequired)
        push()
    }

    func setFlipY(_ value: Bool) {
        flipTrackpadY = value
        UserDefaults.standard.set(value, forKey: Keys.flipY)
        push()
    }

    func setMouseScroll(_ value: ScrollStyle) {
        mouseScroll = value
        UserDefaults.standard.set(value.rawValue, forKey: Keys.mouseScroll)
        push()
    }

    func setTrackpadScroll(_ value: ScrollStyle) {
        trackpadScroll = value
        UserDefaults.standard.set(value.rawValue, forKey: Keys.trackpadScroll)
        push()
    }

    /// The "natural scrolling" switch in System Settings. Missing means on.
    static func readSystemNatural() -> Bool {
        CFPreferencesAppSynchronize(kCFPreferencesAnyApplication)
        let value = CFPreferencesCopyAppValue("com.apple.swipescrolldirection" as CFString, kCFPreferencesAnyApplication)
        return (value as? Bool) ?? true
    }

    func setRuleEnabled(_ id: String, _ value: Bool) {
        guard let index = rules.firstIndex(where: { $0.id == id }) else { return }
        rules[index].enabled = value
        persist()
    }

    func setRecording(_ id: String?) {
        recordingRuleID = id
        push()
        if let id, let rule = rules.first(where: { $0.id == id }) {
            note("请画出「\(rule.title)」的笔迹，画完松开")
        }
    }

    func setGroupEnabled(_ group: RuleGroup, _ value: Bool) {
        for index in rules.indices where RuleGroup.group(of: rules[index].trigger) == group {
            rules[index].enabled = value
        }
        persist()
    }

    /// Adds a new rule or replaces the one with the same ID.
    func saveRule(_ rule: GestureRule) {
        var rule = rule
        if rule.title.trimmingCharacters(in: .whitespaces).isEmpty {
            rule.title = rule.action.title
        }
        if let index = rules.firstIndex(where: { $0.id == rule.id }) {
            // Recorded strokes belong to the letter they were drawn for.
            if rules[index].strokeName != rule.strokeName {
                rule.userSamples = []
            }
            rules[index] = rule
            note("已修改「\(rule.title)」")
        } else {
            rules.append(rule)
            note("已添加「\(rule.title)」")
        }
        persist()
    }

    func deleteRule(_ id: String) {
        guard let index = rules.firstIndex(where: { $0.id == id }) else { return }
        let title = rules[index].title
        rules.remove(at: index)
        if recordingRuleID == id { recordingRuleID = nil }
        persist()
        note("已删除「\(title)」")
    }

    func setCapturingKeys(_ value: Bool) {
        events.box.update { $0.capturingKeys = value }
    }

    func resetRules() {
        rules = BuiltinRules.all
        recordingRuleID = nil
        persist()
        note("已恢复默认手势")
    }

    /// False when a rule opens an app that is not on this Mac.
    func isAvailable(_ rule: GestureRule) -> Bool {
        guard case .openApp(let path, let bundleID) = rule.action else { return true }
        let key = path + "|" + (bundleID ?? "")
        if let cached = installedCache[key] { return cached }
        var found = FileManager.default.fileExists(atPath: path)
        if !found, let bundleID {
            found = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
        }
        installedCache[key] = found
        return found
    }

    func openProjectPage() {
        if let url = URL(string: Self.projectURL) { NSWorkspace.shared.open(url) }
    }

    static let projectURL = "https://github.com/itsdangding/GesturePad"

    static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "开发版"
        let build = info?["CFBundleVersion"] as? String
        return build.map { "\(short) (\($0))" } ?? short
    }

    func saveSample(ruleID: String, points: [CGPoint]) {
        guard let index = rules.firstIndex(where: { $0.id == ruleID }) else { return }
        var samples = rules[index].userSamples
        samples.append(points.map(SamplePoint.init))
        rules[index].userSamples = Array(samples.suffix(3))
        recordingRuleID = nil
        persist()
        note("已记下「\(rules[index].title)」的笔迹，共 \(rules[index].userSamples.count) 笔")
    }

    func clearSamples(_ id: String) {
        guard let index = rules.firstIndex(where: { $0.id == id }) else { return }
        rules[index].userSamples = []
        persist()
    }

    /// Writes to the system log only. Read it with:
    /// log stream --predicate 'process == "GesturePad"'
    func note(_ text: String) {
        Self.log.info("\(text, privacy: .public)")
    }

    private static let log = Logger(subsystem: "com.ddang.gesturepad", category: "actions")

    func refreshStatus() {
        let next: String
        if !accessibilityTrusted {
            next = "需要辅助功能权限"
        } else if !enabled {
            next = "手势已暂停"
        } else {
            next = "手势已开启"
        }
        if next != status { status = next }
    }

    func setLaunchAtLogin(_ value: Bool) {
        do {
            if value {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            refreshLoginItem()
        } catch {
            note("登录时启动没有设上：\(error.localizedDescription)")
            refreshLoginItem()
        }
    }

    func refreshLoginItem() {
        let value = SMAppService.mainApp.status == .enabled
        if value != launchAtLogin { launchAtLogin = value }
    }

    private func persist() {
        if savesRules {
            do {
                try RuleStore.save(rules)
            } catch {
                note("规则没有存上：\(error.localizedDescription)")
            }
        }
        push()
    }

    private func push() {
        events.box.update { snapshot in
            snapshot.enabled = self.enabled
            snapshot.showTrail = self.showTrail
            snapshot.fnRequired = self.fnRequired
            snapshot.flipY = self.flipTrackpadY
            snapshot.mouseScroll = self.mouseScroll
            snapshot.trackpadScroll = self.trackpadScroll
            snapshot.systemNatural = self.systemNatural
            snapshot.rules = self.rules
            snapshot.recordingRuleID = self.recordingRuleID
        }
    }

    private enum Keys {
        static let enabled = "GesturePad.enabled"
        static let showTrail = "GesturePad.showTrail"
        static let fnRequired = "GesturePad.fnRequired"
        static let flipY = "GesturePad.flipY"
        static let reverseMouseY = "GesturePad.reverseMouseY"
        static let mouseScroll = "GesturePad.mouseScroll"
        static let trackpadScroll = "GesturePad.trackpadScroll"
    }
}

#if DEBUG
extension AppModel {
    /// Sample state for UI previews and screenshots. Nothing is saved.
    func loadPreviewState() {
        savesRules = false
        accessibilityTrusted = ProcessInfo.processInfo.environment["GESTUREPAD_PREVIEW_UNTRUSTED"] == nil
        inputTrusted = accessibilityTrusted
        trackpadReady = true
        trackpadMessage = "触控板可用"
        refreshStatus()
        pointerCorner = .bottomRight
        if let index = rules.firstIndex(where: { $0.id == "mouse.w" }) {
            let sample: [(Double, Double)] = [(0, 96), (20, 4), (44, 58), (52, 52), (74, 6), (98, 100)]
            rules[index].userSamples = [sample.map { SamplePoint(CGPoint(x: $0.0, y: $0.1)) }]
        }
        if let index = rules.firstIndex(where: { $0.id == "key.a" }) {
            rules[index].enabled = false
        }
    }
}
#endif
