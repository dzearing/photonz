import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import AppKit

// Generates the thumbnail shapes the history strip has to cope with, for
// Scripts/playtest/history-thumbnail-shapes-walk.json. Run it as:
//   swift Scripts/playtest/fixtures/thumbnail-shapes/make-shapes.swift <this folder>
// The wide recording beside these comes from a separate AVAssetWriter script;
// it is 1600x300, three seconds, same leading/trailing markings.
// Each picture is deliberately ASYMMETRIC left-to-right so a crop anchor is
// visible: a coloured "logo" block at the leading edge, a row of "buttons"
// toward the trailing edge, and a numbered label at each end.

func draw(width: Int, height: Int, hue: CGFloat) -> CGImage {
    let cs = CGColorSpaceCreateDeviceRGB()
    let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                        bytesPerRow: 0, space: cs,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    // Background bar
    ctx.setFillColor(NSColor(hue: hue, saturation: 0.10, brightness: 0.96, alpha: 1).cgColor)
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

    let w = CGFloat(width), h = CGFloat(height)
    let unit = min(w, h)

    // Leading-edge "logo": a filled square hugging the left edge.
    ctx.setFillColor(NSColor(hue: hue, saturation: 0.75, brightness: 0.75, alpha: 1).cgColor)
    ctx.fill(CGRect(x: unit * 0.12, y: h * 0.25, width: unit * 0.5, height: h * 0.5))

    // Trailing-edge "buttons": three pills hugging the right edge.
    ctx.setFillColor(NSColor(hue: hue, saturation: 0.35, brightness: 0.55, alpha: 1).cgColor)
    for i in 0..<3 {
        let bw = unit * 0.34
        let x = w - unit * 0.12 - CGFloat(i + 1) * (bw + unit * 0.12)
        ctx.fill(CGRect(x: x, y: h * 0.3, width: bw, height: h * 0.4))
    }

    // A centre stripe, so "did the middle survive the crop" is answerable.
    ctx.setFillColor(NSColor.black.withAlphaComponent(0.35).cgColor)
    ctx.fill(CGRect(x: w / 2 - unit * 0.03, y: 0, width: unit * 0.06, height: h))

    // Frame
    ctx.setStrokeColor(NSColor.black.withAlphaComponent(0.5).cgColor)
    ctx.setLineWidth(max(1, unit * 0.02))
    ctx.stroke(CGRect(x: 0, y: 0, width: w, height: h).insetBy(dx: unit * 0.01, dy: unit * 0.01))
    return ctx.makeImage()!
}

func write(_ image: CGImage, to path: String, dpi: Double) {
    let url = URL(fileURLWithPath: path)
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, [kCGImagePropertyDPIWidth: dpi,
                                             kCGImagePropertyDPIHeight: dpi] as CFDictionary)
    CGImageDestinationFinalize(dest)
    print("wrote \(path) \(image.width)x\(image.height) @\(Int(dpi))dpi")
}

let dir = CommandLine.arguments[1]
write(draw(width: 2400, height: 300, hue: 0.58), to: "\(dir)/Shape 1 wide 2400x300.png", dpi: 72)
write(draw(width: 1200, height: 800, hue: 0.33), to: "\(dir)/Shape 2 ordinary 1200x800.png", dpi: 72)
write(draw(width: 60, height: 30, hue: 0.08), to: "\(dir)/Shape 3 tiny 60x30.png", dpi: 72)
write(draw(width: 120, height: 60, hue: 0.80), to: "\(dir)/Shape 4 tiny 2x 120x60.png", dpi: 144)
write(draw(width: 40, height: 600, hue: 0.0), to: "\(dir)/Shape 5 tall 40x600.png", dpi: 72)
