import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// A box, an oval or a line becomes a path with every point on it
/// (`docs/design/vector-paths.md`, "Turn Into Path").
@Suite("Turn Into Path")
struct TurnIntoPathTests {

    // MARK: Helpers

    /// The shape tool's own rectangle, built the way the app builds one: a
    /// layer, so its stroke has already moved into the Effects list the way
    /// `Layer.init` moves every shape's (`OutlineRetirement.swift`).
    private func rectangleLayer(size: CGSize = CGSize(width: 200, height: 120),
                                radius: CGFloat = 0,
                                strokeWidth: CGFloat = 4) -> Layer {
        var shape = AnnotationContent(shape: .rectangle, strokeWidth: strokeWidth,
                                      colorHex: "#FF3B30",
                                      start: .zero, end: CGPoint(x: size.width, y: size.height))
        shape.cornerRadius = radius
        shape.fill = Paint(hex: "#3478F6")
        return Layer(name: "Rectangle", content: .annotation(shape),
                     frame: CGRect(origin: CGPoint(x: 40, y: 30), size: size))
    }

    private func ellipseLayer(size: CGSize = CGSize(width: 160, height: 160)) -> Layer {
        var shape = AnnotationContent(shape: .ellipse, strokeWidth: 4, colorHex: "#FF3B30",
                                      start: .zero, end: CGPoint(x: size.width, y: size.height))
        shape.fill = Paint(hex: "#34C759")
        return Layer(name: "Ellipse", content: .annotation(shape),
                     frame: CGRect(origin: CGPoint(x: 10, y: 10), size: size))
    }

    private func lineLayer() -> Layer {
        let shape = AnnotationContent(shape: .line, strokeWidth: 6, colorHex: "#FF3B30",
                                      start: CGPoint(x: 0, y: 0), end: CGPoint(x: 100, y: 60))
        return AnnotationBuilder.layer(content: shape, from: CGPoint(x: 20, y: 20),
                                       to: CGPoint(x: 120, y: 80))
    }

    /// The highlighter's own mark: a wash of colour, no line round it, laid
    /// over whatever is under it. Built as a LAYER, so the mixing rule that
    /// makes it a highlighter (`Layer.mixingIsFixed`) is in play.
    private func highlightLayer(size: CGSize = CGSize(width: 180, height: 40)) -> Layer {
        let wash = AnnotationContent(shape: .highlight, strokeWidth: 4, colorHex: "#FFD60A",
                                     start: .zero, end: CGPoint(x: size.width, y: size.height))
        return Layer(name: "Highlight", content: .annotation(wash),
                     frame: CGRect(origin: CGPoint(x: 24, y: 64), size: size))
    }

    private func near(_ a: CGFloat, _ b: CGFloat, _ slack: CGFloat = 1e-9) -> Bool {
        abs(a - b) <= slack
    }

    private func near(_ a: CGPoint, _ b: CGPoint, _ slack: CGFloat = 1e-9) -> Bool {
        near(a.x, b.x, slack) && near(a.y, b.y, slack)
    }

    // MARK: - Which layers offer it

    @Test("A box, an oval and a line can each become a path")
    func theThreeShapesConvert() {
        #expect(rectangleLayer().canTurnIntoPath)
        #expect(rectangleLayer(radius: 20).canTurnIntoPath)
        #expect(ellipseLayer().canTurnIntoPath)
        #expect(lineLayer().canTurnIntoPath)
    }

    @Test("So can a highlighter wash, which is a box with mixing on it")
    func aWashConverts() {
        #expect(highlightLayer().canTurnIntoPath)
        #expect(highlightLayer().turnedIntoPath() != nil)
    }

