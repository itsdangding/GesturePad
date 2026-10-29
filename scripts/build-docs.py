#!/usr/bin/env python3
"""Writes docs/index.html and docs/gestures.html.

Letter thumbnails use the same display shapes as the app
(Sources/GesturePad/Settings/StrokeShapes.swift). Keep GROUPS in sync with
BuiltinRules in Sources/GesturePadCore/Rules.swift.

    python3 scripts/build-docs.py
"""
import html
import math
import os

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "docs")
REPO = "https://github.com/itsdangding/GesturePad"

# Straight strokes use y-up coordinates from 0 to 100 and are fitted to the box.
DIRECTIONS = {
    "left": [(100, 50), (0, 50)], "right": [(0, 50), (100, 50)],
    "up": [(50, 0), (50, 100)], "down": [(50, 100), (50, 0)],
    "upright": [(0, 0), (100, 100)], "downleft": [(100, 100), (0, 0)],
}


def fit(points, box=100, pad=10):
    xs = [p[0] for p in points]
    ys = [p[1] for p in points]
    w, h = max(xs) - min(xs), max(ys) - min(ys)
    inner = box - 2 * pad
    scale = min(inner / max(w, 1e-3), inner / max(h, 1e-3))
    ox, oy = pad + (inner - w * scale) / 2, pad + (inner - h * scale) / 2
    return [(ox + (x - min(xs)) * scale, oy + (max(ys) - y) * scale) for x, y in points]


def path(d):
    return f'<path d="{d}" fill="none" stroke="currentColor" stroke-width="8" stroke-linecap="round" stroke-linejoin="round"/>'


def svg(body):
    return f'<svg viewBox="0 0 100 100" aria-hidden="true">{body}</svg>'


def stroke(points, arrow=False):
    f = fit(points)
    body = path("M" + " L".join(f"{x:.1f} {y:.1f}" for x, y in f))
    sx, sy = f[0]
    body += f'<circle cx="{sx:.1f}" cy="{sy:.1f}" r="9" fill="currentColor"/>'
    if arrow:
        (ax, ay), (bx, by) = f[-2], f[-1]
        a = math.atan2(by - ay, bx - ax)
        n = 22
        p1 = (bx - n * math.cos(a - math.pi / 5), by - n * math.sin(a - math.pi / 5))
        p2 = (bx - n * math.cos(a + math.pi / 5), by - n * math.sin(a + math.pi / 5))
        body += path(f"M{p1[0]:.1f} {p1[1]:.1f} L{bx:.1f} {by:.1f} L{p2[0]:.1f} {p2[1]:.1f}")
    return svg(body)


# Display shapes, the same as StrokeShapes.swift: 100 x 100 box, y grows downward.
LETTERS = {
    "w": ((8, 16), "M8 16 L28 86 L50 36 L72 86 L92 16"),
    "v": ((16, 14), "M16 14 L50 88 L84 14"),
    "l": ((28, 10), "M28 10 L28 88 L82 88"),
    "h": ((24, 10), "M24 10 L24 90 L24 52 L76 52 L76 10 L76 90"),
    "d": ((28, 10), "M28 10 L28 90 C98 90 98 10 28 10"),
    "p": ((28, 92), "M28 92 L28 10 C92 8 92 56 28 54"),
    "b": ((28, 90), "M28 90 L28 10 C84 10 84 48 30 48 C94 48 94 90 28 90"),
    "j": ((64, 10), "M64 10 L64 64 C64 96 22 98 20 70"),
    "s": ((76, 22), "M76 22 C66 6 26 6 26 30 C26 52 74 46 74 70 C74 96 32 98 22 80"),
    "q": ((50, 12), "M50 12 C28 12 12 28 12 50 C12 72 28 88 50 88 C72 88 88 72 88 50 C88 28 72 12 50 12 M60 66 L88 94"),
}


def letter(name):
    (sx, sy), d = LETTERS[name]
    body = path(d) + f'<circle cx="{sx}" cy="{sy}" r="9" fill="currentColor"/>'
    return f'<svg viewBox="-4 -4 108 108" aria-hidden="true">{body}</svg>'


def direction(name):
    return stroke(DIRECTIONS[name], arrow=True)


CORNERS = {"tl": (22, 30), "tr": (78, 30), "bl": (22, 70), "br": (78, 70)}


