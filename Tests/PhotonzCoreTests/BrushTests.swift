import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// The Brush's model (`docs/design/brushes.md`, decisions 1, 2, 4 and 7): the
/// seven media and their settings, a stroke as data, the paint layer that holds
/// strokes, where a stroke's dabs go, and where a stroke lands in the document.
@Suite("Brush")
struct BrushTests {

    // MARK: - The tool

    @Test("B picks the Brush, and no other tool answers to B")
    func key() {
        #expect(Tool.brush.shortcutKey(handOnBar: true) == "b")
        #expect(Tool.brush.shortcutKey(handOnBar: false) == "b")
        #expect(Tool.allCases.filter { $0.shortcutKey(handOnBar: true) == "b" } == [.brush])
    }

    @Test("The Brush makes layers, paints with its own colour, and owns its clicks")
    func toolFacts() {
        #expect(Tool.brush.createsLayers)
        #expect(Tool.brush.paints)
        #expect(Tool.brush.colorControl == .toolColor)
        #expect(Tool.brush.annotationShape == nil)
        #expect(!Tool.brush.doubleClickOnEmptyCanvasZoomsWindow)
        // The picked layer is where the strokes go, the way Photoshop paints
        // on the current layer, so picking the Brush up keeps it.
        #expect(Tool.brush.preservesLayerSelection)
    }

    // MARK: - What the brush is armed with

    @Test("The brush keeps its own colour and size, apart from the Pen's, across a relaunch")
    func armed() throws {
        var styles = AnnotationStyles()
        #expect(styles.colorHex(for: .brush) == AnnotationStyles.defaultBrushColorHex)
        #expect(styles.strokeWidth(for: .brush) == CGFloat(BrushSettings(medium: .charcoal).size))
        #expect(Tool.brush.usesStrokeWidth)
        styles.setColorHex("#0A84FF", for: .brush)
        styles.setStrokeWidth(30, for: .brush)
        #expect(styles.colorHex(for: .brush) == "#0A84FF")
        #expect(styles.armedBrush.size == 30)
        #expect(styles.colorHex(for: .pen) != "#0A84FF")
        let back = try JSONDecoder().decode(AnnotationStyles.self, from: JSONEncoder().encode(styles))
        #expect(back.colorHex(for: .brush) == "#0A84FF")
        #expect(back.armedBrush.size == 30)
    }

    // MARK: - Media and settings

    @Test("Eight media, each with Size, Opacity and at least two settings of its own")
    func media() {
        #expect(BrushMedium.allCases.count == 8)
        for medium in BrushMedium.allCases {
            let ids = medium.settings.map(\.id)
            #expect(ids.count >= 4, "\(medium) has \(ids)")
            #expect(ids.prefix(2) == ["size", "opacity"])
            #expect(Set(ids).count == ids.count)
            #expect(!medium.title.isEmpty)
            for spec in medium.settings {
                #expect(spec.range.contains(spec.defaultValue), "\(medium).\(spec.id)")
                #expect(!spec.name.isEmpty)
            }
        }
        #expect(BrushMedium.charcoal.settings.map(\.id).suffix(2) == ["grain", "smudge"])
        #expect(BrushMedium.marker.settings.map(\.id).suffix(2) == ["tip", "flow"])
        #expect(BrushMedium.watercolour.settings.map(\.id).suffix(2) == ["wetness", "bleed"])
        #expect(BrushMedium.oil.settings.map(\.id).suffix(2) == ["load", "smear"])
        #expect(BrushMedium.airbrush.settings.map(\.id).suffix(2) == ["flow", "softness"])
        #expect(BrushMedium.crayon.settings.map(\.id).suffix(2) == ["grain", "wax"])
        #expect(BrushMedium.chalk.settings.map(\.id).suffix(2) == ["grain", "smudge"])
        #expect(BrushMedium.pencil.settings.map(\.id).dropFirst(2) == ["hardness", "grain", "tilt"])
    }

