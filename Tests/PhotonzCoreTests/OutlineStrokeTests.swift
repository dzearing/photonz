import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// Outline Stroke: the line round a shape becomes a filled shape of its own, the
/// same picture with no stroke left in it (`icon-draw-wt.html`, `#layerMenu`).
/// It is how an icon drawn in lines leaves as the filled glyph a set ships.
@Suite("Outline stroke")
struct OutlineStrokeTests {

    // MARK: Fixtures

    private func iconDoc(_ children: [Layer]) -> PhotonzDocument {
        let frame = Layer.frameLayer(name: "Icon", origin: CGPoint(x: 100, y: 50),
                                     size: CGSize(width: 24, height: 24), children: children)
        return PhotonzDocument(canvasSize: CGSize(width: 400, height: 300), layers: [frame])
    }

    /// An open straight path from (0, 0) to (10, 0), standing at (4, 8).
    private func line(width: CGFloat = 2, end: PathLineEnd = .flat,
                      pattern: PathLinePattern = .solid) -> Layer {
        let content = PathContent(anchors: [PathAnchor(point: .zero),
                                            PathAnchor(point: CGPoint(x: 10, y: 0))],
                                  isClosed: false, paint: Paint(hex: "#112233"),
                                  strokeWidth: width, fill: nil, lineEnd: end,
                                  linePattern: pattern)
        return Layer(name: "Stroke", content: .path(content),
                     frame: CGRect(x: 4, y: 8, width: 10, height: 0))
    }

