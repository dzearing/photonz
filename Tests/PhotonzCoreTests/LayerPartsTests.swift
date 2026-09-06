import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// A layer is made of parts, and every part works the same way: one switch, one
/// colour, its own settings.
///
/// Raised by the user on 2026-09-06 after failing to find any way to take a
/// rectangle's outline off. There was none: the fill had a checkbox, the
/// outline had nothing at all, and the shadow had a switch of its own in
/// another section. These tests pin the model down.
@Suite("Layer parts")
struct LayerPartsTests {

    private func shape(_ kind: AnnotationShape, strokeWidth: CGFloat = 4,
                       fillHex: String? = nil, style: LayerStyle = LayerStyle(),
                       locked: Bool = false) -> Layer {
        var layer = Layer(name: kind.title,
                          content: .annotation(AnnotationContent(shape: kind,
                                                                 strokeWidth: strokeWidth,
                                                                 colorHex: "#FF0000",
                                                                 start: .zero,
                                                                 end: CGPoint(x: 100, y: 60),
                                                                 fillColorHex: fillHex)),
                          frame: CGRect(x: 0, y: 0, width: 100, height: 60),
                          style: style)
        layer.isLocked = locked
        return layer
    }

    private func picture(style: LayerStyle = LayerStyle()) -> Layer {
        Layer(name: "Shot",
              content: .image(ImageRef(pixelSize: CGSize(width: 40, height: 40))),
              frame: CGRect(x: 0, y: 0, width: 40, height: 40),
              style: style)
    }