    @Test("A marker's Tip is a choice, not a number")
    func markerTipIsAChoice() {
        let tip = BrushMedium.marker.settings.first { $0.id == "tip" }
        #expect(tip?.options == ["Round", "Chisel"])
        #expect(BrushMedium.charcoal.settings.allSatisfy { $0.options == nil })
    }

    @Test("Settings start at each medium's defaults and are clamped to its ranges")
    func settingsClamp() {
        var settings = BrushSettings(medium: .charcoal)
        for spec in BrushMedium.charcoal.settings {
            #expect(settings.value(spec.id) == spec.defaultValue)
        }
        settings.set("size", to: 100_000)
        #expect(settings.size == BrushMedium.charcoal.settings[0].range.upperBound)
        settings.set("opacity", to: -5)
        #expect(settings.opacity == BrushMedium.charcoal.settings[1].range.lowerBound)
        // A setting the medium does not have is ignored rather than stored.
        settings.set("wetness", to: 50)
        #expect(settings.values["wetness"] == nil)
        // Values given at birth are clamped too, and unknown ones dropped.
        let made = BrushSettings(medium: .marker, values: ["tip": 7, "bleed": 3])
        #expect(made.value("tip") == 1)
        #expect(made.values["bleed"] == nil)
    }

    @Test("Switching medium keeps Size and Opacity and takes the new medium's own defaults")
    func switchingMedium() {
        var settings = BrushSettings(medium: .charcoal)
        settings.set("size", to: 40)
        settings.set("opacity", to: 60)
        let wet = settings.switched(to: .watercolour)
        #expect(wet.medium == .watercolour)
        #expect(wet.size == 40)
        #expect(wet.opacity == 60)
        #expect(wet.value("wetness") == BrushMedium.watercolour.settings[2].defaultValue)
        #expect(wet.values["grain"] == nil)
    }

    // MARK: - Strokes and paint layers as data

    private func stroke(_ points: [CGPoint], size: Double = 10, seed: UInt32 = 7) -> BrushStroke {
        var settings = BrushSettings(medium: .charcoal)
        settings.set("size", to: size)
        return BrushStroke(samples: points.enumerated().map { StrokeSample(point: $1, ms: Double($0) * 8) },
                           settings: settings, colorHex: "#112233", seed: seed)
    }

    @Test("A paint layer survives a save and reopen exactly")
    func codableRoundTrip() throws {
        var sample = StrokeSample(point: CGPoint(x: 3, y: 4), pressure: 0.5, tilt: CGPoint(x: 0.1, y: -0.2), ms: 12)
        sample.ms = 12.5
        let one = BrushStroke(samples: [sample, StrokeSample(point: CGPoint(x: 9, y: 9), ms: 20)],
                              settings: BrushSettings(medium: .oil), colorHex: "#FF0000", seed: 42)
        let layer = Layer(name: "Paint", content: .paint(PaintContent(strokes: [one, stroke([.zero, CGPoint(x: 5, y: 0)])])),
                          frame: CGRect(x: 0, y: 0, width: 100, height: 80))
        let data = try JSONEncoder().encode(layer)
        let back = try JSONDecoder().decode(Layer.self, from: data)
        #expect(back == layer)
        #expect(back.paint?.strokes.count == 2)
        #expect(back.paint?.strokes[0].samples[0].pressure == 0.5)
        #expect(back.paint?.strokes[0].samples[1].pressure == nil)
    }

    @Test("A stroke moved into another space moves every sample and nothing else")
    func translated() {
        let moved = stroke([CGPoint(x: 10, y: 10), CGPoint(x: 20, y: 30)]).offsetBy(dx: -5, dy: 2)
        #expect(moved.samples.map(\.point) == [CGPoint(x: 5, y: 12), CGPoint(x: 15, y: 32)])
        #expect(moved.seed == 7)
    }

