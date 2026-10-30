import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// A placed alignment guide judges the edges it crosses AGAIN whenever its line
/// changes, however it changed: dragged, nudged, typed into the panel or moved
/// by an agent. The answer after any of those is exactly the answer a guide
/// drawn fresh along the new line would give (the user, 2026-10-30: "when i
/// draw an alignment guide and move it, it does not recompute").
@Suite("Alignment guide re-measures when its line changes")
struct AlignmentRemeasureTests {

    // MARK: Scenes

    /// Box edges as gradient responses, the way `AlignmentScanTests` paints
    /// them: three stacked boxes whose left edges sit at 100, 100 and
    /// `middleX`, block-clean gaps between them.
    private static func stackedEdges(middleX: Int = 100) -> EdgeMap {
        let w = 400, h = 300
        var gx = [Double](repeating: 0, count: w * h)
        var gy = [Double](repeating: 0, count: w * h)
        func box(_ x: Int, _ y: Int, _ bw: Int, _ bh: Int) {
            for xx in x...(x + bw) { gy[y * w + xx] = 2; gy[(y + bh) * w + xx] = 2 }
            for yy in y...(y + bh) { gx[yy * w + x] = 2; gx[yy * w + x + bw] = 2 }
        }
        box(100, 40, 120, 40)
        box(middleX, 112, 120, 40)
        box(100, 184, 120, 40)
        return EdgeMap(width: w, height: h, gxMagnitude: gx, gyMagnitude: gy, luma: nil)
    }

    /// The same boxes lying on their side, for a horizontal guide: top edges
    /// at 100, 100 and `middleY`.
    private static func sideBySideEdges(middleY: Int = 100) -> EdgeMap {
        let w = 300, h = 400
        var gx = [Double](repeating: 0, count: w * h)
        var gy = [Double](repeating: 0, count: w * h)
        func box(_ x: Int, _ y: Int, _ bw: Int, _ bh: Int) {
            for xx in x...(x + bw) { gy[y * w + xx] = 2; gy[(y + bh) * w + xx] = 2 }
            for yy in y...(y + bh) { gx[yy * w + x] = 2; gx[yy * w + x + bw] = 2 }
        }
        box(40, 100, 40, 120)
        box(112, middleY, 40, 120)
        box(184, 100, 40, 120)
        return EdgeMap(width: w, height: h, gxMagnitude: gx, gyMagnitude: gy, luma: nil)
    }

    private static func document(with layers: [Layer], size: CGSize = CGSize(width: 400, height: 400)) -> PhotonzDocument {
        var doc = PhotonzDocument(canvasSize: size)
        for layer in layers { doc.addLayer(layer) }
        return doc
    }

    /// A guide placed the way the app places one: measured along `line` on
    /// `picture` with the boxes of `doc`, laid down as a layer.
    private static func placedGuide(_ line: AlignmentGuideLine, picture: AlignmentPicture,
                                    in doc: PhotonzDocument) -> Layer {
        var content = MeasureContent(headOffset: 0, mode: line.axis)
        content.alignment = AlignmentCheck(items: [], tolerance: 1)
        let seed = MeasureBuilder.layer(content: content, from: line.start, to: line.end)
        return MeasureBuilder.remeasured(seed, along: line, picture: picture,
                                         boxes: LayerElements.boxes(in: doc),
                                         canvas: doc.canvasSize, avoiding: [])
    }

    private static func moved(_ layer: Layer, by d: CGVector) -> Layer {
        var moved = layer
        moved.frame = layer.frame.offsetBy(dx: d.dx, dy: d.dy)
        return moved
    }

    private static func docItems(_ layer: Layer) -> [AlignmentItem] {
        MeasureBuilder.documentSpaceContent(of: layer)?.alignment?.items ?? []
    }

    // MARK: The line a guide sits on

    @Test func aGuideReadsItsLineInDocumentSpace() {
        let picture = AlignmentPicture(edges: Self.stackedEdges())
        let doc = Self.document(with: [])
        let layer = Self.placedGuide(AlignmentGuideLine(axis: .vertical, position: 102, span: 30...230),
                                     picture: picture, in: doc)
        let line = layer.alignmentGuideLine
        #expect(line?.axis == .vertical)
        // Settled onto the reference edge the boxes share, not where it was drawn.
        #expect(line.map { abs($0.position - 100) < 0.5 } == true)
        #expect(line?.span == 30...230)
        // A caliper is not a guide.
        let caliper = MeasureBuilder.layer(content: MeasureContent(),
                                           from: .zero, to: CGPoint(x: 50, y: 0))
        #expect(caliper.alignmentGuideLine == nil)
    }

    // MARK: Moving the guide is drawing it again there

