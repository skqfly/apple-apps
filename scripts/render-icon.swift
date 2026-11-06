import AppKit
import Foundation

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    fputs("Usage: render-icon.swift <site-mark.svg> <AppIcon.png>\n", stderr)
    exit(1)
}

let source = URL(fileURLWithPath: arguments[1])
let destination = URL(fileURLWithPath: arguments[2])
let canvas = NSRect(x: 0, y: 0, width: 1024, height: 1024)
let image = NSImage(size: canvas.size)

image.lockFocus()
NSColor(srgbRed: 0.965, green: 0.955, blue: 0.937, alpha: 1).setFill()
NSBezierPath(roundedRect: canvas, xRadius: 226, yRadius: 226).fill()

guard let mark = NSImage(contentsOf: source) else {
    fputs("Could not read site mark.\n", stderr)
    exit(1)
}
let markRect = canvas.insetBy(dx: 214, dy: 214)
mark.draw(in: markRect, from: NSRect(origin: .zero, size: mark.size), operation: .sourceOver, fraction: 1)

image.unlockFocus()
guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    fputs("Could not encode app icon.\n", stderr)
    exit(1)
}
try png.write(to: destination)
