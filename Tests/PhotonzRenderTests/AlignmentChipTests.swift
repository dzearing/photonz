import CoreGraphics
import Foundation
import PhotonzCore
@testable import PhotonzRender
import Testing

/// The alignment chip's text is set in words by PhotonzCore, but the room the
/// builder reserves for it is an estimate. These pin the estimate against the
/// real glyphs the rasterizer draws, so no wording can ever spill out of its
/// layer and clip in an export.
@Suite("Alignment chip on the canvas")
struct AlignmentChipTests {

    private func guide(_ mode: MeasureMode, side: EdgeSide?, edges: [CGFloat],
                       labelScale: CGFloat = 1) -> MeasureContent {
        var m = MeasureContent(start: .zero,
                               end: mode == .vertical ? CGPoint(x: 0, y: 300) : CGPoint(x: 300, y: 0),
                               headOffset: 0, mode: mode, labelScale: labelScale)
        m.alignment = AlignmentCheck(items: edges.enumerated().map {
            AlignmentItem(edge: $0.element, spanStart: CGFloat($0.offset * 60),
                          spanEnd: CGFloat($0.offset * 60 + 40), elementSide: side)
        }, tolerance: 1)
        return m
    }

    /// Every edge wording, aligned and off by a three-digit amount, at the
    /// default label size and at the slider's top.
    @Test func theReservationHoldsTheRealTextForEveryWording() {
        let cases: [(MeasureMode, EdgeSide?)] = [
            (.vertical, .after), (.vertical, .before), (.vertical, nil),
            (.horizontal, .after), (.horizontal, .before), (.horizontal, nil),
        ]
        for (mode, side) in cases {
            for edges in [[100, 100, 100], [100, 220, 100]] as [[CGFloat]] {
                for scale in [CGFloat(1), 5] {
                    let m = guide(mode, side: side, edges: edges, labelScale: scale)
                    let text = m.chipText(pixelScale: 1)
                    let real = PillRasterizer.footprint(for: text, fontSize: m.labelPointSize,
                                                        padding: m.labelPadding)
                    let estimate = m.estimatedLabelSize
                    #expect(real.width <= estimate.width, "\(text) at \(scale)x: \(real) vs \(estimate)")
                    #expect(real.height <= estimate.height, "\(text) at \(scale)x: \(real) vs \(estimate)")
                }
            }
        }
    }

    /// The wider chip still draws inside the layer the builder reserves: ink
    /// reaches into the reserved chip rect and nowhere outside the layer.
    @Test func theBuiltLayerHoldsTheWordedChip() {
        let m = guide(.horizontal, side: nil, edges: [100, 100, 100])
        let start = CGPoint(x: 20, y: 100), end = CGPoint(x: 320, y: 100)
        let layer = MeasureBuilder.layer(content: m, from: start, to: end)
        guard let local = layer.measure else {
            Issue.record("built layer lost its measure")
            return
        }
        let frame = CGRect(origin: .zero, size: layer.frame.size)
        let text = local.chipText(pixelScale: 1)
        let real = PillRasterizer.footprint(for: text, fontSize: local.labelPointSize,
                                            padding: local.labelPadding)
        #expect(frame.contains(local.labelRect(chipSize: real)))
        #expect(MeasureRasterizer.rasterize(local, size: layer.frame.size, pixelScale: 1) != nil)
    }
}
