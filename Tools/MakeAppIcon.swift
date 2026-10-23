import AppKit

// Keep the master full-bleed. Apply a precise legacy macOS icon silhouette here,
// so the transparent bounds are square, symmetric, and free of stray pixels.
let arguments = CommandLine.arguments
guard arguments.count == 3 else { fatalError("Usage: MakeAppIcon <opaque square master> <output PNG>") }
guard let source = NSImage(contentsOfFile: arguments[1]) else { fatalError("Cannot load app icon master") }
let master = NSBitmapImageRep(data: try Data(contentsOf: URL(fileURLWithPath: arguments[1])))!
precondition(master.pixelsWide == master.pixelsHigh, "App icon master must be square")
for y in 0..<master.pixelsHigh {
    for x in 0..<master.pixelsWide {
        precondition((master.colorAt(x: x, y: y)?.alphaComponent ?? 0) >= 0.999,
                     "App icon master must be full-bleed and opaque; masking happens during packaging")
    }
}
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024,
                             bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                             isPlanar: false, colorSpaceName: .deviceRGB,
                             bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
NSGraphicsContext.current?.imageInterpolation = .high
let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185).addClip()
source.draw(in: tile, from: .zero, operation: .copy, fraction: 1)
NSGraphicsContext.restoreGraphicsState()
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: arguments[2]))
