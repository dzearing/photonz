import CoreGraphics
import Foundation
import Testing
import PhotonzCore
@testable import PhotonzRender

/// The paint bucket on a picture: flood the area of similar colour around the
/// click and fill only that, the way Photoshop's bucket does.
@Suite("Bucket fill (paint bucket on a picture)")
struct BucketFillTests {

    private let width = 120, height = 100
    private let white = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
    private let black = CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)

    /// The user's picture, in miniature: four thin anti-aliased black lines on
    /// white that cross at the corners and enclose a box, the right one leaning
    /// a little so every edge pixel is a blend. `gap` breaks the bottom line.
    private func box(lineWidth: CGFloat = 1, gap: Bool = false) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height,
                                bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(white)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        // Top-left coordinates, flipped into the context's bottom-left.
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        context.setShouldAntialias(true)
        context.setStrokeColor(black)
        context.setLineWidth(lineWidth)
        let segments: [(CGPoint, CGPoint)] = [
            (CGPoint(x: 10.3, y: 20.4), CGPoint(x: 100.2, y: 15.7)),    // top
            (CGPoint(x: 20.6, y: 8.2), CGPoint(x: 18.1, y: 90.5)),      // left
            (CGPoint(x: 92.4, y: 6.3), CGPoint(x: 97.8, y: 92.1)),      // right
        ]
        for (a, b) in segments {
            context.move(to: a); context.addLine(to: b)
        }
        if gap {
            context.move(to: CGPoint(x: 8.5, y: 78.3)); context.addLine(to: CGPoint(x: 50, y: 82))
            context.move(to: CGPoint(x: 60, y: 83)); context.addLine(to: CGPoint(x: 105.6, y: 87.4))
        } else {
            context.move(to: CGPoint(x: 8.5, y: 78.3)); context.addLine(to: CGPoint(x: 105.6, y: 87.4))
        }
        context.strokePath()
        return context.makeImage()!
    }

    private struct Pixels {
        let bytes: [UInt8]
        let width: Int
        func at(_ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int, a: Int) {
            let o = (y * width + x) * 4
            return (Int(bytes[o]), Int(bytes[o + 1]), Int(bytes[o + 2]), Int(bytes[o + 3]))
        }
    }

    private func pixels(_ image: CGImage) -> Pixels {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = CGContext(data: &bytes, width: image.width, height: image.height,
                                bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return Pixels(bytes: bytes, width: image.width)
    }

    /// Clearly inside the box: a margin of three pixels off every line.
    private func deepInside(_ x: Int, _ y: Int) -> Bool {
        (24...88).contains(x) && (24...76).contains(y)
    }

    /// Clearly outside the box: past every line by three pixels or more.
    private func farOutside(_ x: Int, _ y: Int) -> Bool {
        x < 14 || x > 102 || y < 10 || y > 94
    }

    private let blue = "#0000FF"

    // MARK: The user's report

    @Test func aClickInsideAClosedBoxFillsTheBoxAndNothingElse() throws {
        let image = box()
        let filled = try #require(BucketFill.filled(image, at: CGPoint(x: 55, y: 50),
                                                    hex: blue, options: .photoshop))
        let before = pixels(image), after = pixels(filled)
        var whiteLeftInside = 0, changedOutside = 0
        for y in 0..<height {
            for x in 0..<width {
                let p = after.at(x, y)
                if deepInside(x, y), !(p.r == 0 && p.g == 0 && p.b == 255) { whiteLeftInside += 1 }
                if farOutside(x, y), p != before.at(x, y) { changedOutside += 1 }
            }
        }
        #expect(whiteLeftInside == 0)
        #expect(changedOutside == 0)
    }

    @Test func aThinAntiAliasedLineLeavesNoWhiteRingInside() throws {
        // Every pixel inside the box, right up to the lines, ends up some mix of
        // the black line and the blue fill. White left behind would show as red
        // and green; a seed-coloured pixel is white within the tolerance.
        let image = box()
        let filled = try #require(BucketFill.filled(image, at: CGPoint(x: 55, y: 50),
                                                    hex: blue, options: .photoshop))
        let after = pixels(filled)
        let mask = try #require(FloodFill.mask(in: image, from: CGPoint(x: 55, y: 50), tolerance: 32))
        var seedColouredLeft = 0, palest = 0
        for y in 0..<height {
            for x in 0..<width {
                let p = after.at(x, y)
                let distance = Double((255 - p.r) * (255 - p.r) + (255 - p.g) * (255 - p.g)
                                      + (255 - p.b) * (255 - p.b))
                // Only the box: the mask and the pixels touching it.
                let near = (-1...1).contains { dy in (-1...1).contains { dx in
                    let nx = x + dx, ny = y + dy
                    return nx >= 0 && ny >= 0 && nx < width && ny < height && mask.mask[ny * width + nx]
                } }
                guard near else { continue }
                if distance.squareRoot() <= 32 { seedColouredLeft += 1 }
                if mask.mask[y * width + x] || p.b > p.r + 40 { palest = max(palest, min(p.r, p.g)) }
            }
        }
        #expect(seedColouredLeft == 0)
        // A pixel that took the fill keeps at most a trace of white.
        #expect(palest < 90)
    }

    @Test func aGapInTheLinesLetsTheFillLeakOut() throws {
        let image = box(gap: true)
        let filled = try #require(BucketFill.filled(image, at: CGPoint(x: 55, y: 50),
                                                    hex: blue, options: .photoshop))
        let after = pixels(filled)
        // Below the broken bottom line is the outside, and it is blue now.
        let p = after.at(55, 97)
        #expect(p.r == 0 && p.g == 0 && p.b == 255)
    }

    // MARK: Settings

    @Test func toleranceDecidesWhetherANearColourJoins() throws {
        // Left half white, right half a light grey 26 units of distance away.
        let context = CGContext(data: nil, width: 20, height: 10, bitsPerComponent: 8,
                                bytesPerRow: 80, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(white)
        context.fill(CGRect(x: 0, y: 0, width: 20, height: 10))
        context.setFillColor(CGColor(srgbRed: 240 / 255, green: 240 / 255, blue: 240 / 255, alpha: 1))
        context.fill(CGRect(x: 10, y: 0, width: 10, height: 10))
        let image = try #require(context.makeImage())

        var tight = BucketFill.Options.photoshop
        tight.tolerance = 10
        let strict = pixels(try #require(BucketFill.filled(image, at: CGPoint(x: 2, y: 5),
                                                           hex: blue, options: tight)))
        #expect(strict.at(15, 5).b == 240)
        let loose = pixels(try #require(BucketFill.filled(image, at: CGPoint(x: 2, y: 5),
                                                          hex: blue, options: .photoshop)))
        #expect(loose.at(15, 5).r == 0 && loose.at(15, 5).b == 255)
    }

    @Test func contiguousOffFillsEveryPixelOfThatColour() throws {
        // A black wall down the middle: two white rooms.
        let context = CGContext(data: nil, width: 21, height: 10, bitsPerComponent: 8,
                                bytesPerRow: 84, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(white)
        context.fill(CGRect(x: 0, y: 0, width: 21, height: 10))
        context.setFillColor(black)
        context.fill(CGRect(x: 10, y: 0, width: 1, height: 10))
        let image = try #require(context.makeImage())

        let together = pixels(try #require(BucketFill.filled(image, at: CGPoint(x: 2, y: 5),
                                                             hex: blue, options: .photoshop)))
        #expect(together.at(2, 5).b == 255 && together.at(2, 5).r == 0)
        #expect(together.at(18, 5).r == 255)

        var everywhere = BucketFill.Options.photoshop
        everywhere.contiguous = false
        let apart = pixels(try #require(BucketFill.filled(image, at: CGPoint(x: 2, y: 5),
                                                          hex: blue, options: everywhere)))
        #expect(apart.at(18, 5).r == 0 && apart.at(18, 5).b == 255)
        // The wall itself is no colour of the seed's and stays black.
        #expect(apart.at(10, 5).r == 0 && apart.at(10, 5).b == 0)
    }

    @Test func antiAliasOffLeavesBlendedEdgePixelsAlone() throws {
        let image = box()
        var hard = BucketFill.Options.photoshop
        hard.antiAlias = false
        let before = pixels(image)
        let after = pixels(try #require(BucketFill.filled(image, at: CGPoint(x: 55, y: 50),
                                                          hex: blue, options: hard)))
        let mask = try #require(FloodFill.mask(in: image, from: CGPoint(x: 55, y: 50), tolerance: 32))
        var changedOffMask = 0, unfilledOnMask = 0
        for y in 0..<height {
            for x in 0..<width {
                let p = after.at(x, y)
                if mask.mask[y * width + x] {
                    if !(p.r == 0 && p.g == 0 && p.b == 255) { unfilledOnMask += 1 }
                } else if p != before.at(x, y) {
                    changedOffMask += 1
                }
            }
        }
        #expect(unfilledOnMask == 0)
        #expect(changedOffMask == 0)
    }

    @Test func antiAliasOnSoftensTheEdgeIntoTheLine() throws {
        // With anti-alias, pixels just past the flood's edge (blends of white and
        // the line) take their share of the fill rather than staying pale.
        let image = box()
        let before = pixels(image)
        let after = pixels(try #require(BucketFill.filled(image, at: CGPoint(x: 55, y: 50),
                                                          hex: blue, options: .photoshop)))
        let mask = try #require(FloodFill.mask(in: image, from: CGPoint(x: 55, y: 50), tolerance: 32))
        var softened = 0
        for y in 0..<height {
            for x in 0..<width where !mask.mask[y * width + x] && after.at(x, y) != before.at(x, y) {
                softened += 1
            }
        }
        #expect(softened > 50)
    }

    // MARK: Transparency and the edges of the bitmap

    @Test func aTransparentAreaFillsOpaque() throws {
        let context = CGContext(data: nil, width: 10, height: 10, bitsPerComponent: 8,
                                bytesPerRow: 40, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(black)
        context.fill(CGRect(x: 5, y: 0, width: 5, height: 10))
        let image = try #require(context.makeImage())
        let after = pixels(try #require(BucketFill.filled(image, at: CGPoint(x: 1, y: 1),
                                                          hex: blue, options: .photoshop)))
        #expect(after.at(1, 1) == (0, 0, 255, 255))
        #expect(after.at(8, 1) == (0, 0, 0, 255))
    }

    @Test func aClickOffTheBitmapFillsNothing() {
        #expect(BucketFill.filled(box(), at: CGPoint(x: -1, y: 4), hex: blue, options: .photoshop) == nil)
        #expect(BucketFill.filled(box(), at: CGPoint(x: 4, y: 100), hex: blue, options: .photoshop) == nil)
    }

    @Test func theDefaultsAreThePhotoshopOnes() {
        #expect(BucketFill.Options.photoshop.tolerance == 32)
        #expect(BucketFill.Options.photoshop.antiAlias)
        #expect(BucketFill.Options.photoshop.contiguous)
    }
}
