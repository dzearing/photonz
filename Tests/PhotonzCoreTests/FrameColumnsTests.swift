import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// A screen's column overlay: the numbers it holds, the bands they describe,
/// and the promise that a document with none of them is what it always was.
///
/// Not the canvas grid. That one covers the whole canvas, is set by a spacing,
/// belongs to the view rather than the document, and never pulls at a drag
/// (`CanvasGridTests`). This one belongs to one screen.
@Suite("Frame columns")
struct FrameColumnsTests {

    private func leaf(_ name: String, _ frame: CGRect) -> Layer {
        Layer(name: name, content: .text(TextContent(string: name)), frame: frame)
    }

    // MARK: The numbers

    @Test("A column count below one is not a layout")
    func countIsClamped() {
        #expect(FrameColumns(count: 0).count == 1)
        #expect(FrameColumns(count: -4).count == 1)
        #expect(FrameColumns(count: 1000).count == FrameColumns.countRange.upperBound)
    }

    @Test("A gutter and a margin are whole points and never negative")
    func spacingIsClamped() {
        #expect(FrameColumns(gutter: -8).gutter == 0)
        #expect(FrameColumns(gutter: 23.6).gutter == 24)
        #expect(FrameColumns(margin: -1).margin == 0)
        #expect(FrameColumns(margin: 31.4).margin == 31)
    }

    @Test("A number that is not a number falls back rather than drawing nothing")
    func nonFiniteFallsBack() {
        #expect(FrameColumns(gutter: .nan).gutter == FrameColumns.defaultGutter)
        #expect(FrameColumns(margin: .infinity).margin == FrameColumns.defaultMargin)
    }

    @Test("A phone gets four columns, anything wider gets twelve")
    func suggestedFollowsTheScreen() {
        let phone = FrameColumns.suggested(forWidth: 390)
        #expect(phone.count == 4)
        #expect(phone.gutter == 16)
        #expect(phone.margin == 16)

        let desktop = FrameColumns.suggested(forWidth: 1440)
        #expect(desktop.count == 12)
        #expect(desktop.gutter == 24)
        #expect(desktop.margin == 32)

        // And it arrives switched on: it is what you asked for.
        #expect(phone.isVisible)
        #expect(desktop.isVisible)
    }

    // MARK: The bands

    @Test("Four even columns land exactly where the arithmetic says")
    func evenBands() {
        let columns = FrameColumns(count: 4, gutter: 20, margin: 20)
        // 400 wide, 40 of margin, 60 of gutter, 300 over four columns = 75.
        let bands = columns.bands(inWidth: 400)
        #expect(bands.count == 4)
        #expect(bands[0] == FrameColumns.Band(start: 20, end: 95))
        #expect(bands[1] == FrameColumns.Band(start: 115, end: 190))
        #expect(bands[2] == FrameColumns.Band(start: 210, end: 285))
        #expect(bands[3] == FrameColumns.Band(start: 305, end: 380))
    }

    @Test("An uneven division still lands on whole points, and still fills the screen")
    func unevenBandsAreWholePoints() {
        // The everyday case: 1440 wide, 12 columns, a 24 gutter and a 32
        // margin. Each column is 85.666… wide, which is not a number anyone
        // wants to type into a width field.
        let columns = FrameColumns(count: 12, gutter: 24, margin: 32)
        let bands = columns.bands(inWidth: 1440)
        #expect(bands.count == 12)
        for band in bands {
            #expect(band.start == band.start.rounded())
            #expect(band.end == band.end.rounded())
        }
        // The outer edges are exactly the margins, whatever the rounding did
        // in between.
        #expect(bands.first?.start == 32)
        #expect(bands.last?.end == 1408)
        // And no column is more than a point off its neighbours.
        let widths = bands.map(\.width)
        #expect((widths.max() ?? 0) - (widths.min() ?? 0) <= 1)
    }

    @Test("Every band is separated by the gutter and none of them overlap")
    func bandsAreOrdered() {
        let columns = FrameColumns(count: 7, gutter: 13, margin: 11)
        let bands = columns.bands(inWidth: 913)
        for (left, right) in zip(bands, bands.dropFirst()) {
            #expect(left.end < right.start)
            #expect(right.start - left.end == 13)
        }
    }

