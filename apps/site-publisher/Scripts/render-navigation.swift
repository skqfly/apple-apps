import AppKit
import Foundation

let size = NSSize(width: 402, height: 874)
let image = NSImage(size: size)
image.lockFocus()

NSColor(srgbRed: 0.965, green: 0.955, blue: 0.937, alpha: 1).setFill()
NSRect(origin: .zero, size: size).fill()

func text(_ value: String, _ rect: NSRect, _ font: NSFont, _ color: NSColor) {
    NSAttributedString(string: value, attributes: [
        .font: font,
        .foregroundColor: color
    ]).draw(in: rect)
}

text("博客", NSRect(x: 24, y: 735, width: 250, height: 58), .systemFont(ofSize: 38, weight: .bold), .labelColor)
text("文章草稿、发布状态与分类。", NSRect(x: 24, y: 690, width: 330, height: 34), .systemFont(ofSize: 16), .secondaryLabelColor)

let card = NSBezierPath(roundedRect: NSRect(x: 20, y: 470, width: 362, height: 190), xRadius: 24, yRadius: 24)
NSColor.white.withAlphaComponent(0.9).setFill()
card.fill()
text("发布队列", NSRect(x: 40, y: 605, width: 220, height: 32), .systemFont(ofSize: 22, weight: .semibold), .labelColor)
text("内容连接还没有配置。", NSRect(x: 40, y: 565, width: 300, height: 28), .systemFont(ofSize: 15), .secondaryLabelColor)
for (index, label) in ["草稿", "待发布", "已发布"].enumerated() {
    let x = CGFloat(42 + index * 112)
    text("0", NSRect(x: x, y: 515, width: 80, height: 32), .monospacedDigitSystemFont(ofSize: 26, weight: .semibold), .labelColor)
    text(label, NSRect(x: x, y: 488, width: 90, height: 22), .systemFont(ofSize: 13), .secondaryLabelColor)
}

let barRect = NSRect(x: 16, y: 28, width: 370, height: 78)
NSColor.white.withAlphaComponent(0.42).setFill()
NSBezierPath(roundedRect: barRect, xRadius: 39, yRadius: 39).fill()
NSColor.white.withAlphaComponent(0.75).setStroke()
let border = NSBezierPath(roundedRect: barRect, xRadius: 39, yRadius: 39)
border.lineWidth = 1
border.stroke()
NSColor.white.withAlphaComponent(0.68).setFill()
NSBezierPath(roundedRect: NSRect(x: 22, y: 34, width: 86, height: 66), xRadius: 33, yRadius: 33).fill()

let items = [
    ("text.alignleft", "博客", true),
    ("square.stack.3d.up", "项目", false),
    ("person.wave.2", "分享", false),
    ("person.2", "朋友", false)
]
for (index, item) in items.enumerated() {
    let x = CGFloat(22 + index * 92)
    let color = item.2 ? NSColor(srgbRed: 0.05, green: 0.38, blue: 0.95, alpha: 1) : NSColor.labelColor
    let symbol = NSImage(systemSymbolName: item.0, accessibilityDescription: nil)!
        .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 20, weight: .regular))!
    let tinted = NSImage(size: symbol.size, flipped: false) { rect in
        symbol.draw(in: rect)
        color.set()
        rect.fill(using: .sourceIn)
        return true
    }
    tinted.draw(in: NSRect(x: x + (86 - symbol.size.width) / 2, y: 68, width: symbol.size.width, height: symbol.size.height))
    let label = NSAttributedString(string: item.1, attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: color])
    let labelWidth = label.size().width
    label.draw(at: NSPoint(x: x + (86 - labelWidth) / 2, y: 44))
}
NSColor.black.setFill()
NSBezierPath(roundedRect: NSRect(x: 136, y: 10, width: 130, height: 5), xRadius: 2.5, yRadius: 2.5).fill()

image.unlockFocus()
guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    fputs("Could not encode navigation preview.\n", stderr)
    exit(1)
}
try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
