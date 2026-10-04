// Draws Switchboard's app icon and writes Resources/AppIcon.icns.
// Run with: swift scripts/make-icon.swift
//
// A wall light switch, flipped on, against warm light. The artwork fills the whole
// square; macOS masks it to the rounded app-icon shape.
import AppKit
import CoreGraphics

let canvas = 1024
let srgb = CGColorSpace(name: CGColorSpace.sRGB)!

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha)
}

func makeContext(_ size: Int) -> CGContext {
    CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
              space: srgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}

func roundedRect(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

func verticalGradient(_ ctx: CGContext, in rect: CGRect, top: UInt32, bottom: UInt32) {
    let gradient = CGGradient(colorsSpace: srgb, colors: [color(top), color(bottom)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: rect.midX, y: rect.maxY),
                           end: CGPoint(x: rect.midX, y: rect.minY), options: [])
}

func drawIcon() -> CGImage {
    let ctx = makeContext(canvas)
    let full = CGRect(x: 0, y: 0, width: canvas, height: canvas)

    // Background: warm amber, the colour of a lamp just switched on.
    verticalGradient(ctx, in: full, top: 0xFFC94D, bottom: 0xF59A1B)

    // The wall plate, white, standing off the wall with a soft shadow.
    let plate = CGRect(x: 512 - 260, y: 512 - 370, width: 520, height: 740)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -18), blur: 44, color: color(0x7A3E00, 0.38))
    ctx.addPath(roundedRect(plate, 70))
    ctx.setFillColor(color(0xFFFFFF))
    ctx.fillPath()
    ctx.restoreGState()

    // Two screws, the giveaway that this is a wall switch.
    for y in [plate.maxY - 78, plate.minY + 78] {
        let screw = CGRect(x: 512 - 24, y: y - 24, width: 48, height: 48)
        ctx.addEllipse(in: screw)
        ctx.setFillColor(color(0xD5DAE4))
        ctx.fillPath()
        ctx.setFillColor(color(0x9AA3B8))
        ctx.fill(CGRect(x: 512 - 15, y: y - 4, width: 30, height: 8))
    }

    // The rocker's opening in the plate.
    let opening = CGRect(x: 512 - 150, y: 512 - 230, width: 300, height: 460)
    ctx.addPath(roundedRect(opening, 44))
    ctx.setFillColor(color(0xC3C9D6))
    ctx.fillPath()

    // The rocker, pressed at the bottom so its top half stands out toward you: on.
    let rocker = opening.insetBy(dx: 16, dy: 16)
    let split = rocker.minY + rocker.height * 0.5
    ctx.saveGState()
    ctx.addPath(roundedRect(rocker, 32))
    ctx.clip()
    // Lower half, tipped back into the wall and in shade.
    verticalGradient(ctx, in: CGRect(x: rocker.minX, y: rocker.minY, width: rocker.width, height: split - rocker.minY),
                     top: 0x7D87A1, bottom: 0x9CA5BC)
    // Upper half, tipped forward into the light, casting a shadow down onto the lower.
    ctx.setShadow(offset: CGSize(width: 0, height: -26), blur: 30, color: color(0x232A4D, 0.55))
    ctx.addPath(roundedRect(CGRect(x: rocker.minX, y: split, width: rocker.width, height: rocker.maxY - split + 40), 0))
    ctx.setFillColor(color(0xFFFFFF))
    ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(roundedRect(rocker, 32))
    ctx.clip()
    verticalGradient(ctx, in: CGRect(x: rocker.minX, y: split, width: rocker.width, height: rocker.maxY - split),
                     top: 0xFFFFFF, bottom: 0xF1F3F8)
    ctx.restoreGState()

    return ctx.makeImage()!
}

func resized(_ image: CGImage, to size: Int) -> CGImage {
    let ctx = makeContext(size)
    ctx.interpolationQuality = .high
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
    return ctx.makeImage()!
}

func writePNG(_ image: CGImage, to url: URL) {
    let rep = NSBitmapImageRep(cgImage: image)
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconset = root.appendingPathComponent("build/AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

let master = drawIcon()
writePNG(master, to: root.appendingPathComponent("Resources/AppIcon.png"))
for points in [16, 32, 128, 256, 512] {
    writePNG(resized(master, to: points), to: iconset.appendingPathComponent("icon_\(points)x\(points).png"))
    writePNG(resized(master, to: points * 2), to: iconset.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", root.appendingPathComponent("Resources/AppIcon.icns").path]
try! iconutil.run()
iconutil.waitUntilExit()
print(iconutil.terminationStatus == 0 ? "Wrote Resources/AppIcon.icns" : "iconutil failed")
