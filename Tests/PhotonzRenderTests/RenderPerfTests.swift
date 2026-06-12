import CoreGraphics
import Foundation
import Testing
import PhotonzCore
@testable import PhotonzRender

/// Performance baseline for the composite path (CLAUDE.md target: <16ms for a
/// 12-megapixel document with 10 layers). The assertion bound is deliberately
/// loose (CI machines vary); the printed numbers are the real deliverable and
/// get recorded in docs/progress/perf.md.
@Suite("Render performance")
struct RenderPerfTests {

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

    /// 12MP canvas (4000x3000) with 10 layers exercising every content type
    /// and the expensive style paths (blur, shadow, corner radius, blends).
    private func makeBenchmarkDocument(store: ImageStore) -> PhotonzDocument {
        let base = store.register(solidImage(width: 4000, height: 3000, r: 200, g: 200, b: 200))
        let photo = store.register(solidImage(width: 1600, height: 1200, r: 80, g: 120, b: 200))
        let patch = store.register(solidImage(width: 800, height: 600, r: 220, g: 90, b: 60))

        var doc = PhotonzDocument.withBaseImage(base)
        doc.addLayer(Layer(name: "Photo", content: .image(photo),
                           frame: CGRect(x: 200, y: 200, width: 1600, height: 1200),
                           style: LayerStyle(cornerRadius: 48, shadow: ShadowStyle())))
        doc.addLayer(Layer(name: "Rotated", content: .image(patch),
                           frame: CGRect(x: 2200, y: 300, width: 800, height: 600),
                           transform: LayerTransform(rotation: .pi / 8),
                           style: LayerStyle(borderWidth: 8, borderColorHex: "#FFFFFF")))
        doc.addLayer(Layer(name: "Blurred", content: .image(patch),
                           frame: CGRect(x: 400, y: 1700, width: 800, height: 600),
                           style: LayerStyle(blurRadius: 20)))
        doc.addLayer(Layer(name: "Screened", content: .image(patch),
                           frame: CGRect(x: 2600, y: 1700, width: 800, height: 600),
                           style: LayerStyle(blendMode: .screen)))
        doc.addLayer(Layer(name: "Title", content: .text(TextContent(string: "Benchmark Title", fontSize: 120, colorHex: "#111111")),
                           frame: CGRect(x: 300, y: 60, width: 2400, height: 200)))
        doc.addLayer(Layer(name: "Caption", content: .text(TextContent(string: "Caption text for the perf run", fontSize: 64, colorHex: "#333333")),
                           frame: CGRect(x: 300, y: 2700, width: 2400, height: 160)))
        doc.addLayer(Layer(name: "Arrow", content: .annotation(AnnotationContent(shape: .arrow, strokeWidth: 16, colorHex: "#FF3B30", start: CGPoint(x: 200, y: 200), end: CGPoint(x: 1400, y: 1000))),
                           frame: CGRect(x: 0, y: 0, width: 4000, height: 3000)))
        doc.addLayer(Layer(name: "Box", content: .annotation(AnnotationContent(shape: .rectangle, strokeWidth: 12, colorHex: "#34C759", start: CGPoint(x: 2300, y: 400), end: CGPoint(x: 3600, y: 1200))),
                           frame: CGRect(x: 0, y: 0, width: 4000, height: 3000)))
        doc.addLayer(Layer(name: "Highlight", content: .annotation(AnnotationContent(shape: .highlight, strokeWidth: 0, colorHex: "#FFF200", start: CGPoint(x: 300, y: 2650), end: CGPoint(x: 2800, y: 2900))),
                           frame: CGRect(x: 0, y: 0, width: 4000, height: 3000)))
        return doc
    }

    @Test func renders12MPTenLayerDocumentWithinBudget() {
        let store = ImageStore()
        let doc = makeBenchmarkDocument(store: store)
        #expect(doc.layers.count == 10)
        let renderer = DocumentRenderer()

        // Warm up: first render pays one-time filter/pipeline compilation.
        #expect(renderer.render(doc, store: store) != nil)

        var samples: [Double] = []
        let clock = ContinuousClock()
        for _ in 0..<10 {
            let duration = clock.measure {
                _ = renderer.render(doc, store: store)
            }
            samples.append(Double(duration.components.seconds) * 1000
                           + Double(duration.components.attoseconds) / 1e15)
        }
        samples.sort()
        let median = samples[samples.count / 2]
        print("[perf] 12MP/10-layer render — median \(String(format: "%.1f", median))ms, " +
              "min \(String(format: "%.1f", samples[0]))ms, " +
              "max \(String(format: "%.1f", samples[samples.count - 1]))ms over \(samples.count) runs")

        // Loose regression guard; the 16ms product target is tracked in docs/progress/perf.md.
        #expect(median < 250, "median render time regressed badly: \(median)ms")
    }
}
