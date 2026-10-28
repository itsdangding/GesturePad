<p align="center">
  <img src="docs/icon.png" width="112" height="112" alt="GesturePad icon">
</p>

<h1 align="center">GesturePad (快捷手势)</h1>

<p align="center">
  Hold, draw, release.<br>
  A macOS menu bar app for mouse, trackpad and hot-corner gestures that open apps, send shortcuts and arrange windows.
</p>

<p align="center">
  <a href="README.md">简体中文</a> · English
</p>

<p align="center">
  <img src="docs/screenshots/mouse.png" width="820" alt="Settings window listing right-button gestures with stroke thumbnails, actions and switches">
</p>

> The app UI is in Simplified Chinese for now. Translations are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md).

## What it does

| Input | Examples |
| --- | --- |
| **Right mouse button**: hold and draw a line or letter, release to run | W opens WeChat, ← goes back, ↗ maximizes the window |
| **Middle button**: draw, or hold and scroll | S locks the screen, scroll switches tabs |
| **Trackpad**: hold Fn, then draw with one finger | → snaps the window right; Fn + tap a corner snaps to a quarter |
| **Screen corners**: push the pointer into a corner, then right-click or scroll | Top-left right-click starts the screensaver; bottom-right scroll changes volume |
| **Keyboard**: global hotkeys | ⌥ + arrows snap windows to halves |

- A short right-click is still a normal right-click, and the trackpad is a normal trackpad unless Fn is held.
- If a letter isn't recognized well, record your own way of drawing it from the settings window.
- Add, edit, delete or switch off any gesture: pick a stroke, corner or hotkey, then an action (open an app, URL or folder, send a shortcut, arrange the window, and more).
- Rules for apps you don't have are marked "未安装" (not installed).
- No network access. Settings and recorded strokes stay on your Mac.

## Install

Requires macOS 14+ and the Xcode command line tools.

```sh
git clone https://github.com/itsdangding/GesturePad.git
cd GesturePad
./scripts/install.sh
```

The script runs the tests, builds, signs and installs to `~/Applications/快捷手势.app`. Prebuilt zips on the Releases page are not notarized. Run `xattr -dr com.apple.quarantine ~/Applications/快捷手势.app` before the first launch.

Permissions: **Accessibility** (required: listens to the mouse, posts shortcuts, moves windows) and **Input Monitoring** (optional: keyboard hotkeys only).

## Develop

```sh
swift build
swift test
GESTUREPAD_PREVIEW=mouse swift run   # opens only the settings window, no event tap
```

`GesturePadCore` holds the stroke recognizer (a $1-style unistroke matcher with shape features) and the rule model. It has no UI dependencies and is covered by unit tests. The app target holds the event tap, the trackpad reader (private `MultitouchSupport` framework), action runner and SwiftUI settings.

## License

[MIT](LICENSE)
