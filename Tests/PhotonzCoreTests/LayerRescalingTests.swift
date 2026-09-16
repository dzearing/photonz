import Foundation
import CoreGraphics
import Testing
@testable import PhotonzCore

/// A drawing restated in a different unit keeps the size it LOOKS
/// (`LayerRescaling.swift`).
///
/// The difference from magnification is the point of it: magnifying leaves the
/// type, the line thickness and the points of an outline alone, because the
/// rasterizer is told how much to magnify them by. Rescaling rewrites them,
/// because the drawing is not being drawn bigger, it is being measured in a
/// different unit from now on.
struct LayerRescalingTests {

    @Test func nothingMovesAtOne() {
        let layer = Layer(name: "Box", content: .text(TextContent(string: "Save", fontSize: 24)),
                          frame: CGRect(x: 10, y: 20, width: 100, height: 40))
        #expect(layer.rescaled(by: 1) == layer)
        #expect(layer.rescaled(by: 0) == layer)
        #expect(layer.rescaled(by: .nan) == layer)
    }

    @Test func theBoxAndTheTypeMoveTogether() {
        let layer = Layer(name: "Label", content: .text(TextContent(string: "Save", fontSize: 24)),
                          frame: CGRect(x: 10, y: 20, width: 100, height: 40))
        let half = layer.rescaled(by: 0.5)
        #expect(half.frame == CGRect(x: 5, y: 10, width: 50, height: 20))
        guard case .text(let text) = half.content else { Issue.record("not text"); return }
        #expect(text.fontSize == 12)
        // The words themselves are words, whatever unit the box is in.
        #expect(text.string == "Save")
    }

    @Test func whatIsMeasuredInPointsMovesToo() {
        var layer = Layer(name: "Box",
                          content: .annotation(AnnotationContent(shape: .rectangle, strokeWidth: 4,
                                                                 start: .zero,
                                                                 end: CGPoint(x: 100, y: 40))),
                          frame: CGRect(x: 0, y: 0, width: 100, height: 40))
        layer.style.cornerRadius = 8
        layer.style.shadows = [ShadowStyle(radius: 12, offset: CGSize(width: 0, height: 4))]
        let big = layer.rescaled(by: 2)
        #expect(big.style.cornerRadius == 16)
        // A box asked for with a stroke of its own wears it as a Border in its
        // Effects list (`OutlineRetirement.swift`), and that is where its
        // thickness has to move.
        #expect(big.style.borderWidth == 8)
        #expect(big.style.shadows.first?.radius == 24)
        #expect(big.style.shadows.first?.offset == CGSize(width: 0, height: 8))
    }

    @Test func anArrowKeepsItsAimAndItsWeight() {
        var arrow = AnnotationContent(shape: .arrow, strokeWidth: 4,
                                      start: CGPoint(x: 0, y: 0), end: CGPoint(x: 80, y: 40))
        arrow.caption = "Tap here"
        arrow.captionFontSize = 20
        let layer = Layer(name: "Arrow", content: .annotation(arrow),
                          frame: CGRect(x: 0, y: 0, width: 80, height: 40))
        guard case .annotation(let out) = layer.rescaled(by: 0.5).content else {
            Issue.record("not an arrow"); return
        }
        #expect(out.strokeWidth == 2)
        #expect(out.end == CGPoint(x: 40, y: 20))
        #expect(out.captionFontSize == 10)
        #expect(out.caption == "Tap here")
    }

    @Test func anOutlineKeepsItsShape() {
        let path = PathContent(anchors: [PathAnchor(point: CGPoint(x: 0, y: 0),
                                                    handleOut: CGPoint(x: 10, y: 0)),
                                         PathAnchor(point: CGPoint(x: 40, y: 20),
                                                    handleIn: CGPoint(x: -10, y: 0))],
                               isClosed: true, strokeWidth: 3)
        let layer = Layer(name: "Icon", content: .path(path),
                          frame: CGRect(x: 0, y: 0, width: 40, height: 20))
        guard case .path(let out) = layer.rescaled(by: 0.5).content else {
            Issue.record("not a path"); return
        }
        #expect(out.strokeWidth == 1.5)
        #expect(out.anchors[0].handleOut == CGPoint(x: 5, y: 0))
        #expect(out.anchors[1].point == CGPoint(x: 20, y: 10))
        #expect(out.isClosed)
    }

    @Test func aStackKeepsItsGapsAndItsRoom() {
        var row = Layer(name: "Row", content: .group(GroupContent(children: [
            Layer(name: "A", content: .annotation(AnnotationContent(shape: .rectangle, start: .zero,
                                                                    end: CGPoint(x: 40, y: 20))),
                  frame: CGRect(x: 0, y: 0, width: 40, height: 20)),
            Layer(name: "B", content: .annotation(AnnotationContent(shape: .rectangle, start: .zero,
                                                                    end: CGPoint(x: 40, y: 20))),
                  frame: CGRect(x: 56, y: 0, width: 40, height: 20)),
        ])), frame: CGRect(x: 0, y: 0, width: 96, height: 20))
        let layout = GroupLayout(kind: .stack, direction: .row, gap: 16,
                                 padding: GroupPadding(top: 8, right: 12, bottom: 8, left: 12))
        row.setGroupLayout(layout)
        let half = row.rescaled(by: 0.5)
        #expect(half.group?.layout?.gap == 8)
        #expect(half.group?.layout?.padding.left == 6)
        #expect(half.children.map(\.frame.width) == [20, 20])
    }
}
