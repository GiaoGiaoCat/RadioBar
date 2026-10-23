import AppKit

// Render through Icon Services, rather than reading the raw ICNS: macOS may reshape it.
let arguments = CommandLine.arguments
guard arguments.count == 3 else { fatalError("Usage: RenderAppIcon <App path> <output directory>") }
let output = URL(fileURLWithPath: arguments[2], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
let icon = NSWorkspace.shared.icon(forFile: arguments[1])
for size in [64, 128, 256] {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                                 bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                 isPlanar: false, colorSpaceName: .deviceRGB,
                                 bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    icon.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
    NSGraphicsContext.restoreGraphicsState()
    let hasPixels = (0..<size).contains { y in
        (0..<size).contains { x in (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0 }
    }
    precondition(hasPixels, "Icon Services returned an empty image; run in an accessible macOS graphical session")
    let file = output.appendingPathComponent("icon-\(size).png")
    try bitmap.representation(using: .png, properties: [:])!.write(to: file)
    print("Rendered system app icon: \(file.path)")
}
