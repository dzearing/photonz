import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// A measurement's parts: the caliper, and the chip's fill, its edge and its
/// text, each with a colour of its own and each reached the way every other
/// colour in the app is reached.
///
/// Before this the chip had no edge to colour at all — its ring was simply the
/// caliper's ink drawn at the caliper's thickness — and none of the four
/// colours was one of the layer's slots, so none of them could take a saved
/// name. These tests pin the two things that could go wrong: the parts really
/// are independent, and a measurement drawn before any of it opens looking
/// exactly as it did.

private func measure(stroke: String = "#FF3B30", width: CGFloat = 2) -> MeasureContent {
    MeasureContent(start: CGPoint(x: 0, y: 40), end: CGPoint(x: 120, y: 40),
                   mode: .horizontal, strokeWidth: width, strokeColorHex: stroke)
}

private func measureLayer(_ content: MeasureContent) -> Layer {
    Layer(name: "Measure", content: .measure(content),
          frame: CGRect(x: 0, y: 0, width: 160, height: 80))
}

@Suite("A measurement chip's edge is its own colour")
struct MeasureChipEdgeTests {

    @Test func aNewChipsEdgeIsTheCalipersColourAtItsThickness() {
        let content = measure(stroke: "#0A84FF", width: 3)
        #expect(content.chipBorderColorHex == "#0A84FF")
        #expect(content.chipBorderWidth == 3)
    }

    @Test func paintingTheCaliperLeavesTheChipsEdgeAlone() {
        var content = measure(stroke: "#FF3B30")
        content.strokeColorHex = "#0A84FF"
        #expect(content.strokeColorHex == "#0A84FF")
        #expect(content.chipBorderColorHex == "#FF3B30")
    }

    @Test func anEdgeIsTakenOffByHavingNoWidth() {
        var content = measure()
        content.chipBorderWidth = 0
        #expect(!content.hasChipBorder)
        content.chipBorderWidth = 2
        #expect(content.hasChipBorder)
    }

