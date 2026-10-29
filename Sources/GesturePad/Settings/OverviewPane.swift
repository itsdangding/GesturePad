import GesturePadCore
import SwiftUI

struct OverviewPane: View {
    @ObservedObject var model: AppModel
    @Binding var pane: Pane?

    var body: some View {
        Form {
            Section {
            } header: {
                hero
                    .glassHeaderCard()
            }

            Section {
                PermissionRow(
                    title: "辅助功能",
                    detail: "监听鼠标、移动窗口都靠它。没有它，手势不会生效。",
                    ready: model.accessibilityTrusted,
                    required: true,
                    action: "打开并授权",
                    perform: model.requestAccessibility
                )
                PermissionRow(
                    title: "输入监控",
                    detail: "只有键盘快捷键（如 ⌥ 加方向键）需要。列表一开始是空的，点加号选「快捷手势」。",
                    ready: model.inputTrusted,
                    required: false,
                    action: "请求权限",
                    perform: model.requestInputMonitoring
                )
                if !model.accessibilityTrusted || !model.inputTrusted {
                    LabeledContent {
                        Button("在访达中显示") { model.revealInFinder() }
                    } label: {
                        Text("在系统设置的列表里找不到？")
                        Text(AppModel.appURL.path)
                            .textSelection(.enabled)
                    }
                }
            } header: {
                Text("权限")
            }

            Section("怎么画") {
                HowRow(symbol: "computermouse", title: "鼠标", text: "按住右键画一笔，松开执行。只点一下仍是右键菜单。") {
                    pane = .rules(.mouse)
                }
                HowRow(symbol: "rectangle.inset.topleft.filled", title: "屏幕四角", text: "指针推到角落，单击右键或滚动。") {
                    pane = .rules(.corner)
                }
            }
        }
        .glassForm()
        .navigationTitle("概览")
    }

    private var hero: some View {
        HStack(spacing: 16) {
            AppIconView(size: 56)
            VStack(alignment: .leading, spacing: 4) {
                Text("快捷手势")
                    .font(.title2.weight(.semibold))
                HStack(spacing: 6) {
                    StatusDot(color: model.statusColor)
                    Text(heroDetail)
                        .foregroundStyle(.secondary)
                }
                .font(.callout)
            }
            Spacer()
            Toggle("启用手势", isOn: Binding(get: { model.enabled }, set: model.setEnabled))
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.large)
        }
    }

    private var heroDetail: String {
        let total = model.rules.filter(\.enabled).count
        if !model.accessibilityTrusted {
            return "需要辅助功能权限才能开始"
        }
        return model.enabled ? "已开启 · \(total) 个手势在用" : "已暂停 · 点右边开关继续"
    }
}

struct PermissionRow: View {
    let title: String
    let detail: String
    let ready: Bool
    let required: Bool
    let action: String
    let perform: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: ready ? "checkmark.circle.fill" : (required ? "exclamationmark.triangle.fill" : "circle.dashed"))
                .font(.title3)
                .foregroundStyle(ready ? .green : (required ? .orange : .secondary))
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title)
                    if !required { Tag("可选") }
                }
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            if ready {
                Text("已允许")
                    .foregroundStyle(.secondary)
            } else {
                if required {
                    Button(action, action: perform)
                        .glassButton(prominent: true)
                } else {
                    Button(action, action: perform)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

struct HowRow: View {
    let symbol: String
    let title: String
    let text: String
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.title3)
                    .foregroundStyle(Color.brand)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    Text(text)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