    @Test("A stroke's bounds reach out by half its tip")
    func bounds() {
        let box = stroke([CGPoint(x: 10, y: 10), CGPoint(x: 30, y: 20)], size: 8).bounds
        #expect(box == CGRect(x: 6, y: 6, width: 28, height: 18))
    }

    // MARK: - Where the dabs go

    @Test("Dabs are spaced evenly along the stroke at a fraction of the tip")
    func spacing() {
        let dabs = BrushPlacement.dabs(for: stroke([CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0)], size: 20))
        let gap = BrushPlacement.spacing(forDiameter: 20)
        #expect(gap > 0 && gap <= 20 * 0.25)
        #expect(dabs.first?.center == CGPoint(x: 0, y: 0))
        // Every gap but the last, which ends on the stroke's own end.
        for (a, b) in zip(dabs.dropLast(), dabs.dropFirst().dropLast()) {
            #expect(abs(hypot(b.center.x - a.center.x, b.center.y - a.center.y) - gap) < 0.01)
        }
        #expect(abs(dabs.count - (Int(100 / gap) + 1)) <= 1)
        #expect(dabs.last?.center == CGPoint(x: 100, y: 0))
        #expect(dabs.allSatisfy { $0.diameter == 20 })
    }

    @Test("A click with no drag still leaves one dab")
    func click() {
        let dabs = BrushPlacement.dabs(for: stroke([CGPoint(x: 5, y: 5)]))
        #expect(dabs.count == 1)
        #expect(dabs.first?.center == CGPoint(x: 5, y: 5))
    }

    @Test("Dabs carry the stroke's opacity as a fraction")
    func opacity() {
        var s = stroke([CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0)])
        s.settings.set("opacity", to: 40)
        #expect(BrushPlacement.dabs(for: s).allSatisfy { abs($0.opacity - 0.4) < 1e-9 })
    }

    @Test("A curve made of a few samples is followed smoothly, not as straight segments")
    func smoothing() {
        // Three points of a right angle: a polyline runs two straight lines;
        // a smooth curve through the same points bows out between them.
        let corner = CGPoint(x: 50, y: 0)
        let dabs = BrushPlacement.dabs(for: stroke([CGPoint(x: 0, y: 0), corner, CGPoint(x: 50, y: 50)], size: 4))
        let nearest = dabs.map { hypot($0.center.x - corner.x, $0.center.y - corner.y) }.min() ?? 0
        #expect(nearest < 1, "a smooth curve still passes through every sample")
        // ...and between the samples it bends rather than running straight.
        let offLine = dabs.filter { $0.center.y < -0.5 || $0.center.x > 50.5 }
        #expect(!offLine.isEmpty)
        #expect(dabs.last?.center == CGPoint(x: 50, y: 50))
    }

    @Test("Jitter is bounded and the same on every render")
    func jitter() {
        let s = stroke([CGPoint(x: 0, y: 0), CGPoint(x: 200, y: 0)], size: 10, seed: 99)
        let a = BrushPlacement.dabs(for: s, jitter: 0.5)
        let b = BrushPlacement.dabs(for: s, jitter: 0.5)
        #expect(a == b)
        #expect(a.contains { $0.center.y != 0 })
        #expect(a.allSatisfy { abs($0.center.y) <= 5 + 1e-9 })
        let other = BrushPlacement.dabs(for: stroke([CGPoint(x: 0, y: 0), CGPoint(x: 200, y: 0)], size: 10, seed: 100),
                                        jitter: 0.5)
        #expect(other != a)
    }

    @Test("Dabs worked out sample by sample are exactly the dabs of the finished stroke")
    func liveMatchesLanded() {
        let points = (0..<40).map { i in
            CGPoint(x: Double(i) * 7.3, y: 40 + sin(Double(i) / 3) * 25)
        }
        let s = stroke(points, size: 12, seed: 5)
        var walker = BrushPlacement.Walker(settings: s.settings, seed: s.seed, jitter: 0.3)
        var live: [BrushDab] = []
        for sample in s.samples { live += walker.add(sample) }
        live += walker.finish()
        #expect(live == BrushPlacement.dabs(for: s, jitter: 0.3))
    }

    // MARK: - Where a stroke lands

    private func picture() -> (PhotonzDocument, UUID) {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 400, height: 300))
        let image = Layer(name: "Screenshot", content: .image(ImageRef(pixelSize: CGSize(width: 400, height: 300))),
                          frame: CGRect(x: 0, y: 0, width: 400, height: 300))
        doc.addLayer(image)
        doc.addLayer(Layer(name: "Box", content: .annotation(AnnotationContent(shape: .rectangle)),
                           frame: CGRect(x: 10, y: 10, width: 20, height: 20)))
        return (doc, image.id)
    }

    @Test("The first stroke makes a Paint layer just above the picked layer, sized to the canvas")
    func firstStrokeMakesAPaintLayer() {
        var (doc, imageID) = picture()
        let before = doc.layer(id: imageID)
        let id = doc.paintStroke(stroke([CGPoint(x: 50, y: 50), CGPoint(x: 80, y: 60)]), onto: imageID)
        #expect(doc.layers.map(\.name) == ["Screenshot", "Paint", "Box"])
        let paint = doc.layer(id: id)
        #expect(paint?.frame == CGRect(x: 0, y: 0, width: 400, height: 300))
        #expect(paint?.paint?.strokes.count == 1)
        // The picture underneath is not touched.
        #expect(doc.layer(id: imageID) == before)
    }

    @Test("With nothing picked the Paint layer goes on top")
    func nothingPicked() {
        var (doc, _) = picture()
        let id = doc.paintStroke(stroke([CGPoint(x: 50, y: 50)]), onto: nil)
        #expect(doc.layers.last?.id == id)
        #expect(doc.layers.last?.name == "Paint")
    }

    @Test("With a paint layer picked the stroke is added to it, in its own space")
    func addsToPickedPaintLayer() {
        var (doc, imageID) = picture()
        let id = doc.paintStroke(stroke([CGPoint(x: 50, y: 50)]), onto: imageID)
        let again = doc.paintStroke(stroke([CGPoint(x: 90, y: 90), CGPoint(x: 120, y: 95)]), onto: id)
        #expect(again == id)
        #expect(doc.layers.filter { $0.paint != nil }.count == 1)
        #expect(doc.layer(id: id)?.paint?.strokes.count == 2)
    }

    @Test("A locked paint layer is not painted on: a new one is made above it")
    func lockedPaintLayer() {
        var (doc, imageID) = picture()
        let id = doc.paintStroke(stroke([CGPoint(x: 50, y: 50)]), onto: imageID)
        doc.updateLayer(id: id) { $0.isLocked = true }
        let next = doc.paintStroke(stroke([CGPoint(x: 60, y: 60)]), onto: id)
        #expect(next != id)
        #expect(doc.layer(id: id)?.paint?.strokes.count == 1)
    }

    @Test("A stroke started on a frame makes a Paint layer the size of that frame, on it")
    func onAFrame() {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 800, height: 600))
        let frame = Layer(name: "Screen", content: .group(GroupContent(isFrame: true)),
                          frame: CGRect(x: 100, y: 100, width: 300, height: 200))
        doc.addLayer(frame)
        let id = doc.paintStroke(stroke([CGPoint(x: 150, y: 150), CGPoint(x: 160, y: 170)]), onto: nil)
        #expect(doc.parentID(of: id) == frame.id)
        #expect(doc.canvasBounds(of: id) == CGRect(x: 100, y: 100, width: 300, height: 200))
        // The samples are stored in the layer's own space.
        #expect(doc.layer(id: id)?.paint?.strokes.first?.samples.first?.point == CGPoint(x: 50, y: 50))
    }
}
