import AppKit
import Foundation

let size = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

let background = NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: size, height: size), xRadius: 226, yRadius: 226)
NSColor(srgbRed: 0.05, green: 0.38, blue: 0.95, alpha: 1).setFill()
background.fill()

let configuration = NSImage.SymbolConfiguration(pointSize: 470, weight: .semibold)
let symbol = NSImage(systemSymbolName: "square.and.arrow.up", accessibilityDescription: nil)!
    .withSymbolConfiguration(configuration)!
NSGraphicsContext.current?.imageInterpolation = .high
let symbolRect = NSRect(x: (size - symbol.size.width) / 2, y: (size - symbol.size.height) / 2, width: symbol.size.width, height: symbol.size.height)
NSColor.white.setFill()
let tinted = NSImage(size: symbol.size, flipped: false) { rect in
    symbol.draw(in: rect)
    NSColor.white.set()
    rect.fill(using: .sourceIn)
    return true
}
tinted.draw(in: symbolRect)

image.unlockFocus()
guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    fputs("Could not encode app icon.\n", stderr)
    exit(1)
}
try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
