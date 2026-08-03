import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
  fputs("Usage: generate-icon.swift <output.png>\n", stderr)
  exit(2)
}

let pixels = 1024
guard let bitmap = NSBitmapImageRep(
  bitmapDataPlanes: nil,
  pixelsWide: pixels,
  pixelsHigh: pixels,
  bitsPerSample: 8,
  samplesPerPixel: 4,
  hasAlpha: true,
  isPlanar: false,
  colorSpaceName: .deviceRGB,
  bytesPerRow: 0,
  bitsPerPixel: 0
) else {
  fputs("Could not create icon bitmap.\n", stderr)
  exit(1)
}
bitmap.size = NSSize(width: pixels, height: pixels)
NSGraphicsContext.saveGraphicsState()
guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
  fputs("Could not create icon graphics context.\n", stderr)
  exit(1)
}
NSGraphicsContext.current = context

// Nexo concentric-ring mark: 深色底、绿青双环与中心光点。
let canvas = NSRect(x: 64, y: 64, width: 896, height: 896)
let cornerRadius: CGFloat = 288
let background = NSBezierPath(roundedRect: canvas, xRadius: cornerRadius, yRadius: cornerRadius)
let navy = NSColor(calibratedRed: 0.0392, green: 0.0549, blue: 0.1020, alpha: 1) // #0a0e1a
let green = NSColor(calibratedRed: 0.5725, green: 0.9961, blue: 0.6157, alpha: 1) // #92FE9D
let cyan = NSColor(calibratedRed: 0.0000, green: 0.7882, blue: 1.0000, alpha: 1) // #00C9FF

navy.setFill()
background.fill()
let outer = NSBezierPath(ovalIn: NSRect(x: 176, y: 176, width: 672, height: 672))
green.setStroke()
outer.lineWidth = 76
outer.stroke()
let inner = NSBezierPath(ovalIn: NSRect(x: 316, y: 316, width: 392, height: 392))
cyan.withAlphaComponent(0.92).setStroke()
inner.lineWidth = 58
inner.stroke()
cyan.setFill()
NSBezierPath(ovalIn: NSRect(x: 454, y: 454, width: 116, height: 116)).fill()

context.flushGraphics()
NSGraphicsContext.restoreGraphicsState()

guard let data = bitmap.representation(using: .png, properties: [:]) else {
  fputs("Could not encode icon PNG.\n", stderr)
  exit(1)
}
do {
  try data.write(to: URL(fileURLWithPath: CommandLine.arguments[1]), options: .atomic)
} catch {
  fputs("Could not write icon: \(error.localizedDescription)\n", stderr)
  exit(1)
}
