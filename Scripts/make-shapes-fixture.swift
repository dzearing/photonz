#!/usr/bin/env swift
// Renders `Tests/PhotonzRenderTests/Fixtures/people-panel-2x.png`: the kind of
// screen Size mode was failing on (2026-10-11), drawn with known geometry so
// the tests can pin what a person should read. Round photo avatars, an initials
// avatar, a presence dot, an overlapping avatar stack, app icons on tinted
// tiles, a pill and a round count badge, a card with a photo, and one plain
// bordered button and some text as the regression check.
//
// Everything is laid out in logical points and drawn at 2x, stamped 144 DPI,
// exactly like a Retina screenshot. The photo texture is seeded, so the file
// comes out the same every run. Only rerun it to change the specimens, and
// update ShapeDetectionFixtureTests to match.
//
//   swift Scripts/make-shapes-fixture.swift

import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let width = 480, height = 360, scale = 2
let out = URL(fileURLWithPath: CommandLine.arguments.count > 1
              ? CommandLine.arguments[1]
              : "Tests/PhotonzRenderTests/Fixtures/people-panel-2x.png")

let space = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: width * scale, height: height * scale, bitsPerComponent: 8,
                    bytesPerRow: 0, space: space,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
// Top-left origin in points, like the document model.
ctx.translateBy(x: 0, y: CGFloat(height * scale))
ctx.scaleBy(x: CGFloat(scale), y: CGFloat(-scale))
NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)

func rgb(_ hex: UInt32) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: 1)
}

func fill(_ path: CGPath, _ color: CGColor) {
    ctx.addPath(path)
    ctx.setFillColor(color)
    ctx.fillPath()
}

func text(_ s: String, at p: CGPoint, size: CGFloat, color: NSColor, weight: NSFont.Weight = .regular) {
    let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size, weight: weight),
                                                .foregroundColor: color]
    NSAttributedString(string: s, attributes: attrs).draw(at: p)
}

func centered(_ s: String, in r: CGRect, size: CGFloat, color: NSColor, weight: NSFont.Weight = .semibold) {
    let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size, weight: weight),
                                                .foregroundColor: color]
    let str = NSAttributedString(string: s, attributes: attrs)
    let sz = str.size()
    str.draw(at: CGPoint(x: r.midX - sz.width / 2, y: r.midY - sz.height / 2))
}

// A seeded generator so the "photos" are the same every run.
var seed: UInt64 = 0x5eed_1234
func rand() -> CGFloat {
    seed = seed &* 6364136223846793005 &+ 1442695040888963407
    return CGFloat((seed >> 33) & 0xffff) / 65535
}

/// A head-and-shoulders portrait clipped to `clip`: a coloured backdrop with a
/// gradient, a face, hair, a shirt and a little noise, so its insides are full
/// of edges the old pair-of-boundaries reader could latch on to.
func portrait(in r: CGRect, clip: CGPath, backdrop: (UInt32, UInt32), skin: UInt32,
              hair: UInt32, shirt: UInt32) {
    ctx.saveGState()
    ctx.addPath(clip)
    ctx.clip()
    let grad = CGGradient(colorsSpace: space, colors: [rgb(backdrop.0), rgb(backdrop.1)] as CFArray,
                          locations: [0, 1])!
    ctx.drawLinearGradient(grad, start: CGPoint(x: r.minX, y: r.minY),
                           end: CGPoint(x: r.maxX, y: r.maxY), options: [])
    let u = r.width
    fill(CGPath(ellipseIn: CGRect(x: r.minX + 0.12 * u, y: r.minY + 0.66 * u,
                                  width: 0.76 * u, height: 0.6 * u), transform: nil), rgb(shirt))
    fill(CGPath(ellipseIn: CGRect(x: r.minX + 0.3 * u, y: r.minY + 0.18 * u,
                                  width: 0.4 * u, height: 0.48 * u), transform: nil), rgb(skin))
    fill(CGPath(ellipseIn: CGRect(x: r.minX + 0.27 * u, y: r.minY + 0.12 * u,
                                  width: 0.46 * u, height: 0.22 * u), transform: nil), rgb(hair))
    for _ in 0..<Int(u * 3) {
        let x = r.minX + rand() * u, y = r.minY + rand() * u
        let g = 0.85 + 0.3 * rand()
        ctx.setFillColor(CGColor(gray: g, alpha: 0.12))
        ctx.fill(CGRect(x: x, y: y, width: 0.5, height: 0.5))
    }
    ctx.restoreGState()
}

