import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// A Border round an OPEN path has no inside to sit in.
///
/// A closed path is something you can paint inside, so Inside, Center and
/// Outside each mean a different place for a ring to sit. An open one is a
/// LINE: it has two sides and no interior, so all three words name the same
/// band, the one running down the middle of the line.
///
/// The path's own edge has always answered this way
/// (`PathContent.effectiveStrokePosition`). Before this, a Border on the same
/// layer did not: Inside reached nowhere at all, which the renderer read as a
/// ring round the layer's BOX, and Outside swept the full width to either side,
/// so an 8 point border came out 16 points thick.
@Suite("A border round an open line")
struct OpenLineBorderTests {

    private func path(closed: Bool) -> PathContent {
        PathContent(anchors: [PathAnchor(point: CGPoint(x: 0, y: 0)),
                              PathAnchor(point: CGPoint(x: 60, y: 100)),
                              PathAnchor(point: CGPoint(x: 120, y: 0))],
                    isClosed: closed)
    }

    private func layer(closed: Bool) -> Layer {
        PathBuilder.layer(path(closed: closed), at: .zero)
    }

    // MARK: Which layers have an inside

    @Test("An open path layer is a line, a closed one is not")
    func onlyAnOpenPathIsALine() {
        #expect(layer(closed: false).ringsAnOpenLine)
        #expect(!layer(closed: true).ringsAnOpenLine)
    }

    @Test("Nothing that is not a path is ever a line")
    func everythingElseHasAnInside() {
        var picture = Layer(name: "Shot", content: .image(ImageRef(id: UUID(), pixelSize: CGSize(width: 10, height: 10))),
                            frame: CGRect(x: 0, y: 0, width: 10, height: 10))
        #expect(!picture.ringsAnOpenLine)
        picture.content = .group(GroupContent(children: [], isFrame: true))
        #expect(!picture.ringsAnOpenLine)
        let oval = Layer(name: "Oval",
                         content: .annotation(AnnotationContent(shape: .ellipse)),
                         frame: CGRect(x: 0, y: 0, width: 40, height: 20))
        #expect(!oval.ringsAnOpenLine)
    }

    // MARK: Where the ring sits

    @Test("Every position collapses to centred on a line")
    func positionsCollapse() {
        for position in BorderPosition.allCases {
            let border = BorderEffect(width: 8, colorHex: "#FF0000", position: position)
            #expect(border.ringOutset(aroundOpenLine: true) == 4,
                    "\(position) should sit half a width past the line")
        }
    }

    @Test("...and nothing collapses on a shape with an inside")
    func positionsStandOnAClosedShape() {
        #expect(BorderEffect(width: 8, colorHex: "#FF0000", position: .inside)
            .ringOutset(aroundOpenLine: false) == 0)
        #expect(BorderEffect(width: 8, colorHex: "#FF0000", position: .center)
            .ringOutset(aroundOpenLine: false) == 4)
        #expect(BorderEffect(width: 8, colorHex: "#FF0000", position: .outside)
            .ringOutset(aroundOpenLine: false) == 8)
    }

    @Test("An offset is dropped on a line, because there is no side to measure from")
    func offsetIsDropped() {
        let border = BorderEffect(width: 8, colorHex: "#FF0000", position: .outside, offset: 10)
        #expect(border.ringOutset(aroundOpenLine: true) == 4)
        #expect(border.ringOutset(aroundOpenLine: false) == 18)
    }

    // MARK: The room it asks for

    @Test("An inside border on a line asks for room, because half of it is outside")
    func roomForAnInsideRing() {
        var line = layer(closed: false)
        line.content = .path({ var p = path(closed: false); p.strokeWidth = 0; return p }())
        line.style.effects = [.border(BorderEffect(width: 8, colorHex: "#FF0000", position: .inside))]
        #expect(line.outlineOutset == 4)
        #expect(line.reachPadding >= 4)
    }

    @Test("...and the same border on a closed path asks for none")
    func noRoomForAnInsideRingOnAShape() {
        var shape = layer(closed: true)
        shape.content = .path({ var p = path(closed: true); p.strokeWidth = 0; return p }())
        shape.style.effects = [.border(BorderEffect(width: 8, colorHex: "#FF0000", position: .inside))]
        #expect(shape.outlineOutset == 0)
    }

    @Test("An outside border on a line asks for half a width, not a whole one")
    func roomForAnOutsideRing() {
        var line = layer(closed: false)
        line.content = .path({ var p = path(closed: false); p.strokeWidth = 0; return p }())
        line.style.effects = [.border(BorderEffect(width: 8, colorHex: "#FF0000", position: .outside))]
        #expect(line.outlineOutset == 4)
    }

    // MARK: What the panel offers

    @Test("The panel reads a line off the document, not out of a flag somebody set")
    func theSelectionCarriesIt() {
        var document = PhotonzDocument(canvasSize: CGSize(width: 200, height: 200))
        let line = layer(closed: false)
        let shape = layer(closed: true)
        document.addLayer(line)
        document.addLayer(shape)
        #expect(document.layerStyleSelection(layerIDs: [line.id]).isOpenLineEverywhere)
        #expect(!document.layerStyleSelection(layerIDs: [shape.id]).isOpenLineEverywhere)
        #expect(!document.layerStyleSelection(layerIDs: [line.id, shape.id]).isOpenLineEverywhere)
    }

    @Test("The Position row is not offered when every picked layer is a line")
    func theRowKnows() {
        let line = LayerStyleSelection.Member(id: UUID(), style: LayerStyle(),
                                              cornerRadiusLimit: 0, hasOpenLine: true)
        let box = LayerStyleSelection.Member(id: UUID(), style: LayerStyle(),
                                             cornerRadiusLimit: 0)
        #expect(LayerStyleSelection(members: [line], selectionCount: 1).isOpenLineEverywhere)
        #expect(!LayerStyleSelection(members: [line, box], selectionCount: 2).isOpenLineEverywhere)
        #expect(!LayerStyleSelection(members: [], selectionCount: 0).isOpenLineEverywhere)
    }
}
