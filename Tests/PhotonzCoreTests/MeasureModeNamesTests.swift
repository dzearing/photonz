import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// A measurement is named for the mode that made it, and every caliper offers
/// the same look whichever mode made it (the user, 2026-10-13: "when I measure
/// with size, the layer should be size. when i measure with gap, the layer
/// should be gap... makes no sense why i click on a size caliper and can't
/// change the color").
@Suite("Measure mode names")
struct MeasureModeNamesTests {

    // MARK: - Fixtures

    /// A horizontal caliper `length` long, made by `mode`, in `role`.
    private func caliper(_ mode: MeasureToolMode?, length: CGFloat = 16,
                         role: MeasureRole = .size, axis: MeasureMode = .horizontal,
                         unit: MeasureUnit = .pixels) -> Layer {
        var content = MeasureContent(mode: axis, unit: unit, role: role)
        content.madeBy = mode
        let end = axis == .horizontal ? CGPoint(x: 100 + length, y: 100)
            : CGPoint(x: 100, y: 100 + length)
        return MeasureBuilder.layer(content: content, from: CGPoint(x: 100, y: 100), to: end)
    }

    private func sizeGroup(round rect: CGRect) -> Layer {
        var template = MeasureContent(role: .size)
        template.madeBy = .size
        var width = template
        width.mode = .horizontal
        var height = template
        height.mode = .vertical
        let w = MeasureBuilder.layer(content: width, from: CGPoint(x: rect.minX, y: rect.maxY),
                                     to: CGPoint(x: rect.maxX, y: rect.maxY))
        let h = MeasureBuilder.layer(content: height, from: CGPoint(x: rect.maxX, y: rect.minY),
                                     to: CGPoint(x: rect.maxX, y: rect.maxY))
        return MeasureSizeGroup.group(measuring: rect, width: w, height: h,
                                      boxColorHex: "#FF3B30", boxOpacity: 0.1, pixelScale: 1)
    }