    @Test func aMeasurementSavedBeforeTheChipHadAnEdgeOpensWearingTheOneItDrew() throws {
        // Exactly what an older build wrote: the ring was the caliper's ink at
        // the caliper's thickness, and neither was stored for the chip.
        let json = """
        {"start":[10,40],"end":[130,40],"headOffset":28,"mode":"horizontal",
         "strokeWidth":3,"strokeColorHex":"#0A84FF","chipColorHex":"#1B3A66",
         "chipOpacity":1,"textColorHex":"#FFFFFF","showLabel":true,
         "unit":"points","decimals":0}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(MeasureContent.self, from: json)
        #expect(decoded.chipBorderColorHex == "#0A84FF")
        #expect(decoded.chipBorderWidth == 3)
    }

    @Test func anEdgeOfItsOwnSurvivesSavingAndOpening() throws {
        var content = measure(stroke: "#FF3B30")
        content.chipBorderColorHex = "#34C759"
        content.chipBorderWidth = 5
        let again = try JSONDecoder().decode(
            MeasureContent.self, from: JSONEncoder().encode(content))
        #expect(again.chipBorderColorHex == "#34C759")
        #expect(again.chipBorderWidth == 5)
        #expect(again.strokeColorHex == "#FF3B30")
    }

    @Test func anEdgeTakenOffStaysOffAcrossSavingAndOpening() throws {
        var content = measure()
        content.chipBorderWidth = 0
        let again = try JSONDecoder().decode(
            MeasureContent.self, from: JSONEncoder().encode(content))
        #expect(again.chipBorderWidth == 0)
        #expect(!again.hasChipBorder)
    }

    @Test func theChipsPaddingFollowsItsOwnEdgeRatherThanTheCalipers() {
        var content = measure(width: 1)
        content.chipBorderWidth = 6
        // A thick ring on a hairline caliper still gets room reserved for it,
        // or the pill would be clipped by its own layer.
        #expect(content.chipRenderPadding >= 4)
    }
}

@Suite("A measurement's colours are slots like everybody else's")
struct MeasureColorSlotTests {

    @Test func aMeasurementOffersItsCaliperAndItsChipsThree() {
        let layer = measureLayer(measure())
        #expect(layer.colorSlots == [.caliper, .chipFill, .chipBorder, .chipText])
    }

    @Test func aMeasurementWithItsReadoutHiddenOffersNoChipParts() {
        var content = measure()
        content.showLabel = false
        #expect(measureLayer(content).colorSlots == [.caliper])
    }

    @Test func eachSlotReadsThePartItNames() {
        var content = measure(stroke: "#FF3B30")
        content.chipColorHex = "#1B3A66"
        content.chipOpacity = 1
        content.textColorHex = "#FFFFFF"
        content.chipBorderColorHex = "#34C759"
        let layer = measureLayer(content)
        #expect(layer.colorHex(for: .caliper) == "#FF3B30")
        #expect(layer.colorHex(for: .chipFill) == "#1B3A66")
        #expect(layer.colorHex(for: .chipBorder) == "#34C759")
        #expect(layer.colorHex(for: .chipText) == "#FFFFFF")
    }

    @Test func paintingASlotPaintsThatPartAndNoOther() {
        var layer = measureLayer(measure(stroke: "#FF3B30"))
        layer.setPaint(Paint(hex: "#34C759"), for: .chipBorder)
        #expect(layer.measure?.chipBorderColorHex == "#34C759")
        #expect(layer.measure?.strokeColorHex == "#FF3B30")
        layer.setPaint(Paint(hex: "#0A84FF"), for: .caliper)
        #expect(layer.measure?.strokeColorHex == "#0A84FF")
        #expect(layer.measure?.chipBorderColorHex == "#34C759")
    }

    @Test func theChipsFillCarriesItsOwnAlpha() {
        var layer = measureLayer(measure())
        layer.setPaint(Paint(hex: "#1B3A6680"), for: .chipFill)
        #expect(layer.measure?.chipColorHex == "#1B3A66")
        #expect(abs((layer.measure?.chipOpacity ?? 0) - 0.5) < 0.01)
        // ...and the well reads back what it wrote, alpha and all.
        #expect(layer.colorHex(for: .chipFill)?.hasPrefix("#1B3A66") == true)
    }

    @Test func aPlainColourLeavesTheChipsAlphaWhereItWas() {
        var content = measure()
        content.chipOpacity = 0.5
        var layer = measureLayer(content)
        layer.setPaint(Paint(hex: "#8C201A"), for: .chipFill)
        #expect(layer.measure?.chipColorHex == "#8C201A")
        #expect(abs((layer.measure?.chipOpacity ?? 0) - 0.5) < 0.01)
    }

    @Test func onlyTheChipsFillAndItsEdgeCanBeSwitchedOff() {
        #expect(ColorSlot.chipFill.isSwitchable)
        #expect(ColorSlot.chipBorder.isSwitchable)
        #expect(!ColorSlot.caliper.isSwitchable)
        #expect(!ColorSlot.chipText.isSwitchable)
    }

    @Test func switchingTheChipsFillOffAndBackOnKeepsItsHue() {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 400, height: 300))
        var content = measure()
        content.chipColorHex = "#1B3A66"
        let layer = measureLayer(content)
        doc.layers.append(layer)
        _ = doc.setColorEnabled(layerIDs: [layer.id], slot: .chipFill, on: false)
        #expect(doc.layer(id: layer.id)?.colorHex(for: .chipFill) == nil)
        #expect(doc.layer(id: layer.id)?.measure?.chipColorHex == "#1B3A66")
        _ = doc.setColorEnabled(layerIDs: [layer.id], slot: .chipFill, on: true)
        #expect(doc.layer(id: layer.id)?.measure?.chipColorHex == "#1B3A66")
        #expect((doc.layer(id: layer.id)?.measure?.chipOpacity ?? 0) > 0)
    }

    @Test func switchingTheChipsEdgeOffAndBackOnBringsBackTheCalipersThickness() {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 400, height: 300))
        let layer = measureLayer(measure(stroke: "#FF3B30", width: 3))
        doc.layers.append(layer)
        _ = doc.setColorEnabled(layerIDs: [layer.id], slot: .chipBorder, on: false)
        #expect(doc.layer(id: layer.id)?.measure?.chipBorderWidth == 0)
        #expect(doc.layer(id: layer.id)?.colorHex(for: .chipBorder) == nil)
        _ = doc.setColorEnabled(layerIDs: [layer.id], slot: .chipBorder, on: true)
        #expect(doc.layer(id: layer.id)?.measure?.chipBorderWidth == 3)
        #expect(doc.layer(id: layer.id)?.colorHex(for: .chipBorder) == "#FF3B30")
    }
}

@Suite("A chip says when its number will be hard to find")
struct MeasureChipLegibilityTests {

    @Test func aChipWithNoFillSaysTheNumberIsOnThePicture() {
        var content = measure()
        content.chipOpacity = 0
        #expect(content.chipLegibilityNote?.contains("straight on the picture") == true)
    }

    @Test func aChipWhoseNumberDisappearsIntoItsFillSaysSo() {
        var content = measure()
        content.chipColorHex = "#FFFFFF"
        content.chipOpacity = 1
        content.textColorHex = "#FFFFFF"
        #expect(content.chipLegibilityNote == "This number will be hard to read on this fill.")
    }

    @Test func theShippedPairSaysNothingAtAll() {
        var content = measure()
        content.chipColorHex = "#8C201A"
        content.chipOpacity = 1
        content.textColorHex = "#FFFFFF"
        #expect(content.chipLegibilityNote == nil)
    }

    @Test func aMeasurementWithNoReadoutSaysNothing() {
        var content = measure()
        content.showLabel = false
        content.chipOpacity = 0
        #expect(content.chipLegibilityNote == nil)
    }
}

@Suite("A measurement's rows in Appearance")
struct MeasurePartRowTests {

    private func document(_ content: MeasureContent = measure()) -> (PhotonzDocument, UUID) {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 400, height: 300))
        let layer = measureLayer(content)
        doc.layers.append(layer)
        return (doc, layer.id)
    }

    @Test func appearanceListsTheCaliperAndTheChipsThree() {
        let (doc, id) = document()
        let rows = doc.layerPartRows(layerIDs: [id])
        #expect(rows.map(\.title) == ["Caliper", "Chip Fill", "Chip Edge", "Chip Text"])
    }

    @Test func theCaliperHasNoSwitchBecauseAMeasurementIsItsCaliper() {
        let (doc, id) = document()
        let rows = doc.layerPartRows(layerIDs: [id])
        #expect(rows.first?.hasSwitch == false)
        #expect(rows.first?.showsSettings == true)
    }

    @Test func theChipsFillAndEdgeSwitchAndItsWordsDoNot() {
        let (doc, id) = document()
        let rows = doc.layerPartRows(layerIDs: [id])
        let switched = rows.filter(\.hasSwitch).map(\.title)
        #expect(switched == ["Chip Fill", "Chip Edge"])
    }

    @Test func aMeasurementWithItsReadoutHiddenShowsNoChipRows() {
        var content = measure()
        content.showLabel = false
        let (doc, id) = document(content)
        #expect(doc.layerPartRows(layerIDs: [id]).map(\.title) == ["Caliper"])
    }

    @Test func aChipEdgeSwitchedOffLeavesItsRowWithNothingToSet() {
        var content = measure()
        content.chipBorderWidth = 0
        let (doc, id) = document(content)
        let edge = doc.layerPartRows(layerIDs: [id]).first { $0.title == "Chip Edge" }
        #expect(edge?.isOn == false)
        #expect(edge?.showsSettings == false)
    }

    @Test func lettingAColourGoOnASwitchedOffChipEdgeGivesItBothAtOnce() {
        var content = measure()
        content.chipBorderWidth = 0
        var (doc, id) = document(content)
        doc.turnOnPart(.chipBorder, layerIDs: [id], paint: Paint(hex: "#34C759"))
        #expect(doc.layer(id: id)?.measure?.chipBorderColorHex == "#34C759")
        #expect((doc.layer(id: id)?.measure?.chipBorderWidth ?? 0) > 0)
    }

    @Test func aMeasurementAndABoxPickedTogetherKeepTheirOwnRows() {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 400, height: 300))
        let box = Layer(name: "Box",
                        content: .annotation(AnnotationContent(shape: .rectangle,
                                                               fillColorHex: "#FFFFFF")),
                        frame: CGRect(x: 0, y: 0, width: 50, height: 50))
        let caliper = measureLayer(measure())
        doc.layers.append(box)
        doc.layers.append(caliper)
        let rows = doc.layerPartRows(layerIDs: [box.id, caliper.id])
        let fill = rows.first { $0.title == "Fill" }
        #expect(fill?.colors.first?.layerIDs == [box.id])
        let caliperRow = rows.first { $0.title == "Caliper" }
        #expect(caliperRow?.colors.first?.layerIDs == [caliper.id])
    }
}

@Suite("A measurement's remembered colours know about its chip edge")
struct MeasureChipEdgeStyleTests {

    @Test func theShippedSetsRingTheChipInTheirOwnInk() {
        #expect(MeasureRoleColors.sizeDefault.chipBorderColorHex == "#FF3B30")
        #expect(MeasureRoleColors.spacingDefault.chipBorderColorHex == "#0A84FF")
    }

    @Test func aRememberedSetFromBeforeTheEdgeExistedRingsItInItsInk() throws {
        let json = """
        {"strokeColorHex":"#0A84FF","chipColorHex":"#1B3A66",
         "chipOpacity":1,"textColorHex":"#FFFFFF"}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(MeasureRoleColors.self, from: json)
        #expect(decoded.chipBorderColorHex == "#0A84FF")
    }

