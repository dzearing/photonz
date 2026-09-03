import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

@Suite("Typed layer geometry")
struct LayerGeometryTests {

    private func rectangle(frame: CGRect, locked: Bool = false) -> Layer {
        var layer = AnnotationBuilder.layer(content: AnnotationContent(shape: .rectangle),
                                            from: CGPoint(x: frame.minX, y: frame.minY),
                                            to: CGPoint(x: frame.maxX, y: frame.maxY))
        layer.isLocked = locked
        return layer
    }

    // MARK: Reading

    @Test("Each field reads its own number off the frame")
    func fieldsReadTheFrame() {
        let frame = CGRect(x: 12, y: 34, width: 296, height: 118)
        #expect(LayerGeometry.value(.x, of: frame) == 12)
        #expect(LayerGeometry.value(.y, of: frame) == 34)
        #expect(LayerGeometry.value(.width, of: frame) == 296)
        #expect(LayerGeometry.value(.height, of: frame) == 118)
    }

    @Test("The number shown is whole document points, so what you read is what you can type")
    func displayValueRounds() {
        let frame = CGRect(x: 12.4, y: 33.6, width: 295.5, height: 117.49)
        #expect(LayerGeometry.displayValue(.x, of: frame) == 12)
        #expect(LayerGeometry.displayValue(.y, of: frame) == 34)
        #expect(LayerGeometry.displayValue(.width, of: frame) == 296)
        #expect(LayerGeometry.displayValue(.height, of: frame) == 117)
    }

    @Test("A negative position reads back as typed, so a layer parked off the canvas is still editable")
    func negativePositionsRead() {
        let frame = CGRect(x: -40, y: -8, width: 100, height: 50)
        #expect(LayerGeometry.displayValue(.x, of: frame) == -40)
        #expect(LayerGeometry.displayValue(.y, of: frame) == -8)
    }

    // MARK: Typing