func avatar(_ r: CGRect, backdrop: (UInt32, UInt32), skin: UInt32, hair: UInt32, shirt: UInt32) {
    portrait(in: r, clip: CGPath(ellipseIn: r, transform: nil), backdrop: backdrop,
             skin: skin, hair: hair, shirt: shirt)
}

let white = rgb(0xffffff)
let page = rgb(0xf3f3f3)

// Page and the two cards.
fill(CGPath(rect: CGRect(x: 0, y: 0, width: width, height: height), transform: nil), page)
let listCard = CGRect(x: 12, y: 12, width: 248, height: 336)
fill(CGPath(roundedRect: listCard, cornerWidth: 10, cornerHeight: 10, transform: nil), white)

// Row 1: a 32 pt photo avatar at (24, 24) with a presence dot cut out of its
// corner by a 2 pt ring, and a name beside it.
let a1 = CGRect(x: 24, y: 24, width: 32, height: 32)
avatar(a1, backdrop: (0x9ec5e8, 0x5b8fc7), skin: 0xf1c7a3, hair: 0x3b2a20, shirt: 0x2d4f7c)
let dot = CGRect(x: 46, y: 46, width: 10, height: 10)
fill(CGPath(ellipseIn: dot.insetBy(dx: -2, dy: -2), transform: nil), white)
fill(CGPath(ellipseIn: dot, transform: nil), rgb(0x34c759))
text("Avery Johnson", at: CGPoint(x: 66, y: 24), size: 13, color: .black, weight: .medium)
text("Design lead", at: CGPoint(x: 66, y: 41), size: 11, color: .darkGray)

// Row 2: a 32 pt initials avatar at (24, 72).
let a2 = CGRect(x: 24, y: 72, width: 32, height: 32)
fill(CGPath(ellipseIn: a2, transform: nil), rgb(0x8a5cf6))
centered("MK", in: a2, size: 13, color: .white)
text("Maya Kim", at: CGPoint(x: 66, y: 72), size: 13, color: .black, weight: .medium)
text("Engineer", at: CGPoint(x: 66, y: 89), size: 11, color: .darkGray)

// Row 3: a 40 pt photo avatar at (24, 116), pale backdrop that nearly melts
// into the card.
let a3 = CGRect(x: 24, y: 116, width: 40, height: 40)
avatar(a3, backdrop: (0xe9e4dc, 0xcfc4b4), skin: 0xd9a27a, hair: 0x1d1d1d, shirt: 0xb0413e)
text("Sam Ortiz", at: CGPoint(x: 74, y: 128), size: 13, color: .black, weight: .medium)

// A stack: four 24 pt avatars every 16 pt, each wearing a 2 pt white ring that
// cuts it out of the one before, then a "+3" pill the same height. On the white
// card the ring is invisible, so the stack reads 32 ... 136 by 176 ... 200.
let stackTones: [((UInt32, UInt32), UInt32, UInt32, UInt32)] = [
    ((0xf7c59f, 0xef8354), 0xf3d2b8, 0x5a3825, 0x22577a),
    ((0xb5e48c, 0x52b69a), 0xc68642, 0x111111, 0xf4f1de),
    ((0xcdb4db, 0x9d4edd), 0xe0ac69, 0x8d5524, 0x264653),
    ((0xa8dadc, 0x457b9d), 0xffdbac, 0xb5651d, 0xe63946),
]
for (i, tone) in stackTones.enumerated() {
    let r = CGRect(x: 32 + CGFloat(i) * 16, y: 176, width: 24, height: 24)
    fill(CGPath(ellipseIn: r.insetBy(dx: -2, dy: -2), transform: nil), white)
    avatar(r, backdrop: tone.0, skin: tone.1, hair: tone.2, shirt: tone.3)
}
let more = CGRect(x: 96, y: 176, width: 40, height: 24)
fill(CGPath(roundedRect: more.insetBy(dx: -2, dy: -2), cornerWidth: 14, cornerHeight: 14,
            transform: nil), white)
