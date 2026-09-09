import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// An arrow's parts: the line, the head, and the label pill's fill, edge and
/// text, each with a colour of its own.
///
/// The old model had ONE colour driving the shaft and the head together, and a
/// label whose three colours were worked out from that one rather than chosen.
/// These tests pin the two things that could go wrong when that changes: the
/// parts really are independent, and an arrow drawn before any of this opens
/// looking exactly as it did.

private func arrow(_ colorHex: String = "#FF3B30", caption: String? = nil) -> AnnotationContent {
    var content = AnnotationContent(shape: .arrow, strokeWidth: 4, colorHex: colorHex)
    content.start = CGPoint(x: 0, y: 0)
    content.end = CGPoint(x: 100, y: 0)
    content.caption = caption
    return content
}

private func arrowLayer(_ content: AnnotationContent) -> Layer {
    Layer(name: "Arrow", content: .annotation(content),
          frame: CGRect(x: 0, y: 0, width: 100, height: 40))
}

@Suite("An arrow's line and head are separate colours")
struct ArrowHeadColorTests {

    @Test func aNewArrowsHeadIsTheColourOfItsLine() {
        #expect(arrow("#0A84FF").headColorHex == "#0A84FF")
    }

    @Test func paintingTheLineLeavesTheHeadAlone() {
        var content = arrow("#FF3B30")
        content.colorHex = "#0A84FF"
        #expect(content.colorHex == "#0A84FF")
        #expect(content.headColorHex == "#FF3B30")
    }

    @Test func paintingTheHeadLeavesTheLineAlone() {
        var content = arrow("#FF3B30")
        content.headColorHex = "#34C759"
        #expect(content.headColorHex == "#34C759")
        #expect(content.colorHex == "#FF3B30")
    }

    @Test func anArrowSavedBeforeTheHeadHadAColourOpensWearingTheLines() throws {
        // Exactly what an older build wrote: one colour for the whole arrow.
        let json = """
        {"shape":"arrow","strokeWidth":4,"colorHex":"#0A84FF",
         "start":[10,20],"end":[110,20]}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(AnnotationContent.self, from: json)
        #expect(decoded.headColorHex == "#0A84FF")
    }

    @Test func aHeadOfItsOwnSurvivesSavingAndOpening() throws {
        var content = arrow("#FF3B30")
        content.headColorHex = "#34C759"
        let again = try JSONDecoder().decode(
            AnnotationContent.self, from: JSONEncoder().encode(content))
        #expect(again.headColorHex == "#34C759")
        #expect(again.colorHex == "#FF3B30")
    }
}

@Suite("A label pill's colours are its own")
struct ArrowCaptionColorTests {

    @Test func typingTheFirstWordsGivesTheLabelTheColoursItAlwaysDrewIn() {
        let content = arrow("#FF3B30", caption: "Save button")
        // The red pair the measure chip and the caption have always shared.
        #expect(content.captionFill?.hex == "#8C201A")
        #expect(content.captionBorder?.hex == "#FF3B30")
        #expect(content.captionTextHex == "#FFFFFF")
    }

    @Test func theLabelIsSeededFromTheLineColourAtTheMomentItGetsWords() {
        // Draw red, repaint the line blue, THEN caption it: the pill is blue's
        // dark tone, not the red the arrow started life as.
        var content = arrow("#FF3B30")
        content.colorHex = "#0A84FF"
        content.caption = "Tap here"
        #expect(content.captionBorder?.hex == "#0A84FF")
        #expect(content.captionFill?.hex == content.captionChipColor.hexString)
    }

    @Test func anArrowWithNoWordsHasNoLabelColoursYet() {
        let content = arrow("#FF3B30")
        #expect(content.captionFill == nil)
        #expect(content.captionBorder == nil)
        #expect(content.captionTextColorHex == nil)
    }

    @Test func paintingTheLabelDoesNotTouchTheLineOrTheHead() {
        var content = arrow("#FF3B30", caption: "Here")
        content.captionFill = Paint(hex: "#1B3A66")
        content.captionTextColorHex = "#FFCC00"
        #expect(content.colorHex == "#FF3B30")
        #expect(content.headColorHex == "#FF3B30")
    }

    @Test func repaintingTheLineLeavesAnAlreadyLabelledPillAlone() {
        var content = arrow("#FF3B30", caption: "Here")
        content.colorHex = "#0A84FF"
        #expect(content.captionFill?.hex == "#8C201A")
        #expect(content.captionBorder?.hex == "#FF3B30")
    }

    @Test func aLabelSavedBeforeItHadColoursOpensWearingTheOnesItDrew() throws {
        // A caption written by the build that derived all three.
        let json = """
        {"shape":"arrow","strokeWidth":4,"colorHex":"#0A84FF",
         "start":[10,20],"end":[110,20],"caption":"Save"}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(AnnotationContent.self, from: json)
        var derived = arrow("#0A84FF")
        derived.caption = "Save"
        #expect(decoded.captionFill?.hex == derived.captionChipColor.hexString)
        #expect(decoded.captionBorder?.hex == "#0A84FF")
        #expect(decoded.captionTextHex == "#FFFFFF")
    }