    @Test func aVerticalGuideMovedOntoTheEdgesMatchesOneDrawnThere() {
        let picture = AlignmentPicture(edges: Self.stackedEdges(middleX: 104))
        var doc = Self.document(with: [])
        // Drawn well clear of every edge: it finds nothing.
        let guide = Self.placedGuide(AlignmentGuideLine(axis: .vertical, position: 40, span: 30...230),
                                     picture: picture, in: doc)
        #expect(Self.docItems(guide).isEmpty)
        doc.addLayer(guide)
        let before = doc
        // Dragged 61 px right, onto the column of left edges.
        doc.updateLayer(id: guide.id) { $0 = Self.moved($0, by: CGVector(dx: 61, dy: 0)) }
        doc.keepAlignmentGuidesMeasured(since: before, picture: picture)

        let fresh = Self.placedGuide(AlignmentGuideLine(axis: .vertical, position: 101, span: 30...230),
                                     picture: picture, in: before)
        let moved = doc.layer(id: guide.id)
        #expect(moved.map(Self.docItems) == Self.docItems(fresh))
        #expect(moved?.measure?.alignment?.verdict == fresh.measure?.alignment?.verdict)
        #expect(moved?.alignmentGuideLine == fresh.alignmentGuideLine)
        // And it found the misaligned middle box, which the stale guide never could.
        #expect(moved?.measure?.alignment?.verdict?.isAligned == false)
        #expect(Self.docItems(fresh).count == 3)
    }

    @Test func aHorizontalGuideMovedOntoTheTopsMatchesOneDrawnThere() {
        let picture = AlignmentPicture(edges: Self.sideBySideEdges())
        var doc = Self.document(with: [])
        let guide = Self.placedGuide(AlignmentGuideLine(axis: .horizontal, position: 300, span: 30...230),
                                     picture: picture, in: doc)
        doc.addLayer(guide)
        let before = doc
        doc.updateLayer(id: guide.id) { $0 = Self.moved($0, by: CGVector(dx: 0, dy: -198)) }
        doc.keepAlignmentGuidesMeasured(since: before, picture: picture)

        let fresh = Self.placedGuide(AlignmentGuideLine(axis: .horizontal, position: 102, span: 30...230),
                                     picture: picture, in: before)
        let moved = doc.layer(id: guide.id)
        #expect(Self.docItems(fresh).count == 3)
        #expect(moved.map(Self.docItems) == Self.docItems(fresh))
        #expect(moved?.measure?.alignment?.verdict == fresh.measure?.alignment?.verdict)
        #expect(moved?.alignmentGuideLine == fresh.alignmentGuideLine)
        #expect(moved?.measure?.alignment?.verdict?.isAligned == true)
    }

    @Test func aGuideMovedAcrossDrawnBoxesMatchesOneDrawnThere() {
        // A canvas with no picture: two rectangles the person drew, left edges
        // at 60 and 63. Their edges are known, not read.
        func box(_ name: String, _ rect: CGRect) -> Layer {
            Layer(name: name, content: .annotation(AnnotationContent(
                shape: .rectangle, start: .zero, end: CGPoint(x: rect.width, y: rect.height))),
                  frame: rect)
        }
        let a = box("A", CGRect(x: 60, y: 40, width: 100, height: 50))
        let b = box("B", CGRect(x: 63, y: 120, width: 100, height: 50))
        var doc = Self.document(with: [a, b])
        let picture = AlignmentPicture.none
        let guide = Self.placedGuide(AlignmentGuideLine(axis: .vertical, position: 20, span: 20...200),
                                     picture: picture, in: doc)
        #expect(Self.docItems(guide).isEmpty)
        doc.addLayer(guide)
        let before = doc
        doc.updateLayer(id: guide.id) { $0 = Self.moved($0, by: CGVector(dx: 41, dy: 0)) }
        doc.keepAlignmentGuidesMeasured(since: before, picture: picture)

        let fresh = Self.placedGuide(AlignmentGuideLine(axis: .vertical, position: 61, span: 20...200),
                                     picture: picture, in: before)
        let moved = doc.layer(id: guide.id)
        #expect(Self.docItems(fresh).count == 2)
        #expect(moved.map(Self.docItems) == Self.docItems(fresh))
        #expect(moved?.measure?.alignment?.verdict == fresh.measure?.alignment?.verdict)
        #expect(moved?.alignmentGuideLine == fresh.alignmentGuideLine)
        #expect(moved?.measure?.alignment?.itemsAreElements == true)
    }

    // MARK: Changing the span is drawing it again too