    @Test("An arrow does not: its head is how it is drawn, not part of an outline")
    func arrowRefuses() {
        let arrow = AnnotationContent(shape: .arrow, strokeWidth: 4, colorHex: "#FF3B30",
                                      start: .zero, end: CGPoint(x: 100, y: 0))
        let arrowLayer = Layer(name: "Arrow", content: .annotation(arrow),
                               frame: CGRect(x: 0, y: 0, width: 100, height: 20))
        #expect(!arrowLayer.canTurnIntoPath)
        #expect(arrowLayer.turnedIntoPath() == nil)
    }

    @Test("Nor does a picture, a label, a group or a path that already is one")
    func everythingElseRefuses() {
        let picture = Layer(name: "Shot", content: .image(ImageRef(pixelSize: CGSize(width: 10, height: 10))),
                            frame: CGRect(x: 0, y: 0, width: 10, height: 10))
        #expect(!picture.canTurnIntoPath)
        let words = Layer(name: "Words", content: .text(TextContent(string: "hi")),
                          frame: CGRect(x: 0, y: 0, width: 10, height: 10))
        #expect(!words.canTurnIntoPath)
        let group = Layer(name: "Group", content: .group(GroupContent(children: [])),
                          frame: CGRect(x: 0, y: 0, width: 10, height: 10))
        #expect(!group.canTurnIntoPath)
        let already = PathBuilder.layer(PathContent(anchors: [
            PathAnchor(point: .zero), PathAnchor(point: CGPoint(x: 10, y: 10))
        ]), at: .zero)
        #expect(!already.canTurnIntoPath)
    }

    // MARK: - A square box

    @Test("A square box becomes four corners with no handles on them")
    func squareBoxBecomesFourCorners() throws {
        let converted = try #require(rectangleLayer().turnedIntoPath())
        let path = try #require(converted.path)
        #expect(path.isClosed)
        #expect(path.anchors.count == 4)
        #expect(path.anchors.allSatisfy { $0.handleIn == nil && $0.handleOut == nil })
        #expect(path.anchors.allSatisfy { $0.kind == .corner })
        // Clockwise from the top left, in the layer's own top-left space.
        #expect(near(path.anchors[0].point, CGPoint(x: 0, y: 0)))
        #expect(near(path.anchors[1].point, CGPoint(x: 200, y: 0)))
        #expect(near(path.anchors[2].point, CGPoint(x: 200, y: 120)))
        #expect(near(path.anchors[3].point, CGPoint(x: 0, y: 120)))
    }

    @Test("...and keeps the box it had, so nothing moves on the canvas")
    func boxIsUnchanged() throws {
        let before = rectangleLayer()
        let after = try #require(before.turnedIntoPath())
        #expect(after.frame == before.frame)
        #expect(after.id == before.id)
        #expect(after.name == before.name)
        #expect(after.style == before.style)
    }

    // MARK: - A rounded box

    @Test("A rounded box becomes eight points, the four curved ones half smooth")
    func roundedBoxBecomesEightPoints() throws {
        let converted = try #require(rectangleLayer(radius: 20).turnedIntoPath())
        let path = try #require(converted.path)
        #expect(path.anchors.count == 8)
        // Four arcs, so four runs with a bulge and four dead straight ones.
        let curved = path.segments.filter { !$0.isStraight }
        #expect(curved.count == 4)
        // Each arc's two ends are straight on the far side: a point a straight
        // edge arrives at and a curve leaves from.
        #expect(path.anchors.allSatisfy { $0.isHalfSmooth })
    }

    @Test("The curve is a real quarter circle: handles at 0.5523 of the radius")
    func roundedCornerUsesTheStandardConstant() throws {
        let converted = try #require(rectangleLayer(radius: 20).turnedIntoPath())
        let path = try #require(converted.path)
        // The top-left corner: the outline arrives at (0, 20) going up and
        // leaves (20, 0) going right, so both handles are 0.5523 x 20 long.
        let lever = ShapeToPath.circleHandle * 20
        let top = try #require(path.anchors.first { near($0.point, CGPoint(x: 20, y: 0)) })
        let left = try #require(path.anchors.first { near($0.point, CGPoint(x: 0, y: 20)) })
        let leaving = try #require(left.handleOut)
        let arriving = try #require(top.handleIn)
        #expect(near(leaving.x, 0))
        #expect(near(leaving.y, -lever))
        #expect(near(arriving.x, -lever))
        #expect(near(arriving.y, 0))
    }

