import CoreGraphics
import Foundation
import Testing
import PhotonzCore
@testable import PhotonzRender

/// What a key and a matte cost on the stack the repo's budget is written
/// against: a 12-megapixel document with ten layers, re-rendering in under
/// 16ms.
///
/// The number that mattered before this was measured is the colour table. The
/// key's arithmetic runs once per COLOUR rather than once per pixel — 262,144
/// times for a 64 cube, whatever the frame is — and the table is then kept, so
/// the question is whether a re-render pays for it again. It must not: a
/// tolerance slider being dragged re-renders on every frame of the drag.
@Suite("What keying and matting cost")
struct CompositingPerfTests {

    /// The budget's own document: 4000 x 3000 with ten layers on it.
    private func stack(keyed: Bool, matted: Bool) -> PhotonzDocument {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 4000, height: 3000))
        var layers: [Layer] = []
        for index in 0..<10 {
            var content = AnnotationContent(shape: .rectangle, strokeWidth: 6,
                                            colorHex: "#3366FF", fillColorHex: "#00D84A")
            content.start = .zero
            content.end = CGPoint(x: 1200, y: 900)
            var layer = AnnotationBuilder.layer(content: content, from: .zero,
                                                to: CGPoint(x: 1200, y: 900))
            layer.frame.origin = CGPoint(x: Double(index) * 240, y: Double(index) * 180)
            // Every other layer wears the rule, so half the stack is paying
            // for it — more than any real document does.
            if keyed, index % 2 == 1 { layer.style.key = ChromaKey(colorHex: "#00D84A") }
            if matted, index % 2 == 1 { layer.style.matte = .shape }
            layers.append(layer)
        }
        doc.layers = layers
        return doc
    }

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

    @Test func aKeyedStackReRendersForWhatAPlainOneCosts() {
        let plain = Settled(stack(keyed: false, matted: false))
        let keyed = Settled(stack(keyed: true, matted: false))
        let reading = PerfClock.compare("keyed", rounds: 5,
                                        subject: { keyed.reRender() },
                                        reference: { plain.reRender() })
        let cost = String(format: "%.1f", reading.cost)
        let flat = String(format: "%.1f", reading.baseline)
        if MachineSpeed.isGating {
            // Generous, because this runs on whatever machine is free. What it
            // guards is the table being rebuilt every render, which is a
            // quarter of a second rather than a few percent.
            #expect(reading.cost < reading.baseline * 3 + 10,
                    "five keyed layers re-render in \(cost)ms of cpu against \(flat)ms plain")
        }
    }

    @Test func aMattedStackReRendersForWhatAPlainOneCosts() {
        let plain = Settled(stack(keyed: false, matted: false))
        let matted = Settled(stack(keyed: false, matted: true))
        let reading = PerfClock.compare("matted", rounds: 5,
                                        subject: { matted.reRender() },
                                        reference: { plain.reRender() })
        let cost = String(format: "%.1f", reading.cost)
        let flat = String(format: "%.1f", reading.baseline)
        if MachineSpeed.isGating {
            #expect(reading.cost < reading.baseline * 3 + 10,
                    "five matted layers re-render in \(cost)ms of cpu against \(flat)ms plain")
        }
    }

    /// The table is built once and kept. Asked for a second time it must come
    /// straight back, because a slider being dragged asks for one every frame
    /// and the frames either side of it ask for the same one again.
    @Test func theColourTableIsBuiltOnceAndKept() {
        let key = ChromaKey(colorHex: "#00D84A", tolerance: 0.21, softness: 0.07, spill: 0.33)
        let cold = PerfClock.fastestCallMS(batches: 1, callsPerBatch: 1) {
            _ = ChromaKeyFilter.table(for: key)
        }
        let warm = PerfClock.fastestCallMS(batches: 3, callsPerBatch: 20) {
            _ = ChromaKeyFilter.table(for: key)
        }
        let built = String(format: "%.2f", cold)
        let fetched = String(format: "%.4f", warm)
        #expect(warm < max(cold / 10, 0.05),
                "the table took \(built)ms to build and \(fetched)ms to fetch again")
    }
}
