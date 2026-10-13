import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// A Size measurement is one group: a faint box over the measured area, the
/// width caliper and the height caliper (the user, 2026-10-13: "I'd like the
/// size tool to be one layer group but can be expanded to modify the 3 parts").
@Suite("MeasureSizeGroup")
struct MeasureSizeGroupTests {

    // MARK: - Fixtures

    /// The two calipers Size mode puts round `rect`, the way the app builds
    /// them: width along the bottom edge, height up the right one.
    private func calipers(round rect: CGRect, unit: MeasureUnit = .pixels) -> (Layer, Layer) {
        var template = MeasureContent(role: .size)
        template.unit = unit
        var width = template
        width.mode = .horizontal
        var height = template
        height.mode = .vertical
        return (MeasureBuilder.layer(content: width, from: CGPoint(x: rect.minX, y: rect.maxY),
                                     to: CGPoint(x: rect.maxX, y: rect.maxY)),
                MeasureBuilder.layer(content: height, from: CGPoint(x: rect.maxX, y: rect.minY),
                                     to: CGPoint(x: rect.maxX, y: rect.maxY)))
    }

    private func sizeGroup(round rect: CGRect, unit: MeasureUnit = .pixels,
                           pixelScale: CGFloat = 1) -> Layer {
        let (width, height) = calipers(round: rect, unit: unit)
        return MeasureSizeGroup.group(measuring: rect, width: width, height: height,
                                      boxColorHex: "#FF3B30", boxOpacity: 0.1,
                                      pixelScale: pixelScale)
    }

    // MARK: - What the group holds

    @Test func theGroupHoldsABoxAWidthAndAHeight() throws {
        let rect = CGRect(x: 100, y: 200, width: 320, height: 48)
        let group = sizeGroup(round: rect)
        #expect(group.isGroup)
        #expect(group.isSizeMeasurement)
        #expect(group.isMeasurement)
        #expect(group.children.map(\.name) == ["Box", "Width", "Height"])
        #expect(group.children.compactMap(\.measure).map(\.mode) == [.horizontal, .vertical])
        #expect(MeasureSizeGroup.calipers(of: group).count == 2)
        #expect(MeasureSizeGroup.box(of: group)?.annotation?.shape == .rectangle)
    }

    /// The box sits exactly over what was measured, wherever the group's own
    /// anchor ends up, and nothing in it moves on screen for being grouped.
    @Test func theBoxSitsExactlyOverTheMeasuredArea() throws {
        let rect = CGRect(x: 100, y: 200, width: 320, height: 48)
        var doc = PhotonzDocument(canvasSize: CGSize(width: 800, height: 600))
        let (width, height) = calipers(round: rect)
        let group = MeasureSizeGroup.group(measuring: rect, width: width, height: height,
                                           boxColorHex: "#FF3B30", boxOpacity: 0.1,
                                           pixelScale: 1)
        doc.addLayer(group)
        let box = try #require(MeasureSizeGroup.box(of: group))
        #expect(doc.canvasLayer(id: box.id)?.frame == rect)
        #expect(doc.canvasLayer(id: width.id)?.frame == width.frame)
        #expect(doc.canvasLayer(id: height.id)?.frame == height.frame)
    }

    /// No outline, a fill in the colour asked for, and the faintness on the
    /// box's own Opacity so the panel's Opacity row reads 10% and the Fill
    /// swatch reads plainly as the colour.
    @Test func theBoxIsAFaintFillWithNoOutline() throws {
        let group = sizeGroup(round: CGRect(x: 10, y: 10, width: 50, height: 20))
        let box = try #require(MeasureSizeGroup.box(of: group))
        let shape = try #require(box.annotation)
        #expect(shape.strokeWidth == 0)
        #expect(shape.fill?.hex == "#FF3B30")
        #expect(box.style.opacity == 0.1)
        #expect(box.style.effects.isEmpty)
        #expect(box.name == "Box")
    }

    // MARK: - Its name

    @Test func theGroupIsNamedForWhatItMeasures() {
        let group = sizeGroup(round: CGRect(x: 0, y: 0, width: 320, height: 48))
        #expect(group.name == "Size 320 × 48")
    }

    /// The numbers are the ones the calipers show: on a 2x capture measured in
    /// points they are half the pixels.
    @Test func theNameUsesTheCalipersOwnUnit() {
        let group = sizeGroup(round: CGRect(x: 0, y: 0, width: 640, height: 96),
                              unit: .points, pixelScale: 2)
        #expect(group.name == "Size 320 × 48")
    }

    @Test func theValueCarriesBothNumbersAndTheUnit() {
        let group = sizeGroup(round: CGRect(x: 0, y: 0, width: 320, height: 48))
        #expect(MeasureSizeGroup.valueText(of: group, pixelScale: 1) == "320 × 48 px")
    }

