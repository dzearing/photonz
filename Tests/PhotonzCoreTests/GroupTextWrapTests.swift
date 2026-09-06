import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// Words that outgrow their container wrap instead of hanging out of it
/// (`docs/design/ui-building.md`, "A container closes around its contents").
///
/// The complaint this answers, from the size limits audit: "There is no way to
/// make words wrap or shrink when they outgrow a ceiling, so they overhang."
/// A label is as wide as its words until something narrows it, and a box with
/// a width of its own — one somebody typed, or one a ceiling is holding in —
/// is exactly that something.
@Suite("Words that outgrow their container wrap instead of hanging out of it")
struct GroupTextWrapTests {

    // MARK: - Building blocks

    /// Small type, so the numbers in these tests are ones a person can hold in
    /// their head: about 5.2 points a letter and a line 12 tall, plus the 4
    /// points of slack every measured box carries.
    private func words(_ string: String, at x: CGFloat = 16, _ y: CGFloat = 8) -> Layer {
        let content = TextContent(string: string, fontSize: 10)
        let size = TextMeasurement.size(of: content)
        return Layer(name: "Label", content: .text(content),
                     frame: CGRect(origin: CGPoint(x: x, y: y), size: size))
    }

    private func box(_ name: String, _ frame: CGRect,
                     placement: LayerPlacement? = nil) -> Layer {
        Layer(name: name, content: .image(ImageRef(pixelSize: frame.size)),
              frame: frame, placement: placement)
    }

    private func group(_ children: [Layer], layout: GroupLayout,
                       contents: LayerPlacement? = nil) -> Layer {
        var content = GroupContent(children: children)
        content.layout = layout
        content.contentPlacement = contents
        return Layer(name: "Group", content: .group(content),
                     frame: CGRect(origin: .zero, size: .zero))
    }

    private func piece(_ layer: Layer, _ name: String) -> CGRect {
        layer.children.first { $0.name == name }?.frame.standardized ?? .null
    }

    private func label(_ layer: Layer) -> Layer? {
        layer.children.first { $0.name == "Label" }
    }

    /// A button as the starters draw one: a surface that fills, a word in the
    /// middle of it, 16 of room either side.
    private func button(saying string: String, layout: GroupLayout) -> Layer {
        group([box("Background", CGRect(x: 0, y: 0, width: 100, height: 36),
                   placement: .fill),
               words(string)],
              layout: layout,
              contents: LayerPlacement(horizontal: .center, vertical: .center))
    }

    private func room(_ all: CGFloat) -> GroupPadding { GroupPadding(all) }

    /// How tall one line of these words is, which is what "it did not wrap"
    /// looks like.
    private var oneLine: CGFloat {
        TextMeasurement.size(of: TextContent(string: "x", fontSize: 10)).height
    }

    // MARK: - A ceiling

    @Test("A ceiling wraps the words instead of letting them hang out of it")
    func aCeilingWrapsTheWords() {
        var layout = GroupLayout.free(padding: room(16))
        layout.maxWidth = 100
        let held = GroupFlow.flowing(button(saying: "Save all the changes", layout: layout))
        // 100 wide, 32 of it room, so the words get 68 across.
        #expect(held.localBounds.width == 100)
        let words = piece(held, "Label")
        #expect(words.width == 68 + TextMeasurement.slack)
        #expect(words.maxX - TextMeasurement.slack <= 100 - 16)
        #expect(words.height > oneLine)
    }

    @Test("The group grows taller as the words wrap")
    func theGroupGrowsTallerAsTheWordsWrap() {
        let plain = GroupLayout.free(padding: room(16))
        var capped = plain
        capped.maxWidth = 100
        let loose = GroupFlow.flowing(button(saying: "Save all the changes", layout: plain))
        let held = GroupFlow.flowing(button(saying: "Save all the changes", layout: capped))
        #expect(held.localBounds.height > loose.localBounds.height)
        // ...and the surface behind the words grows with it, so the pill still
        // sits behind every line.
        #expect(piece(held, "Background").size == held.localBounds.size)
    }

    @Test("A height ceiling holds the group in even as the words wrap")
    func aHeightCeilingIsStillHonouredOnceTheWordsWrap() {
        var layout = GroupLayout.free(padding: room(16))
        layout.maxWidth = 100
        layout.maxHeight = 40
        let held = GroupFlow.flowing(button(saying: "Save all the changes", layout: layout))
        #expect(held.localBounds.size == CGSize(width: 100, height: 40))
    }

