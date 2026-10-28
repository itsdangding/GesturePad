import GesturePadCore
import SwiftUI

enum Pane: Hashable {
    case overview
    case rules(RuleGroup)
    case preferences
    case about

    var title: String {
        switch self {
        case .overview: return "概览"
        case .rules(let group): return group.shortTitle
        case .preferences: return "偏好设置"
        case .about: return "关于"
        }
    }

    /// Names accepted by GESTUREPAD_PREVIEW, so each pane can be screenshotted.
    init?(previewName: String) {
        switch previewName {
        case "overview", "1": self = .overview
        case "mouse": self = .rules(.mouse)
        case "middle": self = .rules(.middle)
        case "trackpad": self = .rules(.trackpad)
        case "corner": self = .rules(.corner)
        case "key": self = .rules(.key)
        case "preferences": self = .preferences
        case "about": self = .about
        default: return nil
        }
    }
}

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @State var pane: Pane? = .overview

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 260)
        } detail: {
            detail
                .frame(minWidth: 540, minHeight: 480)
        }
        .toolbar(removing: .sidebarToggle)
        .frostedWindow()
        .safeAreaInset(edge: .bottom) {
            if let id = model.recordingRuleID, let rule = model.rules.first(where: { $0.id == id }) {
                RecordingBanner(rule: rule) { model.setRecording(nil) }
                    .padding(12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.3), value: model.recordingRuleID)
    }

    private var sidebar: some View {
        List(selection: $pane) {
            // The tag has to be the outermost modifier, or List cannot select the row.
            Label("概览", systemImage: "square.grid.2x2")
                .badge(attentionCount)
                .tag(Pane.overview)

            Section("手势") {
                ForEach(RuleGroup.allCases, id: \.self) { group in
                    Label(group.shortTitle, systemImage: group.symbol)
                        .badge(model.enabledCount(group))
                        .tag(Pane.rules(group))
                }
            }

            Section("应用") {
                Label("偏好设置", systemImage: "gearshape")
                    .tag(Pane.preferences)
                Label("关于", systemImage: "info.circle")
                    .tag(Pane.about)
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) { sidebarFooter }
    }

    private var sidebarFooter: some View {
        HStack(spacing: 8) {
            StatusDot(color: model.statusColor)
            Text(model.status)
                .font(.callout)
                .lineLimit(1)
            Spacer(minLength: 4)
            Toggle("启用手势", isOn: Binding(get: { model.enabled }, set: model.setEnabled))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
                .help(model.enabled ? "暂停全部手势" : "继续手势")
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .glassCapsule()
        .padding(10)
    }

    private var attentionCount: Int {
        (model.accessibilityTrusted ? 0 : 1)
    }

    @ViewBuilder private var detail: some View {
        switch pane ?? .overview {
        case .overview:
            OverviewPane(model: model, pane: $pane)
        case .rules(let group):
            RulesPane(model: model, group: group)
                .id(group)
        case .preferences:
            PreferencesPane(model: model, pane: $pane)
        case .about:
            AboutPane()
        }
    }
}

struct RecordingBanner: View {
    let rule: GestureRule
    let cancel: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "record.circle")
                .font(.title2)
                .foregroundStyle(.red)
                .symbolEffect(.pulse)
            VStack(alignment: .leading, spacing: 2) {
                Text("正在录制「\(rule.title)」")
                    .font(.headline)
                Text(howToRecord)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("取消", action: cancel)
                .keyboardShortcut(.cancelAction)
                .glassButton()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .glassPanel(cornerRadius: 18, tint: .red.opacity(0.12))
    }

    private var howToRecord: String {
        if case .fnStroke = rule.trigger {
            return "按住 Fn，照你的写法在触控板上画一次。松开就保存。"
        }
        return "按住右键，照你的写法画一次。松开就保存，最多留 3 笔。"
    }
}

extension AppModel {
    func enabledCount(_ group: RuleGroup) -> Int {
        rules.filter { $0.enabled && RuleGroup.group(of: $0.trigger) == group }.count
    }

    var statusColor: Color {
        if !accessibilityTrusted { return .orange }
        return enabled ? .green : .secondary
    }
}
