#!/usr/bin/env swift
// Renders `Tests/PhotonzRenderTests/Fixtures/objects-1x.png` and `objects-2x.png`:
// the buttons and cards Size mode could not read on 2026-10-13 ("the size tool's
// edge detection is great for text but hoooooorible for just objects"). Big
// pills wider than 160 points, gradient fills, a glow and a drop shadow round
// them, a button the same brightness as its page in another colour, a big flat
// button and a card, all with known geometry so the tests can pin the number a
// spec would quote.
//
// Everything is laid out in logical points and drawn at 1x and 2x (the 2x one
// stamped 144 DPI, exactly like a Retina screenshot). Only rerun it to change
// the specimens, and update ObjectDetectionFixtureTests to match.
//
//   swift Scripts/make-objects-fixture.swift

import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let width = 640, height = 400
let folder = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1] : "Tests/PhotonzRenderTests/Fixtures"

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: alpha)
}

func render(scale: Int) {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: width * scale, height: height * scale, bitsPerComponent: 8,
                        bytesPerRow: 0, space: space,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.translateBy(x: 0, y: CGFloat(height * scale))
    ctx.scaleBy(x: CGFloat(scale), y: CGFloat(-scale))
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)

    func fill(_ rect: CGRect, _ color: CGColor) {
        ctx.setFillColor(color)
        ctx.fill(rect)
    }

    func pill(_ r: CGRect, radius: CGFloat) -> CGPath {
        CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)
    }

    /// A rounded shape filled top to bottom from `top` to `bottom`, with an
    /// optional soft shadow (or glow) under it.
    func shape(_ r: CGRect, radius: CGFloat, top: UInt32, bottom: UInt32,
               shadow: (dy: CGFloat, blur: CGFloat, color: CGColor)? = nil) {
        let path = pill(r, radius: radius)
        if let shadow {
            ctx.saveGState()
            // The context is flipped, so a shadow offset down the page is +y in
            // the flipped space, which CG reads in the unflipped base space.
            ctx.setShadow(offset: CGSize(width: 0, height: -shadow.dy * CGFloat(scale)),
                          blur: shadow.blur * CGFloat(scale), color: shadow.color)
            ctx.addPath(path)
            ctx.setFillColor(rgb(bottom))
            ctx.fillPath()
            ctx.restoreGState()
        }
        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        let gradient = CGGradient(colorsSpace: space, colors: [rgb(top), rgb(bottom)] as CFArray,
                                  locations: [0, 1])!
        ctx.drawLinearGradient(gradient, start: CGPoint(x: r.midX, y: r.minY),
                               end: CGPoint(x: r.midX, y: r.maxY), options: [])
        ctx.restoreGState()
    }

    func label(_ s: String, in r: CGRect, size: CGFloat, color: NSColor,
               weight: NSFont.Weight = .semibold) {
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size, weight: weight),
                                                    .foregroundColor: color]
        let str = NSAttributedString(string: s, attributes: attrs)
        let sz = str.size()
        str.draw(at: CGPoint(x: r.midX - sz.width / 2, y: r.midY - sz.height / 2))
    }

    // Left half: a near black page, like a product site.
    fill(CGRect(x: 0, y: 0, width: 320, height: 400), rgb(0x0b0a10))
    // A: a 240 x 56 gradient pill with a purple glow, the user's case.
    let a = CGRect(x: 40, y: 40, width: 240, height: 56)
    shape(a, radius: 28, top: 0x9d6bff, bottom: 0x7c3aed,
          shadow: (dy: 12, blur: 32, color: rgb(0x7c3aed, 0.45)))
    label("Get started", in: a, size: 19, color: .white)
    // B: a 200 x 40 flat teal button, no halo.
    let b = CGRect(x: 60, y: 160, width: 200, height: 40)
    shape(b, radius: 8, top: 0x14b8a6, bottom: 0x14b8a6)
    label("Continue", in: b, size: 15, color: .white)
    // C: a 280 x 48 dark card button barely off the page, with a white label.
    let c = CGRect(x: 20, y: 250, width: 280, height: 48)
    shape(c, radius: 10, top: 0x2a2833, bottom: 0x2a2833)
    label("Open the full changelog", in: c, size: 15, color: .white, weight: .regular)

    // Right half: a mid grey page, where a red button is as bright as the page.
    fill(CGRect(x: 320, y: 0, width: 320, height: 160), rgb(0x7f7f7f))
    // D: 200 x 40, #d0604a (luma 127 on a luma 127 page).
    let d = CGRect(x: 380, y: 60, width: 200, height: 40)
    shape(d, radius: 20, top: 0xd0604a, bottom: 0xd0604a)
    label("Delete", in: d, size: 15, color: .white)

    // Right, lower: a light page with a card under a soft shadow and a big
    // flat button.
    fill(CGRect(x: 320, y: 160, width: 320, height: 240), rgb(0xf2f2f7))
    // E: a 240 x 100 white card with a drop shadow.
    let e = CGRect(x: 360, y: 180, width: 240, height: 100)
    shape(e, radius: 12, top: 0xffffff, bottom: 0xffffff,
          shadow: (dy: 6, blur: 20, color: rgb(0x000000, 0.18)))
    label("Weekly report", in: CGRect(x: 360, y: 180, width: 240, height: 40), size: 15,
          color: .black)
    // F: a 280 x 44 navy button with a blue glow, wider than 160 points.
    let f = CGRect(x: 340, y: 320, width: 280, height: 44)
    shape(f, radius: 22, top: 0x3b82f6, bottom: 0x1d4ed8,
          shadow: (dy: 4, blur: 16, color: rgb(0x3b82f6, 0.5)))
    label("Upgrade to Pro", in: f, size: 15, color: .white)

    NSGraphicsContext.current = nil
    let out = URL(fileURLWithPath: "\(folder)/objects-\(scale)x.png")
    guard let image = ctx.makeImage(),
          let dest = CGImageDestinationCreateWithURL(out as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { fatalError("could not render") }
    let dpi = 72 * scale
    CGImageDestinationAddImage(dest, image, [kCGImagePropertyDPIWidth: dpi,
                                             kCGImagePropertyDPIHeight: dpi] as CFDictionary)
    guard CGImageDestinationFinalize(dest) else { fatalError("could not write \(out.path)") }
    print("wrote \(out.path) (\(width * scale) x \(height * scale))")
}

render(scale: 1)
render(scale: 2)
