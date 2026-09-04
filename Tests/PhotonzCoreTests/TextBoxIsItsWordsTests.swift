import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// A text layer's box is its words (`docs/design/ui-building.md`, "A text
/// layer's box is its words").
///
/// A measured text box carries a few points of empty room on its far edges so
/// antialiased glyph edges never clip at the boundary. That room is real in the
/// stored frame and invisible on screen, so every surface a person reads a box
/// off — the selection outline, the W and H fields, the magnets a drag lines up
/// with, the band you sweep round something — has to speak the box without it.
@Suite("A text layer's box is its words")
struct TextBoxIsItsWordsTests {

    private func label(_ string: String = "Save changes",
                       at origin: CGPoint = CGPoint(x: 40, y: 60)) -> Layer {
        let content = TextContent(string: string, fontSize: 14)
        return Layer(name: "Label", content: .text(content),
                     frame: CGRect(origin: origin, size: TextMeasurement.size(of: content)))
    }

    private func box(_ frame: CGRect) -> Layer {
        Layer(name: "Box",
              content: .annotation(AnnotationContent(shape: .rectangle, start: .zero,
                                                     end: CGPoint(x: frame.width, y: frame.height))),
              frame: frame)
    }

    // MARK: The two primitives

    @Test("The box you see is the stored box without the slack on its far edges")
    func withoutSlackTakesTheRoomOffTheFarEdges() {
        let layer = label()
        let seen = layer.withoutSlack(layer.frame)
        #expect(seen.origin == layer.frame.origin)
        #expect(seen.width == layer.frame.width - TextMeasurement.slack)
        #expect(seen.height == layer.frame.height - TextMeasurement.slack)
    }

    @Test("Putting the slack back gives the stored box again, so nothing drifts through a round trip")
    func slackRoundTrips() {
        let layer = label()
        #expect(layer.withSlack(layer.withoutSlack(layer.frame)) == layer.frame)
    }

    @Test("Everything that is not text sees exactly the box it stores")
    func otherContentCarriesNoSlack() {
        let rect = CGRect(x: 10, y: 20, width: 120, height: 40)
        let layer = box(rect)
        #expect(layer.withoutSlack(rect) == rect)
        #expect(layer.withSlack(rect) == rect)
        #expect(layer.contentBounds == layer.localBounds)
    }

    @Test("A label's content box is its words")
    func contentBoundsIsTheWords() {
        let layer = label()
        #expect(layer.contentBounds == layer.withoutSlack(layer.frame))
    }

    // MARK: The W and H fields

    private func member(_ layer: Layer) -> LayerGeometrySelection.Member {
        LayerGeometrySelection.Member(id: layer.id, frame: layer.withoutSlack(layer.frame),
                                      editing: LayerGeometryEditing(layer: layer),
                                      slack: layer.boxSlack)
    }

    @Test("W and H report the size of the words, not the room round them")
    func fieldsReportTheWords() {
        let layer = label()
        let sel = LayerGeometrySelection([member(layer)])
        #expect(sel.reading(.width) == .agreed((layer.frame.width - TextMeasurement.slack).rounded()))
        #expect(sel.reading(.height) == .agreed((layer.frame.height - TextMeasurement.slack).rounded()))
        // Where it sits is unchanged: the words start at the box's own corner.
        #expect(sel.reading(.x) == .agreed(layer.frame.minX.rounded()))
        #expect(sel.reading(.y) == .agreed(layer.frame.minY.rounded()))
    }

    @Test("Typing a width wraps the words to that width: the box stored carries the slack on top")
    func typingAWidthPutsTheSlackBack() {
        let layer = label()
        let sel = LayerGeometrySelection([member(layer)])
        let moves = sel.applying(150, to: .width)
        #expect(moves[layer.id]?.width == 150 + TextMeasurement.slack)
        #expect(moves[layer.id]?.origin == layer.frame.origin)
    }

    @Test("A width that changes nothing produces no move, counted on the words")
    func typingTheWidthItAlreadyIsMovesNothing() {
        let layer = label()
        let sel = LayerGeometrySelection([member(layer)])
        #expect(sel.applying(layer.frame.width - TextMeasurement.slack, to: .width).isEmpty)
    }

    @Test("An arrow key steps the number on screen and keeps the slack underneath it")
    func steppingKeepsTheSlack() {
        let layer = label()
        let sel = LayerGeometrySelection([member(layer)])
        let words = (layer.frame.width - TextMeasurement.slack).rounded()
        let moves = sel.stepping(.width, direction: 1, coarse: false)
        #expect(moves[layer.id]?.width == words + 1 + TextMeasurement.slack)
    }