    /// A closed 10 x 10 square path at (4, 4).
    private func square(width: CGFloat = 2, position: BorderPosition = .center,
                        fill: Paint? = nil, name: String = "Square") -> Layer {
        let points = [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0),
                      CGPoint(x: 10, y: 10), CGPoint(x: 0, y: 10)]
        let content = PathContent(anchors: points.map { PathAnchor(point: $0) }, isClosed: true,
                                  paint: Paint(hex: "#112233"), strokeWidth: width,
                                  strokePosition: position, fill: fill)
        return Layer(name: name, content: .path(content),
                     frame: CGRect(x: 4, y: 4, width: 10, height: 10))
    }

    private func id(_ doc: PhotonzDocument, _ name: String) -> UUID {
        doc.allLayers.first { $0.name == name }?.id ?? UUID()
    }

    private func close(_ a: CGRect?, _ b: CGRect, _ slack: CGFloat = 0.01) -> Bool {
        guard let a else { return false }
        return abs(a.minX - b.minX) < slack && abs(a.minY - b.minY) < slack
            && abs(a.width - b.width) < slack && abs(a.height - b.height) < slack
    }

    // MARK: The outline itself

    @Test func aFlatEndedLineBecomesTheBandItCovered() throws {
        var d = iconDoc([line()])
        let made = d.outlineStroke(ids: [id(d, "Stroke")])
        #expect(made == [id(d, "Stroke")])
        let layer = try #require(d.layer(id: made[0]))
        let path = try #require(layer.path)
        #expect(path.isClosed)
        #expect(path.strokeWidth == 0)
        #expect(path.fill == Paint(hex: "#112233"))
        // 10 long, 2 deep, centred on where the line ran.
        #expect(close(d.canvasFrame(of: layer.id), CGRect(x: 104, y: 57, width: 10, height: 2)))
    }

    @Test func roundEndsReachHalfALinePastEachEnd() throws {
        var d = iconDoc([line(end: .round)])
        let made = d.outlineStroke(ids: [id(d, "Stroke")])
        #expect(close(d.canvasFrame(of: made[0]), CGRect(x: 103, y: 57, width: 12, height: 2)))
    }

    @Test func aCentredLineRoundASquareBecomesARingWithAHole() throws {
        var d = iconDoc([square()])
        let made = d.outlineStroke(ids: [id(d, "Square")])
        let path = try #require(d.layer(id: made[0])?.path)
        #expect(path.ringCount == 2)
        #expect(close(d.canvasFrame(of: made[0]), CGRect(x: 103, y: 53, width: 12, height: 12)))
    }

    @Test func anInsideLineStaysInsideTheShape() throws {
        var d = iconDoc([square(position: .inside)])
        let made = d.outlineStroke(ids: [id(d, "Square")])
        #expect(close(d.canvasFrame(of: made[0]), CGRect(x: 104, y: 54, width: 10, height: 10)))
        #expect(d.layer(id: made[0])?.path?.ringCount == 2)
    }

    @Test func anOutsideLineSitsWhollyOutsideTheShape() throws {
        var d = iconDoc([square(position: .outside)])
        let made = d.outlineStroke(ids: [id(d, "Square")])
        #expect(close(d.canvasFrame(of: made[0]), CGRect(x: 102, y: 52, width: 14, height: 14)))
        #expect(d.layer(id: made[0])?.path?.ringCount == 2)
    }

    @Test func aDashedLineComesOutInItsDashes() throws {
        // A dashed line 2 wide is 6 on and 4 off, so 40 long holds four.
        var long = line(pattern: .dashed)
        if case .path(var content) = long.content {
            content.anchors[1].point = CGPoint(x: 40, y: 0)
            long.content = .path(content)
            long.frame.size.width = 40
        }
        var d = iconDoc([long])
        let made = d.outlineStroke(ids: [id(d, "Stroke")])
        let path = try #require(d.layer(id: made[0])?.path)
        // The dashes start at 0, 10, 20 and 30.
        #expect(path.ringCount == 4)
    }

    // MARK: What happens to the layer

    @Test func aShapeWithAFillKeepsItAndGetsItsOutlineAboveIt() throws {
        var d = iconDoc([square(fill: Paint(hex: "#AABBCC"))])
        let source = id(d, "Square")
        let made = d.outlineStroke(ids: [source])
        #expect(made.count == 1)
        #expect(made[0] != source)
        // The fill is still the shape it was, without its line.
        let kept = try #require(d.layer(id: source)?.path)
        #expect(kept.fill == Paint(hex: "#AABBCC"))
        #expect(kept.strokeWidth == 0)
        // The outline sits directly above it, filled in the line's colour.
        let frame = try #require(d.layers.first)
        #expect(frame.children.map(\.id) == [source, made[0]])
        let outline = try #require(d.layer(id: made[0]))
        #expect(outline.path?.fill == Paint(hex: "#112233"))
        #expect(outline.path?.strokeWidth == 0)
        #expect(outline.name == "Square outline")
    }

    @Test func aSeeThroughShapeWithAFillIsGroupedSoItLooksTheSame() throws {
        var shape = square(fill: Paint(hex: "#AABBCC"))
        shape.style.opacity = 0.5
        var d = iconDoc([shape])
        let made = d.outlineStroke(ids: [id(d, "Square")])
        // The two halves are faded together, as one, by a group that wears
        // what the shape wore; neither half is faded on its own.
        let outline = try #require(d.layer(id: made[0]))
        #expect(outline.style.opacity == 1)
        let parent = try #require(d.parentID(of: made[0]).flatMap { d.layer(id: $0) })
        #expect(parent.isGroup)
        #expect(!parent.isFrame)
        #expect(parent.name == "Square")
        #expect(parent.style.opacity == 0.5)
        #expect(parent.children.count == 2)
        #expect(parent.children.allSatisfy { $0.style.opacity == 1 })
    }

    @Test func aDrawnRectangleBecomesAPathNamedLikeOne() throws {
        let content = AnnotationContent(shape: .rectangle, strokeWidth: 2, colorHex: "#112233",
                                        start: .zero, end: CGPoint(x: 10, y: 10))
        let rect = Layer(name: "Rectangle", content: .annotation(content),
                         frame: CGRect(x: 4, y: 4, width: 10, height: 10))
        var d = iconDoc([rect])
        let made = d.outlineStroke(ids: [id(d, "Rectangle")])
        let layer = try #require(d.layer(id: made[0]))
        #expect(layer.path?.strokeWidth == 0)
        #expect(layer.path?.ringCount == 2)
        #expect(layer.name == "Path")
    }

    // MARK: A line worn as a Border

    /// What Union leaves when it joins shapes drawn with the box or oval tool:
    /// a path with no stroke of its own, wearing the bottom shape's Border.
    private func borderedSquare(position: BorderPosition, ownStroke: CGFloat = 0) -> Layer {
        var shape = square(width: ownStroke)
        shape.style.effects = [.border(BorderEffect(width: 2, colorHex: "#334455",
                                                    position: position))]
        return shape
    }

    @Test func aBorderOutsideAPathBecomesTheRingItDrew() throws {
        var d = iconDoc([borderedSquare(position: .outside)])
        let made = d.outlineStroke(ids: [id(d, "Square")])
        #expect(made == [id(d, "Square")])
        let layer = try #require(d.layer(id: made[0]))
        #expect(layer.path?.fill == Paint(hex: "#334455"))
        #expect(layer.path?.ringCount == 2)
        // The ring stood 2 outside the 10 x 10 square.
        #expect(close(d.canvasFrame(of: layer.id), CGRect(x: 102, y: 52, width: 14, height: 14)))
        // And it is no longer a Border, or the line would be drawn twice.
        #expect(layer.style.paintedBorders.isEmpty)
    }

    @Test func aBorderInsideAPathStaysWithinIt() throws {
        var d = iconDoc([borderedSquare(position: .inside)])
        let made = d.outlineStroke(ids: [id(d, "Square")])
        #expect(close(d.canvasFrame(of: made[0]), CGRect(x: 104, y: 54, width: 10, height: 10)))
    }

    @Test func aShapeWithItsOwnLineAndABorderGetsAnOutlineForEach() throws {
        var d = iconDoc([borderedSquare(position: .outside, ownStroke: 2)])
        let source = id(d, "Square")
        let made = d.outlineStroke(ids: [source])
        #expect(made.count == 2)
        // Its own line, painted first, takes the row; the Border's ring goes
        // above it, in the Border's colour.
        #expect(made[0] == source)
        #expect(d.layer(id: made[0])?.path?.fill == Paint(hex: "#112233"))
        #expect(d.layer(id: made[1])?.path?.fill == Paint(hex: "#334455"))
        let frame = try #require(d.layers.first)
        #expect(frame.children.map(\.id) == made)
        #expect(made.allSatisfy { d.layer(id: $0)?.style.paintedBorders.isEmpty == true })
    }

    @Test func aBoxDrawnWithAFillKeepsTheFillAndLosesOnlyItsLine() throws {
        let content = AnnotationContent(shape: .rectangle, strokeWidth: 2, colorHex: "#112233",
                                        start: .zero, end: CGPoint(x: 10, y: 10),
                                        fillColorHex: "#AABBCC")
        let rect = Layer(name: "Rectangle", content: .annotation(content),
                         frame: CGRect(x: 4, y: 4, width: 10, height: 10))
        var d = iconDoc([rect])
        let source = id(d, "Rectangle")
        let made = d.outlineStroke(ids: [source])
        #expect(made.count == 1)
        // Still a box, still filled, with no Border left on it.
        let kept = try #require(d.layer(id: source))
        #expect(kept.annotation?.fill == Paint(hex: "#AABBCC"))
        #expect(kept.style.paintedBorders.isEmpty)
        #expect(d.layer(id: made[0])?.path?.fill == Paint(hex: "#112233"))
    }

    @Test func aNameSomebodyTypedIsKept() throws {
        var d = iconDoc([square(name: "Bezel")])
        let made = d.outlineStroke(ids: [id(d, "Bezel")])
        #expect(d.layer(id: made[0])?.name == "Bezel")
    }

    @Test func aTurnedShapeIsOutlinedWhereItIsDrawn() throws {
        var turned = line(end: .flat)
        turned.transform.rotation = .pi / 2
        var d = iconDoc([turned])
        let made = d.outlineStroke(ids: [id(d, "Stroke")])
        let layer = try #require(d.layer(id: made[0]))
        #expect(layer.transform.isIdentity)
        // Turned a quarter about its middle (9, 8): it now runs down from
        // (9, 3) to (9, 13), 2 wide.
        #expect(close(d.canvasFrame(of: layer.id), CGRect(x: 108, y: 53, width: 2, height: 10)))
    }

    @Test func aColourStyleOnTheLineMovesToTheFill() throws {
        let styleID = UUID()
        var shape = line()
        shape.colorStyleBindings = [ColorStyleBinding(slot: .stroke, styleID: styleID)]
        var d = iconDoc([shape])
        let made = d.outlineStroke(ids: [id(d, "Stroke")])
        let bindings = try #require(d.layer(id: made[0])?.colorStyleBindings)
        #expect(bindings.map(\.slot) == [.fill])
        #expect(bindings.map(\.styleID) == [styleID])
    }

    @Test func severalShapesOutlineInOneGo() throws {
        var other = line()
        other.name = "Other"
        var d = iconDoc([line(), other])
        let made = d.outlineStroke(ids: [id(d, "Stroke"), id(d, "Other")])
        #expect(made.count == 2)
        #expect(made.allSatisfy { d.layer(id: $0)?.path?.strokeWidth == 0 })
    }

    // MARK: When there is nothing to do

    @Test func aShapeWithNoLineHasNothingToOutline() {
        let d = iconDoc([square(width: 0, fill: Paint(hex: "#AABBCC"))])
        #expect(!d.canOutlineStroke(ids: [id(d, "Square")]))
    }

    @Test func aLockedShapeIsLeftAlone() {
        var locked = square()
        locked.isLocked = true
        var d = iconDoc([locked])
        #expect(!d.canOutlineStroke(ids: [id(d, "Square")]))
        let before = d
        let made = d.outlineStroke(ids: [id(d, "Square")])
        #expect(made.isEmpty)
        #expect(d == before)
    }

    @Test func aPictureOrWordsHaveNoLineToOutline() {
        let words = Layer(name: "Words", content: .text(TextContent(string: "Hi")),
                          frame: CGRect(x: 0, y: 0, width: 20, height: 10))
        let d = iconDoc([words])
        #expect(!d.canOutlineStroke(ids: [id(d, "Words")]))
    }

    @Test func theMenuWordsAreTheMocks() {
        #expect(OutlineStroke.title == "Outline Stroke")
        #expect(PathCombine.unionTitle == "Union")
    }
}
