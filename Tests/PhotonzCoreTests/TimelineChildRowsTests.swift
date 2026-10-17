import CoreGraphics
import Foundation
@testable import PhotonzCore
import Testing

/// Anything made of parts opens on the timeline the way it opens in the layers
/// list (task `any-timeline-row-that-holds-sub-layers-expands-a`).
///
/// Written before the code. The timeline is the layers list with a time axis:
/// the same rows, nested and ordered the same way, opened by the same set of
/// open groups. A row with nothing inside it has no arrow; a closed row still
/// shows the part picked inside it, so a pick never leaves the panel talking
/// about something the timeline cannot show.
@Suite("Timeline rows open into their parts")
struct TimelineChildRowsTests {

    static func logo() -> (PhotonzDocument, logo: UUID, mark: UUID, word: UUID, letter: UUID) {
        LayerPartTimeTests.logo()
    }

    static func ids(_ rows: [TimelineChildRow]) -> [UUID] { rows.map(\.layerID) }

    @Test("A closed row lists nothing under it")
    func closedListsNothing() {
        let (doc, logo, _, _, _) = Self.logo()
        #expect(doc.timelineChildRows(of: logo, open: [], picked: nil).isEmpty)
    }

    @Test("Opened, its parts are listed top first, the layers list's order, one step in")
    func openListsChildren() {
        let (doc, logo, mark, word, _) = Self.logo()
        let rows = doc.timelineChildRows(of: logo, open: [logo], picked: nil)
        // The logo holds [mark, word] bottom first, so the list reads Word, Mark.
        #expect(Self.ids(rows) == [word, mark])
        #expect(rows.map(\.depth) == [1, 1])
        #expect(rows.map(\.parentID) == [logo, logo])
        // The Word holds letters, so it has an arrow; the Mark does not.
        #expect(rows.map(\.opens) == [true, false])
        #expect(rows.map(\.isOpen) == [false, false])
    }

    @Test("A group two levels deep opens one step further in")
    func nested() {
        let (doc, logo, mark, word, letter) = Self.logo()
        let rows = doc.timelineChildRows(of: logo, open: [logo, word], picked: nil)
        #expect(rows.count == 4)
        #expect(rows[0].layerID == word && rows[0].isOpen)
        #expect(rows[1].depth == 2 && rows[1].parentID == word)
        #expect(rows[2].layerID == letter && rows[2].depth == 2)
        #expect(rows[3].layerID == mark && rows[3].depth == 1)
    }

    @Test("Closed, the part picked inside still has its row, and the groups it is in")
    func pickedShowsThroughClosed() {
        let (doc, logo, _, word, letter) = Self.logo()
        let rows = doc.timelineChildRows(of: logo, open: [], picked: letter)
        #expect(Self.ids(rows) == [word, letter])
        #expect(rows.map(\.depth) == [1, 2])
        #expect(rows.map(\.isOpen) == [false, false])
    }

    @Test("Only something with parts opens: a shape, a clip and Captions do not")
    func whatOpens() {
        let (doc, logo, mark, word, _) = Self.logo()
        #expect(doc.timelineRowOpens(logo))
        #expect(doc.timelineRowOpens(word))
        #expect(!doc.timelineRowOpens(mark))
    }

    @Test("Option-click opens every level: the row and every part inside it that opens")
    func openEveryLevel() {
        let (doc, logo, _, word, _) = Self.logo()
        #expect(doc.timelineRowsOpeningEveryLevel(from: logo) == [logo, word])
    }

    @Test("A title page's parts are its rows, in the layers list's order")
    func titleParts() throws {
        let (doc, id) = try TitleRestyleTests.placed(.keynote)
        let rows = doc.timelineChildRows(of: id, open: [id], picked: nil)
        let names = rows.compactMap { doc.layer(id: $0.layerID)?.name }
        #expect(Set(rows.map(\.layerID)) == Set(doc.titlePartTimings(layerID: id).map(\.pieceID)))
        #expect(names.count == 3)
        #expect(rows.allSatisfy { $0.depth == 1 && !$0.opens })
        #expect(doc.timelineRowOpens(id))
    }

    @Test("Closed, a row marks where its parts' own timings fall, and only those")
    func summaryMarks() throws {
        var (doc, logo, mark, _, _) = Self.logo()
        // Every part runs the logo's whole length: nothing to mark.
        #expect(doc.timelineChildMarks(of: logo).isEmpty)
        _ = doc.retimePart(mark, grab: .start, byMS: 1_000)
        let marks = doc.timelineChildMarks(of: logo)
        #expect(marks.count == 1)
        #expect(marks.first?.inMS == 3_000 && marks.first?.outMS == 6_000)
        // A title's parts each come in on their own beat, so each is marked.
        let (title, id) = try TitleRestyleTests.placed(.keynote)
        #expect(title.timelineChildMarks(of: id).count >= 2)
    }
}