    // MARK: - A width somebody typed

    @Test("A width somebody typed wraps the words the same way a ceiling does")
    func aTypedWidthWrapsTheWords() {
        var layout = GroupLayout.free(padding: room(16))
        layout.width = 100
        let held = GroupFlow.flowing(button(saying: "Save all the changes", layout: layout))
        #expect(held.localBounds.width == 100)
        #expect(piece(held, "Label").width == 68 + TextMeasurement.slack)
        #expect(piece(held, "Label").height > oneLine)
    }

    // MARK: - Nothing else moves

    @Test("A label that fits changes in no way at all")
    func aLabelThatFitsIsUntouched() {
        let plain = GroupLayout.free(padding: room(16))
        var capped = plain
        capped.maxWidth = 400
        let loose = GroupFlow.flowing(button(saying: "Save", layout: plain))
        let held = GroupFlow.flowing(button(saying: "Save", layout: capped))
        #expect(held.children.map(\.frame) == loose.children.map(\.frame))
        #expect(held.localBounds == loose.localBounds)
        #expect(label(held)?.wrappedByItsContainer == nil)
    }

    @Test("A paragraph somebody narrowed by hand keeps the width they gave it")
    func aParagraphIsLeftAlone() {
        var layout = GroupLayout.free(padding: room(16))
        // A ceiling of 80 leaves 48 across, well under the 60 this box is: the
        // paragraph outgrows the room and is STILL left alone, because that 60
        // is a width somebody chose and not one the flow worked out.
        layout.maxWidth = 80
        var paragraph = words("Save all the changes")
        let wide = paragraph.frame.width
        paragraph.frame = CGRect(x: 16, y: 8, width: 60, height: 40)
        #expect(wide > 60)
        let held = GroupFlow.flowing(group([paragraph], layout: layout))
        #expect(piece(held, "Label") == CGRect(x: 16, y: 16, width: 60, height: 40))
        #expect(label(held)?.wrappedByItsContainer == nil)
    }

    // MARK: - Lifting the ceiling gives the line back

    @Test("Clearing the ceiling gives the words their one line back")
    func liftingTheCeilingUnwrapsTheWords() {
        var capped = GroupLayout.free(padding: room(16))
        capped.maxWidth = 100
        let held = GroupFlow.flowing(button(saying: "Save all the changes", layout: capped))
        #expect(label(held)?.wrappedByItsContainer == true)

        var lifted = held
        var content = lifted.group!
        content.layout = GroupLayout.free(padding: room(16))
        lifted.content = .group(content)
        let loose = GroupFlow.flowing(lifted)

        let plain = GroupFlow.flowing(button(saying: "Save all the changes",
                                             layout: GroupLayout.free(padding: room(16))))
        #expect(loose.localBounds.size == plain.localBounds.size)
        #expect(piece(loose, "Label").size == piece(plain, "Label").size)
        #expect(label(loose)?.wrappedByItsContainer == nil)
    }

    @Test("Raising the ceiling settles rather than flipping between wrapped and not")
    func aCeilingJustAboveTheWordsSettles() {
        var layout = GroupLayout.free(padding: room(16))
        layout.maxWidth = 100
        let once = GroupFlow.flowing(button(saying: "Save all the changes", layout: layout))
        let twice = GroupFlow.flowing(once)
        let thrice = GroupFlow.flowing(twice)
        #expect(twice.children.map(\.frame) == once.children.map(\.frame))
        #expect(thrice.children.map(\.frame) == once.children.map(\.frame))
    }

    // MARK: - Stacks and grids

