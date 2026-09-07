import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// A caliper reaching the exact edge of a layer the app itself drew.
///
/// The bug this covers, reproduced in the probe on 2026-09-07: a rectangle set
/// to exactly 128 tall measured 124, because the only snap candidates a foot
/// ever had came from the BACKGROUND PICTURE's edge map. A shape drawn on top
/// of the picture is not in that map, so nothing pulled a foot onto its box and
/// the reading was whatever the hand did. Its 4 wide outline is drawn inside
/// the box, so a hand aiming at the middle of the line it can see lands 2 in at
/// each end, which is exactly the 4 that went missing.
@Suite("A caliper reaches a layer's own edges")
struct MeasureLayerEdgeSnappingTests {

    private func rectangle(_ frame: CGRect, name: String = "Rectangle",
                           visible: Bool = true, strokeWidth: CGFloat = 4) -> Layer {
        var content = AnnotationContent(shape: .rectangle)
        content.strokeWidth = strokeWidth
        return Layer(name: name, content: .annotation(content),
                     frame: frame, isVisible: visible)
    }

    private func caliper(from start: CGPoint, to end: CGPoint,
                         mode: MeasureMode = .vertical) -> Layer {
        MeasureBuilder.layer(content: MeasureContent(headOffset: 40, mode: mode),
                             from: start, to: end)
    }

    private func document(_ layers: [Layer]) -> PhotonzDocument {
        PhotonzDocument(canvasSize: CGSize(width: 1440, height: 960), layers: layers)
    }

    // MARK: The candidate list

    @Test func aLayerOffersItsFourEdges() {
        let doc = document([rectangle(CGRect(x: 400, y: 300, width: 128, height: 128))])
        let lines = MeasureSnapping.layerLines(in: doc, excluding: nil)
        #expect(lines.vertical == [400, 528])
        #expect(lines.horizontal == [300, 428])
    }

    @Test func aHiddenLayerOffersNothing() {
        let doc = document([rectangle(CGRect(x: 400, y: 300, width: 128, height: 128),
                                      visible: false)])
        #expect(MeasureSnapping.layerLines(in: doc, excluding: nil).isEmpty)
    }

