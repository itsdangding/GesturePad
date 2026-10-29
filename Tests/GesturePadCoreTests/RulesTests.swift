import CoreGraphics
import XCTest
@testable import GesturePadCore

final class RulesTests: XCTestCase {
    private let screens = [
        CGRect(x: 0, y: 0, width: 1440, height: 900),
        CGRect(x: 1440, y: 0, width: 1920, height: 1080)
    ]

    func testCornerUsesAppKitCoordinates() {
        XCTAssertEqual(Corner.at(CGPoint(x: 5, y: 895), in: screens), .topLeft)
        XCTAssertEqual(Corner.at(CGPoint(x: 1435, y: 3), in: screens), .bottomRight)
        XCTAssertEqual(Corner.at(CGPoint(x: 3355, y: 1075), in: screens), .topRight)
        XCTAssertNil(Corner.at(CGPoint(x: 700, y: 450), in: screens))
        XCTAssertNil(Corner.at(CGPoint(x: 5, y: 895), in: []))
    }

    func testCornerInset() {
        XCTAssertNil(Corner.at(CGPoint(x: 40, y: 40), in: screens, inset: 28))
        XCTAssertEqual(Corner.at(CGPoint(x: 40, y: 40), in: screens, inset: 48), .bottomLeft)
    }

    func testKeyComboUsesMenuOrder() {
        XCTAssertEqual(KeyNames.combo(keyCode: 48, modifiers: [.shift, .control]), "⌃⇧⇥")
        XCTAssertEqual(KeyNames.combo(keyCode: 0, modifiers: [.option, .control]), "⌃⌥A")
        XCTAssertEqual(KeyNames.combo(keyCode: 13, modifiers: [.command]), "⌘W")
        XCTAssertEqual(KeyNames.name(for: 999), "键 999")
    }

    func testHotkeySummaryNamesTheKey() {
        let rule = BuiltinRules.all.first { $0.id == "key.right" }
        XCTAssertEqual(rule?.trigger.summary, "按 ⌥→")
    }

    func testScopedScrollSummaryNamesTheApp() {
        let rule = BuiltinRules.all.first { $0.id == "pad.dia.scroll-up" }
        XCTAssertEqual(rule?.trigger.summary, "在 Dia 里按住右键向上滚")
    }

    func testBuiltinIDsAreUnique() {
        let ids = BuiltinRules.all.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count)
    }

    func testEveryGroupHasRules() {
        for group in RuleGroup.allCases {
            XCTAssertFalse(BuiltinRules.all.filter { RuleGroup.group(of: $0.trigger) == group }.isEmpty, group.rawValue)
        }
    }

    func testMergeDropsUnknownIDsAndKeepsAtMostThreeSamples() {
        var saved = BuiltinRules.all
        let sample = [SamplePoint(CGPoint(x: 0, y: 0)), SamplePoint(CGPoint(x: 1, y: 1))]
        saved[1].userSamples = Array(repeating: sample, count: 5)
        saved.append(GestureRule(id: "gone", title: "旧规则", trigger: .rightStroke(.b), action: .lockScreen))
        let merged = RuleStore.merge(saved: saved)
        XCTAssertEqual(merged.count, BuiltinRules.all.count)
        XCTAssertEqual(merged[1].userSamples.count, 3)
        XCTAssertFalse(merged.contains { $0.id == "gone" })
    }

    func testCorruptFileFallsBackToBuiltins() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("gesturepad-bad-\(UUID().uuidString).json")
        try Data("not json".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertEqual(RuleStore.load(from: url), BuiltinRules.all)
    }

    // MARK: Editing and storage

    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("gesturepad-\(UUID().uuidString).json")
    }

    func testCustomAndEditedRulesSurviveSaving() throws {
        var rules = BuiltinRules.all
        rules[0].title = "改过的名字"
        rules[0].action = .lockScreen
        let custom = GestureRule(id: RuleStore.newID(), title: "打开下载", trigger: .rightStroke(.b),
                                 action: .openFolder("/Users/me/Downloads"))
        rules.append(custom)
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try RuleStore.save(rules, to: url)
        let loaded = RuleStore.load(from: url)
        XCTAssertEqual(loaded, rules)
    }

    func testDeletedBuiltinStaysDeleted() throws {
        let rules = BuiltinRules.all.filter { $0.id != "mouse.w" }
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try RuleStore.save(rules, to: url)
        XCTAssertFalse(RuleStore.load(from: url).contains { $0.id == "mouse.w" })
    }

    func testNewBuiltinIsAddedToAnOlderFile() {
        let file = RuleFile(rules: [BuiltinRules.all[0]], knownBuiltinIDs: [BuiltinRules.all[0].id])
        let upgraded = RuleStore.upgrade(file)
        XCTAssertEqual(upgraded.count, BuiltinRules.all.count)
        XCTAssertEqual(upgraded.first, BuiltinRules.all[0])
    }

    func testVersionOneFileDropsRemovedBuiltins() throws {
        var old = BuiltinRules.all
        old.append(GestureRule(id: "pad.j", title: "打开京东", trigger: .rightStroke(.j), action: .openURL("https://www.jd.com")))
        old[0].enabled = false
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let data = try JSONEncoder().encode(RuleFile(version: 1, rules: old))
        try data.write(to: url)
        let loaded = RuleStore.load(from: url)
        XCTAssertFalse(loaded.contains { $0.id == "pad.j" })
        XCTAssertFalse(loaded[0].enabled)
    }

    func testOldTrackpadRulesAreSkippedAndTheRestKept() throws {
        let custom = GestureRule(id: "custom.x", title: "打开下载", trigger: .rightStroke(.b), action: .openFolder("/tmp"))
        let file = RuleFile(rules: [custom], knownBuiltinIDs: BuiltinRules.all.map(\.id))
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(file)) as! [String: Any]
        var rules = json["rules"] as! [[String: Any]]
        rules.insert([
            "id": "pad.d", "title": "打开访达", "enabled": true, "userSamples": [],
            "trigger": ["fnStroke": ["_0": "d"]],
            "action": ["lockScreen": [String: Any]()]
        ], at: 0)
        json["rules"] = rules
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try JSONSerialization.data(withJSONObject: json).write(to: url)
        let loaded = RuleStore.load(from: url)
        XCTAssertEqual(loaded.first, custom)
        XCTAssertFalse(loaded.contains { $0.id == "pad.d" })
    }

    func testRemovedDefaultsAreGone() {
        XCTAssertFalse(BuiltinRules.all.contains { $0.id == "pad.j" || $0.id == "pad.q" || $0.id.hasPrefix("pad.corner") || $0.id == "pad.d" })
    }

    func testConflictsFindTheSameEnabledTrigger() {
        let rules = BuiltinRules.all
        let copy = GestureRule(id: "x", title: "另一个后退", trigger: .rightStroke(.arrowLeft), action: .lockScreen)
        XCTAssertEqual(RuleStore.conflicts(for: copy, in: rules).map(\.id), ["mouse.left"])
        var disabled = rules
        disabled[disabled.firstIndex { $0.id == "mouse.left" }!].enabled = false
        XCTAssertTrue(RuleStore.conflicts(for: copy, in: disabled).isEmpty)
    }
}
