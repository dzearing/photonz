import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// A reading that has landed is remembered, so the line counting what it gave
/// up on can be asked for again after it fades (`TextReading.Remembered`).
@Suite("What a reading gave up on, after the line goes")
struct TextReadingMemoryTests {

    private func picture(_ id: UUID, at x: CGFloat = 0) -> TextReading.Remembered.StillAPicture {
        TextReading.Remembered.StillAPicture(id: id, box: CGRect(x: x, y: 0, width: 40, height: 12))
    }

    // MARK: - The line it says again

    @Test func theCountItSaysAgainIsTheCountItSaidTheFirstTime() {
        // The whole point: the same line, the same numbers, the same face. A
        // reading asked for a second time must not come back saying something
        // else about labels nothing has touched.
        let stayed = [picture(UUID()), picture(UUID(), at: 60), picture(UUID(), at: 120)]
        let remembered = TextReading.Remembered(read: (0..<12).map { _ in UUID() },
                                                stayed: stayed, family: "SF Pro")
        #expect(remembered.batch == TextReading.Batch(read: 12, stillPictures: 3, family: "SF Pro"))
        #expect(remembered.batch.detail == "12 labels, set in SF Pro. 3 stayed pictures")
        #expect(remembered.labels == stayed.map(\.id))
    }

    @Test func aReadingWithNothingLeftToPointAtIsNotWorthKeeping() {
        // Every label came back, so there is no count to press and nothing to
        // say again: the line was a plain report and asking again has nothing
        // to recover.
        let all = TextReading.Remembered(read: [UUID(), UUID()], stayed: [], family: "SF Pro")
        #expect(!all.isWorthKeeping)
        // And a reading where nothing landed is not this line either: the whole
        // sentence is already about what stayed, with nothing to pick them out
        // FROM (`Batch.stillPicturesTail`).
        let none = TextReading.Remembered(read: [], stayed: [picture(UUID())], family: nil)
        #expect(!none.isWorthKeeping)
        let some = TextReading.Remembered(read: [UUID()], stayed: [picture(UUID())], family: nil)
        #expect(some.isWorthKeeping)
    }

    // MARK: - It still stands, or it does not

    @Test func nothingTouchedMeansTheWholeLineStands() {
        let read = [UUID(), UUID()]
        let stayed = [picture(UUID()), picture(UUID(), at: 60)]
        let remembered = TextReading.Remembered(read: read, stayed: stayed, family: "SF Pro")
        var rows: [UUID: TextReading.RowNow] = [:]
        for id in read { rows[id] = .words }
        for row in stayed { rows[row.id] = .stillAPicture(box: row.box) }
        #expect(remembered.standing(given: rows) == remembered)
    }

    @Test func aLabelRetypedByHandStopsBeingCounted() {
        // Somebody gave up on one of the three and typed it themselves. It is
        // words now, so the line must say two, not three: a count that goes on
        // naming a label that is no longer a picture sends people to look for
        // something that is not there.
        let read = [UUID()]
        let stayed = [picture(UUID()), picture(UUID(), at: 60)]
        let remembered = TextReading.Remembered(read: read, stayed: stayed, family: "SF Pro")
        var rows: [UUID: TextReading.RowNow] = [read[0]: .words]
        rows[stayed[0].id] = .words
        rows[stayed[1].id] = .stillAPicture(box: stayed[1].box)
        let standing = remembered.standing(given: rows)
        #expect(standing?.labels == [stayed[1].id])
        #expect(standing?.batch.detail == "1 label, set in SF Pro. 1 stayed a picture")
    }

    @Test func aLabelDeletedSinceStopsBeingCounted() {
        let read = [UUID(), UUID()]
        let stayed = [picture(UUID()), picture(UUID(), at: 60)]
        let remembered = TextReading.Remembered(read: read, stayed: stayed, family: "SF Pro")
        // The second straggler and one of the labels that came back are gone
        // from the document altogether: absent from the rows, absent from the
        // count.
        let rows: [UUID: TextReading.RowNow] = [
            read[0]: .words,
            stayed[0].id: .stillAPicture(box: stayed[0].box),
        ]
        let standing = remembered.standing(given: rows)
        #expect(standing?.batch == TextReading.Batch(read: 1, stillPictures: 1, family: "SF Pro"))
    }

    @Test func aLabelResizedSinceIsWorthReadingAgain() {
        // The words are set at the size the picture holds them at, so a label
        // somebody has stretched is not the label the reading gave up on. The
        // memory stands down and the reading is really done again.
        let stayed = [picture(UUID())]
        let remembered = TextReading.Remembered(read: [UUID()], stayed: stayed, family: "SF Pro")
        let rows: [UUID: TextReading.RowNow] = [
            remembered.read[0]: .words,
            stayed[0].id: .stillAPicture(box: stayed[0].box.insetBy(dx: -4, dy: 0)),
        ]
        #expect(remembered.standing(given: rows) == nil)
    }

    @Test func aReadingTakenBackByUndoIsNotSaidAgain() {
        // Command Z put every label back to a picture. Saying "12 labels, set
        // in SF Pro" over a screenshot where nothing is text would be the app
        // reporting on a state that no longer exists.
        let read = [UUID(), UUID()]
        let stayed = [picture(UUID())]
        let remembered = TextReading.Remembered(read: read, stayed: stayed, family: "SF Pro")
        var rows: [UUID: TextReading.RowNow] = [:]
        for id in read { rows[id] = .stillAPicture(box: CGRect(x: 0, y: 0, width: 40, height: 12)) }
        rows[stayed[0].id] = .stillAPicture(box: stayed[0].box)
        #expect(remembered.standing(given: rows) == nil)
    }

    @Test func aReadingWhoseStragglersHaveAllGoneSaysNothing() {
        // Nothing left to point at, so there is no line to bring back: the ask
        // goes through to a real reading, which is the honest answer.
        let remembered = TextReading.Remembered(read: [UUID()], stayed: [picture(UUID())],
                                                family: nil)
        #expect(remembered.standing(given: [remembered.read[0]: .words]) == nil)
    }

    @Test func aReadingWhoseLandingHasAllGoneSaysNothing() {
        let stayed = [picture(UUID())]
        let remembered = TextReading.Remembered(read: [UUID()], stayed: stayed, family: nil)
        let rows: [UUID: TextReading.RowNow] = [
            stayed[0].id: .stillAPicture(box: stayed[0].box)
        ]
        #expect(remembered.standing(given: rows) == nil)
    }
}