fill(CGPath(roundedRect: more, cornerWidth: 12, cornerHeight: 12, transform: nil), rgb(0xe5e5ea))
centered("+3", in: more, size: 11, color: .darkGray)

// App icons: 40 pt tiles with 9 pt corners, a white glyph on each.
let icons: [(CGRect, UInt32)] = [
    (CGRect(x: 24, y: 224, width: 40, height: 40), 0x0a84ff),
    (CGRect(x: 76, y: 224, width: 40, height: 40), 0xff9f0a),
    (CGRect(x: 128, y: 224, width: 40, height: 40), 0x30d158),
]
for (r, tone) in icons {
    fill(CGPath(roundedRect: r, cornerWidth: 9, cornerHeight: 9, transform: nil), rgb(tone))
}
fill(CGPath(ellipseIn: icons[0].0.insetBy(dx: 11, dy: 11), transform: nil), white)
fill(CGPath(rect: icons[1].0.insetBy(dx: 12, dy: 17), transform: nil), white)
fill(CGPath(rect: icons[1].0.insetBy(dx: 17, dy: 10), transform: nil), white)
for k in 0..<3 {
    fill(CGPath(roundedRect: CGRect(x: icons[2].0.minX + 10 + CGFloat(k) * 7,
                                    y: icons[2].0.minY + 26 - CGFloat(k) * 6,
                                    width: 5, height: 4 + CGFloat(k) * 6),
                cornerWidth: 1, cornerHeight: 1, transform: nil), white)
}

// Badges: a pill "New" 40 x 20 and a round count "3" 18 x 18.
let pill = CGRect(x: 24, y: 288, width: 40, height: 20)
fill(CGPath(roundedRect: pill, cornerWidth: 10, cornerHeight: 10, transform: nil), rgb(0x0a84ff))
centered("New", in: pill, size: 11, color: .white)
let count = CGRect(x: 76, y: 289, width: 18, height: 18)
fill(CGPath(ellipseIn: count, transform: nil), rgb(0xff3b30))
centered("3", in: count, size: 11, color: .white)

// A card with a photo: 168 x 180 at (280, 12), a 1 pt hairline border, and a
// 152 x 88 photo with 6 pt corners inside it.
let card = CGRect(x: 280, y: 12, width: 168, height: 180)
fill(CGPath(roundedRect: card, cornerWidth: 10, cornerHeight: 10, transform: nil), rgb(0xd8d8dc))
fill(CGPath(roundedRect: card.insetBy(dx: 1, dy: 1), cornerWidth: 9, cornerHeight: 9,
            transform: nil), white)
let photo = CGRect(x: 288, y: 20, width: 152, height: 88)
portrait(in: photo, clip: CGPath(roundedRect: photo, cornerWidth: 6, cornerHeight: 6, transform: nil),
         backdrop: (0x87bba2, 0x364958), skin: 0xe8b796, hair: 0x2b2118, shirt: 0xc9e4ca)
text("Team offsite", at: CGPoint(x: 288, y: 118), size: 15, color: .black, weight: .semibold)
text("Thursday, 9:00", at: CGPoint(x: 288, y: 140), size: 11, color: .darkGray)

// The regression check: a plain bordered button, 80 x 28.
let button = CGRect(x: 280, y: 220, width: 80, height: 28)
fill(CGPath(roundedRect: button, cornerWidth: 6, cornerHeight: 6, transform: nil), rgb(0xc7c7cc))
fill(CGPath(roundedRect: button.insetBy(dx: 1, dy: 1), cornerWidth: 5, cornerHeight: 5,
            transform: nil), white)
centered("Save", in: button, size: 13, color: .black, weight: .regular)

NSGraphicsContext.current = nil
guard let image = ctx.makeImage(),
      let dest = CGImageDestinationCreateWithURL(out as CFURL, UTType.png.identifier as CFString, 1, nil)
else { fatalError("could not render") }
CGImageDestinationAddImage(dest, image, [kCGImagePropertyDPIWidth: 144,
                                         kCGImagePropertyDPIHeight: 144] as CFDictionary)
guard CGImageDestinationFinalize(dest) else { fatalError("could not write \(out.path)") }
print("wrote \(out.path) (\(width * scale) x \(height * scale))")