    @Test("A corner rounded past half the box is a capsule, not an overlap")
    func radiusIsClampedLikeTheShapeIs() throws {
        // 200 x 120 with a 400 radius: the rasterizer clamps to a capsule, so
        // the path has to as well or the outline would cross itself.
        let converted = try #require(rectangleLayer(radius: 400).turnedIntoPath())
        let path = try #require(converted.path)
        #expect(path.bounds.width == 200)
        #expect(path.bounds.height == 120)
        // Every anchor is on the box, never past it.
        for anchor in path.anchors {
            #expect(anchor.point.x >= -1e-9 && anchor.point.x <= 200 + 1e-9)
            #expect(anchor.point.y >= -1e-9 && anchor.point.y <= 120 + 1e-9)
        }
    }

    @Test("Corners rounded one at a time each keep their own radius")
    func perCornerRadiiSurvive() throws {
        var shape = AnnotationContent(shape: .rectangle, strokeWidth: 0, colorHex: "#FF3B30",
                                      start: .zero, end: CGPoint(x: 200, y: 120))
        shape.cornerRadii = CornerRadii(topLeft: 30, topRight: 0, bottomRight: 12, bottomLeft: 0)
        let layer = Layer(name: "Card", content: .annotation(shape),
                          frame: CGRect(x: 0, y: 0, width: 200, height: 120))
        let turned = try #require(layer.turnedIntoPath())
        let path = try #require(turned.path)
        // Two square corners are one point each, two round ones are two.
        #expect(path.anchors.count == 6)
        #expect(path.segments.filter { !$0.isStraight }.count == 2)
    }

    // MARK: - An oval

