import Testing
@testable import PhotonzRender

/// A live stroke's tail is drawn as if the stroke ended at the pointer and
/// taken back on the next move (`LiveMarker`): the journal keeps what a field
/// held over each box before the tail wrote there, and puts it all back.
@Suite("A field's journal puts back what the tail wrote over")
struct FieldJournalTests {

    @Test func overlappingBoxesComeBackAsTheyWereBeforeEither() {
        let box = PixelBox(minX: 10, minY: 20, maxX: 50, maxY: 45)
        let channels = 3
        let before = (0..<(box.width * box.height * channels)).map { Float($0) * 0.5 }
        var values = before
        var journal = FieldJournal()
        let first = PixelBox(minX: 12, minY: 22, maxX: 30, maxY: 40)
        let second = PixelBox(minX: 25, minY: 30, maxX: 60, maxY: 50)  // runs past the field
        // Every write lands inside a box saved first, as a stroke's do.
        func write(_ value: Float, over wanted: PixelBox) {
            let region = wanted.intersection(box)
            for y in region.minY..<region.maxY {
                for x in region.minX..<region.maxX {
                    let at = ((y - box.minY) * box.width + (x - box.minX)) * channels
                    for c in 0..<channels { values[at + c] = value }
                }
            }
        }
        journal.save(first, from: values, box: box, channels: channels)
        write(-1, over: first)
        journal.save(second, from: values, box: box, channels: channels)
        write(-2, over: second)
        journal.save(first, from: values, box: box, channels: channels)
        write(-3, over: first)
        journal.restore(into: &values, box: box, channels: channels)
        #expect(values == before)
    }

    @Test func aPixelIsSavedOnceHoweverManyBoxesOverlapIt() {
        // A thinned end's dabs nearly cover each other: saving each dab's box
        // whole copied the same pixels four times over at 150 points, twenty
        // at 20 (2026-10-30).
        let box = PixelBox(minX: 0, minY: 0, maxX: 400, maxY: 300)
        let values = [Float](repeating: 1, count: box.width * box.height)
        var journal = FieldJournal()
        for k in 0..<20 {
            journal.save(PixelBox(minX: 100 + k * 2, minY: 100, maxX: 124 + k * 2, maxY: 124),
                         from: values, box: box, channels: 1)
        }
        // The dabs reach from 100 to 162 across and 24 down.
        #expect(journal.savedValues == 62 * 24)
    }

    @Test func aFieldThatGrewSinceIsPutBackInItsNewPlace() {
        var field = CoverageField(limit: PixelBox(minX: 0, minY: 0, maxX: 2000, maxY: 2000))
        field.ensure(PixelBox(minX: 100, minY: 100, maxX: 140, maxY: 130))
        for y in 100..<130 { for x in 100..<140 { field.set(x, y, Float(x * 1000 + y)) } }
        field.record()
        // The tail grows the field and writes over what was there.
        field.ensure(PixelBox(minX: 120, minY: 110, maxX: 900, maxY: 700))
        for y in 110..<700 { for x in 120..<900 { field.set(x, y, 7) } }
        field.rollBack()
        for y in 100..<130 {
            for x in 100..<140 { #expect(field.value(x, y) == Float(x * 1000 + y)) }
        }
        #expect(field.value(500, 500) == 0)
    }
}
