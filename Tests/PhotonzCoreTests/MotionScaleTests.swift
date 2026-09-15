import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// A layer told to grow GROWS, and everything on it grows together.
///
/// Scale used to set `frame` and nothing else, so the box round the drawing
/// got bigger and the drawing inside it stayed exactly the size it was: a pen
/// path told to go to 200% was drawn at 100%, and so was a box. The fix is a
/// real magnification — the shape, the line round it, the words, the corner
/// and the shadow all multiplied — which is what `scale()` in an exported SVG
/// does, so the canvas and the file can agree.
@Suite("Scale magnifies the drawing, not just its box")
struct MotionScaleTests {

    private func square(strokeWidth: CGFloat = 0) -> Layer {
        let content = PathContent(anchors: [PathAnchor(point: .zero),
                                            PathAnchor(point: CGPoint(x: 40, y: 0)),
                                            PathAnchor(point: CGPoint(x: 40, y: 40)),
                                            PathAnchor(point: CGPoint(x: 0, y: 40))],
                                  isClosed: true,
                                  paint: Paint(hex: "#FF0000"),
                                  strokeWidth: strokeWidth,
                                  fill: Paint(hex: "#FF0000"))
        return PathBuilder.layer(content, at: CGPoint(x: 30, y: 30))
    }

    private func box(strokeWidth: CGFloat = 0) -> Layer {
        Layer(name: "Box",
              content: .annotation(AnnotationContent(shape: .rectangle,
                                                     strokeWidth: strokeWidth,
                                                     colorHex: "#FF0000",
                                                     start: .zero,
                                                     end: CGPoint(x: 40, y: 40),
                                                     fillColorHex: "#FF0000")),
              frame: CGRect(x: 30, y: 30, width: 40, height: 40))
    }

    private func scaled(_ layer: Layer, toPercent percent: Double) -> Layer {
        var moving = layer
        moving.motions = [LayerMotion(property: .scale,
                                      from: .number(percent), to: .number(percent),
                                      timing: MotionTiming(startMS: 0, durationMS: 1000),
                                      curve: .linear, repeats: .forever)]
        return moving.moved(toMotionTimeMS: 0, cycleMS: 1000)
    }

    // MARK: The drawing itself

    /// THE TEST: a pen path told to double is drawn twice as big. The anchors
    /// have to move, or the rasterizer paints a 40pt shape into an 80pt box.
    @Test func aPathToldToDoubleIsDrawnTwiceAsBig() throws {
        let grown = scaled(square(), toPercent: 200)
        #expect(grown.frame.width == 80)
        #expect(grown.frame.height == 80)
        let anchors = try #require(grown.path).anchors.map(\.point)
        #expect(anchors.contains(CGPoint(x: 80, y: 80)))
        #expect(try #require(grown.path).bounds.size == CGSize(width: 80, height: 80))
    }

    /// ...and a rectangle too, by exactly the amount the row says rather than
    /// some fraction of it.
    @Test func aBoxToldToDoubleIsDrawnTwiceAsBig() throws {
        let grown = scaled(box(), toPercent: 200)
        #expect(grown.frame.width == 80)
        #expect(grown.frame.height == 80)
        let drawn = try #require(grown.annotation)
        #expect(abs(drawn.end.x - drawn.start.x) == 80)
        #expect(abs(drawn.end.y - drawn.start.y) == 80)
    }

    /// Growing happens about the MIDDLE of the box, the same pivot the export
    /// writes, so a shape swells in place instead of walking off to the right.
    @Test func itGrowsAboutTheMiddleOfTheBox() {
        let middleBefore = CGPoint(x: square().frame.midX, y: square().frame.midY)
        for percent in [50.0, 200.0, 325.0] {
            let grown = scaled(square(), toPercent: percent)
            #expect(abs(grown.frame.midX - middleBefore.x) < 0.001)
            #expect(abs(grown.frame.midY - middleBefore.y) < 0.001)
        }
    }

    /// Shrinking is the same sum the other way.
    @Test func halfSizeIsHalfTheDrawing() throws {
        let shrunk = scaled(square(), toPercent: 50)
        #expect(shrunk.frame.width == 20)
        #expect(try #require(shrunk.path).bounds.size == CGSize(width: 20, height: 20))
    }

    // MARK: Everything grows together

    /// The line round a shape is part of the drawing, so it thickens with it.
    /// An SVG `scale()` multiplies stroke-width, and a 4pt outline left at 4pt
    /// on a doubled icon reads as a different icon.
    @Test func theLineRoundItThickensWithIt() throws {
        let grown = scaled(square(strokeWidth: 4), toPercent: 200)
        #expect(try #require(grown.path).strokeWidth == 8)
    }

    /// So does the corner it is rounded with, and the shadow under it.
    @Test func theCornerAndTheShadowGrowWithIt() {
        var layer = box()
        layer.style.cornerRadii = CornerRadii(6)
        layer.style.borderWidth = 2
        let grown = scaled(layer, toPercent: 200)
        #expect(grown.style.cornerRadii.topLeft == 12)
        #expect(grown.style.borderWidth == 4)
    }