    @Test func aNewCaliperTakesTheRolesRememberedEdge() {
        var styles = MeasureStyles()
        styles.updateColors(for: .size) { $0.chipBorderColorHex = "#34C759" }
        #expect(styles.content(for: .size).chipBorderColorHex == "#34C759")
    }

    @Test func stylingAMeasurementRemembersItsEdgeForTheNextOne() {
        var styles = MeasureStyles()
        var content = measure()
        content.chipBorderColorHex = "#34C759"
        content.chipBorderWidth = 4
        styles.absorb(content)
        #expect(styles.colors(for: content.role).chipBorderColorHex == "#34C759")
        #expect(styles.chipBorderWidth == 4)
    }
}

@Suite("The paint bucket still means make this thing this colour")
struct MeasureBucketTests {

    @Test func theBucketTakesTheChipsRingWithTheCaliper() {
        var content = measure(stroke: "#FF3B30")
        content.chipColorHex = "#8C201A"
        let layer = measureLayer(content)
        let filled = Fill.filled(layer, colorHex: "#0A84FF", solidRef: nil)
        #expect(filled?.measure?.strokeColorHex == "#0A84FF")
        #expect(filled?.measure?.chipBorderColorHex == "#0A84FF")
        // ...and leaves the chip's own fill alone, exactly as it always has.
        #expect(filled?.measure?.chipColorHex == "#8C201A")
    }
}