def corner(name, scroll=None):
    x, y = CORNERS[name]
    body = f'<rect x="8" y="18" width="84" height="64" rx="8" fill="none" stroke="currentColor" stroke-width="6" opacity=".6"/>'
    body += f'<circle cx="{x}" cy="{y}" r="9" fill="currentColor"/>'
    if scroll:
        y1, y2, head = (62, 40, 9) if scroll == "up" else (40, 62, -9)
        body += f'<path d="M50 {y1} L50 {y2} M41 {y2 + head} L50 {y2} L59 {y2 + head}" stroke="currentColor" stroke-width="6" fill="none" stroke-linecap="round" stroke-linejoin="round"/>'
    return svg(body)


def wheel(scroll):
    body = '<rect x="24" y="12" width="40" height="66" rx="20" fill="none" stroke="currentColor" stroke-width="6"/>'
    body += '<path d="M44 24 L44 38" stroke="currentColor" stroke-width="6" stroke-linecap="round"/>'
    y1, y2, head = (80, 40, 10) if scroll == "up" else (40, 80, -10)
    body += f'<path d="M86 {y1} L86 {y2} M77 {y2 + head} L86 {y2} L95 {y2 + head}" stroke="currentColor" stroke-width="6" fill="none" stroke-linecap="round" stroke-linejoin="round"/>'
    return svg(body)


def keys(text):
    return f'<span class="keytext">{html.escape(text)}</span>'


def act(text=None, kbd=None):
    if kbd:
        return f"<kbd>{html.escape(kbd)}</kbd>"
    return f'<span class="act">{html.escape(text)}</span>' if text else ""


GROUPS = [
    ("mouse", "鼠标右键", "按住右键画一笔，松开才执行。只动一小段仍是普通右键。", [
        (letter("w"), "打开微信", "字母 W", act("微信")),
        (letter("h"), "打开活动监视器", "字母 H", act("活动监视器")),
        (letter("l"), "关闭窗口", "字母 L", act(kbd="⌘W")),
        (letter("p"), "打开系统设置", "字母 P", act("系统设置")),
        (direction("left"), "后退", "向左直线", act(kbd="⌘[")),
        (direction("right"), "前进", "向右直线", act(kbd="⌘]")),
        (letter("v"), "打开 Visual Studio Code", "字母 V", act("VS Code")),
        (direction("upright"), "窗口最大化", "向右上", ""),
        (direction("downleft"), "窗口最小化", "向左下", ""),
        (direction("down"), "复制", "向下直线", act(kbd="⌘C")),
        (direction("up"), "粘贴", "向上直线", act(kbd="⌘V")),
        (letter("d"), "新建访达窗口", "字母 D", ""),
        (wheel("up"), "Dia 上一个标签", "在 Dia 里按住右键，滚轮向上", act(kbd="⌃⇧⇥")),
        (wheel("down"), "Dia 下一个标签", "在 Dia 里按住右键，滚轮向下", act(kbd="⌃⇥")),
    ]),
    ("middle", "鼠标中键", "按住中键画，或按住中键滚动滚轮。", [
        (letter("s"), "锁定屏幕", "字母 S", act(kbd="⌃⌘Q")),
        (wheel("up"), "上一个标签", "按住中键，滚轮向上", act(kbd="⌃⇧⇥")),
        (wheel("down"), "下一个标签", "按住中键，滚轮向下", act(kbd="⌃⇥")),
    ]),
    ("corner", "屏幕四角", "把指针推到屏幕角落，再单击右键或滚动鼠标滚轮。触控板双指滑动不会触发。", [
        (corner("tl"), "启动屏保", "左上角单击右键", ""),
        (corner("tr"), "锁定屏幕", "右上角单击右键", ""),
        (corner("bl", "up"), "提高亮度", "左下角滚轮向上", ""),
        (corner("bl", "down"), "降低亮度", "左下角滚轮向下", ""),
        (corner("br", "up"), "提高音量", "右下角滚轮向上", ""),
        (corner("br", "down"), "降低音量", "右下角滚轮向下", ""),
    ]),
    ("key", "键盘", "全局快捷键。⌥ 加方向键会占掉系统里按词移动光标，不需要可以关掉。需要「输入监控」权限。", [
        (keys("⌥↑"), "窗口靠上半屏", "按 ⌥↑", ""),
        (keys("⌥→"), "窗口靠右半屏", "按 ⌥→", ""),
        (keys("⌥↓"), "窗口靠下半屏", "按 ⌥↓", ""),
        (keys("⌥←"), "窗口靠左半屏", "按 ⌥←", ""),
        (keys("⌃⌥A"), "打开应用程序文件夹", "按 ⌃⌥A", ""),
    ]),
]

