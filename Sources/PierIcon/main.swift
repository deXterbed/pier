import AppKit
import CoreGraphics
import Foundation

// Draws Pier's app icon at build time. The repo ships no binary art — the icon is code,
// like everything else here.

let sizes: [(name: String, pixels: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

guard CommandLine.arguments.count > 1 else {
    FileHandle.standardError.write(Data("usage: PierIcon <output.iconset>\n".utf8))
    exit(1)
}

let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

func squircle(in rect: CGRect) -> CGPath {
    CGPath(
        roundedRect: rect,
        cornerWidth: rect.width * 0.2237,
        cornerHeight: rect.height * 0.2237,
        transform: nil
    )
}

func draw(size: CGFloat) -> CGImage? {
    let space = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
        data: nil,
        width: Int(size),
        height: Int(size),
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    context.setAllowsAntialiasing(true)
    context.interpolationQuality = .high

    let inset = size * 0.09
    let plate = CGRect(x: inset, y: inset * 1.25, width: size - inset * 2, height: size - inset * 2)

    context.saveGState()
    context.setShadow(
        offset: CGSize(width: 0, height: -size * 0.012),
        blur: size * 0.045,
        color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.45)
    )
    context.addPath(squircle(in: plate))
    context.setFillColor(CGColor(red: 0.09, green: 0.10, blue: 0.13, alpha: 1))
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(squircle(in: plate))
    context.clip()
    if let gradient = CGGradient(
        colorsSpace: space,
        colors: [
            CGColor(red: 0.19, green: 0.21, blue: 0.28, alpha: 1),
            CGColor(red: 0.06, green: 0.07, blue: 0.11, alpha: 1),
        ] as CFArray,
        locations: [0, 1]
    ) {
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: plate.midX, y: plate.maxY),
            end: CGPoint(x: plate.midX, y: plate.minY),
            options: []
        )
    }
    context.setLineWidth(size * 0.006)
    context.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.16))
    context.addPath(squircle(in: plate.insetBy(dx: size * 0.004, dy: size * 0.004)))
    context.strokePath()
    context.restoreGState()

    /// Two docks — one lying down, one standing up. That's the whole app in one mark.
    func dock(_ rect: CGRect, dots: Int, vertical: Bool, fill: CGColor, dotColor: CGColor) {
        let radius = min(rect.width, rect.height) / 2
        context.saveGState()
        context.setShadow(
            offset: CGSize(width: 0, height: -size * 0.005),
            blur: size * 0.02,
            color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.35)
        )
        context.addPath(
            CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        )
        context.setFillColor(fill)
        context.fillPath()
        context.restoreGState()

        let thickness = min(rect.width, rect.height)
        let dotSize = thickness * 0.46
        let span = (vertical ? rect.height : rect.width) - thickness
        let step = dots > 1 ? span / CGFloat(dots - 1) : 0
        let start = vertical
            ? CGPoint(x: rect.midX, y: rect.minY + thickness / 2)
            : CGPoint(x: rect.minX + thickness / 2, y: rect.midY)

        context.setFillColor(dotColor)
        for index in 0..<dots {
            let centre = vertical
                ? CGPoint(x: start.x, y: start.y + step * CGFloat(index))
                : CGPoint(x: start.x + step * CGFloat(index), y: start.y)
            context.fillEllipse(in: CGRect(
                x: centre.x - dotSize / 2,
                y: centre.y - dotSize / 2,
                width: dotSize,
                height: dotSize
            ))
        }
    }

    let blue = CGColor(red: 0.24, green: 0.47, blue: 0.98, alpha: 1)
    let pale = CGColor(red: 1, green: 1, blue: 1, alpha: 0.28)

    // The standing dock, tucked behind and to the left.
    dock(
        CGRect(
            x: plate.minX + plate.width * 0.13,
            y: plate.midY - plate.height * 0.09,
            width: plate.width * 0.17,
            height: plate.height * 0.50
        ),
        dots: 3,
        vertical: true,
        fill: pale,
        dotColor: CGColor(red: 1, green: 1, blue: 1, alpha: 0.72)
    )

    // The lying-down dock, in front.
    dock(
        CGRect(
            x: plate.minX + plate.width * 0.25,
            y: plate.minY + plate.height * 0.19,
            width: plate.width * 0.62,
            height: plate.height * 0.20
        ),
        dots: 3,
        vertical: false,
        fill: blue,
        dotColor: CGColor(red: 1, green: 1, blue: 1, alpha: 0.95)
    )

    return context.makeImage()
}

for entry in sizes {
    guard let image = draw(size: CGFloat(entry.pixels)) else { continue }
    let rep = NSBitmapImageRep(cgImage: image)
    rep.size = NSSize(width: entry.pixels, height: entry.pixels)
    guard let data = rep.representation(using: .png, properties: [:]) else { continue }
    try data.write(to: output.appendingPathComponent("\(entry.name).png"))
}

print("wrote \(sizes.count) icon sizes to \(output.path)")