    @Test("One column with no gutter is the content area itself")
    func singleColumn() {
        let bands = FrameColumns(count: 1, gutter: 0, margin: 40).bands(inWidth: 500)
        #expect(bands == [FrameColumns.Band(start: 40, end: 460)])
    }

    @Test("Numbers that leave no room draw nothing rather than drawing backwards")
    func impossibleLayoutsDrawNothing() {
        // Margins wider than the screen.
        #expect(FrameColumns(count: 4, gutter: 8, margin: 300).bands(inWidth: 400).isEmpty)
        // Gutters wider than what is left.
        #expect(FrameColumns(count: 12, gutter: 200, margin: 0).bands(inWidth: 400).isEmpty)
        // A screen with no width at all.
        #expect(FrameColumns(count: 4).bands(inWidth: 0).isEmpty)
    }

    @Test("The bands sit inside the screen, in canvas coordinates")
    func bandsInCanvasSpace() {
        let columns = FrameColumns(count: 2, gutter: 20, margin: 20)
        let screen = CGRect(x: 100, y: 250, width: 240, height: 600)
        let rects = columns.bands(in: screen)
        #expect(rects.count == 2)
        #expect(rects[0] == CGRect(x: 120, y: 250, width: 90, height: 600))
        #expect(rects[1] == CGRect(x: 230, y: 250, width: 90, height: 600))
    }

    @Test("Columns switched off describe no bands at all")
    func hiddenColumnsHaveNoBands() {
        var columns = FrameColumns(count: 12)
        columns.isVisible = false
        #expect(columns.bands(in: CGRect(x: 0, y: 0, width: 1440, height: 1024)).isEmpty)
        // ...but the numbers are still there, waiting to be switched back on.
        #expect(columns.count == 12)
        #expect(!columns.bands(inWidth: 1440).isEmpty)
    }

    // MARK: A screen carrying them

