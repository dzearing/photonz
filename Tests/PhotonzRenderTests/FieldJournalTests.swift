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
        journal.save(first, from: values, box: box, channels: channels)
        for i in values.indices { values[i] = -1 }
        journal.save(second, from: values, box: box, channels: channels)
        for i in values.indices { values[i] = -2 }
        journal.restore(into: &values, box: box, channels: channels)

        let inside = { (x: Int, y: Int, b: PixelBox) in x >= b.minX && x < b.maxX && y >= b.minY && y < b.maxY }
        for y in box.minY..<box.maxY {
            for x in box.minX..<box.maxX {
                let at = ((y - box.minY) * box.width + (x - box.minX)) * channels
                for c in 0..<channels {
                    let expected: Float = inside(x, y, first) ? before[at + c]
                        : inside(x, y, second) ? -1 : -2
                    #expect(values[at + c] == expected, "pixel \(x),\(y) channel \(c)")
                }
            }
        }
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