    private func document(_ layers: [Layer], pixelScale: CGFloat = 1) -> PhotonzDocument {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 800, height: 600))
        doc.pixelScale = pixelScale
        for layer in layers { doc.addLayer(layer) }
        return doc
    }

    // MARK: - The word a mode gives

    /// The mode decides the word, not the role: a Distance caliper in the Size
    /// role was listed as "Width" and in the Spacing role as "Gap".
    @Test func theModeNamesTheMeasurementWhateverItsRole() {
        #expect(MeasureSpecList.derivedName(for: caliper(.gap, role: .size).measure!) == "Gap")
        #expect(MeasureSpecList.derivedName(for: caliper(.gap, role: .spacing).measure!) == "Gap")
        #expect(MeasureSpecList.derivedName(for: caliper(.distance, role: .size).measure!) == "Distance")
        #expect(MeasureSpecList.derivedName(for: caliper(.distance, role: .spacing).measure!) == "Distance")
        #expect(MeasureSpecList.derivedName(for: caliper(.size, role: .spacing).measure!) == "Width")
        #expect(MeasureSpecList.derivedName(
            for: caliper(.size, role: .spacing, axis: .vertical).measure!) == "Height")
    }

    /// A measurement saved before it knew its mode keeps the name it had.
    @Test func aMeasurementWithNoModeIsNamedAsBefore() {
        #expect(MeasureSpecList.derivedName(for: caliper(nil, role: .size).measure!) == "Width")
        #expect(MeasureSpecList.derivedName(for: caliper(nil, role: .spacing).measure!) == "Gap")
    }

    // MARK: - The layer's own name

    @Test func aGapAndADistanceAreNamedForTheirModeAndReading() {
        let gap = caliper(.gap, length: 16).measure!
        let distance = caliper(.distance, length: 240).measure!
        #expect(MeasureNaming.automaticName(for: gap, pixelScale: 1) == "Gap 16")
        #expect(MeasureNaming.automaticName(for: distance, pixelScale: 1) == "Distance 240")
    }

    /// The number is in the caliper's own unit: a Logical reading on a 2x
    /// screenshot is half the bitmap's pixels.
    @Test func theNumberIsInTheMeasurementsUnit() {
        let logical = caliper(.gap, length: 32, unit: .points).measure!
        #expect(MeasureNaming.automaticName(for: logical, pixelScale: 2) == "Gap 16")
        let actual = caliper(.gap, length: 32, unit: .pixels).measure!
        #expect(MeasureNaming.automaticName(for: actual, pixelScale: 2) == "Gap 32")
    }

    @Test func aSizeCaliperIsItsAxisAndAnUnknownModeHasNoAutomaticName() {
        #expect(MeasureNaming.automaticName(for: caliper(.size).measure!, pixelScale: 1) == "Width")
        #expect(MeasureNaming.automaticName(
            for: caliper(.size, axis: .vertical).measure!, pixelScale: 1) == "Height")
        #expect(MeasureNaming.automaticName(for: caliper(nil).measure!, pixelScale: 1) == nil)
    }

    @Test func automaticNamesAreToldApartFromChosenOnes() {
        let gap = caliper(.gap).measure!
        #expect(MeasureNaming.isAutomaticName("Measure", for: gap))
        #expect(MeasureNaming.isAutomaticName("Gap", for: gap))
        #expect(MeasureNaming.isAutomaticName("Gap 16", for: gap))
        #expect(MeasureNaming.isAutomaticName("Gap 12.5", for: gap))
        #expect(!MeasureNaming.isAutomaticName("Gap above the title", for: gap))
        #expect(!MeasureNaming.isAutomaticName("Distance 16", for: gap))
        #expect(!MeasureNaming.isAutomaticName("Card padding", for: gap))
    }

    // MARK: - Kept in step

    /// A fresh caliper lands named "Measure"; the step that adds it names it.
    @Test func aNewGapIsNamedInTheStepThatAddsIt() throws {
        let gap = caliper(.gap, length: 16)
        let before = document([])
        var after = before
        after.addLayer(gap)
        after.keepMeasureNamesInStep(since: before)
        #expect(after.layer(id: gap.id)?.name == "Gap 16")
    }

    /// Dragging a foot renames it in the same step.
    @Test func aChangedReadingRenamesIt() throws {
        let gap = caliper(.gap, length: 16)
        var before = document([gap])
        before.keepMeasureNamesInStep(since: nil)
        var after = before
        after.updateLayer(id: gap.id) {
            $0 = MeasureBuilder.updating($0, start: CGPoint(x: 100, y: 100),
                                         end: CGPoint(x: 124, y: 100))
        }
        after.keepMeasureNamesInStep(since: before)
        #expect(after.layer(id: gap.id)?.name == "Gap 24")
    }

    /// A name somebody chose is never touched, and neither is a name changed
    /// by the very edit being finished.
    @Test func aChosenNameIsKept() throws {
        var gap = caliper(.distance, length: 16)
        gap.name = "Card padding"
        let before = document([gap])
        var after = before
        after.updateLayer(id: gap.id) {
            $0 = MeasureBuilder.updating($0, start: CGPoint(x: 100, y: 100),
                                         end: CGPoint(x: 124, y: 100))
        }
        after.keepMeasureNamesInStep(since: before)
        #expect(after.layer(id: gap.id)?.name == "Card padding")

        var renamed = after
        renamed.updateLayer(id: gap.id) { $0.name = "Gap 3" }
        renamed.keepMeasureNamesInStep(since: after)
        #expect(renamed.layer(id: gap.id)?.name == "Gap 3")
    }

    /// Old documents, Current's calipers and alignment guides keep their names.
    @Test func aMeasurementWithNoModeKeepsItsName() throws {
        let old = caliper(nil, length: 16)
        let before = document([])
        var after = before
        after.addLayer(old)
        after.keepMeasureNamesInStep(since: before)
        #expect(after.layer(id: old.id)?.name == MeasureBuilder.defaultName)
    }

    /// Size groups are still named the way they were, in the same pass.
    @Test func aSizeGroupIsStillKeptInStep() throws {
        let group = sizeGroup(round: CGRect(x: 100, y: 100, width: 120, height: 30))
        let before = document([])
        var after = before
        after.addLayer(group)
        after.keepMeasureNamesInStep(since: before)
        #expect(after.layer(id: group.id)?.name == "Size 120 × 30")
        #expect(after.layer(id: group.id)?.children.map(\.name) == ["Box", "Width", "Height"])
    }

    // MARK: - What the Measurements list and spec list say

    @Test func theMeasurementsRowSaysTheWordAndTheSpecLineReadsTheSame() throws {
        var doc = document([caliper(.gap, length: 16), caliper(.distance, length: 240)])
        doc.keepMeasureNamesInStep(since: nil)
        let rows = MeasureSpecList.measureLayers(in: doc)
        #expect(Set(rows.map { $0.name }) == ["Gap 16", "Distance 240"])
        #expect(Set(rows.map { MeasureSpecList.displayName(for: $0) }) == ["Gap", "Distance"])
        let lines = rows.compactMap { MeasureSpecList.specLine(for: $0, in: doc) }
        #expect(lines.contains("- Gap: 16 px (size)"))
        #expect(lines.contains("- Distance: 240 px (size)"))
    }

    // MARK: - Codable

    @Test func theModeSurvivesSavingAndAnOldDocumentHasNone() throws {
        let content = caliper(.gap).measure!
        let data = try JSONEncoder().encode(content)
        let back = try JSONDecoder().decode(MeasureContent.self, from: data)
        #expect(back.madeBy == .gap)

        let old = caliper(nil).measure!
        let oldData = try JSONEncoder().encode(old)
        let json = try #require(String(data: oldData, encoding: .utf8))
        #expect(!json.contains("madeBy"))
        #expect(try JSONDecoder().decode(MeasureContent.self, from: oldData).madeBy == nil)
    }

    // MARK: - One look for every caliper

    /// Appearance reads a picked Size measurement as its two calipers, so the
    /// Caliper and Chip rows are there exactly as for any other caliper.
    @Test func aPickedSizeGroupIsReadAsItsCalipers() throws {
        let group = sizeGroup(round: CGRect(x: 100, y: 100, width: 120, height: 30))
        let gap = caliper(.gap)
        let doc = document([group, gap])
        let calipers = MeasureSizeGroup.calipers(of: group).map(\.id)
        #expect(doc.measureLookIDs([group.id]) == calipers)
        #expect(doc.measureLookIDs([group.id, gap.id]) == calipers + [gap.id])
        #expect(doc.measureLookIDs([gap.id]) == [gap.id])
        // A caliper picked inside the group is itself, once.
        #expect(doc.measureLookIDs([calipers[0], group.id]) == calipers)
    }

    @Test func aSizeGroupsCaliperRowsMatchALooseCalipers() throws {
        let group = sizeGroup(round: CGRect(x: 100, y: 100, width: 120, height: 30))
        let gap = caliper(.gap)
        let doc = document([group, gap])
        let titles = { (ids: [UUID]) in doc.layerPartRows(layerIDs: doc.measureLookIDs(ids)).map(\.title) }
        #expect(!titles([group.id]).isEmpty)
        #expect(titles([group.id]) == titles([gap.id]))
        #expect(titles([group.id, gap.id]) == titles([gap.id]))
    }

    /// Lining a caliper up inside its own Size measurement means nothing: the
    /// parts sit where they measured.
    @Test func aSizeMeasurementsPartsHaveNothingToArrangeAgainst() throws {
        let group = sizeGroup(round: CGRect(x: 100, y: 100, width: 120, height: 30))
        let doc = document([group])
        for part in group.children {
            #expect(doc.arrangeContainer(of: part.id) == nil)
        }
    }

    /// A Size measurement offers no Masked by, the way a caliper never has, so
    /// its Caliper row lands where a caliper's does.
    @Test func aSizeMeasurementIsNeverMasked() throws {
        let group = sizeGroup(round: CGRect(x: 100, y: 100, width: 120, height: 30))
        #expect(!group.canBeMasked)
        #expect(!caliper(.gap).canBeMasked)
    }
}
