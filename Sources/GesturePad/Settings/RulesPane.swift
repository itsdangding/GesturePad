import GesturePadCore
import SwiftUI

struct RulesPane: View {
    @ObservedObject var model: AppModel
    let group: RuleGroup
    @State private var editing: EditorTarget?

    private var items: [GestureRule] {
        model.rules.filter { RuleGroup.group(of: $0.trigger) == group }
    }

    var body: some View {
        Form {
            Section {
            } header: {
                header
                    .glassHeaderCard()
            }

            if let warning {
                Section {
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }

            if group == .corner {
                Section {
                    CornerMap(rules: items, highlight: model.pointerCorner)
                } footer: {
                    Text("把指针推到角落试试，对应的那一格会亮。")
                }
            }

            Section {
                if items.isEmpty {
                    Text("这一类还没有手势。点右上角「添加手势」新建一个。")
                        .foregroundStyle(.secondary)
                }
                ForEach(items) { rule in
                    RuleRow(model: model, rule: rule) {
                        editing = EditorTarget(draft: RuleDraft(rule: rule), isNew: false)
                    }
                }
            } header: {
                Text("\(items.filter(\.enabled).count) / \(items.count) 个开启")
            } footer: {
                if items.contains(where: { $0.strokeName?.isLetter == true }) {
                    Text("字母认不准时，点那一行的 \(Image(systemName: "pencil.and.scribble"))，照你的写法画一次。录下的笔迹只存在这台 Mac 上。")
                }
            }
        }
        .glassForm()
        .navigationTitle(group.shortTitle)
        .sheet(item: $editing) { target in
            RuleEditor(model: model, draft: target.draft, isNew: target.isNew)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: group.symbol)
                .font(.system(size: 22))
                .foregroundStyle(Color.brand)
                .frame(width: 44, height: 44)
                .background(Color.brand.opacity(0.11), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(group.shortTitle)
                    .font(.title3.weight(.semibold))
                Text(group.hint)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 8) {
                Button {
                    editing = EditorTarget(draft: RuleDraft(newIn: group, existing: model.rules), isNew: true)
                } label: {
                    Label("添加手势", systemImage: "plus")
                }
                .glassButton(prominent: true)
                if !items.isEmpty {
                    let allOn = items.allSatisfy(\.enabled)
                    Button(allOn ? "全部关闭" : "全部开启") {
                        model.setGroupEnabled(group, !allOn)
                    }
                    .buttonStyle(.link)
                    .foregroundStyle(Color.accentColor)
                    .font(.callout)
                }
            }
        }
    }

    private var warning: String? {
        switch group {
        case .key where !model.inputTrusted:
            return "键盘快捷键需要「输入监控」权限，在概览里可以申请。"
        default:
            return model.accessibilityTrusted ? nil : "还没有辅助功能权限，这些手势暂时不会生效。"
        }
    }
}

struct RuleRow: View {
    @ObservedObject var model: AppModel
    let rule: GestureRule
    let edit: () -> Void
    @State private var confirmDelete = false

    var body: some View {
        let available = model.isAvailable(rule)
        let recording = model.recordingRuleID == rule.id
        HStack(spacing: 12) {
            HStack(spacing: 12) {
            TriggerGlyph(rule: rule, active: rule.enabled && available)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(rule.title)
                        .lineLimit(1)
                        .fontWeight(.medium)
                    if !available {
                        Tag("未安装", tint: .orange)
                    }
                    if !rule.userSamples.isEmpty {
                        Tag("已录 \(rule.userSamples.count) 笔", tint: .brand)
                    }
                }
                Text(rule.trigger.summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .opacity(rule.enabled ? 1 : 0.55)
            Spacer(minLength: 12)
            ActionBadge(action: rule.action)
                .opacity(rule.enabled ? 1 : 0.55)
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: edit)
            .help("点一下编辑")
            if rule.strokeName?.isLetter == true {
                recordControl(recording: recording)
            }
            Menu {
                menuItems
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("编辑或删除")
            Toggle(rule.title, isOn: Binding(
                get: { rule.enabled },
                set: { model.setRuleEnabled(rule.id, $0) }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)
            .labelsHidden()
        }
        .padding(.vertical, 3)
        .listRowBackground(recording ? Color.red.opacity(0.08) : nil)
        .contextMenu { menuItems }
        .confirmationDialog("删除「\(rule.title)」？", isPresented: $confirmDelete) {
            Button("删除", role: .destructive) { model.deleteRule(rule.id) }
        } message: {
            Text(RuleStore.isBuiltin(rule.id) ? "这是默认手势。删掉后可以在偏好设置里「恢复默认」找回。" : "删掉后不能撤销。")
        }
    }

    @ViewBuilder private var menuItems: some View {
        Button("编辑…", action: edit)
        if rule.strokeName?.isLetter == true {
            Button(model.recordingRuleID == rule.id ? "停止录制" : "录下我的写法") {
                model.setRecording(model.recordingRuleID == rule.id ? nil : rule.id)
            }
            if !rule.userSamples.isEmpty {
                Button("清除录下的笔迹") { model.clearSamples(rule.id) }
            }
        }
        Divider()
        Button("删除…", role: .destructive) { confirmDelete = true }
    }

    @ViewBuilder private func recordControl(recording: Bool) -> some View {
        if rule.userSamples.isEmpty {
            Button {
                model.setRecording(recording ? nil : rule.id)
            } label: {
                Image(systemName: recording ? "stop.circle.fill" : "pencil.and.scribble")
                    .foregroundStyle(recording ? Color.red : Color.secondary)
            }
            .buttonStyle(.borderless)
            .help(recording ? "停止录制" : "录下你的写法")
        } else {
            Menu {
                Button(recording ? "停止录制" : "再录一笔") {
                    model.setRecording(recording ? nil : rule.id)
                }
                Divider()
                Button("清除录下的 \(rule.userSamples.count) 笔", role: .destructive) {
                    model.clearSamples(rule.id)
                }
            } label: {
                Image(systemName: recording ? "stop.circle.fill" : "pencil.and.scribble")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("录制或清除你的写法")
        }
    }
}

/// A screen with what each corner does written in it.
struct CornerMap: View {
    let rules: [GestureRule]
    let highlight: Corner?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.04))
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
            Text("指针推到角落")
                .font(.callout)
                .foregroundStyle(.tertiary)
            ForEach(Corner.allCases, id: \.self) { corner in
                cell(corner)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: corner.alignment)
                    .padding(10)
            }
        }
        .frame(height: 170)
        .padding(.vertical, 4)
    }

    private func cell(_ corner: Corner) -> some View {
        let lines = rules.compactMap { rule -> String? in
            switch rule.trigger {
            case .hotCornerClick(let c) where c == corner:
                return "右键 · \(rule.title)"
            case .hotCornerScroll(let c, let direction) where c == corner:
                return "\(direction == .up ? "↑" : "↓") \(rule.title)"
            default:
                return nil
            }
        }
        let lit = highlight == corner
        let horizontal: HorizontalAlignment = (corner == .topLeft || corner == .bottomLeft) ? .leading : .trailing
        return VStack(alignment: horizontal, spacing: 2) {
            ForEach(lines, id: \.self) { Text($0) }
            if lines.isEmpty { Text("未设置").foregroundStyle(.tertiary) }
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .glassPanel(cornerRadius: 12, tint: Color.brand.opacity(0.18), active: lit)
        .animation(.easeOut(duration: 0.2), value: lit)
    }
}
