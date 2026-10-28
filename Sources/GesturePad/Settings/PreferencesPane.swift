import GesturePadCore
import SwiftUI

struct PreferencesPane: View {
    @ObservedObject var model: AppModel
    @Binding var pane: Pane?
    @State private var confirmReset = false

    var body: some View {
        Form {
            Section("通用") {
                Toggle(isOn: Binding(get: { model.launchAtLogin }, set: model.setLaunchAtLogin)) {
                    Text("登录时启动")
                    Text("开机后自动出现在菜单栏。")
                }
                Toggle(isOn: Binding(get: { model.showTrail }, set: model.setShowTrail)) {
                    Text("画出轨迹")
                    Text("画的时候在屏幕上显示笔迹，松手就消失。")
                }
            }

            Section {
                Picker(selection: Binding(get: { model.mouseScroll }, set: model.setMouseScroll)) {
                    Text("跟随系统").tag(ScrollStyle.system)
                    Text("滚轮向下，看下面的内容").tag(ScrollStyle.standard)
                    Text("滚轮向下，看上面的内容").tag(ScrollStyle.natural)
                } label: {
                    Text("鼠标滚轮")
                    Text(scrollNote(model.mouseScroll, natural: "自然滚动", standard: "和 Windows 一样"))
                }
                Picker(selection: Binding(get: { model.trackpadScroll }, set: model.setTrackpadScroll)) {
                    Text("跟随系统").tag(ScrollStyle.system)
                    Text("手指向下滑，看下面的内容").tag(ScrollStyle.standard)
                    Text("手指向下滑，看上面的内容").tag(ScrollStyle.natural)
                } label: {
                    Text("触控板")
                    Text(scrollNote(model.trackpadScroll, natural: "自然滚动，内容跟着手指走", standard: "传统方向，手指和滚动条同向"))
                }
            } header: {
                Text("滚动方向")
            } footer: {
                Text("系统设置里的「自然滚动」现在是\(model.systemNatural ? "开" : "关")，它同时管鼠标和触控板。这里可以分开设。妙控鼠标算作鼠标。")
            }

            Section("鼠标") {
                LabeledContent("短按右键") {
                    Text("仍是普通右键菜单")
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Toggle(isOn: Binding(get: { model.fnRequired }, set: model.setFnRequired)) {
                    Text("必须按住 Fn 才画")
                    Text("关掉后，每次单指滑动都可能被当成手势，不建议。")
                }
                Toggle(isOn: Binding(get: { model.flipTrackpadY }, set: model.setFlipY)) {
                    Text("画手势时上下对调")
                    Text("如果在触控板上向上画被认成向下，打开这一项。不影响滚动。")
                }
                LabeledContent {
                    Button("重新检查") {
                        model.refreshTrust()
                        model.events.ensureRunning()
                    }
                } label: {
                    HStack(spacing: 6) {
                        StatusDot(color: model.trackpadReady ? .green : .orange)
                        Text(model.trackpadReady ? "内置触控板可用" : model.trackpadMessage)
                    }
                }
            } header: {
                Text("触控板")
            }

            Section {
                LabeledContent {
                    Button("查看键盘手势") { pane = .rules(.key) }
                } label: {
                    Text("⌥ 加方向键")
                    Text("会占掉系统里按词移动光标。不需要的话，到键盘手势里关掉那几条。")
                }
            } header: {
                Text("键盘")
            }

            Section("数据") {
                LabeledContent {
                    Button("在访达中显示") {
                        NSWorkspace.shared.activateFileViewerSelecting([RuleStore.fileURL()])
                    }
                } label: {
                    Text("规则文件")
                    Text(RuleStore.fileURL().path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                        .textSelection(.enabled)
                }
                LabeledContent {
                    Button("恢复默认…", role: .destructive) { confirmReset = true }
                } label: {
                    Text("恢复默认手势")
                    Text("重新打开全部默认手势，并清除录下的笔迹。")
                }
            }
        }
        .glassForm()
        .navigationTitle("偏好设置")
        .confirmationDialog("恢复默认手势？", isPresented: $confirmReset) {
            Button("恢复默认", role: .destructive) { model.resetRules() }
        } message: {
            Text("开关会回到默认状态，录下的笔迹会被清除。这一步不能撤销。")
        }
    }
}

private func scrollNote(_ style: ScrollStyle, natural: String, standard: String) -> String {
    switch style {
    case .system: return "和系统设置一样"
    case .standard: return standard
    case .natural: return natural
    }
}

struct AboutPane: View {
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 14) {
                AppIconView(size: 96)
                VStack(spacing: 4) {
                    Text("快捷手势")
                        .font(.title.weight(.semibold))
                    Text("GesturePad · 版本 \(AppModel.version)")
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Text("按住，画一笔，松手。\n在 macOS 菜单栏里，用鼠标、触控板和屏幕四角打开应用、移动窗口。")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    Link(destination: URL(string: AppModel.projectURL)!) {
                        Label("源码", systemImage: "chevron.left.forwardslash.chevron.right")
                    }
                    Link(destination: URL(string: AppModel.projectURL + "/issues/new/choose")!) {
                        Label("反馈问题", systemImage: "exclamationmark.bubble")
                    }
                }
                .glassButton()
                .padding(.top, 4)
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 32)
            .frame(maxWidth: 520)
            .glassPanel(cornerRadius: 30, tint: nil)
            Spacer()
            Text("MIT 许可 · 开源，欢迎贡献")
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .padding(.bottom, 18)
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("关于")
    }
}
