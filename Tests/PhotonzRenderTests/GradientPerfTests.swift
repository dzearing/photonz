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

    /// One warmed-up renderer bound to its document, so a reading is a
    /// re-render: the first render fills the caches, every one after it is
    /// what happens while a person works.
    ///
    /// Timed through `PerfClock`, which explains why this is measured on the
    /// thread's CPU clock rather than the wall: this check went red on a busy
    /// machine on 2026-09-04 by two percent, for no reason to do with
    /// gradients. A gradient surface is drawn on the CPU into a bitmap
    /// (`GradientPainter`), so a real regression lands squarely on that clock:
    /// measured cold, an angular surface redrawn every render reads 142ms
    /// against 9ms warm.
    private final class Settled {
        let renderer = DocumentRenderer()
        let store = ImageStore()
        let doc: PhotonzDocument
        init(_ doc: PhotonzDocument) {
            self.doc = doc
            _ = renderer.render(doc, store: store)
        }
        func reRender() { _ = renderer.render(doc, store: store) }
    }

    private func gradient(_ kind: Paint.Kind) -> Paint {
        var paint = Paint(hex: "#FF3B30")
        paint.becoming(kind)
        return paint
    }

    @Test func aGradientCostsWhatAFlatColorCostsOnceItIsDrawn() {
        let plain = Settled(document(paint: nil, layers: 10, surface: false))
        for kind in [Paint.Kind.linear, .radial, .angular] {
            let hot = Settled(document(paint: gradient(kind), layers: 10, surface: true))
            let reading = PerfClock.compare(kind.rawValue, rounds: 5,
                                            subject: { hot.reRender() },
                                            reference: { plain.reRender() })
            // Generous, because this runs on whatever machine is free: the
            // failure being guarded against was a hundredfold, not a fifth.
            // On this clock the three kinds all read within a few percent of
            // flat, and the regression this guards reads fifteen times it.
            let cost = String(format: "%.1f", reading.cost)
            let flat = String(format: "%.1f", reading.baseline)
            #expect(reading.cost < reading.baseline * 3 + 10,
                    "a \(kind.rawValue) surface re-renders in \(cost)ms of cpu against \(flat)ms flat")
        }
    }
}