    @Test func aFillSwitchedOffStaysOffAcrossSavingAndOpening() throws {
        var content = arrow("#FF3B30", caption: "Here")
        content.captionFill = nil
        let again = try JSONDecoder().decode(
            AnnotationContent.self, from: JSONEncoder().encode(content))
        #expect(again.captionFill == nil)
        // ...and the edge it kept is still there, so "off" is one part's
        // answer rather than the whole pill's.
        #expect(again.captionBorder?.hex == "#FF3B30")
    }

    @Test func anEdgeSwitchedOffDrawsNoBorderAtAll() {
        var content = arrow("#FF3B30", caption: "Here")
        #expect(content.drawnCaptionBorderWidth > 0)
        content.captionBorder = nil
        #expect(content.drawnCaptionBorderWidth == 0)
        // The pill's geometry is unchanged: the label does not jump when its
        // edge is taken off.
        #expect(content.captionBorderWidth > 0)
    }
}

@Suite("Where an arrow's colours are offered")
struct ArrowColorSlotTests {

    @Test func anArrowOffersItsLineAndItsHead() {
        let layer = arrowLayer(arrow("#FF3B30"))
        #expect(layer.colorSlots.contains(.stroke))
        #expect(layer.colorSlots.contains(.arrowHead))
    }

    @Test func anArrowWithNoLabelOffersNoLabelColours() {
        let layer = arrowLayer(arrow("#FF3B30"))
        #expect(!layer.colorSlots.contains(.captionFill))
        #expect(!layer.colorSlots.contains(.captionBorder))
        #expect(!layer.colorSlots.contains(.captionText))
    }

    @Test func anArrowWithALabelOffersAllThreeOfItsColours() {
        let layer = arrowLayer(arrow("#FF3B30", caption: "Save"))
        #expect(layer.colorSlots.contains(.captionFill))
        #expect(layer.colorSlots.contains(.captionBorder))
        #expect(layer.colorSlots.contains(.captionText))
    }

    @Test func anArrowThatEndsInNothingOffersNoHeadColour() {
        var content = arrow("#FF3B30")
        content.arrowheadStyle = .plain
        #expect(!arrowLayer(content).colorSlots.contains(.arrowHead))
    }

    @Test func aLineIsAllShaftAndHasNoHead() {
        var content = arrow("#FF3B30")
        content.shape = .line
        #expect(!arrowLayer(content).colorSlots.contains(.arrowHead))
    }

    @Test func readingAndPaintingEachSlotReachesTheRightPart() {
        var layer = arrowLayer(arrow("#FF3B30", caption: "Save"))
        #expect(layer.colorHex(for: .stroke) == "#FF3B30")
        #expect(layer.colorHex(for: .arrowHead) == "#FF3B30")
        #expect(layer.colorHex(for: .captionFill) == "#8C201A")
        #expect(layer.colorHex(for: .captionBorder) == "#FF3B30")
        #expect(layer.colorHex(for: .captionText) == "#FFFFFF")

        layer.setPaint(Paint(hex: "#34C759"), for: .arrowHead)
        layer.setPaint(Paint(hex: "#1B3A66"), for: .captionFill)
        layer.setPaint(Paint(hex: "#FFFFFF"), for: .captionBorder)
        layer.setPaint(Paint(hex: "#000000"), for: .captionText)
        #expect(layer.colorHex(for: .stroke) == "#FF3B30")
        #expect(layer.colorHex(for: .arrowHead) == "#34C759")
        #expect(layer.colorHex(for: .captionFill) == "#1B3A66")
        #expect(layer.colorHex(for: .captionBorder) == "#FFFFFF")
        #expect(layer.colorHex(for: .captionText) == "#000000")
    }

    @Test func onlyTheLabelsFillAndEdgeCanBeSwitchedOff() {
        #expect(ColorSlot.captionFill.isSwitchable)
        #expect(ColorSlot.captionBorder.isSwitchable)
        #expect(!ColorSlot.captionText.isSwitchable)
        #expect(!ColorSlot.arrowHead.isSwitchable)
    }

