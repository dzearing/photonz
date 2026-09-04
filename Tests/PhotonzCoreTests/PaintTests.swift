import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

@Suite("Paint: a color slot that can hold a gradient")
struct PaintTests {

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    // MARK: - What a paint is

    @Test func aPaintStartsFlat() {
        let paint = Paint(hex: "#3366FF")
        #expect(paint.kind == .solid)
        #expect(paint.hex == "#3366FF")
        #expect(paint.isGradient == false)
    }

    @Test func aGradientNeedsTwoStopsBeforeItIsOne() {
        var paint = Paint(hex: "#3366FF")
        paint.kind = .linear
        // The type is set but nothing has seeded the ramp yet: still flat.
        #expect(paint.isGradient == false)
        paint.stops = Paint.seededStops(from: "#3366FF")
        #expect(paint.isGradient)
        #expect(paint.stops.count == 2)
    }

    @Test func seededStopsRunFromTheColorYouAlreadyHad() {
        let stops = Paint.seededStops(from: "#3366FF")
        #expect(stops.count == 2)
        // Your color at one end, a lighter turn of it at the other: what you
        // see first is YOUR color fading, not a stock preset.
        #expect(stops.first?.hex == "#3366FF")
        #expect(stops.first?.position == 0)
        #expect(stops.last?.position == 1)
        #expect(stops.last?.hex != "#3366FF")
    }

    @Test func turningAGradientBackToSolidKeepsTheFlatColor() {
        var paint = Paint(hex: "#3366FF")
        paint.becoming(.linear)
        paint.becoming(.solid)
        #expect(paint.hex == "#3366FF")
        #expect(paint.kind == .solid)
        // The ramp is kept too, so flipping back does not rebuild it.
        #expect(paint.stops.count == 2)
    }

    // MARK: - Reading the ramp

    @Test func stopsAreReadInPositionOrderHoweverTheyWereAdded() {
        var paint = Paint(hex: "#000000")
        paint.kind = .linear
        paint.stops = [GradientStop(hex: "#FFFFFF", position: 0.8),
                       GradientStop(hex: "#000000", position: 0.1)]
        #expect(paint.orderedStops.map(\.position) == [0.1, 0.8])
    }

    @Test func reversingARampMirrorsEveryStop() {
        var paint = Paint(hex: "#000000")
        paint.kind = .linear
        paint.stops = [GradientStop(hex: "#AA0000", position: 0),
                       GradientStop(hex: "#00BB00", position: 0.25),
                       GradientStop(hex: "#0000CC", position: 1)]
        paint.reverseStops()
        #expect(paint.orderedStops.map(\.position) == [0, 0.75, 1])
        #expect(paint.orderedStops.map(\.hex) == ["#0000CC", "#00BB00", "#AA0000"])
    }

    @Test func addingAStopLandsBetweenTheOneYouAreOnAndTheNext() {
        var paint = Paint(hex: "#000000")
        paint.kind = .linear
        paint.stops = [GradientStop(hex: "#000000", position: 0),
                       GradientStop(hex: "#FFFFFF", position: 1)]
        let added = paint.addStop(after: 0)
        #expect(added == 2)
        #expect(paint.stops[2].position == 0.5)
        #expect(paint.stops[2].hex == "#000000")
    }

    @Test func addingAStopPastTheLastOneStaysInsideTheRamp() {
        var paint = Paint(hex: "#000000")
        paint.kind = .linear
        paint.stops = [GradientStop(hex: "#000000", position: 0),
                       GradientStop(hex: "#FFFFFF", position: 0.5)]
        let added = paint.addStop(after: 1)
        #expect(abs(paint.stops[added].position - 0.7) < 0.0001)
        _ = paint.addStop(after: added)
        #expect(paint.stops.allSatisfy { $0.position <= 1 })
    }

