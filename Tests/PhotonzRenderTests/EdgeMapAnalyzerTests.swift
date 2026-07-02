import CoreGraphics
import Foundation
import Testing
import PhotonzCore
@testable import PhotonzRender

@Suite("Edge map analyzer")
struct EdgeMapAnalyzerTests {

    /// Black background with a white rectangle in top-left coordinates.
    private func rectImage(width: Int, height: Int,
                           rect: CGRect) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height,
                                bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        // CGContext is bottom-left; flip the rect's y so the white box lands where
        // top-left coordinates say it should.
        let flipped = CGRect(x: rect.minX, y: CGFloat(height) - rect.maxY,
                             width: rect.width, height: rect.height)
        context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        context.fill(flipped)
        return context.makeImage()!
    }

    /// True if some detected position lands within `tol` of `target`.
    private func near(_ edges: [EdgeCandidate], _ target: Double, tol: Double = 3) -> Bool {
        edges.contains { abs($0.position - target) <= tol }
    }

    @Test func detectsRectangleEdgesOnAllFourSides() {
        // 100×80 image, white rect from (20,15) to (80,65) in top-left coords.
        let img = rectImage(width: 100, height: 80,
                            rect: CGRect(x: 20, y: 15, width: 60, height: 50))
        let map = EdgeMapAnalyzer.analyze(img)

        #expect(map.width == 100)
        #expect(map.height == 80)
        let horizontal = map.horizontalEdges(inXRange: 20...80)
        #expect(near(horizontal, 15))
        #expect(near(horizontal, 65))
        let vertical = map.verticalEdges(inYRange: 15...65)
        #expect(near(vertical, 20))
        #expect(near(vertical, 80))
    }

    @Test func rectangleEdgesAreLocalNotGlobal() {
        // A window that does not overlap the rectangle's span sees nothing.
        let img = rectImage(width: 200, height: 160,
                            rect: CGRect(x: 20, y: 15, width: 60, height: 50))
        let map = EdgeMapAnalyzer.analyze(img)
        #expect(map.horizontalEdges(inXRange: 120...190).isEmpty)
        #expect(map.verticalEdges(inYRange: 100...150).isEmpty)
    }

    /// A row of glyph "stems": equal-height black bars on white, spanning a text
    /// band. The band's top and baseline are the only true horizontal edges —
    /// the stems' vertical strokes must not pollute the horizontal query.
    private func textBandImage(width: Int, height: Int,
                               top: Int, baseline: Int,
                               stemXs: [Int], stemWidth: Int = 2) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height,
                                bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
        let flippedY = CGFloat(height) - CGFloat(baseline)
        for x in stemXs {
            context.fill(CGRect(x: CGFloat(x), y: flippedY,
                                width: CGFloat(stemWidth), height: CGFloat(baseline - top)))
        }
        return context.makeImage()!
    }

    @Test func detectsTextCapLineAndBaselineNotTheBandInterior() {
        // Text band y=30..50 (x-height 20), stems every 8px across cols 20..100.
        let stems = Array(stride(from: 20, through: 100, by: 8))
        let img = textBandImage(width: 120, height: 80, top: 30, baseline: 50, stemXs: stems)
        let map = EdgeMapAnalyzer.analyze(img)

        let horizontal = map.horizontalEdges(inXRange: 20...102)
        #expect(near(horizontal, 30))
        #expect(near(horizontal, 50))
        // The band INTERIOR (mid-x-height) must NOT be detected — directional
        // gradients keep the stems out of the horizontal signal.
        #expect(!horizontal.contains { $0.position > 34 && $0.position < 46 })
        // And the stems themselves are findable as vertical edges in the band.
        let vertical = map.verticalEdges(inYRange: 30...50)
        #expect(near(vertical, 20, tol: 2))
    }

    @Test func flatImageProducesNoEdges() {
        let img = rectImage(width: 60, height: 40, rect: .zero) // all black
        let map = EdgeMapAnalyzer.analyze(img)
        #expect(map.horizontalEdges(inXRange: 0...59).isEmpty)
        #expect(map.verticalEdges(inYRange: 0...39).isEmpty)
    }

    @Test func cacheReturnsSameMapForSameRef() {
        let store = ImageStore()
        let ref = store.register(rectImage(width: 80, height: 60,
                                           rect: CGRect(x: 10, y: 10, width: 40, height: 30)))
        let cache = EdgeMapCache()
        let first = cache.edgeMap(for: ref, store: store)
        let second = cache.edgeMap(for: ref, store: store)
        #expect(first == second)
        #expect(!first.horizontalEdges(inXRange: 10...50).isEmpty)
    }
}