GH_ICON = '<svg viewBox="0 0 16 16" aria-hidden="true"><path d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27.68 0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.013 8.013 0 0016 8c0-4.42-3.58-8-8-8z"/></svg>'
BRAND = '<svg viewBox="0 0 100 100" aria-hidden="true"><path class="stroke" d="M74 24C72 56 40 74 22 72" stroke-width="10" stroke-linecap="round" fill="none"/><circle class="dot" cx="74" cy="24" r="6.5"/></svg>'


def page(title, desc, current, body):
    def nav(href, label, key, cls=""):
        cur = ' aria-current="page"' if key == current else ""
        c = f' class="{cls}"' if cls else ""
        return f'<a href="{href}"{cur}{c}>{label}</a>'

    return f'''<!DOCTYPE html>
<html lang="zh-Hans">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>{title}</title>
  <meta name="description" content="{desc}">
  <meta property="og:title" content="{title}">
  <meta property="og:description" content="{desc}">
  <meta property="og:image" content="screenshots/mouse.png">
  <meta name="theme-color" content="#f4f0e8" media="(prefers-color-scheme: light)">
  <meta name="theme-color" content="#161512" media="(prefers-color-scheme: dark)">
  <link rel="icon" href="icon.png">
  <link rel="stylesheet" href="styles.css">
</head>
<body>
  <header class="top">
    <div class="wrap">
      <a class="brand" href="index.html">{BRAND}快捷手势</a>
      <nav>
        {nav("index.html#how", "怎么用", "how", "hide-sm")}
        {nav("gestures.html", "手势表", "gestures")}
        {nav("index.html#install", "安装", "install", "hide-sm")}
        <a class="gh" href="{REPO}">{GH_ICON}GitHub</a>
      </nav>
    </div>
  </header>
{body}
  <footer>
    <div class="wrap">
      <span>快捷手势 GesturePad · <a href="{REPO}/blob/main/LICENSE">MIT 许可</a></span>
      <span><a href="{REPO}">源码</a> · <a href="{REPO}/issues">反馈问题</a> · <a href="{REPO}/blob/main/CONTRIBUTING.md">参与贡献</a></span>
    </div>
  </footer>
</body>
</html>
'''


GH_BUTTON = GH_ICON.replace("<svg", '<svg width="18" height="18" fill="currentColor"')

