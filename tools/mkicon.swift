import AppKit

// Genera el .icns de Tapadera: taza monocroma sobre bandeja clara,
// siguiendo la silueta redondeada del sistema. Sin degradados ni brillos.

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
let sizes = [16, 32, 64, 128, 256, 512, 1024]
let cfg = NSImage.SymbolConfiguration(pointSize: 512, weight: .regular)

guard let symbol = NSImage(systemSymbolName: "cup.and.saucer.fill",
                           accessibilityDescription: nil)?
        .withSymbolConfiguration(cfg) else {
    FileHandle.standardError.write(Data("no se pudo cargar el simbolo\n".utf8))
    exit(1)
}

for s in sizes {
    let side = CGFloat(s)
    let img = NSImage(size: NSSize(width: side, height: side))
    img.lockFocus()

    let inset = side * 0.06
    let tray = NSRect(x: inset, y: inset, width: side - inset * 2, height: side - inset * 2)
    let path = NSBezierPath(roundedRect: tray,
                            xRadius: side * 0.225, yRadius: side * 0.225)
    NSColor(calibratedWhite: 0.97, alpha: 1).setFill()
    path.fill()
    NSColor(calibratedWhite: 0.78, alpha: 1).setStroke()
    path.lineWidth = max(1, side * 0.006)
    path.stroke()

    let g = side * 0.30
    let glyph = NSRect(x: g, y: g, width: side - g * 2, height: side - g * 2)
    let tinted = NSImage(size: glyph.size)
    tinted.lockFocus()
    symbol.draw(in: NSRect(origin: .zero, size: glyph.size),
                from: .zero, operation: .sourceOver, fraction: 1)
    NSColor(calibratedWhite: 0.13, alpha: 1).set()
    NSRect(origin: .zero, size: glyph.size).fill(using: .sourceAtop)
    tinted.unlockFocus()
    tinted.draw(in: glyph)

    img.unlockFocus()

    guard let tiff = img.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else { continue }
    try? png.write(to: URL(fileURLWithPath: "\(out)/icon_\(s).png"))
}
