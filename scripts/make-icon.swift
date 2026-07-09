#!/usr/bin/env swift
// Genera Resources/AppIcon.icns con la onda de Marea sobre fondo teal.
// Uso: swift scripts/make-icon.swift
import AppKit

let outDir = "Resources"
let iconset = "\(outDir)/Marea.iconset"
try? FileManager.default.createDirectory(atPath: iconset, withIntermediateDirectories: true)

// Paleta Marea (de la config de Ghostty/Orca)
let navy = NSColor(srgbRed: 0x11/255.0, green: 0x16/255.0, blue: 0x1d/255.0, alpha: 1)
let teal = NSColor(srgbRed: 0x07/255.0, green: 0xed/255.0, blue: 0xc7/255.0, alpha: 1)
let tealDim = NSColor(srgbRed: 0x0a/255.0, green: 0x9d/255.0, blue: 0x88/255.0, alpha: 1)

func render(_ px: Int) -> Data {
    let size = CGFloat(px)
    let img = NSImage(size: NSSize(width: size, height: size))
    img.lockFocus()
    let ctx = NSGraphicsContext.current!
    ctx.imageInterpolation = .high

    // Fondo: rounded-square con gradiente (macOS "squircle"-ish)
    let inset = size * 0.06
    let rect = NSRect(x: inset, y: inset, width: size - 2*inset, height: size - 2*inset)
    let radius = rect.width * 0.225
    let bg = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    NSGradient(colors: [tealDim, navy])!.draw(in: bg, angle: -90)
    bg.addClip()

    // Brillo sutil arriba
    NSGradient(colors: [teal.withAlphaComponent(0.28), .clear])!.draw(in: rect, angle: -90)

    // Onda (SF Symbol water.waves) centrada, en teal claro
    let cfg = NSImage.SymbolConfiguration(pointSize: size * 0.52, weight: .semibold)
    if let sym = NSImage(systemSymbolName: "water.waves", accessibilityDescription: nil)?
        .withSymbolConfiguration(cfg) {
        let tint = NSImage(size: sym.size)
        tint.lockFocus()
        teal.set()
        NSRect(origin: .zero, size: sym.size).fill()
        sym.draw(at: .zero, from: .zero, operation: .destinationIn, fraction: 1)
        tint.unlockFocus()
        let w = sym.size.width, h = sym.size.height
        tint.draw(in: NSRect(x: (size - w)/2, y: (size - h)/2, width: w, height: h))
    }

    img.unlockFocus()
    let tiff = img.tiffRepresentation!
    let rep = NSBitmapImageRep(data: tiff)!
    return rep.representation(using: .png, properties: [:])!
}

// tamaños del iconset de macOS
let specs: [(Int, String)] = [
    (16,"16x16"),(32,"16x16@2x"),(32,"32x32"),(64,"32x32@2x"),
    (128,"128x128"),(256,"128x128@2x"),(256,"256x256"),(512,"256x256@2x"),
    (512,"512x512"),(1024,"512x512@2x")
]
for (px, name) in specs {
    let data = render(px)
    try! data.write(to: URL(fileURLWithPath: "\(iconset)/icon_\(name).png"))
}
print("iconset generado en \(iconset)")