    @Test func aGradientRefusesToDropBelowTwoStops() {
        var paint = Paint(hex: "#000000")
        paint.kind = .linear
        paint.stops = Paint.seededStops(from: "#000000")
        let refused = paint.removeStop(at: 0)
        #expect(refused == false)
        #expect(paint.stops.count == 2)
        _ = paint.addStop(after: 0)
        let removed = paint.removeStop(at: 0)
        #expect(removed)
        #expect(paint.stops.count == 2)
    }

    // MARK: - The color at a point along the ramp

    @Test func aFlatPaintIsItsOwnColorEverywhere() {
        let paint = Paint(hex: "#3366FF")
        #expect(paint.color(at: 0)?.hexString == "#3366FF")
        #expect(paint.color(at: 1)?.hexString == "#3366FF")
    }

    @Test func aRampBlendsBetweenItsStops() {
        var paint = Paint(hex: "#000000")
        paint.kind = .linear
        paint.stops = [GradientStop(hex: "#000000", position: 0),
                       GradientStop(hex: "#FFFFFF", position: 1)]
        let middle = paint.color(at: 0.5)
        #expect(middle != nil)
        #expect(abs((middle?.r ?? 0) - 0.5) < 0.01)
    }

    @Test func pastTheEndsARampHoldsItsEndColors() {
        var paint = Paint(hex: "#000000")
        paint.kind = .linear
        paint.stops = [GradientStop(hex: "#000000", position: 0.25),
                       GradientStop(hex: "#FFFFFF", position: 0.75)]
        #expect(paint.color(at: 0)?.hexString == "#000000")
        #expect(paint.color(at: 1)?.hexString == "#FFFFFF")
    }

    // MARK: - Documents written before gradients existed

    @Test func aFlatPaintWritesThePlainHexStringItAlwaysWrote() throws {
        let data = try encoder.encode(Paint(hex: "#FF3B30"))
        #expect(String(decoding: data, as: UTF8.self) == "\"#FF3B30\"")
    }

    @Test func aPlainHexStringReadsBackAsAFlatPaint() throws {
        let paint = try decoder.decode(Paint.self, from: Data("\"#FF3B30\"".utf8))
        #expect(paint.kind == .solid)
        #expect(paint.hex == "#FF3B30")
    }

    @Test func aGradientSurvivesTheRoundTrip() throws {
        var paint = Paint(hex: "#3366FF")
        paint.becoming(.radial)
        paint.angle = 42
        paint.center = CGPoint(x: 0.25, y: 0.75)
        let back = try decoder.decode(Paint.self, from: encoder.encode(paint))
        #expect(back == paint)
        #expect(back.kind == .radial)
        #expect(back.center == CGPoint(x: 0.25, y: 0.75))
    }

    // MARK: - Slots that can only take a flat color

    @Test func onlyFillAndStrokeOfferGradients() {
        #expect(ColorSlot.fill.acceptsGradient)
        #expect(ColorSlot.stroke.acceptsGradient)
        #expect(ColorSlot.text.acceptsGradient == false)
        #expect(ColorSlot.border.acceptsGradient == false)
    }
}

@Suite("Gradient paint on a layer")
struct LayerPaintTests {

    private func box(fill: Paint?) -> Layer {
        var content = AnnotationContent(shape: .rectangle, strokeWidth: 2, colorHex: "#112233",
                                        start: .zero, end: CGPoint(x: 100, y: 80))
        content.fill = fill
        return AnnotationBuilder.layer(content: content, from: .zero, to: CGPoint(x: 100, y: 80))
    }

    @Test func aBoxHandsBackTheGradientItWasPainted() {
        var gradient = Paint(hex: "#3366FF")
        gradient.becoming(.linear)
        let layer = box(fill: gradient)
        #expect(layer.paint(for: .fill)?.isGradient == true)
        #expect(layer.colorHex(for: .fill) == gradient.hex)
    }

