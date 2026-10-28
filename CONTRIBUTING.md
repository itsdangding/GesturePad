# 贡献指南

谢谢你愿意帮忙。问题、建议、文档修正、代码都欢迎。

## 报告问题

在 [Issues](https://github.com/itsdangding/GesturePad/issues/new/choose) 里选对应的模板。手势认不准时，请写清楚：

- macOS 版本，用的是鼠标还是触控板
- 画的是哪个字母或方向，大概画多大
- 系统日志里的记录：在终端运行 `log show --last 10m --predicate 'process == "GesturePad"'`

## 本地开发

```sh
swift build
swift test
GESTUREPAD_PREVIEW=overview swift run
```

预览模式只打开设置窗口，不建事件监听，也不读触控板，可以和已经装好的那一份同时运行。

真机试手势需要打包成 app 并授权辅助功能：

```sh
./scripts/install.sh
```

## 改代码

- 识别和规则逻辑放在 `GesturePadCore`，并补上测试。这一层不能依赖 AppKit 或 SwiftUI。
- 事件监听回调跑在后台线程。要读界面状态，请通过 `ConfigBox` 快照，不要直接碰 `NSScreen` 或 `AppModel`。
- 新增默认规则时，`id` 一旦发布就不要改。规则文件记着见过哪些默认 `id`：用户删掉的不会再加回来，新加的会自动补上。
- 界面文字目前是简体中文，句子短、直接，说清楚用户要做什么。
- 改了默认手势，记得同步 `docs/gestures.html` 和 README。

## 提交 PR

1. 从 `main` 拉一个分支。
2. 保证 `swift test` 通过，`swift build -c release` 没有警告。
3. 界面有变化时，在 PR 里附截图（预览模式加 `screencapture` 就行）。
4. 在 `CHANGELOG.md` 的「未发布」下加一行。

## 想帮忙但不知道从哪开始

- 手势导入和导出，方便分享一套配置
- 只在某个应用里生效的手势（目前只有「按住右键滚动」支持）
- 英文界面和其他语言
- 支持外接妙控板
- 改进字母识别，补更多测试笔迹

提交代码即表示你同意以 [MIT 许可](LICENSE) 发布这些改动。