    @Test("Typing X or Y moves the layer without changing its size")
    func typingPositionMoves() {
        let frame = CGRect(x: 12, y: 34, width: 296, height: 118)
        #expect(LayerGeometry.applying(200, to: .x, of: frame)
                == CGRect(x: 200, y: 34, width: 296, height: 118))
        #expect(LayerGeometry.applying(0, to: .y, of: frame)
                == CGRect(x: 12, y: 0, width: 296, height: 118))
    }

    @Test("Typing a width grows the layer to the right, and a height downward")
    func typingSizeAnchorsTopLeft() {
        let frame = CGRect(x: 12, y: 34, width: 100, height: 50)
        let wider = LayerGeometry.applying(296, to: .width, of: frame)
        #expect(wider == CGRect(x: 12, y: 34, width: 296, height: 50))
        let taller = LayerGeometry.applying(118, to: .height, of: frame)
        #expect(taller == CGRect(x: 12, y: 34, width: 100, height: 118))
    }

    @Test("A width of zero or less clamps to the smallest layer that can still be seen and grabbed")
    func sizeClampsToMinimum() {
        let frame = CGRect(x: 0, y: 0, width: 100, height: 50)
        #expect(LayerGeometry.applying(0, to: .width, of: frame).width == LayerGeometry.minimumSide)
        #expect(LayerGeometry.applying(-40, to: .height, of: frame).height == LayerGeometry.minimumSide)
    }

    @Test("A position is free to go negative, so a layer can hang off the canvas edge")
    func positionDoesNotClamp() {
        let frame = CGRect(x: 0, y: 0, width: 100, height: 50)
        #expect(LayerGeometry.applying(-30, to: .x, of: frame).minX == -30)
    }

    @Test("A number that is not a number leaves the layer exactly where it was")
    func nonFiniteInputIsIgnored() {
        let frame = CGRect(x: 12, y: 34, width: 100, height: 50)
        #expect(LayerGeometry.applying(.nan, to: .width, of: frame) == frame)
        #expect(LayerGeometry.applying(.infinity, to: .x, of: frame) == frame)
    }

    @Test("An absurd number is capped rather than making a layer nothing can render")
    func sizeCapsAtMaximum() {
        let frame = CGRect(x: 0, y: 0, width: 100, height: 50)
        let huge = LayerGeometry.applying(9_000_000, to: .width, of: frame)
        #expect(huge.width == LayerGeometry.maximumSide)
    }

    // MARK: Arrow keys

    @Test("An arrow key steps the field by one")
    func arrowStepsByOne() {
        #expect(LayerGeometry.stepped(296, direction: 1, coarse: false) == 297)
        #expect(LayerGeometry.stepped(296, direction: -1, coarse: false) == 295)
    }

    @Test("Shift and an arrow key steps by ten")
    func shiftArrowStepsByTen() {
        #expect(LayerGeometry.stepped(296, direction: 1, coarse: true) == 306)
        #expect(LayerGeometry.stepped(296, direction: -1, coarse: true) == 286)
    }

    @Test("Stepping starts from the whole number on screen, not the fraction behind it")
    func steppingRoundsFirst() {
        #expect(LayerGeometry.stepped(12.4, direction: 1, coarse: false) == 13)
        #expect(LayerGeometry.stepped(12.4, direction: -1, coarse: false) == 11)
    }

    @Test("Stepping a position down past zero keeps going negative")
    func steppingGoesNegative() {
        #expect(LayerGeometry.stepped(0, direction: -1, coarse: false) == -1)
    }

    // MARK: Reading what was typed

    @Test("A plain number is read as itself")
    func parsePlainNumber() {
        #expect(LayerGeometry.parse("296") == 296)
        #expect(LayerGeometry.parse("-40") == -40)
        #expect(LayerGeometry.parse("0") == 0)
    }

    @Test("Spaces around a number, a leading plus, and a pasted unit word all still read")
    func parseIsForgiving() {
        #expect(LayerGeometry.parse("  296  ") == 296)
        #expect(LayerGeometry.parse("+296") == 296)
        #expect(LayerGeometry.parse("296 px") == 296)
        #expect(LayerGeometry.parse("296px") == 296)
    }

    @Test("A fraction is kept, so a half point measured off a capture can be typed back")
    func parseKeepsFractions() {
        #expect(LayerGeometry.parse("296.5") == 296.5)
        #expect(LayerGeometry.parse("-0.5") == -0.5)
    }

    @Test("Anything that is not plainly one number changes nothing, rather than being guessed at")
    func parseRejectsNonsense() {
        #expect(LayerGeometry.parse("") == nil)
        #expect(LayerGeometry.parse("   ") == nil)
        #expect(LayerGeometry.parse("-") == nil)
        #expect(LayerGeometry.parse("wide") == nil)
        #expect(LayerGeometry.parse("px") == nil)
        // Ambiguous or clever input is refused rather than interpreted: a comma
        // means one thing in New York and another in Berlin.
        #expect(LayerGeometry.parse("1,296") == nil)
        #expect(LayerGeometry.parse("1e9") == nil)
        #expect(LayerGeometry.parse("29.6.5") == nil)
    }

    // MARK: Which fields accept typing

    @Test("A plain rectangle takes all four numbers")
    func rectangleIsFullyEditable() {
        let editing = LayerGeometryEditing(layer: rectangle(frame: CGRect(x: 0, y: 0, width: 100, height: 50)))
        #expect(editing.allows(.x))
        #expect(editing.allows(.y))
        #expect(editing.allows(.width))
        #expect(editing.allows(.height))
    }

    @Test("A locked layer takes none of them")
    func lockedLayerIsReadOnly() {
        let editing = LayerGeometryEditing(layer: rectangle(frame: CGRect(x: 0, y: 0, width: 100, height: 50),
                                                            locked: true))
        for field in LayerGeometryField.allCases { #expect(!editing.allows(field)) }
        #expect(editing.fixedReason(for: .width) == LayerGeometryEditing.lockedReason)
    }

    @Test("An arrow moves but does not stretch: its box is padding around a shaft, not the shape you drew")
    func arrowTakesPositionOnly() {
        let arrow = AnnotationBuilder.layer(content: AnnotationContent(shape: .arrow),
                                            from: .zero, to: CGPoint(x: 100, y: 100))
        let editing = LayerGeometryEditing(layer: arrow)
        #expect(editing.allows(.x))
        #expect(editing.allows(.y))
        #expect(!editing.allows(.width))
        #expect(!editing.allows(.height))
        #expect(editing.fixedReason(for: .width) != nil)
    }

    @Test("Text takes a width, which is its wrap width, but not a height")
    func textTakesWidthOnly() {
        let text = Layer(name: "Text", content: .text(TextContent(string: "hi")),
                         frame: CGRect(x: 0, y: 0, width: 100, height: 30))
        let editing = LayerGeometryEditing(layer: text)
        #expect(editing.allows(.x))
        #expect(editing.allows(.width))
        #expect(!editing.allows(.height))
        #expect(editing.fixedReason(for: .height) != nil)
    }

    @Test("An image takes all four")
    func imageIsFullyEditable() {
        let image = Layer(name: "Photo",
                          content: .image(ImageRef(pixelSize: CGSize(width: 400, height: 300))),
                          frame: CGRect(x: 0, y: 0, width: 400, height: 300))
        let editing = LayerGeometryEditing(layer: image)
        for field in LayerGeometryField.allCases { #expect(editing.allows(field)) }
        #expect(editing.fixedReason(for: .height) == nil)
    }

    @Test("A group takes all four numbers: resizing it scales what is inside it")
    func aGroupTakesEveryNumber() {
        let child = Layer(name: "Box", content: .image(ImageRef(pixelSize: CGSize(width: 20, height: 10))),
                          frame: CGRect(x: 0, y: 0, width: 20, height: 10))
        let group = Layer(name: "Group", content: .group(GroupContent(children: [child])),
                          frame: CGRect(x: 5, y: 5, width: 0, height: 0))
        let editing = LayerGeometryEditing(layer: group)
        for field in LayerGeometryField.allCases { #expect(editing.allows(field)) }
        #expect(editing.fixedReason(for: .width) == nil)
        #expect(editing.fixedReason(for: .height) == nil)
    }

    @Test("A copy of a component says its size comes from the original it follows")
    func aComponentCopyExplainsWhyItsSizeIsFixed() {
        let child = Layer(name: "Box", content: .image(ImageRef(pixelSize: CGSize(width: 20, height: 10))),
                          frame: CGRect(x: 0, y: 0, width: 20, height: 10))
        var content = GroupContent(children: [child])
        content.instanceOf = UUID()
        let copy = Layer(name: "Group", content: .group(content),
                         frame: CGRect(x: 5, y: 5, width: 0, height: 0))
        let editing = LayerGeometryEditing(layer: copy)
        // A copy moves, so X and Y stay typeable; its size comes from elsewhere.
        #expect(editing.allows(.x))
        #expect(editing.allows(.y))
        #expect(!editing.allows(.width))
        #expect(!editing.allows(.height))
        #expect(editing.fixedReason(for: .width) == LayerGeometryEditing.instanceSizeReason)
        #expect(editing.fixedReason(for: .height) == LayerGeometryEditing.instanceSizeReason)
    }

    @Test("Every reason a field is fixed reads as a plain sentence, not a code word")
    func reasonsArePlainLanguage() {
        let arrow = AnnotationBuilder.layer(content: AnnotationContent(shape: .arrow),
                                            from: .zero, to: CGPoint(x: 10, y: 10))
        let reasons = [LayerGeometryEditing.lockedReason,
                       LayerGeometryEditing(layer: arrow).fixedReason(for: .width) ?? "",
                       LayerGeometryEditing.instanceSizeReason]
        for reason in reasons {
            #expect(!reason.isEmpty)
            #expect(reason.first!.isUppercase)
            #expect(!reason.contains("—"))
        }
    }

    // MARK: Labels

    @Test("The fields are labelled the way every design tool labels them")
    func fieldLabels() {
        #expect(LayerGeometryField.x.label == "X")
        #expect(LayerGeometryField.y.label == "Y")
        #expect(LayerGeometryField.width.label == "W")
        #expect(LayerGeometryField.height.label == "H")
    }

    @Test("Each field says in words which edge or measurement it is")
    func fieldTitles() {
        for field in LayerGeometryField.allCases {
            #expect(!field.title.isEmpty)
            #expect(field.title != field.label)
        }
    }

    @Test("An arrow key in a field steps a layer by exactly what an arrow key on the canvas does")
    func steppingMatchesTheCanvasNudge() {
        #expect(Nudge.delta(keyCode: 124, large: false)?.dx == LayerGeometry.step)
        #expect(Nudge.delta(keyCode: 124, large: true)?.dx == LayerGeometry.coarseStep)
    }

    @Test("The unit word is the one the measure readouts already use")
    func unitMatchesMeasure() {
        #expect(LayerGeometry.unitSuffix == MeasureUnit.pixels.suffix)
    }

    // MARK: Round trip through a real layer

    @Test("Typing a width on a rectangle really does make the drawn rectangle that wide")
    func rectangleResizesToTypedWidth() {
        let layer = rectangle(frame: CGRect(x: 20, y: 40, width: 100, height: 50))
        // A rectangle pads its frame by nothing, so the frame IS the drawn shape.
        #expect(layer.frame == CGRect(x: 20, y: 40, width: 100, height: 50))
        let resized = layer.resized(to: LayerGeometry.applying(296, to: .width, of: layer.frame))
        #expect(resized.frame.width == 296)
        #expect(resized.frame.minX == 20)
        #expect(resized.frame.height == 50)
    }

    @Test("Typing X on a rectangle slides it without resizing it")
    func rectangleMovesToTypedX() {
        let layer = rectangle(frame: CGRect(x: 20, y: 40, width: 100, height: 50))
        let moved = layer.resized(to: LayerGeometry.applying(200, to: .x, of: layer.frame))
        #expect(moved.frame == CGRect(x: 200, y: 40, width: 100, height: 50))
    }
}