    @Test func aLabelColourTakesASavedName() {
        let layer = arrowLayer(arrow("#FF3B30", caption: "Save"))
        var doc = PhotonzDocument(canvasSize: CGSize(width: 400, height: 300), layers: [layer])
        let styleID = doc.saveColorStyle(from: [layer.id], slot: .captionFill, name: "Pill")
        #expect(styleID != nil)
        #expect(doc.layer(id: layer.id)?.colorStyleID(for: .captionFill) == styleID)
        #expect(doc.layer(id: layer.id)?.colorStyleID(for: .captionBorder) == nil)
    }
}

@Suite("An arrow's parts in Appearance")
struct ArrowPartRowTests {

    private func document(_ content: AnnotationContent) -> (PhotonzDocument, UUID) {
        let layer = arrowLayer(content)
        let doc = PhotonzDocument(canvasSize: CGSize(width: 400, height: 300), layers: [layer])
        return (doc, layer.id)
    }

    @Test func aPlainArrowListsItsLineAndItsHead() {
        let (doc, id) = document(arrow("#FF3B30"))
        let titles = doc.layerPartRows(layerIDs: [id]).map(\.title)
        #expect(titles == ["Line", "Head"])
    }

    @Test func aLabelledArrowListsTheLabelsThreeParts() {
        let (doc, id) = document(arrow("#FF3B30", caption: "Save"))
        let titles = doc.layerPartRows(layerIDs: [id]).map(\.title)
        #expect(titles == ["Line", "Head", "Label Fill", "Label Edge", "Label Text"])
    }

    /// The Ending picker lives under the Head row. Hang that row off the head's
    /// COLOUR and choosing "no ending" takes away the control you just used —
    /// which is exactly what the arrow endings walk caught on 2026-09-09. So
    /// the row is there for every arrow, and only its colour comes and goes.
    @Test func anArrowEndingInNothingKeepsItsHeadRowAndLosesOnlyItsColour() {
        var content = arrow("#FF3B30")
        content.arrowheadStyle = .plain
        let (doc, id) = document(content)
        let rows = doc.layerPartRows(layerIDs: [id])
        #expect(rows.map(\.title) == ["Line", "Head"])
        let head = rows[1]
        #expect(head.colors.isEmpty)
        #expect(!head.showsSettings)
        // ...and with an ending back, the colour is back with it.
        let (withHead, headID) = document(arrow("#FF3B30"))
        #expect(withHead.layerPartRows(layerIDs: [headID])[1].showsSettings)
    }

    @Test func theLabelsFillAndEdgeCarryASwitchAndTheRestDoNot() {
        let (doc, id) = document(arrow("#FF3B30", caption: "Save"))
        let rows = doc.layerPartRows(layerIDs: [id])
        let switched = rows.filter(\.hasSwitch).map(\.title)
        #expect(switched == ["Label Fill", "Label Edge"])
    }

    @Test func switchingTheLabelsFillOffAndOnKeepsTheRestOfTheArrow() {
        var (doc, id) = document(arrow("#FF3B30", caption: "Save"))
        #expect(doc.setColorEnabled(layerIDs: [id], slot: .captionFill, on: false) == 1)
        #expect(doc.layer(id: id)?.colorHex(for: .captionFill) == nil)
        #expect(doc.layer(id: id)?.colorHex(for: .stroke) == "#FF3B30")
        #expect(doc.setColorEnabled(layerIDs: [id], slot: .captionFill, on: true) == 1)
        // Back to the tone the arrow's own colour makes, not to black.
        #expect(doc.layer(id: id)?.colorHex(for: .captionFill) == "#8C201A")
    }

    @Test func aBoxIsUntouchedByAnyOfThis() {
        var box = AnnotationContent(shape: .rectangle, strokeWidth: 0, colorHex: "#FF3B30")
        box.fillColorHex = "#FFFFFF"
        let (doc, id) = document(box)
        #expect(doc.layerPartRows(layerIDs: [id]).map(\.title) == ["Fill"])
    }
}

@Suite("A label that cannot be read says so")
struct ArrowCaptionLegibilityTests {

    @Test func aSensiblePairSaysNothing() {
        #expect(arrow("#FF3B30", caption: "Save").captionLegibilityNote == nil)
    }

    @Test func whiteOnWhiteIsCalledOut() {
        var content = arrow("#FF3B30", caption: "Save")
        content.captionFill = Paint(hex: "#FFFFFF")
        #expect(content.captionLegibilityNote != nil)
    }

    @Test func aLabelWithNoFillIsJudgedAgainstNothingRatherThanGuessed() {
        // With the fill off the words sit on whatever is underneath, which the
        // model cannot see, so it keeps quiet rather than crying wolf.
        var content = arrow("#FF3B30", caption: "Save")
        content.captionFill = nil
        #expect(content.captionLegibilityNote == nil)
    }
}
