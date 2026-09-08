import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// Measuring the boxes the app DREW, rather than the ones it reads off a
/// picture. Size mode used to have only the picture reader, so a rectangle you
/// drew a moment ago was the one thing on the canvas it could not measure.
@Suite("Elements the document itself knows")
struct LayerElementsTests {
    let canvas = CGSize(width: 900, height: 600)

    private func shape(_ frame: CGRect, name: String = "Rectangle",
                       isVisible: Bool = true) -> Layer {
        Layer(name: name,
              content: .annotation(AnnotationContent(shape: .rectangle, strokeWidth: 2)),
              frame: frame, isVisible: isVisible)
    }

    private func picture(_ frame: CGRect, name: String = "Background") -> Layer {
        Layer(name: name,
              content: .image(ImageRef(pixelSize: frame.size)),
              frame: frame)
    }

    private func group(_ origin: CGPoint, _ children: [Layer], name: String = "Group") -> Layer {
        Layer(name: name, content: .group(GroupContent(children: children)),
              frame: CGRect(origin: origin, size: .zero))
    }

    private func document(_ layers: [Layer]) -> PhotonzDocument {
        PhotonzDocument(canvasSize: canvas, layers: layers)
    }

    // MARK: The basic miss and hit

    @Test func aDrawnRectangleUnderThePointerIsAnElement() {
        let doc = document([picture(CGRect(origin: .zero, size: canvas)),
                            shape(CGRect(x: 300, y: 240, width: 260, height: 180))])
        let ladder = LayerElements.candidates(at: CGPoint(x: 430, y: 330), in: doc)
        #expect(ladder == [CGRect(x: 300, y: 240, width: 260, height: 180)])
    }

    @Test func pointingBesideEverythingFindsNothing() {
        let doc = document([picture(CGRect(origin: .zero, size: canvas)),
                            shape(CGRect(x: 300, y: 240, width: 260, height: 180))])
        #expect(LayerElements.candidates(at: CGPoint(x: 80, y: 80), in: doc).isEmpty)
    }

    @Test func theBackdropIsNotAnElement() {
        // The picture filling the canvas is the thing Size mode reads pixels
        // from; offering its own frame would turn every miss into a hit on the
        // whole canvas.
        let doc = document([picture(CGRect(origin: .zero, size: canvas))])
        #expect(LayerElements.candidates(at: CGPoint(x: 430, y: 330), in: doc).isEmpty)
    }

    @Test func aPictureDroppedInTheMiddleIsAnElement() {
        // A second screenshot dropped onto the canvas is never analyzed (only
        // the backdrop is), so its own box is the only answer there is.
        let doc = document([picture(CGRect(origin: .zero, size: canvas)),
                            picture(CGRect(x: 100, y: 100, width: 400, height: 300), name: "Shot")])
        let ladder = LayerElements.candidates(at: CGPoint(x: 200, y: 200), in: doc)
        #expect(ladder == [CGRect(x: 100, y: 100, width: 400, height: 300)])
    }

    @Test func aTurnedShapeIsLeftToThePictureReader() {
        // Its box is stored unturned, so outlining it would draw a rectangle
        // that is not the shape on screen.
        var turned = shape(CGRect(x: 300, y: 240, width: 260, height: 180))
        turned.transform = LayerTransform(rotation: 0.4)
        #expect(LayerElements.candidates(at: CGPoint(x: 430, y: 330), in: document([turned])).isEmpty)
    }