    @Test("A typed width stops at the narrowest the WORDS go, which is the number the field says")
    func theFloorIsCountedOnTheWords() {
        let layer = label()
        let sel = LayerGeometrySelection([member(layer)])
        #expect(sel.landing(12, in: .width) == .agreed(TextMeasurement.minimumContentWidth))
        let moves = sel.applying(12, to: .width)
        #expect(moves[layer.id]?.width
                == TextMeasurement.minimumContentWidth + TextMeasurement.slack)
    }

    @Test("The stored floor is the words' floor plus the slack, so a box dragged as narrow as it goes reads the same number")
    func theStoredFloorHoldsTheWordsFloor() {
        #expect(TextMeasurement.minimumWidth
                == TextMeasurement.minimumContentWidth + TextMeasurement.slack)
    }

    // MARK: What a drag lines up with

    @Test("A label offers its words as a magnet, not the empty room past them")
    func snapPeersOfferTheWords() {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 600, height: 400))
        let words = label()
        let other = box(CGRect(x: 300, y: 300, width: 40, height: 40))
        doc.layers = [words, other]
        let peers = doc.snapPeers(excluding: other.id)
        #expect(peers == [words.contentBounds])
    }

    // MARK: The outline, and the band you sweep

    @Test("The corners the outline draws are the words' corners")
    func outlineCornersAreTheWords() {
        let layer = label()
        let seen = layer.withoutSlack(layer.frame)
        #expect(layer.transformedCorners == [CGPoint(x: seen.minX, y: seen.minY),
                                             CGPoint(x: seen.maxX, y: seen.minY),
                                             CGPoint(x: seen.maxX, y: seen.maxY),
                                             CGPoint(x: seen.minX, y: seen.maxY)])
    }

    @Test("A turned label's outline turns about the box it is DRAWN in, so the outline stays on the words")
    func rotatedOutlineTurnsAboutTheStoredBox() {
        var layer = label()
        layer.transform = LayerTransform(rotation: .pi / 4)
        let centre = CGPoint(x: layer.frame.midX, y: layer.frame.midY)
        let turn = layer.transform.affineTransform(around: centre)
        let seen = layer.withoutSlack(layer.frame)
        let expected = [CGPoint(x: seen.minX, y: seen.minY),
                        CGPoint(x: seen.maxX, y: seen.minY),
                        CGPoint(x: seen.maxX, y: seen.maxY),
                        CGPoint(x: seen.minX, y: seen.maxY)].map { $0.applying(turn) }
        for (drawn, want) in zip(layer.transformedCorners, expected) {
            #expect(abs(drawn.x - want.x) < 0.001)
            #expect(abs(drawn.y - want.y) < 0.001)
        }
    }

    @Test("A band swept round the words picks the label up")
    func aBandRoundTheWordsCatchesTheLabel() {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 600, height: 400))
        let layer = label()
        doc.layers = [layer]
        let round = layer.contentBounds.insetBy(dx: -1, dy: -1)
        #expect(doc.layerIDs(fullyInside: round) == [layer.id])
    }

    // MARK: Nothing about how the words are drawn changes

    @Test("The stored box still carries the room the renderer needs")
    func theStoredBoxIsUntouched() {
        let content = TextContent(string: "Save changes", fontSize: 14)
        let measured = TextMeasurement.size(of: content)
        let layer = label()
        #expect(layer.frame.size == measured)
        // And a re-fit still stores a box with the room in it.
        let refit = layer.resized(to: CGRect(x: 40, y: 60, width: 150, height: 10))
        #expect(refit.frame.width == 150)
        #expect(refit.frame.height == TextMeasurement.size(of: content, wrappingAt: 150).height)
    }

    @Test("Two stacked labels sit the gap apart on screen, which is what a caliper across them reads")
    func stackedLabelsAreTheGapApart() {
        var content = GroupContent(children: [label("First line", at: .zero),
                                              label("Second line", at: .zero)])
        content.layout = GroupLayout(kind: .stack, direction: .column, gap: 8)
        let stack = GroupFlow.flowing(Layer(name: "Stack", content: .group(content),
                                            frame: CGRect(x: 20, y: 20, width: 0, height: 0)))
        let rows = stack.children
        #expect(rows.count == 2)
        #expect(rows[1].contentBounds.minY - rows[0].contentBounds.maxY == 8)
    }
}
