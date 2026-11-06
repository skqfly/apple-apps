import AppKit
import Foundation

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    fputs("Usage: render-icon.swift <logo.svg> <AppIcon.png>\n", stderr)
    exit(1)
}

let source = URL(fileURLWithPath: arguments[1])
let destination = URL(fileURLWithPath: arguments[2])
let canvas = NSRect(x: 0, y: 0, width: 1024, height: 1024)
let image = NSImage(size: canvas.size)
image.lockFocus()

NSColor(srgbRed: 0.965, green: 0.955, blue: 0.937, alpha: 1).setFill()
NSBezierPath(roundedRect: canvas, xRadius: 226, yRadius: 226).fill()

guard let logo = NSImage(contentsOf: source) else {
    fputs("Could not read the website SVG.\n", stderr)
    exit(1)
}
let longest = max(logo.size.width, logo.size.height)
let scale = 620 / longest
let drawSize = NSSize(width: logo.size.width * scale, height: logo.size.height * scale)
let drawRect = NSRect(
    x: (canvas.width - drawSize.width) / 2,
    y: (canvas.height - drawSize.height) / 2,
    width: drawSize.width,
    height: drawSize.height
)
logo.draw(in: drawRect, from: NSRect(origin: .zero, size: logo.size), operation: .sourceOver, fraction: 1)

image.unlockFocus()
guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    fputs("Could not encode app icon.\n", stderr)
    exit(1)
}
try png.write(to: destination)
