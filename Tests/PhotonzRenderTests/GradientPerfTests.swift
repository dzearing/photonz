import CoreGraphics
import Foundation
import Testing
import PhotonzCore
@testable import PhotonzRender

/// The guard on what a gradient costs to composite.
///
/// A screen's surface is as big as the screen, and the sweeping gradient is
/// worked out a pixel at a time, so painting one at full size cost a second and
/// a half on a 12-megapixel canvas the first time this was measured. The
/// surface is drawn small, stretched, and kept, which is what these numbers
/// hold in place: once it is drawn, a screen with a gradient behind it
/// re-renders for what a flat one costs.
@Suite("Gradient paint cost")
struct GradientPerfTests {

    /// A 12-megapixel canvas with a screen filling it and ten boxes on top,
    /// which is the size the repo's render budget is written against.
    private func document(paint: Paint?, layers: Int, surface: Bool) -> PhotonzDocument {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 4000, height: 3000))
        var frame = Layer.frameLayer(name: "Screen", origin: .zero,
                                     size: CGSize(width: 4000, height: 3000))
        if let paint, surface { frame.setPaint(paint, for: .fill) }
        var kids: [Layer] = []
        for index in 0..<layers {
            var content = AnnotationContent(shape: .rectangle, strokeWidth: 6,
                                            colorHex: "#3366FF", fillColorHex: "#FF9900")
            content.start = .zero
            content.end = CGPoint(x: 600, y: 400)
            if let paint { content.fill = paint }
            var layer = AnnotationBuilder.layer(content: content, from: .zero,
                                                to: CGPoint(x: 600, y: 400))
            layer.frame.origin = CGPoint(x: 100 + Double(index) * 120,
                                         y: 100 + Double(index) * 90)
            kids.append(layer)
        }
        if case .group(var group) = frame.content {
            group.children = kids
            frame.content = .group(group)
        }
        doc.layers = [frame]
        return doc
    }

    /// The best of five re-renders on one renderer, which is the number a
    /// person feels: the first render fills the caches, every one after it is
    /// what happens while they work.
    private func settledCost(_ doc: PhotonzDocument) -> Double {
        let renderer = DocumentRenderer()
        let store = ImageStore()
        _ = renderer.render(doc, store: store)
        var best = Double.infinity
        for _ in 0..<5 {
            let start = Date()
            _ = renderer.render(doc, store: store)
            best = min(best, Date().timeIntervalSince(start) * 1000)
        }
        return best
    }

    private func gradient(_ kind: Paint.Kind) -> Paint {
        var paint = Paint(hex: "#FF3B30")
        paint.becoming(kind)
        return paint
    }

    @Test func aGradientCostsWhatAFlatColorCostsOnceItIsDrawn() {
        let flat = settledCost(document(paint: nil, layers: 10, surface: false))
        for kind in [Paint.Kind.linear, .radial, .angular] {
            let cost = settledCost(document(paint: gradient(kind), layers: 10, surface: true))
            // Generous, because this runs on whatever machine is free: the
            // failure being guarded against was a hundredfold, not a fifth.
            #expect(cost < flat * 3 + 10,
                    "a \(kind.rawValue) surface re-renders in \(Int(cost))ms against \(Int(flat))ms flat")
        }
    }
}
