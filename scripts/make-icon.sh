#!/bin/bash
# Generates AppIcon.icns (a key glyph on an indigo→purple rounded square) using only the
# system toolchain — renders a 1024px master with AppKit, then sips + iconutil for the iconset.
set -euo pipefail
cd "$(dirname "$0")"
OUT_PNG="$PWD/AppIcon-1024.png"
ICONSET="$PWD/AppIcon.iconset"
ICNS="$PWD/AppIcon.icns"

cat > /tmp/notiful_icon.swift <<'SWIFT'
import AppKit

let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
let ctx = NSGraphicsContext.current!.cgContext

// Rounded-square background with a diagonal gradient.
let inset: CGFloat = 0
let rect = CGRect(x: inset, y: inset, width: size - inset*2, height: size - inset*2)
let radius: CGFloat = size * 0.2237  // macOS "squircle"-ish corner
let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
path.addClip()
let gradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.36, green: 0.32, blue: 0.86, alpha: 1),  // indigo
    NSColor(calibratedRed: 0.55, green: 0.27, blue: 0.80, alpha: 1),  // purple
])!
gradient.draw(in: rect, angle: -45)

// White key glyph, centered.
let cfg = NSImage.SymbolConfiguration(pointSize: size * 0.5, weight: .semibold)
if let sym = NSImage(systemSymbolName: "key.fill", accessibilityDescription: nil)?
    .withSymbolConfiguration(cfg) {
    let tinted = NSImage(size: sym.size)
    tinted.lockFocus()
    NSColor.white.set()
    let r = NSRect(origin: .zero, size: sym.size)
    sym.draw(in: r)
    r.fill(using: .sourceAtop)
    tinted.unlockFocus()
    // rotate slightly for a friendlier look
    ctx.saveGState()
    ctx.translateBy(x: size/2, y: size/2)
    ctx.rotate(by: -.pi/8)
    let w = sym.size.width, h = sym.size.height
    let scale = (size * 0.52) / max(w, h)
    let dw = w * scale, dh = h * scale
    tinted.draw(in: NSRect(x: -dw/2, y: -dh/2, width: dw, height: dh))
    ctx.restoreGState()
}

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write(Data("failed to render icon\n".utf8)); exit(1)
}
let outPath = CommandLine.arguments[1]
try! png.write(to: URL(fileURLWithPath: outPath))
SWIFT

echo "==> Rendering 1024px master"
swift /tmp/notiful_icon.swift "$OUT_PNG"

echo "==> Building iconset"
rm -rf "$ICONSET"; mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z $s $s        "$OUT_PNG" --out "$ICONSET/icon_${s}x${s}.png"     >/dev/null
  sips -z $((s*2)) $((s*2)) "$OUT_PNG" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done

echo "==> iconutil → $ICNS"
iconutil -c icns "$ICONSET" -o "$ICNS"
rm -rf "$ICONSET"
echo "Done: $ICNS"
