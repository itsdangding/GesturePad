import AppKit

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : FileManager.default.currentDirectoryPath)
let packaging = root.appendingPathComponent("packaging")
let docs = root.appendingPathComponent("docs")
let iconset = packaging.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)

let paper = NSColor(srgbRed: 0.953, green: 0.941, blue: 0.910, alpha: 1)
let ink = NSColor(srgbRed: 0.102, green: 0.094, blue: 0.082, alpha: 1)
let mark = NSColor(srgbRed: 0.831, green: 0.325, blue: 0.169, alpha: 1)

func point(_ x: CGFloat, _ y: CGFloat, in rect: CGRect) -> CGPoint {
    CGPoint(x: rect.minX + x / 100 * rect.width, y: rect.minY + y / 100 * rect.height)
}

func drawIcon(side: Int) {
    let rect = NSRect(x: 0, y: 0, width: side, height: side)
    NSColor.clear.setFill()
    rect.fill()
    paper.setFill()
    rect.fill()

    let stroke = NSBezierPath()
    stroke.move(to: point(74, 76, in: rect))
    stroke.curve(to: point(22, 28, in: rect), controlPoint1: point(72, 44, in: rect), controlPoint2: point(40, 26, in: rect))
    stroke.lineWidth = CGFloat(side) * 0.085
    stroke.lineCapStyle = .round
    mark.setStroke()
    stroke.stroke()

    let origin = point(74, 76, in: rect)
    let radius = CGFloat(side) * 0.055
    ink.setFill()
    NSBezierPath(ovalIn: NSRect(x: origin.x - radius, y: origin.y - radius, width: radius * 2, height: radius * 2)).fill()
}

func png(side: Int, _ url: URL) throws {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: side,
        pixelsHigh: side,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        throw NSError(domain: "icon", code: 1)
    }
    rep.size = NSSize(width: side, height: side)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    drawIcon(side: side)
    NSGraphicsContext.restoreGraphicsState()
    guard let data = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "icon", code: 2)
    }
    try data.write(to: url)
}

let sizes: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]
for (name, side) in sizes {
    try png(side: side, iconset.appendingPathComponent(name))
}
try png(side: 1024, docs.appendingPathComponent("icon.png"))

let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", packaging.appendingPathComponent("AppIcon.icns").path]
try task.run()
task.waitUntilExit()
if task.terminationStatus != 0 {
    fputs("iconutil failed\n", stderr)
    exit(1)
}
try? FileManager.default.removeItem(at: iconset)
print(packaging.appendingPathComponent("AppIcon.icns").path)