INDEX = f'''  <main>
    <div class="wrap">
      <section class="hero">
        <p class="kicker">开源 · macOS 菜单栏工具</p>
        <h1>按住，画一笔，<em>松手</em>。</h1>
        <p class="lead">按住右键画个 W 打开微信，向左一划就后退。指针推到屏幕角落就能锁屏、调音量。手势可以自己添加和修改。不联网，不收集数据。</p>
        <div class="actions">
          <a class="btn primary" href="#install">安装到这台 Mac</a>
          <a class="btn" href="{REPO}">{GH_BUTTON}在 GitHub 查看源码</a>
        </div>
        <p class="meta">macOS 14 及以上 · Swift 编写 · MIT 许可</p>
        <figure class="shot">
          <img src="screenshots/mouse.png" width="1920" height="1440" alt="快捷手势的设置窗口：左边是分类，右边列出鼠标右键手势，每一条有笔迹缩略图、要做的事和开关">
        </figure>
      </section>
    </div>

    <section class="block" id="how">
      <div class="wrap">
        <p class="eyebrow">三种画法</p>
        <h2>平常怎么用鼠标，就还怎么用</h2>
        <p class="sub">只有按住并明显画长一笔才算手势。短按右键仍然是右键菜单，触控板照常使用，不会误触。</p>
        <div class="cards">
          <article class="card">
            <div class="glyph">{letter("w")}</div>
            <h3>鼠标右键</h3>
            <p>按住右键画直线或字母，松开才执行。中键也能画，按住中键滚动可以切标签。</p>
          </article>
          <article class="card">
            <div class="glyph">{keys("⌥→")}</div>
            <h3>键盘</h3>
            <p>全局快捷键。⌥ 加方向键把窗口放到半屏，⌃⌥A 打开应用程序文件夹。</p>
          </article>
          <article class="card">
            <div class="glyph">{corner("br", "up")}</div>
            <h3>屏幕四角</h3>
            <p>指针推到角落，右键单击开屏保、锁屏；滚动鼠标滚轮调亮度和音量。</p>
          </article>
        </div>
      </div>
    </section>

    <section class="block">
      <div class="wrap split">
        <div>
          <p class="eyebrow">按你的习惯</p>
          <h2>自己定手势，认不准就录一笔</h2>
          <p class="sub" style="margin:0">选一种画法、一个角落或一个快捷键，再选要做的事：打开应用、网址、文件夹，发快捷键，摆放窗口。字母认不准时，照你的写法录一次。</p>
          <ul class="ticks">
            <li>每一条手势都能开关、修改、删除，也能添加自己的</li>
            <li>触发方式和别的手势重复时会提醒</li>
            <li>没装的应用会标出「未安装」</li>
            <li>画的时候屏幕上显示轨迹，可以关掉</li>
          </ul>
        </div>
        <img src="screenshots/editor.png" width="1920" height="1440" loading="lazy" alt="编辑手势：选触发方式和画法，再选要做的事">
      </div>
    </section>

    <section class="block" id="install">
      <div class="wrap">
        <p class="eyebrow">安装</p>
        <h2>从源码装，三步</h2>
        <p class="sub">需要 macOS 14 和 Xcode 命令行工具（<code>xcode-select --install</code>）。</p>
        <ol class="steps">
          <li>
            <h3>下载并安装</h3>
            <p>脚本会跑测试、编译、签名，装到 <code>~/Applications/快捷手势.app</code> 并打开。</p>
<pre><code>git clone {REPO}.git
cd GesturePad
./scripts/install.sh</code></pre>
          </li>
          <li>
            <h3>允许「辅助功能」</h3>
            <p>第一次打开会弹出设置窗口，点「打开并授权」，在系统设置里打开「快捷手势」。监听鼠标、移动窗口都靠它。</p>
          </li>
          <li>
            <h3>（可选）允许「输入监控」</h3>
            <p>只有键盘快捷键（如 ⌥ 加方向键）需要。系统设置的列表里没有时，点加号，前往 <code>~/Applications/快捷手势.app</code>。</p>
          </li>
        </ol>
      </div>
    </section>

    <section class="block">
      <div class="wrap split">
        <div>
          <p class="eyebrow">隐私</p>
          <h2>只在这台 Mac 上</h2>
          <p class="sub" style="margin:0">快捷手势不联网，也不上传任何东西。手势设置和录下的笔迹存在 <code>~/Library/Application Support/GesturePad/rules.json</code>，触发记录只写进系统日志。</p>
        </div>
        <div>
          <p class="eyebrow">参与</p>
          <h2>开源，欢迎一起改</h2>
          <p class="sub" style="margin:0">代码用 MIT 许可。识别器在 <code>GesturePadCore</code> 里，有单元测试，不依赖界面，很适合从这里上手。提问题、提建议、发 PR 都欢迎。</p>
          <div class="actions" style="justify-content:flex-start">
            <a class="btn" href="{REPO}/blob/main/CONTRIBUTING.md">贡献指南</a>
            <a class="btn" href="{REPO}/issues">反馈问题</a>
          </div>
        </div>
      </div>
    </section>
  </main>'''


def gestures_body():
    toc = "\n".join(f'          <li><a href="#{key}">{title}</a></li>' for key, title, _, _ in GROUPS)
    sections = []
    for key, title, hint, rows in GROUPS:
        items = "\n".join(f'''          <div class="rule">
            <div class="glyph sm">{glyph}</div>
            <div><strong>{html.escape(name)}</strong><span>{html.escape(how)}</span></div>
            {action}
          </div>''' for glyph, name, how, action in rows)
        sections.append(f'''      <section class="group" id="{key}">
        <h2>{title}<small>{len(rows)} 条</small></h2>
        <p class="sub">{html.escape(hint)}</p>
        <div class="rules">
{items}
        </div>
      </section>''')
    return f'''  <main>
    <div class="wrap">
      <div class="page-head">
        <p class="eyebrow">默认手势</p>
        <h1>全部手势</h1>
        <p class="lead">第一次打开时就是这一套。圆点是落笔的地方。设置里可以开关、修改、删除每一条，也可以添加自己的手势。</p>
        <ul class="toc">
{toc}
        </ul>
      </div>
{chr(10).join(sections)}
    </div>
  </main>'''


def write(name, text):
    with open(os.path.join(OUT, name), "w", encoding="utf-8") as f:
        f.write(text)


write("index.html", page("快捷手势 · macOS 手势工具",
                         "开源的 macOS 菜单栏手势工具。按住鼠标右键画一笔，打开应用、发快捷键、移动窗口。",
                         "home", INDEX))
write("gestures.html", page("全部手势 · 快捷手势", "快捷手势的默认手势表。每一条都可以在设置里修改或关掉。",
                            "gestures", gestures_body()))
print("wrote docs/index.html and docs/gestures.html")