    @Test func aFlippedShapeIsStillAnElement() {
        // A mirrored shape fills exactly the box it always did.
        var flipped = shape(CGRect(x: 300, y: 240, width: 260, height: 180))
        flipped.transform = LayerTransform(flipHorizontal: true)
        #expect(LayerElements.candidates(at: CGPoint(x: 430, y: 330), in: document([flipped]))
                == [CGRect(x: 300, y: 240, width: 260, height: 180)])
    }

    @Test func aHiddenShapeIsNotAnElement() {
        let doc = document([shape(CGRect(x: 300, y: 240, width: 260, height: 180),
                                  isVisible: false)])
        #expect(LayerElements.candidates(at: CGPoint(x: 430, y: 330), in: doc).isEmpty)
    }

    @Test func aCaliperIsNotAnElement() {
        // A measurement's bounding box is not something anybody aims at, the
        // same rule foot snapping already follows.
        let caliper = MeasureBuilder.layer(content: MeasureContent(headOffset: -40, mode: .horizontal),
                                           from: CGPoint(x: 300, y: 400), to: CGPoint(x: 560, y: 400))
        let doc = document([caliper])
        #expect(LayerElements.candidates(at: CGPoint(x: 430, y: 390), in: doc).isEmpty)
    }

    // MARK: The ladder

    @Test func theLadderClimbsFromAShapeToTheGroupHoldingIt() {
        let inner = shape(CGRect(x: 20, y: 20, width: 100, height: 40), name: "Button")
        let outer = shape(CGRect(x: 0, y: 0, width: 300, height: 200), name: "Card")
        let doc = document([group(CGPoint(x: 100, y: 100), [outer, inner])])
        let ladder = LayerElements.candidates(at: CGPoint(x: 170, y: 140), in: doc)
        // The button first, then the card it sits on, then the group's own box.
        #expect(ladder.first == CGRect(x: 120, y: 120, width: 100, height: 40))
        #expect(ladder.contains(CGRect(x: 100, y: 100, width: 300, height: 200)))
        #expect(ladder.count == 2) // the group's box IS the card's, read twice
    }

    @Test func twoRungsThatAreTheSameBoxAreOfferedOnce() {
        let inner = shape(CGRect(x: 0, y: 0, width: 200, height: 100))
        let doc = document([group(CGPoint(x: 50, y: 50), [inner])])
        #expect(LayerElements.candidates(at: CGPoint(x: 100, y: 80), in: doc)
                == [CGRect(x: 50, y: 50, width: 200, height: 100)])
    }

    @Test func theInnermostRungComesFirst() {
        let doc = document([shape(CGRect(x: 100, y: 100, width: 400, height: 300), name: "Card"),
                            shape(CGRect(x: 150, y: 150, width: 120, height: 44), name: "Button")])
        let ladder = LayerElements.candidates(at: CGPoint(x: 200, y: 170), in: doc)
        #expect(ladder == [CGRect(x: 150, y: 150, width: 120, height: 44),
                           CGRect(x: 100, y: 100, width: 400, height: 300)])
    }

    // MARK: Merging with what the picture says

    @Test func aRungThePictureFoundInsideADrawnOneComesFirst() {
        // Somebody drew a box around a button to point at it. The button is
        // still the thing they want to measure, so the drawn box is the SECOND
        // rung, not the only one.
        let drawn = [CGRect(x: 140, y: 140, width: 140, height: 64)]
        let picture = [CGRect(x: 150, y: 150, width: 120, height: 44)]
        #expect(LayerElements.merged(drawn: drawn, picture: picture)
                == [CGRect(x: 150, y: 150, width: 120, height: 44),
                    CGRect(x: 140, y: 140, width: 140, height: 64)])
    }

    @Test func aDrawnRungWinsAndThePictureCarriesTheLadderOn() {
        let drawn = [CGRect(x: 150, y: 150, width: 120, height: 44)]
        let picture = [CGRect(x: 152, y: 152, width: 116, height: 40),  // the same thing, guessed
                       CGRect(x: 100, y: 100, width: 400, height: 300)] // the card behind it
        let merged = LayerElements.merged(drawn: drawn, picture: picture)
        #expect(merged == [CGRect(x: 150, y: 150, width: 120, height: 44),
                           CGRect(x: 100, y: 100, width: 400, height: 300)])
    }

    @Test func withNothingDrawnThePictureLadderIsUntouched() {
        let picture = [CGRect(x: 152, y: 152, width: 116, height: 40),
                       CGRect(x: 100, y: 100, width: 400, height: 300)]
        #expect(LayerElements.merged(drawn: [], picture: picture) == picture)
    }

    @Test func theMergedLadderStaysAHandfulOfPresses() {
        let drawn = (0..<6).map { CGRect(x: 100 - $0 * 10, y: 100, width: 40 + $0 * 20, height: 40) }
        let picture = (0..<20).map { CGRect(x: 0, y: 0, width: 500 + $0 * 20, height: 500) }
        #expect(LayerElements.merged(drawn: drawn, picture: picture).count
                <= ElementBounds.candidateLimit)
    }

    // MARK: The whole list, for the readers that take a point of their own

    @Test func everyDrawnBoxIsOfferedToTheReadersThatTakeAList() {
        // Gap and the alignment scan aim at a point or a line rather than at a
        // box, so they take the whole list and do their own aiming.
        let a = CGRect(x: 200, y: 240, width: 180, height: 180)
        let b = CGRect(x: 460, y: 240, width: 180, height: 180)
        let doc = document([picture(CGRect(origin: .zero, size: canvas)), shape(a), shape(b)])
        #expect(Set(LayerElements.boxes(in: doc)) == [a, b])
    }

    @Test func aMeasurementIsNotOneOfTheBoxes() {
        // Same rule the ladder follows: nobody points at a caliper to measure
        // the space beside it.
        let caliper = MeasureBuilder.layer(content: MeasureContent(headOffset: -40, mode: .horizontal),
                                           from: CGPoint(x: 100, y: 100), to: CGPoint(x: 300, y: 100))
        let doc = document([caliper, shape(CGRect(x: 400, y: 100, width: 100, height: 40))])
        #expect(LayerElements.boxes(in: doc) == [CGRect(x: 400, y: 100, width: 100, height: 40)])
    }

    // MARK: Neighbours, so a readout steers around the other shapes

    @Test func theShapeNextDoorIsANeighbour() {
        let doc = document([shape(CGRect(x: 100, y: 100, width: 100, height: 40), name: "A"),
                            shape(CGRect(x: 240, y: 100, width: 100, height: 40), name: "B")])
        let found = LayerElements.neighbors(of: CGRect(x: 100, y: 100, width: 100, height: 40),
                                            in: doc, reach: 120)
        #expect(found == [CGRect(x: 240, y: 100, width: 100, height: 40)])
    }

    @Test func aShapeAcrossTheCanvasIsNotANeighbour() {
        let doc = document([shape(CGRect(x: 100, y: 100, width: 100, height: 40), name: "A"),
                            shape(CGRect(x: 700, y: 500, width: 100, height: 40), name: "B")])
        #expect(LayerElements.neighbors(of: CGRect(x: 100, y: 100, width: 100, height: 40),
                                        in: doc, reach: 120).isEmpty)
    }

    @Test func theMeasuredShapeIsNotItsOwnNeighbour() {
        let doc = document([shape(CGRect(x: 100, y: 100, width: 100, height: 40))])
        #expect(LayerElements.neighbors(of: CGRect(x: 100, y: 100, width: 100, height: 40),
                                        in: doc, reach: 120).isEmpty)
    }
}
