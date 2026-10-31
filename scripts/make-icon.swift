import AppKit
let folder = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.lockFocus()
        let factor = CGFloat(pixels) / 512
        let transform = NSAffineTransform(); transform.scale(by: factor); transform.concat()
        NSColor(calibratedRed: 0.20, green: 0.34, blue: 0.32, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 18, y: 18, width: 476, height: 476), xRadius: 105, yRadius: 105).fill()
        NSColor(calibratedWhite: 1, alpha: 0.75).setFill()
        NSBezierPath(roundedRect: NSRect(x: 78, y: 124, width: 12, height: 264), xRadius: 6, yRadius: 6).fill()
        for y in [286, 146] {
            NSColor(calibratedWhite: 1, alpha: 0.12).setFill()
            NSBezierPath(roundedRect: NSRect(x: 120, y: y, width: 280, height: 110), xRadius: 18, yRadius: 18).fill()
            NSColor(calibratedWhite: 1, alpha: 0.92).setStroke()
            for (dy, width) in [(70, 176), (40, 120)] {
                let line = NSBezierPath(); line.move(to: NSPoint(x: 150, y: y + dy)); line.line(to: NSPoint(x: 150 + width, y: y + dy)); line.lineWidth = 8; line.lineCapStyle = .round; line.stroke()
            }
        }
        image.unlockFocus()
        let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
        let name = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: folder).appendingPathComponent(name))
    }
}