    @Test func automaticNamesAreToldApartFromChosenOnes() {
        #expect(MeasureSizeGroup.isAutomaticName("Size 320 × 48"))
        #expect(MeasureSizeGroup.isAutomaticName("Size 12.5 × 4"))
        #expect(!MeasureSizeGroup.isAutomaticName("Save button"))
        #expect(!MeasureSizeGroup.isAutomaticName("Size"))
    }

    /// Dragging a caliper's foot changes what it reads, and the group's name
    /// follows, in the same step.
    @Test func theNameFollowsWhenAPartIsEdited() throws {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 800, height: 600))
        let group = sizeGroup(round: CGRect(x: 0, y: 0, width: 320, height: 48))
        doc.addLayer(group)
        let before = doc
        let width = MeasureSizeGroup.calipers(of: group)[0]
        doc.updateLayer(id: width.id) { layer in
            layer.content = .measure({
                var m = layer.measure!
                m.end.x = m.start.x + 300
                return m
            }())
        }
        doc.keepSizeMeasureNamesInStep(since: before)
        #expect(doc.layer(id: group.id)?.name == "Size 300 × 48")
    }

    /// A name somebody chose stays what they chose.
    @Test func aChosenNameIsKept() throws {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 800, height: 600))
        var group = sizeGroup(round: CGRect(x: 0, y: 0, width: 320, height: 48))
        group.name = "Save button"
        doc.addLayer(group)
        let before = doc
        let width = MeasureSizeGroup.calipers(of: group)[0]
        doc.updateLayer(id: width.id) { layer in
            layer.content = .measure({
                var m = layer.measure!
                m.end.x = m.start.x + 300
                return m
            }())
        }
        doc.keepSizeMeasureNamesInStep(since: before)
        #expect(doc.layer(id: group.id)?.name == "Save button")
    }

    /// Renaming the group in the very edit that is being kept in step is the
    /// rename winning, even when the new name happens to look automatic.
    @Test func aRenameInTheSameEditWins() throws {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 800, height: 600))
        let group = sizeGroup(round: CGRect(x: 0, y: 0, width: 320, height: 48))
        doc.addLayer(group)
        let before = doc
        doc.updateLayer(id: group.id) { $0.name = "Size 1 × 1" }
        doc.keepSizeMeasureNamesInStep(since: before)
        #expect(doc.layer(id: group.id)?.name == "Size 1 × 1")
    }

    // MARK: - Saved and opened

    @Test func theGroupSurvivesASaveAndOpen() throws {
        let group = sizeGroup(round: CGRect(x: 0, y: 0, width: 320, height: 48))
        let data = try JSONEncoder().encode(group)
        let back = try JSONDecoder().decode(Layer.self, from: data)
        #expect(back.isSizeMeasurement)
        #expect(back == group)
    }

    /// An ordinary group writes nothing new, so a document saved before this
    /// existed is byte for byte what it was.
    @Test func anOrdinaryGroupWritesNoNewKey() throws {
        let content = GroupContent(children: [])
        let json = String(decoding: try JSONEncoder().encode(content), as: UTF8.self)
        #expect(!json.contains("measuresSize"))
    }

    // MARK: - The Measurements panel and the spec list

    @Test func thePanelListsTheGroupAsOneSizeEntry() {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 800, height: 600))
        let group = sizeGroup(round: CGRect(x: 0, y: 0, width: 320, height: 48))
        doc.addLayer(group)
        let rows = MeasureSpecList.measureLayers(in: doc)
        #expect(rows.map(\.id) == [group.id])
        #expect(MeasureSpecList.displayName(for: group) == "Size")
        #expect(MeasureSpecList.rowValue(for: group, pixelScale: 1) == "320 × 48 px")
        #expect(MeasureSpecList.swatchContent(for: group)?.role == .size)
    }

    @Test func aRenamedGroupShowsItsName() {
        var group = sizeGroup(round: CGRect(x: 0, y: 0, width: 320, height: 48))
        group.name = "Save button"
        #expect(MeasureSpecList.displayName(for: group) == "Save button")
    }

    /// Copy as Spec List still gives a Width line and a Height line, as it did
    /// when the two calipers were loose.
    @Test func theSpecListStillSaysWidthAndHeight() {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 800, height: 600))
        let group = sizeGroup(round: CGRect(x: 0, y: 0, width: 320, height: 48))
        doc.addLayer(group)
        let text = MeasureSpecList.render(document: doc, name: "Shot")
        #expect(text == """
            Shot · 800 × 600 px
            - Width: 320 px (size)
            - Height: 48 px (size)
            """)
        #expect(MeasureSpecList.render(document: doc, ids: [group.id]) == """
            - Width: 320 px (size)
            - Height: 48 px (size)
            """)
        #expect(MeasureSpecList.specLines(for: group, in: doc) == [
            "- Width: 320 px (size)", "- Height: 48 px (size)",
        ])
    }

    @Test func aHiddenGroupIsLeftOutOfTheSpecList() {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 800, height: 600))
        var group = sizeGroup(round: CGRect(x: 0, y: 0, width: 320, height: 48))
        group.isVisible = false
        doc.addLayer(group)
        #expect(MeasureSpecList.render(document: doc, name: "Shot") == "Shot · 800 × 600 px")
    }

    // MARK: - What else reads measurements

    /// Size mode's element reader never offers the box as a thing to measure:
    /// it is part of a measurement, not part of the picture.
    @Test func theBoxIsNotAnElementToMeasure() {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 800, height: 600))
        doc.addLayer(sizeGroup(round: CGRect(x: 100, y: 100, width: 320, height: 48)))
        #expect(LayerElements.boxes(in: doc).isEmpty)
    }

    /// Readouts dodge every caliper on the canvas, the ones inside a size
    /// group included, in canvas space.
    @Test func everyCaliperIsFoundInCanvasSpace() {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 800, height: 600))
        let rect = CGRect(x: 100, y: 100, width: 320, height: 48)
        let (width, height) = calipers(round: rect)
        doc.addLayer(MeasureSizeGroup.group(measuring: rect, width: width, height: height,
                                            boxColorHex: "#FF3B30", boxOpacity: 0.1,
                                            pixelScale: 1))
        let found = doc.canvasMeasureLayers
        #expect(found.map(\.id) == [width.id, height.id])
        #expect(found.map(\.frame) == [width.frame, height.frame])
    }

    @Test func theBoxIsKnownAsASizeBox() throws {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 800, height: 600))
        let group = sizeGroup(round: CGRect(x: 0, y: 0, width: 320, height: 48))
        doc.addLayer(group)
        let box = try #require(MeasureSizeGroup.box(of: group))
        #expect(doc.isSizeMeasureBox(box.id))
        #expect(!doc.isSizeMeasureBox(group.id))
    }

    // MARK: - What new measurements start with

    @Test func newBoxesStartFaintInTheMeasureInk() {
        let styles = MeasureStyles()
        #expect(styles.sizeBoxOpacity == 0.1)
        #expect(styles.sizeBoxColorHex == styles.colors.strokeColorHex)
        #expect(styles.sizeBoxColorHex == MeasureColors.standard.strokeColorHex)
    }

    /// Until somebody picks a box colour of its own, the box follows the
    /// calipers' ink, so retuning a caliper retunes the box with it.
    @Test func theBoxFollowsTheCalipersUntilGivenAColourOfItsOwn() {
        var styles = MeasureStyles()
        styles.colors.strokeColorHex = "#00FF00"
        #expect(styles.sizeBoxColorHex == "#00FF00")
        styles.sizeBoxColorHex = "#123456"
        styles.colors.strokeColorHex = "#FF0000"
        #expect(styles.sizeBoxColorHex == "#123456")
    }

    @Test func aBoxPickIsRememberedAcrossALaunch() throws {
        var styles = MeasureStyles()
        styles.sizeBoxColorHex = "#123456"
        styles.sizeBoxOpacity = 0.25
        let back = try JSONDecoder().decode(MeasureStyles.self,
                                            from: try JSONEncoder().encode(styles))
        #expect(back.sizeBoxColorHex == "#123456")
        #expect(back.sizeBoxOpacity == 0.25)
    }

    /// A remembered style written before the box existed opens with the box's
    /// defaults rather than losing everything else it remembered.
    @Test func anOlderMemoryOpensWithTheBoxDefaults() throws {
        let old = #"{"role":"size","strokeWidth":3}"#
        let styles = try JSONDecoder().decode(MeasureStyles.self, from: Data(old.utf8))
        #expect(styles.strokeWidth == 3)
        #expect(styles.sizeBoxOpacity == 0.1)
        #expect(styles.sizeBoxColorHex == styles.colors.strokeColorHex)
    }

    // MARK: - What the panel offers

    /// A measurement has nothing to arrange: picking the group or one of its
    /// parts offers no Arrangement, Hug or Fixed rows, and no rows about where
    /// a part sits when the group is resized.
    @Test func aSizeMeasurementOffersNothingToArrange() throws {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 800, height: 600))
        let group = sizeGroup(round: CGRect(x: 0, y: 0, width: 320, height: 48))
        doc.addLayer(group)
        let box = try #require(MeasureSizeGroup.box(of: group))
        #expect(!doc.contentsSelection(layerIDs: [group.id]).isPresent)
        #expect(!doc.placementSelection(layerIDs: [box.id]).isPresent)
    }
}