    private func document(_ layers: [Layer]) -> PhotonzDocument {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 400, height: 300))
        for layer in layers { doc.addLayer(layer) }
        return doc
    }

    private func border(_ width: CGFloat) -> LayerStyle {
        var style = LayerStyle()
        style.borderWidth = width
        return style
    }

    // MARK: - Which ring a layer's outline part paints

    @Test func aShapePaintsItsOwnStrokeAndEverythingElseTakesARing() {
        #expect(shape(.rectangle).outlineSlot == .stroke)
        #expect(shape(.arrow).outlineSlot == .stroke)
        #expect(picture().outlineSlot == .border)
        #expect(shape(.highlight).outlineSlot == .border)
    }

    @Test func onlyAShapeWithAnInsideCanHaveItsOutlineSwitchedOff() {
        #expect(shape(.rectangle).outlineIsSwitchable)
        #expect(shape(.ellipse).outlineIsSwitchable)
        // A line IS its line: switching it off is a delete, not a setting.
        #expect(!shape(.line).outlineIsSwitchable)
        #expect(!shape(.arrow).outlineIsSwitchable)
        // ...but a ring round a box is styling, and anything can take one.
        #expect(picture().outlineIsSwitchable)
        #expect(shape(.highlight).outlineIsSwitchable)
    }

    @Test func aHighlightsUnpaintedStrokeWidthIsNotAnOutline() {
        // It carries a stroke width it never draws, so only the ring its
        // styling adds counts as an outline.
        #expect(!shape(.highlight, strokeWidth: 6).hasOutline)
        #expect(shape(.highlight, strokeWidth: 6, style: border(2)).hasOutline)
    }

    // MARK: - The rows a selection gets

    @Test func aRectangleGetsFillOutlineAndShadow() {
        let box = shape(.rectangle, fillHex: "#00FF00")
        let doc = document([box])
        let rows = doc.layerPartRows(layerIDs: [box.id])
        #expect(rows.map(\.title) == ["Fill", "Outline", "Shadow"])
        #expect(rows.map(\.hasSwitch) == [true, true, true])
        // Fill and outline are both on; the shadow is not.
        #expect(rows[0].isOn)
        #expect(rows[1].isOn)
        #expect(!rows[2].isOn)
        // Only the outline and the shadow have anything to unfold.
        #expect(rows.map(\.hasSettings) == [false, true, true])
    }

    @Test func anArrowsOneColorIsNotCalledAnOutlineAndHasNoSwitch() {
        let arrow = shape(.arrow)
        let doc = document([arrow])
        let rows = doc.layerPartRows(layerIDs: [arrow.id])
        // No Outline row at all: the arrow's line IS its colour, and a ring
        // round its bounding box is not something anyone reaches for.
        #expect(rows.map(\.title) == ["Color", "Shadow"])
        let ink = rows[0]
        #expect(ink.part == nil)
        #expect(!ink.hasSwitch)
        // It still has a width to set, so the row unfolds.
        #expect(ink.widthIDs == [arrow.id])
        #expect(ink.hasSettings)
    }

    @Test func aPictureGetsAnOutlineItCanSwitchOnAndAShadow() {
        let shot = picture()
        let doc = document([shot])
        let rows = doc.layerPartRows(layerIDs: [shot.id])
        #expect(rows.map(\.title) == ["Outline", "Shadow"])
        // The same model as a rectangle's, on a layer that is not a shape at
        // all: the ring is off, and one switch turns it on.
        #expect(rows[0].part == .outline)
        #expect(rows[0].slot == .border)
        #expect(rows[0].hasSwitch)
        #expect(!rows[0].isOn)
    }

    @Test func nothingIsCalledABorderAnyMore() {
        let shot = picture(style: border(3))
        let doc = document([shot])
        let titles = doc.layerPartRows(layerIDs: [shot.id]).map(\.title)
        #expect(!titles.contains("Border"))
    }

    @Test func aSwitchReadsOffUntilEveryLayerItReachesHasThePart() throws {
        let outlined = shape(.rectangle)
        let plain = shape(.rectangle, strokeWidth: 0, fillHex: "#00FF00")
        let doc = document([outlined, plain])
        let rows = doc.layerPartRows(layerIDs: [outlined.id, plain.id])
        let outline = try #require(rows.first { $0.slot == .stroke })
        #expect(outline.onCount == 1)
        #expect(!outline.isOn)
    }

    @Test func aLockedLayerIsLeftOutOfEveryRow() {
        let box = shape(.rectangle, locked: true)
        let doc = document([box])
        #expect(doc.layerPartRows(layerIDs: [box.id]).isEmpty)
    }

    @Test func aRowSaysWhenItLeavesAPickedLayerOut() throws {
        let box = shape(.rectangle, fillHex: "#00FF00")
        let arrow = shape(.arrow)
        let doc = document([box, arrow])
        let rows = doc.layerPartRows(layerIDs: [box.id, arrow.id])
        let fill = try #require(rows.first { $0.slot == .fill })
        #expect(fill.reachNote == "Applies to 1 of the 2 selected layers.")
        // The shadow reaches both, so it says nothing.
        let shadow = try #require(rows.first { $0.part == .shadow })
        #expect(shadow.reachNote == nil)
    }

    // MARK: - Switching the outline off, which could not be done at all

    @Test func aRectanglesOutlineComesOffAndItsColorIsKept() {
        let box = shape(.rectangle, fillHex: "#00FF00")
        var doc = document([box])
        #expect(doc.setOutlineEnabled(layerIDs: [box.id], on: false) == 1)
        let after = doc.layer(id: box.id)!
        #expect(!after.hasOutline)
        #expect(after.annotation?.strokeWidth == 0)
        // The colour is exactly where it was, so switching back on brings the
        // same ring back rather than a black one.
        #expect(after.annotation?.colorHex == "#FF0000")
    }

    @Test func switchingItBackOnRestoresTheWidthThePanelRemembers() {
        let box = shape(.rectangle, strokeWidth: 12, fillHex: "#00FF00")
        var doc = document([box])
        doc.setOutlineEnabled(layerIDs: [box.id], on: false)
        doc.setOutlineEnabled(layerIDs: [box.id], on: true, restoring: [box.id: 12])
        #expect(doc.layer(id: box.id)?.annotation?.strokeWidth == 12)
    }

    @Test func withNothingRememberedItComesBackAtTheWidthAFreshOneWears() {
        let box = shape(.rectangle, strokeWidth: 0, fillHex: "#00FF00")
        var doc = document([box])
        doc.setOutlineEnabled(layerIDs: [box.id], on: true)
        #expect(doc.layer(id: box.id)?.annotation?.strokeWidth == AnnotationContent.defaultStrokeWidth)
    }

    @Test func aPicturesRingIsTheSameSwitch() {
        let shot = picture()
        var doc = document([shot])
        #expect(doc.setOutlineEnabled(layerIDs: [shot.id], on: true) == 1)
        #expect(doc.layer(id: shot.id)!.style.borderWidth > 0)
        #expect(doc.setOutlineEnabled(layerIDs: [shot.id], on: false) == 1)
        #expect(doc.layer(id: shot.id)!.style.borderWidth == 0)
    }

    @Test func anArrowRefusesToLoseItsLineAndSaysSoByChangingNothing() {
        let arrow = shape(.arrow)
        var doc = document([arrow])
        #expect(doc.setOutlineEnabled(layerIDs: [arrow.id], on: false) == 0)
        #expect(doc.layer(id: arrow.id)?.annotation?.strokeWidth == 4)
    }

    @Test func aLockedLayerIsNeverSwitched() {
        let box = shape(.rectangle, fillHex: "#00FF00", locked: true)
        var doc = document([box])
        #expect(doc.setOutlineEnabled(layerIDs: [box.id], on: false) == 0)
    }

    @Test func switchingOnWhatIsAlreadyOnChangesNothing() {
        let box = shape(.rectangle)
        var doc = document([box])
        #expect(doc.setOutlineEnabled(layerIDs: [box.id], on: true) == 0)
    }

    @Test func oneSwitchReachesEveryPickedShape() {
        let a = shape(.rectangle, fillHex: "#00FF00")
        let b = shape(.ellipse, fillHex: "#0000FF")
        var doc = document([a, b])
        #expect(doc.setOutlineEnabled(layerIDs: [a.id, b.id], on: false) == 2)
        #expect(doc.layer(id: a.id)!.hasOutline == false)
        #expect(doc.layer(id: b.id)!.hasOutline == false)
    }
}