    @Test func shorteningTheSpanDropsTheElementsItNoLongerCrosses() {
        let picture = AlignmentPicture(edges: Self.stackedEdges(middleX: 104))
        var doc = Self.document(with: [])
        let guide = Self.placedGuide(AlignmentGuideLine(axis: .vertical, position: 101, span: 30...230),
                                     picture: picture, in: doc)
        #expect(guide.measure?.alignment?.verdict?.isAligned == false)
        doc.addLayer(guide)
        let before = doc
        // The bottom end pulled up past the middle box: only the top box is left.
        // Then the top end pulled down so it starts at the bottom box instead.
        guard let line = guide.alignmentGuideLine else {
            Issue.record("a placed guide has a line")
            return
        }
        let shorter = AlignmentGuideLine(axis: .vertical, position: line.position, span: 170...230)
        doc.updateLayer(id: guide.id) {
            $0 = MeasureBuilder.updating($0, start: shorter.start, end: shorter.end)
        }
        doc.keepAlignmentGuidesMeasured(since: before, picture: picture)
        let fresh = Self.placedGuide(shorter, picture: picture, in: before)
        let changed = doc.layer(id: guide.id)
        #expect(changed.map(Self.docItems) == Self.docItems(fresh))
        #expect(changed?.alignmentGuideLine?.span == 170...230)
        #expect(Self.docItems(fresh).count == 1)
    }

    // MARK: What does not re-measure

    @Test func aRestyleLeavesTheItemsAlone() {
        let picture = AlignmentPicture(edges: Self.stackedEdges(middleX: 104))
        var doc = Self.document(with: [])
        let guide = Self.placedGuide(AlignmentGuideLine(axis: .vertical, position: 101, span: 30...230),
                                     picture: picture, in: doc)
        doc.addLayer(guide)
        let before = doc
        doc.updateLayer(id: guide.id) { $0 = MeasureBuilder.restyled($0, strokeColorHex: "#00FF00") }
        let restyled = doc
        // The picture vanished (say, the analysis was thrown away): a restyle
        // must not read it, or the guide would lose everything it found.
        doc.keepAlignmentGuidesMeasured(since: before, picture: .none)
        #expect(doc == restyled)
    }

    @Test func aGuideJustDrawnIsNotMeasuredTwice() {
        let picture = AlignmentPicture(edges: Self.stackedEdges())
        let empty = Self.document(with: [])
        var doc = empty
        let guide = Self.placedGuide(AlignmentGuideLine(axis: .vertical, position: 101, span: 30...230),
                                     picture: picture, in: doc)
        doc.addLayer(guide)
        let added = doc
        doc.keepAlignmentGuidesMeasured(since: empty, picture: .none)
        #expect(doc == added)
    }

    @Test func noPictureYetLeavesAMovedGuideAsItWas() {
        // The edge analysis has not landed: the app passes nil rather than an
        // empty picture, and the guide keeps what it had rather than finding
        // nothing.
        let picture = AlignmentPicture(edges: Self.stackedEdges())
        var doc = Self.document(with: [])
        let guide = Self.placedGuide(AlignmentGuideLine(axis: .vertical, position: 101, span: 30...230),
                                     picture: picture, in: doc)
        doc.addLayer(guide)
        let before = doc
        doc.updateLayer(id: guide.id) { $0 = Self.moved($0, by: CGVector(dx: 5, dy: 0)) }
        let movedOnly = doc
        doc.keepAlignmentGuidesMeasured(since: before, picture: nil)
        #expect(doc == movedOnly)
    }

    @Test func aGuideInsideAGroupIsReadInDocumentSpace() {
        let picture = AlignmentPicture(edges: Self.stackedEdges(middleX: 104))
        let empty = Self.document(with: [])
        let guide = Self.placedGuide(AlignmentGuideLine(axis: .vertical, position: 40, span: 30...230),
                                     picture: picture, in: empty)
        // The guide, re-expressed in a group that sits 20 px right of the
        // canvas origin, the way grouping it would leave it.
        var local = guide
        local.frame = guide.frame.offsetBy(dx: -20, dy: 0)
        let group = Layer(name: "Group", content: .group(GroupContent(children: [local])),
                          frame: CGRect(x: 20, y: 0, width: 300, height: 300))
        var doc = Self.document(with: [group])
        let before = doc
        doc.updateLayer(id: guide.id) { $0 = Self.moved($0, by: CGVector(dx: 61, dy: 0)) }
        doc.keepAlignmentGuidesMeasured(since: before, picture: picture)
        let fresh = Self.placedGuide(AlignmentGuideLine(axis: .vertical, position: 101, span: 30...230),
                                     picture: picture, in: empty)
        guard let moved = doc.layer(id: guide.id) else {
            Issue.record("the guide is still in its group")
            return
        }
        // Document-space items of the nested guide are the parent offset away
        // from its own layer-local ones.
        let items = Self.docItems(moved).map { item -> AlignmentItem in
            var item = item
            item.edge += 20
            return item
        }
        #expect(items == Self.docItems(fresh))
        #expect(Self.docItems(fresh).count == 3)
    }
}
