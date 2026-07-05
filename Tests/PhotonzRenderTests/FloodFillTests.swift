import CoreGraphics
import Foundation
import Testing
import PhotonzCore
@testable import PhotonzRender

@Suite("Flood fill (magic wand)")
struct FloodFillTests {

    /// Draws colored rects (top-left coordinates) onto a background color.
    private func image(width: Int, height: Int,
                       background: CGColor,
                       rects: [(CGRect, CGColor)] = []) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height,
                                bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(background)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        for (rect, color) in rects {
            // CGContext is bottom-left; flip y so top-left rects land right.
            let flipped = CGRect(x: rect.minX, y: CGFloat(height) - rect.maxY,
                                 width: rect.width, height: rect.height)
            context.setFillColor(color)
            context.fill(flipped)
        }
        return context.makeImage()!
    }

    private let white = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
    private let black = CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
    private let red = CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)

    private func isSet(_ result: FloodFill.Mask, _ x: Int, _ y: Int) -> Bool {
        result.mask[y * result.width + x]
    }

    private func setCount(_ result: FloodFill.Mask) -> Int {
        result.mask.count(where: { $0 })
    }

    // MARK: Basics

    @Test func seedOutsideTheImageYieldsNil() {
        let img = image(width: 10, height: 10, background: white)
        #expect(FloodFill.mask(in: img, from: CGPoint(x: -1, y: 5), tolerance: 0) == nil)
        #expect(FloodFill.mask(in: img, from: CGPoint(x: 5, y: 10), tolerance: 0) == nil)
    }

    @Test func uniformImageFloodsEverything() throws {
        let img = image(width: 8, height: 6, background: white)
        let result = try #require(FloodFill.mask(in: img, from: CGPoint(x: 4, y: 3), tolerance: 0))
        #expect(result.width == 8 && result.height == 6)
        #expect(setCount(result) == 48)
    }

    @Test func floodStopsAtAColorBoundary() throws {
        // Left half black, right half white; seed in the left half.
        let img = image(width: 20, height: 10, background: white,
                        rects: [(CGRect(x: 0, y: 0, width: 10, height: 10), black)])
        let result = try #require(FloodFill.mask(in: img, from: CGPoint(x: 2, y: 5), tolerance: 0))
        #expect(setCount(result) == 100)
        #expect(isSet(result, 9, 5))
        #expect(!isSet(result, 10, 5))
    }

    @Test func maskIsInTopLeftRowOrder() throws {
        // Black box only in the TOP-left corner; a flood seeded there must set
        // low row indices, proving the buffer is not vertically flipped.
        let img = image(width: 10, height: 10, background: white,
                        rects: [(CGRect(x: 0, y: 0, width: 4, height: 4), black)])
        let result = try #require(FloodFill.mask(in: img, from: CGPoint(x: 1, y: 1), tolerance: 0))
        #expect(setCount(result) == 16)
        #expect(isSet(result, 1, 1))
        #expect(!isSet(result, 1, 8))
    }

    // MARK: Contiguity

    @Test func onlyTheContiguousBlobIsSelected() throws {
        // Two same-colored squares that do not touch; seed hits one.
        let img = image(width: 20, height: 20, background: white, rects: [
            (CGRect(x: 1, y: 1, width: 4, height: 4), red),
            (CGRect(x: 12, y: 12, width: 4, height: 4), red),
        ])
        let result = try #require(FloodFill.mask(in: img, from: CGPoint(x: 2, y: 2), tolerance: 0))
        #expect(setCount(result) == 16)
        #expect(isSet(result, 2, 2))
        #expect(!isSet(result, 13, 13))
    }

    @Test func diagonalTouchDoesNotLeak() throws {
        // Two red squares meeting only at a corner: 4-connectivity keeps the
        // flood inside the seeded one.
        let img = image(width: 8, height: 8, background: white, rects: [
            (CGRect(x: 0, y: 0, width: 3, height: 3), red),
            (CGRect(x: 3, y: 3, width: 3, height: 3), red),
        ])
        let result = try #require(FloodFill.mask(in: img, from: CGPoint(x: 1, y: 1), tolerance: 0))
        #expect(setCount(result) == 9)
        #expect(!isSet(result, 4, 4))
    }

    @Test func concaveShapesFillCompletely() throws {
        // A "U" of black: left wall, right wall, bottom bar. The scanline fill
        // must reach both arms from a seed in one of them.
        let img = image(width: 12, height: 12, background: white, rects: [
            (CGRect(x: 1, y: 1, width: 2, height: 9), black),
            (CGRect(x: 9, y: 1, width: 2, height: 9), black),
            (CGRect(x: 1, y: 8, width: 10, height: 2), black),
        ])
        let result = try #require(FloodFill.mask(in: img, from: CGPoint(x: 1, y: 2), tolerance: 0))
        #expect(isSet(result, 10, 2))   // other arm reached via the bottom bar
        #expect(!isSet(result, 5, 2))   // white gap between the arms untouched
        #expect(setCount(result) == 2 * 9 + 2 * 9 + 2 * 6) // walls + bar remainder
    }

    // MARK: Tolerance

    @Test func toleranceZeroRequiresExactMatch() throws {
        // Background 200-gray, one near-match 204-gray box adjacent to seed.
        let gray200 = CGColor(srgbRed: 200 / 255, green: 200 / 255, blue: 200 / 255, alpha: 1)
        let gray204 = CGColor(srgbRed: 204 / 255, green: 204 / 255, blue: 204 / 255, alpha: 1)
        let img = image(width: 10, height: 10, background: gray200,
                        rects: [(CGRect(x: 5, y: 0, width: 5, height: 10), gray204)])
        let exact = try #require(FloodFill.mask(in: img, from: CGPoint(x: 2, y: 5), tolerance: 0))
        #expect(setCount(exact) == 50)
        #expect(!isSet(exact, 7, 5))
    }

    @Test func toleranceAdmitsNearbyShades() throws {
        // Euclidean RGB distance between 200- and 204-gray = √(3·4²) ≈ 6.9:
        // tolerance 7 crosses, tolerance 5 does not.
        let gray200 = CGColor(srgbRed: 200 / 255, green: 200 / 255, blue: 200 / 255, alpha: 1)
        let gray204 = CGColor(srgbRed: 204 / 255, green: 204 / 255, blue: 204 / 255, alpha: 1)
        let img = image(width: 10, height: 10, background: gray200,
                        rects: [(CGRect(x: 5, y: 0, width: 5, height: 10), gray204)])
        let loose = try #require(FloodFill.mask(in: img, from: CGPoint(x: 2, y: 5), tolerance: 7))
        #expect(setCount(loose) == 100)
        let tight = try #require(FloodFill.mask(in: img, from: CGPoint(x: 2, y: 5), tolerance: 5))
        #expect(setCount(tight) == 50)
    }

    @Test func toleranceComparesAgainstTheSeedNotTheNeighbor() throws {
        // A gradient of steps (0, 10, 20, ... gray): with tolerance 12 a seed at
        // step 0 admits step 10 but must NOT creep step-by-step to step 20
        // (distance from the SEED is what counts, Photoshop-style).
        let steps: [(CGRect, CGColor)] = (0..<5).map { i in
            let v = CGFloat(i) * 10 / 255
            return (CGRect(x: i * 4, y: 0, width: 4, height: 4),
                    CGColor(srgbRed: v, green: v, blue: v, alpha: 1))
        }
        let img = image(width: 20, height: 4, background: white, rects: steps)
        let result = try #require(FloodFill.mask(in: img, from: CGPoint(x: 1, y: 1), tolerance: 20))
        #expect(isSet(result, 5, 1))    // step 10: √300 ≈ 17.3 ≤ 20
        #expect(!isSet(result, 9, 1))   // step 20: √1200 ≈ 34.6 > 20
    }

    // MARK: Composes into a selection path

    @Test func pathWrapsTheFloodedRegion() throws {
        let img = image(width: 20, height: 10, background: white,
                        rects: [(CGRect(x: 0, y: 0, width: 10, height: 10), black)])
        let path = try #require(FloodFill.path(in: img, from: CGPoint(x: 2, y: 5), tolerance: 0))
        #expect(path.boundingBoxOfPath == CGRect(x: 0, y: 0, width: 10, height: 10))
        let region = try #require(SelectionRegion(path: path))
        #expect(region.contains(CGPoint(x: 5, y: 5)))
        #expect(!region.contains(CGPoint(x: 15, y: 5)))
    }
}
