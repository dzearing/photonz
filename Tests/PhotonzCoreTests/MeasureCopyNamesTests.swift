import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// A copied measurement is named for what it measures, the way a fresh one
/// is, so its name keeps following its numbers. Copying a Size measurement
/// used to name it "Size 274 × 62 copy", a name that no longer looked like
/// the app's, and resizing the copy then left it saying the old size.
@Suite("Measure copy names")
struct MeasureCopyNamesTests {

    // MARK: - Fixtures

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

    private func gap(length: CGFloat = 16) -> Layer {
        var content = MeasureContent(mode: .horizontal, unit: .pixels, role: .size)
        content.madeBy = .gap
        return MeasureBuilder.layer(content: content, from: CGPoint(x: 100, y: 100),
                                    to: CGPoint(x: 100 + length, y: 100))
    }

    /// The document holding `layers`, every name already brought into step.
    private func document(_ layers: [Layer]) -> PhotonzDocument {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 800, height: 600))
        for layer in layers { doc.addLayer(layer) }
        doc.keepMeasureNamesInStep(since: nil)
        return doc
    }

    // MARK: - Duplicate and ⌥-drag

    @Test func aDuplicatedSizeMeasurementIsNamedForItsSize() throws {
        let group = sizeGroup(round: CGRect(x: 100, y: 100, width: 274, height: 62))
        var doc = document([group])
        #expect(doc.layer(id: group.id)?.name == "Size 274 × 62")
        let copy = try #require(doc.duplicateLayers(ids: [group.id]).first)
        #expect(copy.name == "Size 274 × 62")
    }

    @Test func anOptionDraggedSizeMeasurementIsNamedForItsSize() throws {
        let group = sizeGroup(round: CGRect(x: 100, y: 100, width: 274, height: 62))
        var doc = document([group])
        let ids = doc.duplicateLayers(movingCopiesTo: [group.id: CGPoint(x: 300, y: 300)])
        let id = try #require(ids.first)
        #expect(doc.layer(id: id)?.name == "Size 274 × 62")
    }

    /// The copy's name keeps following it: resizing it renames it in the
    /// same step, and the original keeps its own.
    @Test func resizingTheCopyRenamesIt() throws {
        let group = sizeGroup(round: CGRect(x: 100, y: 100, width: 274, height: 62))
        var doc = document([group])
        let ids = doc.duplicateLayers(movingCopiesTo: [group.id: CGPoint(x: 300, y: 300)])
        doc.keepMeasureNamesInStep(since: nil)
        let id = try #require(ids.first)
        let before = doc
        let copy = try #require(doc.layer(id: id))
        let resized = MeasureSizeGroup.resized(copy, toBox: CGRect(x: 300, y: 300, width: 200, height: 40))
        doc.updateLayer(id: id) { $0 = resized }
        doc.keepMeasureNamesInStep(since: before)
        #expect(doc.layer(id: id)?.name == "Size 200 × 40")
        #expect(doc.layer(id: group.id)?.name == "Size 274 × 62")
    }

    /// A name somebody chose is still theirs, and the copy says it is a copy.
    @Test func aChosenNameStillGainsCopy() throws {
        var group = sizeGroup(round: CGRect(x: 100, y: 100, width: 274, height: 62))
        group.name = "Save button"
        var doc = document([group])
        let copy = try #require(doc.duplicateLayers(ids: [group.id]).first)
        #expect(copy.name == "Save button copy")
    }

    @Test func aDuplicatedGapIsNamedForItsReading() throws {
        let caliper = gap()
        var doc = document([caliper])
        #expect(doc.layer(id: caliper.id)?.name == "Gap 16")
        let copy = try #require(doc.duplicateLayers(ids: [caliper.id]).first)
        #expect(copy.name == "Gap 16")
    }

    // MARK: - Copy and paste

    @Test func aPastedSizeMeasurementIsNamedForItsSize() throws {
        let group = sizeGroup(round: CGRect(x: 100, y: 100, width: 274, height: 62))
        let doc = document([group])
        let source = try #require(doc.layer(id: group.id))
        let taken = Set(doc.allLayers.map(\.name))
        #expect(LayerNaming.pastedName(of: source, taken: taken) == "Size 274 × 62")
        var chosen = source
        chosen.name = "Save button"
        #expect(LayerNaming.pastedName(of: chosen, taken: taken.union(["Save button"]))
            == "Save button copy")
    }
}