    @Test("A screen keeps its own columns and no other screen's")
    func columnsBelongToOneScreen() {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 4000, height: 2000))
        let phone = doc.addFrame(name: "Phone", origin: .zero, size: CGSize(width: 390, height: 844))
        let desktop = doc.addFrame(name: "Desktop", origin: CGPoint(x: 600, y: 0),
                                   size: CGSize(width: 1440, height: 1024))

        doc.setFrameColumns(id: phone.id, FrameColumns(count: 4, gutter: 16, margin: 16))

        #expect(doc.layer(id: phone.id)?.columns?.count == 4)
        #expect(doc.layer(id: desktop.id)?.columns == nil)
    }

    @Test("Only a screen can be given columns")
    func onlyFramesTakeColumns() {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 800, height: 600))
        let box = leaf("Box", CGRect(x: 0, y: 0, width: 100, height: 100))
        doc.addLayer(box)
        doc.setFrameColumns(id: box.id, FrameColumns(count: 12))
        #expect(doc.layer(id: box.id)?.columns == nil)
    }

    @Test("Switching the columns off keeps the numbers")
    func toggleKeepsTheNumbers() {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 2000, height: 2000))
        let screen = doc.addFrame(origin: .zero, size: CGSize(width: 1440, height: 1024))
        doc.setFrameColumns(id: screen.id, FrameColumns(count: 8, gutter: 30, margin: 40))

        doc.setFrameColumnsVisible(id: screen.id, false)
        #expect(doc.layer(id: screen.id)?.columns?.isVisible == false)
        #expect(doc.layer(id: screen.id)?.columns?.count == 8)
        #expect(doc.layer(id: screen.id)?.columns?.gutter == 30)

        doc.setFrameColumnsVisible(id: screen.id, true)
        #expect(doc.layer(id: screen.id)?.columns?.isVisible == true)
        #expect(doc.layer(id: screen.id)?.columns?.count == 8)
    }

    @Test("Switching on a screen that has never had columns picks numbers for its size")
    func toggleOnFromNothing() {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 2000, height: 2000))
        let phone = doc.addFrame(origin: .zero, size: CGSize(width: 390, height: 844))
        doc.setFrameColumnsVisible(id: phone.id, true)
        #expect(doc.layer(id: phone.id)?.columns?.count == 4)
        #expect(doc.layer(id: phone.id)?.columns?.isVisible == true)
    }

    // MARK: What a drag can catch

    @Test("The bands a drag can catch are every showing screen's, in canvas space")
    func documentBands() {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 4000, height: 2000))
        let a = doc.addFrame(origin: .zero, size: CGSize(width: 240, height: 600))
        let b = doc.addFrame(origin: CGPoint(x: 1000, y: 0), size: CGSize(width: 240, height: 600))
        doc.setFrameColumns(id: a.id, FrameColumns(count: 2, gutter: 20, margin: 20))

        // Only the screen that has them on contributes.
        #expect(doc.columnBands(excluding: []).count == 2)

        doc.setFrameColumns(id: b.id, FrameColumns(count: 2, gutter: 20, margin: 20))
        #expect(doc.columnBands(excluding: []).count == 4)

        // A screen being dragged cannot line itself up with its own columns.
        #expect(doc.columnBands(excluding: [a.id]).count == 2)
    }

    @Test("A layer inside a screen still catches that screen's columns")
    func aChildCatchesItsOwnScreensColumns() {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 2000, height: 2000))
        let screen = doc.addFrame(origin: .zero, size: CGSize(width: 240, height: 600))
        doc.setFrameColumns(id: screen.id, FrameColumns(count: 2, gutter: 20, margin: 20))
        let box = leaf("Box", CGRect(x: 10, y: 10, width: 40, height: 40))
        _ = doc.addLayer(box, toGroup: screen.id)

        // The screen it lives in does not travel with the drag, so its columns
        // are lines that stay put — which is the entire point of the feature.
        #expect(doc.columnBands(excluding: [box.id]).count == 2)
    }

    @Test("A hidden screen offers nothing to catch")
    func hiddenScreensOfferNothing() {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 2000, height: 2000))
        let screen = doc.addFrame(origin: .zero, size: CGSize(width: 240, height: 600))
        doc.setFrameColumns(id: screen.id, FrameColumns(count: 2, gutter: 20, margin: 20))
        doc.updateLayer(id: screen.id) { $0.isVisible = false }
        #expect(doc.columnBands(excluding: []).isEmpty)
    }

    @Test("A document with no screens has nothing to catch, which is every screenshot")
    func aScreenshotIsUntouched() {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 1200, height: 800))
        doc.addLayer(leaf("Shot", CGRect(x: 0, y: 0, width: 1200, height: 800)))
        #expect(doc.columnBands(excluding: []).isEmpty)
    }

    // MARK: Saving

    @Test("Columns survive a save and an open")
    func codableRoundTrip() throws {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 2000, height: 2000))
        let screen = doc.addFrame(origin: .zero, size: CGSize(width: 1440, height: 1024))
        doc.setFrameColumns(id: screen.id, FrameColumns(isVisible: true, count: 12,
                                                        gutter: 24, margin: 32))

        let data = try JSONEncoder().encode(doc)
        let back = try JSONDecoder().decode(PhotonzDocument.self, from: data)
        let columns = try #require(back.layer(id: screen.id)?.columns)
        #expect(columns.isVisible)
        #expect(columns.count == 12)
        #expect(columns.gutter == 24)
        #expect(columns.margin == 32)
    }

    @Test("A document with no columns anywhere is byte for byte what it was")
    func absenceWritesNothing() throws {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 2000, height: 2000))
        let screen = doc.addFrame(origin: .zero, size: CGSize(width: 1440, height: 1024))
        _ = doc.addLayer(leaf("Box", CGRect(x: 10, y: 10, width: 40, height: 40)),
                         toGroup: screen.id)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let before = try encoder.encode(doc)
        #expect(!String(decoding: before, as: UTF8.self).contains("columns"))

        // Setting them and clearing them again gets back to the same bytes.
        doc.setFrameColumns(id: screen.id, FrameColumns(count: 12))
        doc.setFrameColumns(id: screen.id, nil)
        #expect(try encoder.encode(doc) == before)
    }
}