    @Test("A column stack wraps its labels across the width it was given")
    func aColumnStackWrapsAcrossItsWidth() {
        var layout = GroupLayout(kind: .stack, direction: .column, gap: 8,
                                 padding: room(10))
        layout.maxWidth = 100
        let stacked = GroupFlow.flowing(
            group([words("Save all the changes", at: 0, 0),
                   box("Icon", CGRect(x: 0, y: 40, width: 20, height: 20))],
                  layout: layout))
        #expect(stacked.localBounds.width == 100)
        // 100 wide, 20 of it room, so the words get 80 across.
        #expect(piece(stacked, "Label").width == 80 + TextMeasurement.slack)
        #expect(piece(stacked, "Label").height > oneLine)
        // The row under the words is pushed down by the line they gained.
        #expect(piece(stacked, "Icon").minY
                == 10 + piece(stacked, "Label").height - TextMeasurement.slack + 8)
    }

    @Test("A row stack gives its one long label the room the other pieces leave")
    func aRowStackWrapsTheLabelIntoWhatIsLeft() {
        var layout = GroupLayout(kind: .stack, direction: .row, gap: 8,
                                 padding: room(10))
        layout.maxWidth = 120
        let row = GroupFlow.flowing(
            group([box("Icon", CGRect(x: 0, y: 0, width: 20, height: 20)),
                   words("Save all the changes", at: 30, 0)],
                  layout: layout))
        #expect(row.localBounds.width == 120)
        // 120 wide, 20 of room, a 20 wide icon and an 8 gap: 72 left.
        #expect(piece(row, "Label").width == 72 + TextMeasurement.slack)
        #expect(piece(row, "Label").maxX - TextMeasurement.slack <= 120 - 10)
    }

    @Test("A grid wraps a label into its cell")
    func aGridWrapsIntoItsCell() {
        var layout = GroupLayout(kind: .grid, columns: 2, gap: 10, padding: room(10))
        layout.width = 150
        let grid = GroupFlow.flowing(
            group([words("Save all the changes", at: 0, 0),
                   box("Icon", CGRect(x: 60, y: 0, width: 20, height: 20))],
                  layout: layout))
        // 150 wide, 20 of room, one 10 gap, two columns: 60 a cell.
        #expect(piece(grid, "Label").width == 60 + TextMeasurement.slack)
        #expect(piece(grid, "Label").height > oneLine)
    }

    // MARK: - Words that cannot break

    @Test("One long word is left hanging out rather than broken in the middle")
    func oneWordTooWideIsNotBrokenApart() {
        let plain = GroupLayout.free(padding: room(16))
        var capped = plain
        capped.maxWidth = 56
        let loose = GroupFlow.flowing(button(saying: "Button", layout: plain))
        let held = GroupFlow.flowing(button(saying: "Button", layout: capped))
        // The pill still stops at the ceiling, and the word is exactly the
        // word it was: one line, its own width, hanging out of the right edge.
        #expect(held.localBounds.width == 56)
        #expect(piece(held, "Label").size == piece(loose, "Label").size)
        #expect(label(held)?.wrappedByItsContainer == nil)
    }

    @Test("Words wrap only as far as the longest of them allows")
    func theWidestWordIsTheFloor() {
        var layout = GroupLayout.free(padding: room(16))
        layout.maxWidth = 56
        let held = GroupFlow.flowing(button(saying: "Save all the changes", layout: layout))
        let widest = TextMeasurement.widestWord(
            in: TextContent(string: "changes", fontSize: 10))
        // 56 wide leaves 24 across, which is under the widest word, so the
        // words break at the word and overhang rather than coming apart.
        #expect(piece(held, "Label").width == widest)
        #expect(widest > 24 + TextMeasurement.slack)
    }

    // MARK: - What the container decided is not what somebody chose

    @Test("Dragging a wrapped label's own width makes it the person's answer again")
    func resizingByHandTakesTheWidthBack() {
        var layout = GroupLayout.free(padding: room(16))
        layout.maxWidth = 100
        let held = GroupFlow.flowing(button(saying: "Save all the changes", layout: layout))
        let wrapped = label(held)!
        #expect(wrapped.wrappedByItsContainer == true)
        let dragged = wrapped.resized(to: CGRect(x: 16, y: 8, width: 50, height: 40))
        #expect(dragged.wrappedByItsContainer == nil)
    }

    @Test("A wrapped label survives being saved and opened again")
    func theMarkIsWrittenDownAndReadBack() throws {
        var layout = GroupLayout.free(padding: room(16))
        layout.maxWidth = 100
        let held = GroupFlow.flowing(button(saying: "Save all the changes", layout: layout))
        let data = try JSONEncoder().encode(held)
        let back = try JSONDecoder().decode(Layer.self, from: data)
        #expect(label(back)?.wrappedByItsContainer == true)
        #expect(back.children.map(\.frame) == held.children.map(\.frame))
    }
}
