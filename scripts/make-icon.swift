import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Geometric icon, rendered locally; no external images or model calls.
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let output = root.appendingPathComponent("build/AppIcon.iconset")
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
let artwork = root.appendingPathComponent("Resources/icons")
try FileManager.default.createDirectory(at: artwork, withIntermediateDirectories: true)
let svg = """
<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
  <rect x="64" y="64" width="896" height="896" rx="212" fill="#172635"/>
  <rect x="166" y="338" width="692" height="348" rx="92" fill="#eef3f6"/>
  <rect x="246" y="474" width="76" height="128" rx="22" fill="#283e51"/>
  <rect x="364" y="418" width="76" height="184" rx="22" fill="#283e51"/>
  <rect x="482" y="450" width="76" height="152" rx="22" fill="#283e51"/>
  <circle cx="718" cy="478" r="48" fill="#26b98c"/>
  <rect x="654" y="570" width="128" height="26" rx="13" fill="#aebfc9"/>
</svg>
"""
try svg.write(to: artwork.appendingPathComponent("AppIcon.svg"), atomically: true, encoding: .utf8)
func color(_ hex: UInt32) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255,
            blue: CGFloat(hex & 255) / 255, alpha: 1)
}
func render(_ size: Int, to url: URL) throws {
    guard let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { fatalError("No graphics context") }
    let scale = CGFloat(size) / 1024
    context.translateBy(x: 0, y: CGFloat(size)); context.scaleBy(x: scale, y: -scale)
    context.setAllowsAntialiasing(true); context.setShouldAntialias(true)
    func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ radius: CGFloat, _ fill: UInt32) {
        context.setFillColor(color(fill))
        context.addPath(CGPath(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerWidth: radius, cornerHeight: radius, transform: nil)); context.fillPath()
    }
    rect(64,64,896,896,212,0x172635)
    rect(166,338,692,348,92,0xeef3f6)
    rect(246,474,76,128,22,0x283e51)
    rect(364,418,76,184,22,0x283e51)
    rect(482,450,76,152,22,0x283e51)
    context.setFillColor(color(0x26b98c)); context.fillEllipse(in: CGRect(x: 670, y: 430, width: 96, height: 96))
    rect(654,570,128,26,13,0xaebfc9)
    guard let image = context.makeImage(), let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { fatalError("No PNG destination") }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { fatalError("Could not save icon") }
}
for size in [16,32,128,256,512] {
    try render(size, to: output.appendingPathComponent("icon_\(size)x\(size).png"))
    try render(size * 2, to: output.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
try render(1024, to: artwork.appendingPathComponent("AppIcon.png"))
try render(128, to: artwork.appendingPathComponent("AppIcon-preview.png"))
print("Generated editable SVG, PNG previews and standard macOS iconset")
