import CoreGraphics
import Foundation
import Testing
import PhotonzCore
@testable import PhotonzRender

/// The renderer caches per-layer content (rasterized text/annotations and
/// CIImage wraps of stored bitmaps) across renders — the phase-7 perf pass.
/// These tests pin the cache's correctness: repeat renders hit it, content
/// and size changes miss it, and nothing ever serves stale pixels.
@Suite("Render content cache")
struct ContentCacheTests {

    private func solidImage(width: Int, height: Int, r: UInt8, g: UInt8, b: UInt8) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height,
                                bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255,
                                     blue: CGFloat(b) / 255, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    private func pixel(_ image: CGImage, x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        let width = image.width
        let height = image.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        let context = CGContext(data: &data, width: width, height: height,
                                bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let offset = (y * width + x) * 4
        return (data[offset], data[offset + 1], data[offset + 2], data[offset + 3])
    }

    /// Largest per-channel difference between two renders (sampled grid).
    private func maxDelta(_ a: CGImage, _ b: CGImage) -> Int {
        guard a.width == b.width, a.height == b.height else { return .max }
        var worst = 0
        for ny in 0..<8 {
            for nx in 0..<8 {
                let x = min(a.width - 1, a.width * nx / 8 + a.width / 16)
                let y = min(a.height - 1, a.height * ny / 8 + a.height / 16)
                let pa = pixel(a, x: x, y: y)
                let pb = pixel(b, x: x, y: y)
                worst = max(worst,
                            abs(Int(pa.r) - Int(pb.r)), abs(Int(pa.g) - Int(pb.g)),
                            abs(Int(pa.b) - Int(pb.b)), abs(Int(pa.a) - Int(pb.a)))
            }
        }
        return worst
    }

    private func makeDocument(store: ImageStore) -> PhotonzDocument {
        let base = store.register(solidImage(width: 200, height: 150, r: 200, g: 200, b: 200))
        var doc = PhotonzDocument.withBaseImage(base)
        doc.addLayer(Layer(name: "Text",
                           content: .text(TextContent(string: "Hi", fontSize: 40, colorHex: "#112233")),
                           frame: CGRect(x: 10, y: 10, width: 120, height: 60)))
        doc.addLayer(Layer(name: "Box",
                           content: .annotation(AnnotationContent(shape: .rectangle, strokeWidth: 6,
                                                                  colorHex: "#FF3B30",
                                                                  start: CGPoint(x: 20, y: 90),
                                                                  end: CGPoint(x: 150, y: 140))),
                           frame: CGRect(x: 0, y: 0, width: 200, height: 150)))
        return doc
    }

    @Test func repeatRenderHitsTheCacheAndMatches() throws {
        let store = ImageStore()
        let doc = makeDocument(store: store)
        let renderer = DocumentRenderer()

        let first = try #require(renderer.render(doc, store: store))
        let missesAfterFirst = renderer.contentCacheMisses
        let second = try #require(renderer.render(doc, store: store))

        // Second render rasterizes nothing new…
        #expect(renderer.contentCacheMisses == missesAfterFirst,
                "unchanged content re-rasterized on a repeat render")
        #expect(renderer.contentCacheHits > 0, "cache never consulted")
        // …and the output is the same picture.
        #expect(maxDelta(first, second) <= 2)
    }

    @Test func textContentChangeIsNotServedStale() throws {
        let store = ImageStore()
        var doc = makeDocument(store: store)
        let renderer = DocumentRenderer()
        _ = renderer.render(doc, store: store)

        // Same layer, different string: must re-rasterize, and match what a
        // cold renderer produces.
        let textID = doc.layers[1].id
        doc.updateLayer(id: textID) {
            $0.content = .text(TextContent(string: "WWWW", fontSize: 40, colorHex: "#112233"))
        }
        let cached = try #require(renderer.render(doc, store: store))
        let cold = try #require(DocumentRenderer().render(doc, store: store))
        #expect(maxDelta(cached, cold) <= 2, "cached renderer served stale text pixels")
    }

    @Test func annotationFrameResizeIsNotServedStale() throws {
        let store = ImageStore()
        var doc = makeDocument(store: store)
        let renderer = DocumentRenderer()
        _ = renderer.render(doc, store: store)

        // Rasterized content keys on the raster size: a resized frame must
        // produce a fresh raster, not a stretched stale one.
        let boxID = doc.layers[2].id
        doc.updateLayer(id: boxID) {
            $0.frame = CGRect(x: 0, y: 0, width: 100, height: 75)
        }
        let cached = try #require(renderer.render(doc, store: store))
        let cold = try #require(DocumentRenderer().render(doc, store: store))
        #expect(maxDelta(cached, cold) <= 2, "cached renderer served a stale raster size")
    }

    @Test func reRegisteredBitmapIsNotServedStale() throws {
        let store = ImageStore()
        let ref = store.register(solidImage(width: 64, height: 64, r: 255, g: 0, b: 0))
        let doc = PhotonzDocument.withBaseImage(ref)
        let renderer = DocumentRenderer()
        let first = try #require(renderer.render(doc, store: store))
        #expect(pixel(first, x: 32, y: 32).r > 240)

        // Package loading re-registers pixels under the same ref. The wrap
        // cache keys on bitmap identity, so this must invalidate.
        store.register(solidImage(width: 64, height: 64, r: 0, g: 0, b: 255), as: ref)
        let second = try #require(renderer.render(doc, store: store))
        let p = pixel(second, x: 32, y: 32)
        #expect(p.b > 240 && p.r < 16, "renderer served the old bitmap after re-register")
    }

    @Test func cacheStaysBounded() throws {
        let store = ImageStore()
        let base = store.register(solidImage(width: 100, height: 100, r: 255, g: 255, b: 255))
        var doc = PhotonzDocument.withBaseImage(base)
        doc.addLayer(Layer(name: "Text",
                           content: .text(TextContent(string: "x", fontSize: 20, colorHex: "#000000")),
                           frame: CGRect(x: 0, y: 0, width: 80, height: 30)))
        let renderer = DocumentRenderer()
        let textID = doc.layers[1].id

        // Churn far past any sane cap; the cache must not grow without bound.
        for i in 0..<200 {
            doc.updateLayer(id: textID) {
                $0.content = .text(TextContent(string: "x\(i)", fontSize: 20, colorHex: "#000000"))
            }
            _ = renderer.render(doc, store: store)
        }
        #expect(renderer.contentCacheCount <= 64, "cache grew without bound: \(renderer.contentCacheCount)")
    }
}