    @Test("An oval becomes four smooth points on its compass points")
    func ovalBecomesFourSmoothPoints() throws {
        let converted = try #require(ellipseLayer(size: CGSize(width: 200, height: 100))
            .turnedIntoPath())
        let path = try #require(converted.path)
        #expect(path.isClosed)
        #expect(path.anchors.count == 4)
        #expect(path.anchors.allSatisfy { $0.kind == .smooth })
        #expect(near(path.anchors[0].point, CGPoint(x: 100, y: 0)))
        #expect(near(path.anchors[1].point, CGPoint(x: 200, y: 50)))
        #expect(near(path.anchors[2].point, CGPoint(x: 100, y: 100)))
        #expect(near(path.anchors[3].point, CGPoint(x: 0, y: 50)))
    }

    @Test("Its handles take the constant on each axis separately, so an oval is an oval")
    func ovalHandlesFollowTheirOwnAxis() throws {
        let converted = try #require(ellipseLayer(size: CGSize(width: 200, height: 100))
            .turnedIntoPath())
        let path = try #require(converted.path)
        let acrossLever = ShapeToPath.circleHandle * 100      // half the width
        let downLever = ShapeToPath.circleHandle * 50         // half the height
        // The top point travels across, so its levers are the WIDTH's.
        let top = try #require(path.anchors[0].handleOut)
        #expect(near(top.x, acrossLever))
        #expect(near(top.y, 0))
        // The right-hand point travels down, so its levers are the HEIGHT's.
        let right = try #require(path.anchors[1].handleOut)
        #expect(near(right.x, 0))
        #expect(near(right.y, downLever))
    }

    @Test("A circle stays a circle: the outline is the same distance out all the way round")
    func circleStaysACircle() throws {
        let converted = try #require(ellipseLayer(size: CGSize(width: 160, height: 160))
            .turnedIntoPath())
        let path = try #require(converted.path)
        let centre = CGPoint(x: 80, y: 80)
        // Sampled all the way round rather than at the four points, which any
        // approximation would pass.
        var worst: CGFloat = 0
        for point in path.flattened(steps: 64) {
            worst = max(worst, abs(hypot(point.x - centre.x, point.y - centre.y) - 80))
        }
        // The standard cubic approximation is out by about 0.027% of the
        // radius at its worst, which on 80 points is 0.022.
        #expect(worst < 0.03)
    }

    // MARK: - A line

    @Test("A line becomes an open path of two points")
    func lineBecomesTwoPoints() throws {
        let before = lineLayer()
        let converted = try #require(before.turnedIntoPath())
        let path = try #require(converted.path)
        #expect(!path.isClosed)
        #expect(path.anchors.count == 2)
        #expect(path.fill == nil)
        #expect(path.strokeWidth == 6)
        #expect(path.colorHex == "#FF3B30")
        // Its two ends land exactly where the line's did, in the document.
        let was = try #require(before.annotation)
        let wasStart = CGPoint(x: before.frame.minX + was.start.x,
                               y: before.frame.minY + was.start.y)
        let nowStart = CGPoint(x: converted.frame.minX + path.anchors[0].point.x,
                               y: converted.frame.minY + path.anchors[0].point.y)
        #expect(near(wasStart, nowStart, 1e-6))
    }

    // MARK: - What the shape was wearing

    @Test("The fill comes across, paint and all")
    func fillSurvives() throws {
        var shape = AnnotationContent(shape: .rectangle, strokeWidth: 0, colorHex: "#FF3B30",
                                      start: .zero, end: CGPoint(x: 100, y: 100))
        shape.fill = Paint(hex: "#FF0000", kind: .linear,
                           stops: [GradientStop(hex: "#FF0000", position: 0),
                                   GradientStop(hex: "#0000FF", position: 1)])
        let layer = Layer(name: "Box", content: .annotation(shape),
                          frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        let turned = try #require(layer.turnedIntoPath())
        let path = try #require(turned.path)
        #expect(path.fill == shape.fill)
    }

    @Test("A box with no fill converts to a path with no fill")
    func noFillStaysNoFill() throws {
        var shape = AnnotationContent(shape: .rectangle, strokeWidth: 0, colorHex: "#FF3B30",
                                      start: .zero, end: CGPoint(x: 100, y: 100))
        shape.fill = nil
        let layer = Layer(name: "Box", content: .annotation(shape),
                          frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        let turned = try #require(layer.turnedIntoPath())
        let path = try #require(turned.path)
        #expect(path.fill == nil)
    }

    @Test("The shape's edge is a Border in Effects, and it stays one")
    func borderEffectsAreLeftAlone() throws {
        let before = rectangleLayer(radius: 16, strokeWidth: 4)
        // `Layer.init` already moved the stroke into Effects, so the box wears
        // one border and no stroke of its own (`OutlineRetirement.swift`).
        #expect(before.annotation?.strokeWidth == 0)
        #expect(before.style.paintedBorders.count == 1)
        let after = try #require(before.turnedIntoPath())
        #expect(after.style.effects == before.style.effects)
        // The path itself has no line: the ring is still the Border, so the
        // edge is not drawn twice.
        #expect(after.path?.strokeWidth == 0)
    }

    @Test("Every other effect and the layer's own transform come across untouched")
    func effectsAndTransformSurvive() throws {
        var layer = rectangleLayer(radius: 12)
        layer.style.effects.append(.shadow(ShadowStyle()))
        layer.style.opacity = 0.4
        layer.style.blurRadius = 3
        layer.transform = LayerTransform(rotation: .pi / 8)
        let after = try #require(layer.turnedIntoPath())
        #expect(after.style == layer.style)
        #expect(after.transform == layer.transform)
    }

    // MARK: - One step, and the way back

    @Test("It is one undo step, and undo brings back a real rectangle")
    func oneUndoStepBackToARectangle() throws {
        var document = PhotonzDocument(canvasSize: CGSize(width: 400, height: 300))
        let layer = rectangleLayer(radius: 18)
        document.addLayer(layer)
        var history = History(document: document)

        _ = history.perform { $0.turnLayerIntoPath(id: layer.id) }
        #expect(history.current.layer(id: layer.id)?.path != nil)

        history.undo()
        let back = try #require(history.current.layer(id: layer.id))
        #expect(back.path == nil)
        // Not a path pretending to be a box: a real rectangle, with the corner
        // radius control it had.
        #expect(back.annotation?.shape == .rectangle)
        #expect(back.annotation?.cornerRadius == 18)
        #expect(back.canTurnIntoPath)
    }

    @Test("Turning an oval into a path twice does nothing the second time")
    func convertingIsIdempotent() throws {
        var document = PhotonzDocument(canvasSize: CGSize(width: 400, height: 300))
        let layer = ellipseLayer()
        document.addLayer(layer)
        document.turnLayerIntoPath(id: layer.id)
        let once = try #require(document.layer(id: layer.id))
        document.turnLayerIntoPath(id: layer.id)
        #expect(document.layer(id: layer.id) == once)
    }

    // MARK: - What it is afterwards

    @Test("Every point is editable the moment it converts")
    func pointsAreEditableImmediately() throws {
        let converted = try #require(rectangleLayer(radius: 20).turnedIntoPath())
        var path = try #require(converted.path)
        let count = path.anchors.count

        // Move one.
        let was = path.anchors[0].point
        path.moveAnchors([0], by: CGPoint(x: 5, y: -5))
        #expect(path.anchors[0].point != was)
        // Turn a corner into a bend and back.
        let smoothed = path.toggleAnchorKind(at: 0)
        #expect(smoothed == .smooth)
        let cornered = path.toggleAnchorKind(at: 0)
        #expect(cornered == .corner)
        // Add one on a run, and take one out.
        let added = path.insertAnchor(onSegment: 0, at: 0.5)
        #expect(added == 1)
        #expect(path.anchors.count == count + 1)
        let removed = path.removeAnchors([1])
        #expect(removed)
        #expect(path.anchors.count == count)
        // And a press finds them, which is what the reshaping tools ask.
        let target = path.editTarget(at: path.anchors[2].point, zoom: 1, handlesShowing: [])
        #expect(target == .anchor(2))
    }

    @Test("A path has points rather than corners, so the Corner Radius row goes")
    func theCornerRadiusRowGoes() throws {
        var document = PhotonzDocument(canvasSize: CGSize(width: 400, height: 300))
        let layer = rectangleLayer(radius: 18)
        document.addLayer(layer)
        // Before: a rectangle rounds its own outline, so the row is there.
        #expect(document.cornerRadiusSelection(layerIDs: [layer.id], cornersOnly: true).count == 1)
        document.turnLayerIntoPath(id: layer.id)
        // After: nothing to round. Rounding a path through the style would lay
        // a rounded rectangle over it and cut its outline off at the box.
        let turned = try #require(document.layer(id: layer.id))
        #expect(!turned.hasCorners)
        #expect(document.cornerRadiusSelection(layerIDs: [layer.id], cornersOnly: true).isEmpty)
    }

    // MARK: - A highlighter wash

    @Test("A wash becomes a closed box of four corners in its own colour")
    func washBecomesABox() throws {
        let layer = highlightLayer()
        let converted = try #require(layer.turnedIntoPath())
        let path = try #require(converted.path)
        #expect(path.isClosed)
        #expect(path.anchors.count == 4)
        // No line round it at any width: a wash is ink and nothing else, so a
        // path of one that carried a stroke would grow an edge it never had.
        #expect(path.strokeWidth == 0)
        // The inside is the wash's own paint, which is what the highlighter
        // actually fills with.
        #expect(path.fill?.hex == "#FFD60A")
        #expect(path.paintsAnInside)
    }

    @Test("It keeps mixing with what is under it, which is the whole point of a highlighter")
    func theMixingSurvives() throws {
        let layer = highlightLayer()
        #expect(layer.mixingIsFixed)
        #expect(layer.effectiveBlendMode == .multiply)

        let converted = try #require(layer.turnedIntoPath())
        // It is no longer a highlight mark, so nothing FORCES the mixing any
        // more. It has to be carried into the style, or the wash would go flat
        // and paint straight over the words the instant it converted.
        #expect(!converted.mixingIsFixed)
        #expect(converted.style.blendMode == .multiply)
        #expect(converted.effectiveBlendMode == .multiply)
    }

    @Test("...and keeps the box it was drawn in, so the wash does not move")
    func theWashStaysPut() throws {
        let layer = highlightLayer()
        let converted = try #require(layer.turnedIntoPath())
        #expect(near(converted.frame.origin, layer.frame.origin))
        #expect(near(converted.frame.width, layer.frame.width))
        #expect(near(converted.frame.height, layer.frame.height))
    }

    @Test("A shape that never mixed does not come out mixing")
    func anOrdinaryBoxIsNotToldToMix() throws {
        let converted = try #require(rectangleLayer().turnedIntoPath())
        #expect(converted.style.blendMode == .normal)
    }

    // MARK: - The question it asks first

    @Test("The question names the layer and says what is lost")
    func theQuestionReads() throws {
        let prompt = try #require(TurnIntoPathPrompt(layer: rectangleLayer(radius: 20)))
        #expect(prompt.title.contains("Rectangle"))
        #expect(prompt.message.lowercased().contains("corner"))
        #expect(prompt.confirm == "Turn Into Path")
        #expect(TurnIntoPathPrompt.menuItem == "Turn Into Path\u{2026}")
        // No em dashes in anything a person reads.
        #expect(!prompt.message.contains("\u{2014}"))
        #expect(!prompt.title.contains("\u{2014}"))
    }

    @Test("An oval's question does not talk about corners it never had")
    func theQuestionFitsTheShape() throws {
        let prompt = try #require(TurnIntoPathPrompt(layer: ellipseLayer()))
        #expect(!prompt.message.lowercased().contains("corner"))
        #expect(prompt.title.contains("Ellipse"))
    }

    @Test("A wash's question says what happens to its mixing, not to corners")
    func theWashQuestionReads() throws {
        let prompt = try #require(TurnIntoPathPrompt(layer: highlightLayer()))
        #expect(prompt.title.contains("Highlight"))
        #expect(!prompt.message.lowercased().contains("corner"))
        #expect(prompt.message.lowercased().contains("mix"))
        #expect(!prompt.message.contains("\u{2014}"))
    }

    @Test("There is no question over a layer that cannot convert")
    func noQuestionWhereThereIsNothingToTurn() {
        let picture = Layer(name: "Shot", content: .image(ImageRef(pixelSize: CGSize(width: 10, height: 10))),
                            frame: CGRect(x: 0, y: 0, width: 10, height: 10))
        #expect(TurnIntoPathPrompt(layer: picture) == nil)
    }

    @Test("It can be silenced, and turned back on, like every other question")
    func theQuestionCanBeSilenced() {
        let store = SilencedQuestions(defaults: InMemorySilenceDefaults())
        #expect(!store.isSilenced(.turnIntoPath))
        store.silence(.turnIntoPath)
        #expect(store.isSilenced(.turnIntoPath))
        #expect(store.silenced.contains(.turnIntoPath))
        store.askAgain(.turnIntoPath)
        #expect(!store.isSilenced(.turnIntoPath))
        // And it is in the roll call, so the list can show it.
        #expect(SilenceableQuestion.all.contains(.turnIntoPath))
    }
}