    @Test func theMeasurementsThemselvesAreNotLayerEdges() {
        // A caliper's bounding box is not a thing anyone aims at, and its feet
        // and head lines already come through `MeasureSnapping.lines`.
        let ruler = caliper(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 100, y: 200))
        let doc = document([ruler])
        #expect(MeasureSnapping.layerLines(in: doc, excluding: nil).isEmpty)
    }

    @Test func theCaliperBeingDraggedIsLeftOut() {
        let ruler = caliper(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 100, y: 200))
        let box = rectangle(CGRect(x: 400, y: 300, width: 128, height: 128))
        let lines = MeasureSnapping.layerLines(in: document([box, ruler]), excluding: box.id)
        #expect(lines.isEmpty)
    }

    @Test func twoLayersSharingAnEdgeOfferItOnce() {
        let a = rectangle(CGRect(x: 400, y: 300, width: 128, height: 128), name: "a")
        let b = rectangle(CGRect(x: 400, y: 500, width: 200, height: 40), name: "b")
        let lines = MeasureSnapping.layerLines(in: document([a, b]), excluding: nil)
        #expect(lines.vertical == [400, 528, 600])
    }

    // MARK: What a foot does with them

    @Test func aFootLandsOnTheLayerEdgeItIsAimedNear() {
        let lines = EdgeSnapping.GuideLines(vertical: [400, 528], horizontal: [300, 428])
        let snap = EdgeSnapping.snap(CGPoint(x: 464, y: 302), edges: .empty, zoom: 1,
                                     layerLines: lines)
        #expect(snap.point.y == 300)
        #expect(snap.guideY == 300)
    }

    @Test func aBoxOfAKnownSizeMeasuresExactly() {
        // The reproduction, in one test. A 128 tall box whose visible outline is
        // 4 wide: both feet aimed at the MIDDLE of that line, 2 in at each end,
        // which is what a hand does. The caliper must still read 128.
        let box = rectangle(CGRect(x: 400, y: 300, width: 128, height: 128))
        let lines = MeasureSnapping.layerLines(in: document([box]), excluding: nil)
        for zoom in [CGFloat(0.25), 0.5, 1, 1.68, 2, 4] {
            let top = EdgeSnapping.snap(CGPoint(x: 464, y: 302), edges: .empty, zoom: zoom,
                                        layerLines: lines).point
            let bottom = EdgeSnapping.snap(CGPoint(x: 464, y: 426), edges: .empty, zoom: zoom,
                                           layerLines: lines).point
            #expect(bottom.y - top.y == 128, "at zoom \(zoom)")
        }
    }

    @Test func aKnownEdgeBeatsOneGuessedFromThePicture() {
        // A maximally strong detected edge sits right under the pointer at 302
        // and the layer's own box is 2 away at 300. The box is KNOWN, so it
        // wins: this is the whole point of the fix, since an antialiased
        // boundary is exactly what puts a strong gradient a pixel inside.
        var gy = [Double](repeating: 0, count: 800 * 600)
        for x in 400...528 { gy[302 * 800 + x] = 4 }
        let edges = EdgeMap(width: 800, height: 600,
                            gxMagnitude: [Double](repeating: 0, count: 800 * 600),
                            gyMagnitude: gy)
        let lines = EdgeSnapping.GuideLines(horizontal: [300, 428])
        let snap = EdgeSnapping.snap(CGPoint(x: 464, y: 302), edges: edges, zoom: 1,
                                     xSpan: 400...528, layerLines: lines)
        #expect(snap.point.y == 300)
    }

    @Test func aPictureEdgeStillCapturesWhenNoLayerEdgeIsInReach() {
        // Measuring a captured picture is unchanged: with no layer line nearby
        // the detected edge captures exactly as it did before.
        var gy = [Double](repeating: 0, count: 800 * 600)
        for x in 100...200 { gy[50 * 800 + x] = 2 }
        let edges = EdgeMap(width: 800, height: 600,
                            gxMagnitude: [Double](repeating: 0, count: 800 * 600),
                            gyMagnitude: gy)
        let lines = EdgeSnapping.GuideLines(horizontal: [300, 428])
        let snap = EdgeSnapping.snap(CGPoint(x: 150, y: 53), edges: edges, zoom: 1,
                                     xSpan: 100...200, layerLines: lines)
        #expect(snap.point.y == 50)
    }

    @Test func aCallOutBoxDoesNotStealTheThingItIsDrawnAround() {
        // The other half of the rule, and the reason a known line does not
        // simply outrank everything: a redliner draws a box AROUND a button to
        // call it out, then measures the button. The button's own edge is the
        // one under the pointer and the box is 12 away, so the button keeps it.
        var gy = [Double](repeating: 0, count: 800 * 900)
        for x in 234...480 { gy[756 * 800 + x] = 4 }
        let edges = EdgeMap(width: 800, height: 900,
                            gxMagnitude: [Double](repeating: 0, count: 800 * 900),
                            gyMagnitude: gy)
        let box = rectangle(CGRect(x: 224, y: 748, width: 266, height: 77))
        let lines = MeasureSnapping.layerLines(in: document([box]), excluding: nil)
        let snap = EdgeSnapping.snap(CGPoint(x: 356, y: 760), edges: edges, zoom: 0.5,
                                     xSpan: 234...480, layerLines: lines)
        #expect(snap.point.y == 756)
    }

    @Test func aLayerEdgeOutOfReachDoesNotPull() {
        // The magnet has the same reach as every other: 8 screen points.
        let lines = EdgeSnapping.GuideLines(horizontal: [300])
        let snap = EdgeSnapping.snap(CGPoint(x: 464, y: 340), edges: .empty, zoom: 1,
                                     layerLines: lines)
        #expect(snap.point.y == 340)
        #expect(snap.guideY == nil)
    }

    @Test func aLineAlreadyCaughtKeepsTheFoot() {
        // A layer edge holds a wobbling hand the same way every other snap
        // line does, rather than handing the foot back and forth.
        let lines = EdgeSnapping.GuideLines(horizontal: [300, 428])
        let snap = EdgeSnapping.snap(CGPoint(x: 464, y: 309), edges: .empty, zoom: 1,
                                     layerLines: lines, holding: SnapHold(x: nil, y: 300))
        #expect(snap.point.y == 300)
    }
}