    @Test func paintingASlotWithAGradientSticks() {
        var layer = box(fill: Paint(hex: "#FFFFFF"))
        var gradient = Paint(hex: "#3366FF")
        gradient.becoming(.angular)
        layer.setPaint(gradient, for: .fill)
        #expect(layer.annotation?.fill?.kind == .angular)
    }

    @Test func aStrokeTakesAGradientToo() {
        var layer = box(fill: nil)
        var gradient = Paint(hex: "#FF0000")
        gradient.becoming(.linear)
        layer.setPaint(gradient, for: .stroke)
        #expect(layer.paint(for: .stroke)?.isGradient == true)
        // The flat stand-in stays readable for everything that still needs one.
        #expect(layer.colorHex(for: .stroke) == "#FF0000")
    }

    @Test func aSlotThatCannotHoldAGradientKeepsTheFlatColor() {
        var layer = box(fill: nil)
        layer.style.borderWidth = 2
        var gradient = Paint(hex: "#00FF00")
        gradient.becoming(.linear)
        layer.setPaint(gradient, for: .border)
        #expect(layer.paint(for: .border)?.isGradient == false)
        #expect(layer.style.borderColorHex == "#00FF00")
    }

    @Test func aFrameSurfaceTakesAGradient() throws {
        var layer = Layer.frameLayer(name: "Screen", origin: .zero,
                                     size: CGSize(width: 320, height: 200))
        var gradient = Paint(hex: "#101820")
        gradient.becoming(.radial)
        layer.setPaint(gradient, for: .fill)
        #expect(layer.group?.background?.kind == .radial)

        let data = try JSONEncoder().encode(layer)
        let back = try JSONDecoder().decode(Layer.self, from: data)
        #expect(back.group?.background?.kind == .radial)
    }

    @Test func aDocumentWrittenBeforeGradientsOpensUnchanged() throws {
        let layer = box(fill: Paint(hex: "#ABCDEF"))
        let data = try JSONEncoder().encode(layer)
        let json = String(decoding: data, as: UTF8.self)
        #expect(json.contains("\"fillColorHex\":\"#ABCDEF\""))
        let back = try JSONDecoder().decode(Layer.self, from: data)
        #expect(back.annotation?.fillColorHex == "#ABCDEF")
    }
}

@Suite("Painting a selection with a gradient")
struct SelectionPaintTests {

    private func document() -> (PhotonzDocument, [UUID]) {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 400, height: 300))
        let boxes = (0..<2).map { _ -> Layer in
            var content = AnnotationContent(shape: .rectangle, strokeWidth: 2,
                                            colorHex: "#112233", fillColorHex: "#FFFFFF")
            content.start = .zero
            content.end = CGPoint(x: 100, y: 80)
            return AnnotationBuilder.layer(content: content, from: .zero,
                                           to: CGPoint(x: 100, y: 80))
        }
        doc.layers = boxes
        return (doc, boxes.map(\.id))
    }

    private func gradient() -> Paint {
        var paint = Paint(hex: "#3366FF")
        paint.becoming(.linear)
        return paint
    }

    @Test func oneGradientReachesEveryPickedShape() {
        var (doc, ids) = document()
        let painted = doc.setPaint(layerIDs: ids, slot: .fill, paint: gradient())
        #expect(painted == 2)
        #expect(doc.layers.allSatisfy { $0.paint(for: .fill)?.isGradient == true })
    }

    @Test func aRowReadsTheGradientEveryShapeAgreesOn() {
        var (doc, ids) = document()
        doc.setPaint(layerIDs: ids, slot: .fill, paint: gradient())
        #expect(doc.sharedPaint(layerIDs: ids, slot: .fill) == gradient())
    }

    @Test func shapesThatDisagreeShareNothing() {
        var (doc, ids) = document()
        doc.setPaint(layerIDs: [ids[0]], slot: .fill, paint: gradient())
        #expect(doc.sharedPaint(layerIDs: ids, slot: .fill) == nil)
    }
}
