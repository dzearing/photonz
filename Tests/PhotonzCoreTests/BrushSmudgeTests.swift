import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// The brush's Paint / Smudge mode (`docs/design/brushes.md`, decision 7) and
/// where a smudge lands: on paint that is already there, never on a picture,
/// and never as a new layer.
@Suite("Brush smudge")
struct BrushSmudgeTests {

    private func stroke(_ points: [CGPoint], mode: BrushMode = .paint) -> BrushStroke {
        var settings = BrushSettings(medium: .charcoal)
        settings.mode = mode
        return BrushStroke(samples: points.enumerated().map { StrokeSample(point: $1, ms: Double($0) * 16) },
                           settings: settings, colorHex: "#000000", seed: 7)
    }

    private func picture() -> (PhotonzDocument, UUID) {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 400, height: 300))
        let image = Layer(name: "Screenshot", content: .image(ImageRef(pixelSize: CGSize(width: 400, height: 300))),
                          frame: CGRect(x: 0, y: 0, width: 400, height: 300))
        doc.addLayer(image)
        return (doc, image.id)
    }

    // MARK: - The mode

    @Test("A brush paints until it is set to smudge, and the mode is named plainly")
    func modeDefaults() {
        #expect(BrushSettings(medium: .charcoal).mode == .paint)
        #expect(BrushMode.allCases == [.paint, .smudge])
        #expect(BrushMode.paint.title == "Paint")
        #expect(BrushMode.smudge.title == "Smudge")
    }

    @Test("Switching medium keeps the brush smudging")
    func switchKeepsMode() {
        var brush = BrushSettings(medium: .charcoal)
        brush.mode = .smudge
        #expect(brush.switched(to: .chalk).mode == .smudge)
    }

    @Test("A stroke saved before the mode existed opens as paint, and a smudge reopens as a smudge")
    func codable() throws {
        let old = #"{"medium":"chalk","values":{"size":12}}"#
        let decoded = try JSONDecoder().decode(BrushSettings.self, from: Data(old.utf8))
        #expect(decoded.mode == .paint)
        var smudge = BrushSettings(medium: .charcoal)
        smudge.mode = .smudge
        let again = try JSONDecoder().decode(BrushSettings.self, from: JSONEncoder().encode(smudge))
        #expect(again == smudge)
    }

    @Test("Medium and Mode are what the brush puts over the tool bar")
    func capsule() {
        #expect(ToolSettingsBar.settings(for: .brush, availability: .all) == [.brushMedium, .brushMode])
        #expect(ToolSetting.brushMedium.title == "Medium")
        #expect(ToolSetting.brushMode.title == "Mode")
    }

    // MARK: - Where a smudge lands

    @Test("A smudge goes onto the picked paint layer as one more stroke")
    func smudgeOntoPicked() {
        var (doc, imageID) = picture()
        let paintID = doc.paintStroke(stroke([CGPoint(x: 50, y: 50), CGPoint(x: 90, y: 50)]), onto: imageID)
        let landed = doc.smudgeStroke(stroke([CGPoint(x: 60, y: 50), CGPoint(x: 120, y: 50)], mode: .smudge),
                                      onto: paintID)
        #expect(landed == paintID)
        #expect(doc.layer(id: paintID)?.paint?.strokes.map(\.settings.mode) == [.paint, .smudge])
        #expect(doc.layers.count == 2)
    }

    @Test("With a picture picked, a smudge finds the paint under the pointer")
    func smudgeFindsPaintUnderPointer() {
        var (doc, imageID) = picture()
        let paintID = doc.paintStroke(stroke([CGPoint(x: 50, y: 50), CGPoint(x: 90, y: 50)]), onto: imageID)
        let landed = doc.smudgeStroke(stroke([CGPoint(x: 60, y: 50), CGPoint(x: 120, y: 50)], mode: .smudge),
                                      onto: imageID)
        #expect(landed == paintID)
        #expect(doc.layer(id: paintID)?.paint?.strokes.count == 2)
    }

    @Test("With no paint to smudge, nothing is made and the picture is left alone")
    func smudgeWithNoPaint() {
        var (doc, imageID) = picture()
        let before = doc
        #expect(doc.smudgeStroke(stroke([CGPoint(x: 60, y: 50), CGPoint(x: 120, y: 50)], mode: .smudge),
                                 onto: imageID) == nil)
        #expect(doc == before)
        #expect(doc.smudgeTarget(at: CGPoint(x: 60, y: 50), picked: imageID) == nil)
    }

    @Test("A locked or hidden paint layer is not smudged")
    func lockedOrHidden() {
        var (doc, imageID) = picture()
        let paintID = doc.paintStroke(stroke([CGPoint(x: 50, y: 50), CGPoint(x: 90, y: 50)]), onto: imageID)
        doc.updateLayer(id: paintID) { $0.isLocked = true }
        #expect(doc.smudgeTarget(at: CGPoint(x: 60, y: 50), picked: paintID) == nil)
        doc.updateLayer(id: paintID) { $0.isLocked = false; $0.isVisible = false }
        #expect(doc.smudgeTarget(at: CGPoint(x: 60, y: 50), picked: nil) == nil)
    }

    @Test("A smudge stroke is stored in the paint layer's own space")
    func smudgeLocalSpace() {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 800, height: 600))
        let frame = Layer(name: "Screen", content: .group(GroupContent(isFrame: true)),
                          frame: CGRect(x: 100, y: 100, width: 300, height: 200))
        doc.addLayer(frame)
        let id = doc.paintStroke(stroke([CGPoint(x: 150, y: 150), CGPoint(x: 160, y: 170)]), onto: nil)
        let landed = doc.smudgeStroke(stroke([CGPoint(x: 155, y: 160), CGPoint(x: 200, y: 160)], mode: .smudge),
                                      onto: nil)
        #expect(landed == id)
        #expect(doc.layer(id: id)?.paint?.strokes.last?.samples.first?.point == CGPoint(x: 55, y: 60))
    }
}
