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
    }

    @Test func anArrowsWidthIsNotHiddenInADrawerThisRowCannotOpen() {
        // A row with no switch is a colour and nothing else, so it has no
        // drawer to keep a width in. Making an arrow thicker is the commonest
        // thing anyone does to one, and it was two clicks down inside a row
        // called Color. The width is the shape's own Thickness setting now,
        // out where the ending and the head size are.
        let arrow = shape(.arrow)
        let doc = document([arrow])
        let ink = doc.layerPartRows(layerIDs: [arrow.id])[0]
        #expect(ink.widthIDs.isEmpty)
        #expect(!ink.hasSettings)
    }

    @Test func aRectanglesWidthStaysWithTheOutlineItBelongsTo() throws {
        // The other half of the same rule: where the outline is a part that
        // switches off, its width is that part's setting and stays in it.
        let box = shape(.rectangle, fillHex: "#00FF00")
        let doc = document([box])
        let outline = try #require(doc.layerPartRows(layerIDs: [box.id]).first { $0.part == .outline })
        #expect(outline.widthIDs == [box.id])
        #expect(outline.hasSettings)
    }

    @Test func anArrowPickedWithABoxTakesTheBoxesOutlineWidthRow() throws {
        // One row speaks for both, it can be switched off (the box can live
        // without its ring), so the width is in there and reaches both.
        let box = shape(.rectangle, fillHex: "#00FF00")
        let arrow = shape(.arrow)
        let doc = document([box, arrow])
        let rows = doc.layerPartRows(layerIDs: [box.id, arrow.id])
        let outline = try #require(rows.first { $0.slot == .stroke })
        #expect(outline.title == "Outline")
        #expect(outline.widthIDs == [box.id, arrow.id])
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

    // MARK: - A highlight, which was offered the same name twice

    @Test func aHighlightIsOfferedOneLineRoundItNotTwo() throws {
        // Reported 2026-09-06: picking a highlight put two rows called Outline
        // one above the other. Both switches wrote the same border width and
        // they painted different colours, so picking either was a guess.
        let wash = shape(.highlight)
        let doc = document([wash])
        let rows = doc.layerPartRows(layerIDs: [wash.id])
        #expect(rows.filter { $0.title == "Outline" }.count == 1)
        let outline = try #require(rows.first { $0.title == "Outline" })
        // The one that is real: the ring the highlight's styling draws.
        #expect(outline.slot == .border)
        #expect(outline.switchIDs == [wash.id])
        #expect(outline.widthIDs == [wash.id])
    }

    @Test func aHighlightsWashIsAColorRatherThanAnOutline() {
        // A highlight IS its wash, the way an arrow is its line: there is no
        // switching it off, and the stroke width it carries is never painted.
        let wash = shape(.highlight)
        let doc = document([wash])
        let rows = doc.layerPartRows(layerIDs: [wash.id])
        #expect(rows.map(\.title) == ["Color", "Outline", "Shadow"])
        let ink = rows[0]
        #expect(ink.slot == .stroke)
        #expect(ink.part == nil)
        #expect(!ink.hasSwitch)
        #expect(ink.widthIDs.isEmpty)
        #expect(!ink.hasSettings)
    }

    @Test func aHighlightsRingIsStillTheSameSwitch() {
        // Dropping the duplicate must not cost the highlight its ring.
        let wash = shape(.highlight)
        var doc = document([wash])
        #expect(doc.setOutlineEnabled(layerIDs: [wash.id], on: true) == 1)
        #expect(doc.layer(id: wash.id)!.style.borderWidth > 0)
        #expect(doc.setOutlineEnabled(layerIDs: [wash.id], on: false) == 1)
        #expect(doc.layer(id: wash.id)!.style.borderWidth == 0)
    }

    @Test func aHighlightPickedWithABoxLeavesTheBoxesOutlineAlone() throws {
        // The box still owns the stroke row, switch, width and all; the
        // highlight is simply not in it.
        let box = shape(.rectangle, fillHex: "#00FF00")
        let wash = shape(.highlight)
        let doc = document([box, wash])
        let rows = doc.layerPartRows(layerIDs: [box.id, wash.id])
        let stroke = try #require(rows.first { $0.slot == .stroke })
        #expect(stroke.title == "Outline")
        #expect(stroke.switchIDs == [box.id])
        #expect(stroke.widthIDs == [box.id])
    }

    @Test func anEllipseStillGetsFillOutlineAndShadow() {
        let oval = shape(.ellipse, fillHex: "#00FF00")
        let doc = document([oval])
        let rows = doc.layerPartRows(layerIDs: [oval.id])
        #expect(rows.map(\.title) == ["Fill", "Outline", "Shadow"])
        #expect(rows[1].slot == .stroke)
        #expect(rows[1].widthIDs == [oval.id])
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