    /// And the words: type is measured in points, so doubling a label without
    /// doubling its type would give a box twice as big with the same small
    /// words rattling round inside it.
    @Test func theWordsGrowWithIt() throws {
        var label = Layer(name: "Label",
                          content: .text(TextContent(string: "Hi", fontSize: 20)),
                          frame: CGRect(x: 0, y: 0, width: 60, height: 24))
        label.motions = []
        let grown = scaled(label, toPercent: 200)
        #expect(try #require(grown.text).fontSize == 40)
    }

    // MARK: Groups

    /// A group magnifies whole: every child moves outward from the middle and
    /// grows by the same amount, so the drawing keeps its shape.
    @Test func aGroupMagnifiesWhole() throws {
        var child = square()
        child.frame = CGRect(x: 0, y: 0, width: 40, height: 40)
        var other = square()
        other.frame = CGRect(x: 60, y: 0, width: 40, height: 40)
        let group = Layer(name: "Icon",
                          content: .group(GroupContent(children: [child, other])),
                          frame: CGRect(x: 0, y: 0, width: 100, height: 40))
        let grown = scaled(group, toPercent: 200)
        let children = try #require(grown.group).children
        #expect(children[0].frame.width == 80)
        #expect(children[1].frame.origin.x == 120)
        #expect(children[1].frame.width == 80)
    }

    // MARK: Nothing is baked in

    /// Asking for a moment never changes the stored layer: the shape you can
    /// still drag is the shape you drew, exactly as with every other motion.
    @Test func theStoredLayerNeverChanges() {
        let layer = square()
        let before = layer
        _ = scaled(layer, toPercent: 300)
        #expect(layer == before)
    }

    /// Nought percent is gone, not full size. It used to collapse the frame,
    /// and it still has to.
    @Test func noughtPercentIsGone() {
        let gone = scaled(square(), toPercent: 0)
        #expect(gone.frame.width == 0)
        #expect(gone.frame.height == 0)
    }

    /// A hundred percent is the layer untouched, to the number.
    @Test func aHundredPercentChangesNothing() {
        let drawn = square(strokeWidth: 4)
        var expected = drawn
        let same = scaled(drawn, toPercent: 100)
        expected.motions = same.motions
        #expect(same == expected)
    }

    // MARK: The canvas and the file agree

    /// The exported file grows the layer with `scale(f f)` about the middle of
    /// its box, so the canvas has to mean the same thing by the same number or
    /// a grown icon in a browser is a different size from the one in the app.
    /// This pins the two to each other at four moments of the lap.
    @Test func theCanvasGrowsByExactlyWhatTheFileSays() throws {
        var drawn = Layer(name: "Bell",
                          content: .path(SVGMotionExportTests.square(24)),
                          frame: CGRect(x: 8, y: 10, width: 24, height: 24))
        drawn.motions = [LayerMotion(property: .scale, from: .number(100), to: .number(250),
                                     timing: MotionTiming(startMS: 0, durationMS: 1000),
                                     curve: .linear, repeats: .forever)]
        let document = PhotonzDocument(canvasSize: CGSize(width: 48, height: 48),
                                       layers: [drawn])
        let middle = CGPoint(x: drawn.frame.midX, y: drawn.frame.midY)
        for ms in [0, 200, 600, 1000] {
            let onCanvas = try #require(document.moved(toMotionTimeMS: ms).layer(id: drawn.id))
            // What the file would write at this moment, read off the same
            // motion the file reads it off.
            let percent: Double
            if case let .number(value) = drawn.motions![0].value(atMS: ms, cycleMS: 1000) {
                percent = value
            } else {
                percent = .nan
            }
            let inTheFile = CGFloat(percent) / 100
            #expect(abs(onCanvas.frame.width / drawn.frame.width - inTheFile) < 0.001,
                    "at \(ms)ms the canvas grew by \(onCanvas.frame.width / drawn.frame.width), the file says \(inTheFile)")
            // ...and about the same point the file steps out to.
            #expect(abs(onCanvas.frame.midX - middle.x) < 0.001)
            #expect(abs(onCanvas.frame.midY - middle.y) < 0.001)
        }
    }

    /// A shape told to double AND to thicken its line ends up with the line
    /// multiplied, because the growth wraps the line the same way it does in
    /// the exported file. Which row was added first has no say in it.
    @Test func growingMultipliesALineThatIsMovingToo() throws {
        let grow = LayerMotion(property: .scale, from: .number(200), to: .number(200),
                               timing: MotionTiming(startMS: 0, durationMS: 1000),
                               curve: .linear, repeats: .forever)
        let thicken = LayerMotion(property: .strokeWidth, from: .number(3), to: .number(3),
                                  timing: MotionTiming(startMS: 0, durationMS: 1000),
                                  curve: .linear, repeats: .forever)
        for rows in [[grow, thicken], [thicken, grow]] {
            var layer = square(strokeWidth: 4)
            layer.motions = rows
            let moved = layer.moved(toMotionTimeMS: 0, cycleMS: 1000)
            #expect(try #require(moved.path).strokeWidth == 6,
                    "3pt of line on a shape drawn at twice the size is 6pt of line")
        }
    }
}
