import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// A row that runs out of room wraps onto the next line
/// (`docs/design/ui-building.md`, "A group can arrange its own contents").
///
/// The thing this answers: a strip of tags, a toolbar of buttons, a set of
/// filter chips. Every one of them is pieces of DIFFERENT widths that have to
/// keep going on a second line when the first one fills up, and until now the
/// only thing in the app that started a second line was a grid, which puts
/// everything in equal cells and so is the wrong shape entirely.
///
/// The rules that keep it small:
///
/// - **Only a row wraps.** "Onto the next line" is a row-shaped idea; a column
///   that wrapped into a second column is a rarity nobody asked for.
/// - **There has to be a width to wrap against.** A row that is the size of its
///   contents can never run out of room, so wrapping is not offered there at
///   all rather than offered and silently doing nothing.
/// - **A row that has not actually wrapped is still just a row**, byte for byte
///   the layout it always had. Once it wraps, each line is as tall as the
///   tallest thing on it and the lines sit one under the other, `rowGap` apart.
@Suite("A row that runs out of room wraps onto the next line")
struct GroupWrapTests {

    // MARK: - Building blocks

    private func box(_ name: String, _ frame: CGRect,
                     placement: LayerPlacement? = nil) -> Layer {
        Layer(name: name, content: .image(ImageRef(pixelSize: frame.size)),
              frame: frame, placement: placement)
    }

    private func group(_ children: [Layer], layout: GroupLayout? = nil,
                       contents: LayerPlacement? = nil) -> Layer {
        var content = GroupContent(children: children)
        content.layout = layout
        content.contentPlacement = contents
        return Layer(name: "Group", content: .group(content), frame: .zero)
    }

    private func frames(_ layer: Layer) -> [CGRect] { layer.children.map(\.frame) }

    /// A row with a width of its own that wraps what does not fit.
    private func wrappingRow(width: CGFloat?, gap: CGFloat = 10,
                             rowGap: CGFloat = 12,
                             padding: GroupPadding = .none) -> GroupLayout {
        var layout = GroupLayout(kind: .stack, direction: .row, gap: gap,
                                 rowGap: rowGap, padding: padding, width: width)
        layout.wraps = true
        return layout
    }

    /// Six chips of six different widths, all 40 tall: the shape a grid cannot
    /// make, laid out end to end so nothing here depends on where they started.
    private func chips(_ widths: [CGFloat] = [80, 120, 60, 140, 100, 50],
                       height: CGFloat = 40) -> [Layer] {
        var x: CGFloat = 0
        return widths.enumerated().map { index, width in
            defer { x += width + 400 }
            return box("Chip \(index)", CGRect(x: x, y: 0, width: width, height: height))
        }
    }

    // MARK: - The row starts a new line

    @Test("A row with a width of its own starts a new line when the next piece will not fit")
    func aRowStartsANewLine() {
        let row = GroupFlow.flowing(group(chips(), layout: wrappingRow(width: 300)))
        // 80 + 10 + 120 + 10 + 60 = 280 fits in 300; the 140 does not.
        #expect(frames(row).map(\.minX) == [0, 90, 220, 0, 150, 0])
        #expect(frames(row).map(\.minY) == [0, 0, 0, 52, 52, 104])
    }

    @Test("The wrapped row is as tall as the lines it ended up with")
    func theRowIsAsTallAsItsLines() {
        let row = GroupFlow.flowing(group(chips(), layout: wrappingRow(width: 300)))
        // Three lines of 40, two gaps of 12.
        #expect(row.localBounds.height == 144)
        #expect(row.localBounds.width == 300)
    }

    @Test("Turning wrapping off puts the row back on one line")
    func turningItOffPutsItBackOnOneLine() {
        var layout = wrappingRow(width: 300)
        layout.wraps = false
        let row = GroupFlow.flowing(group(chips(), layout: layout))
        #expect(frames(row).map(\.minY) == [0, 0, 0, 0, 0, 0])
        #expect(frames(row).map(\.minX) == [0, 90, 220, 290, 440, 550])
        #expect(row.localBounds.height == 40)
    }

    @Test("The space between the lines is its own number")
    func theSpaceBetweenLinesIsItsOwn() {
        let row = GroupFlow.flowing(group(chips(), layout: wrappingRow(width: 300, rowGap: 24)))
        #expect(frames(row).map(\.minY) == [0, 0, 0, 64, 64, 128])
        #expect(row.localBounds.height == 168)
    }

    @Test("Room at the edges is room the lines wrap inside")
    func roomAtTheEdgesIsRoomTheLinesWrapInside() {
        let row = GroupFlow.flowing(group(chips(), layout: wrappingRow(width: 320,
                                                                      padding: GroupPadding(10))))
        // 300 of usable width, so the same three lines, each starting 10 in.
        #expect(frames(row).map(\.minX) == [10, 100, 230, 10, 160, 10])
        #expect(frames(row).map(\.minY) == [10, 10, 10, 62, 62, 114])
        // Three lines of 40, two gaps of 12, and 10 of room top and bottom.
        #expect(row.localBounds.height == 164)
    }

    @Test("A piece wider than the row gets a line of its own")
    func aPieceTooWideGetsALineOfItsOwn() {
        let row = GroupFlow.flowing(group(chips([80, 400, 60]), layout: wrappingRow(width: 300)))
        #expect(frames(row).map(\.minX) == [0, 0, 0])
        #expect(frames(row).map(\.minY) == [0, 52, 104])
        // It overhangs the row rather than being squashed to fit.
        #expect(frames(row)[1].width == 400)
    }

    @Test("A row whose contents all fit stays on one line")
    func everythingThatFitsStaysOnOneLine() {
        let row = GroupFlow.flowing(group(chips([40, 40, 40]), layout: wrappingRow(width: 300)))
        #expect(frames(row).map(\.minY) == [0, 0, 0])
        #expect(frames(row).map(\.minX) == [0, 50, 100])
    }

    // MARK: - It only happens where it can mean something

    @Test("A row that is the size of its contents never wraps")
    func aRowThatHugsNeverWraps() {
        let row = GroupFlow.flowing(group(chips(), layout: wrappingRow(width: nil)))
        #expect(frames(row).map(\.minY) == [0, 0, 0, 0, 0, 0])
        #expect(row.localBounds.height == 40)
    }

    @Test("A column keeps running down the page whatever the switch says")
    func aColumnNeverWraps() {
        var layout = GroupLayout(kind: .stack, direction: .column, gap: 10, height: 100)
        layout.wraps = true
        let column = GroupFlow.flowing(group(chips([80, 120, 60]), layout: layout))
        #expect(column.children.map(\.frame.minX) == [0, 0, 0])
        #expect(column.children.map(\.frame.minY) == [0, 50, 100])
    }

    @Test("Wrapping is offered exactly where there is a width to wrap against")
    func wrappingIsOfferedWhereItCanDoSomething() {
        #expect(GroupLayout(kind: .stack, direction: .row).couldWrap == false)
        #expect(GroupLayout(kind: .stack, direction: .row, width: 300).couldWrap)
        #expect(GroupLayout(kind: .stack, direction: .row, minWidth: 300).couldWrap)
        // A ceiling is a width to wrap against too, and it is the one a strip
        // of tags in a panel actually has.
        #expect(GroupLayout(kind: .stack, direction: .row, maxWidth: 300).couldWrap)
        #expect(GroupLayout(kind: .stack, direction: .column, height: 300).couldWrap == false)
        #expect(GroupLayout(kind: .grid, width: 300).couldWrap == false)
        #expect(GroupLayout.free(width: 300).couldWrap == false)
    }

    @Test("A row held to a largest width wraps at that width")
    func aCeilingIsAWidthToWrapAgainst() {
        var layout = GroupLayout(kind: .stack, direction: .row, gap: 10, rowGap: 12,
                                 maxWidth: 300)
        layout.wraps = true
        let row = GroupFlow.flowing(group(chips(), layout: layout))
        #expect(frames(row).map(\.minY) == [0, 0, 0, 52, 52, 104])
        // A ceiling is not a width the box takes: it wraps at 300 and then
        // closes around the widest line it ended up with, so a strip of tags
        // carries no dead room out to the ceiling.
        #expect(row.localBounds.width == 280)
    }

    // MARK: - What it does with the other things a row can do

    @Test("Every line pushes its own contents to its two ends")
    func everyLineSpreadsToItsOwnEnds() {
        var layout = wrappingRow(width: 300)
        layout.spreadsGap = true
        let row = GroupFlow.flowing(group(chips(), layout: layout))
        // Line one holds 80 + 120 + 60 = 260, so 40 is shared between its two
        // gaps; line two holds 140 + 100 = 240 and shares 60 in its one gap.
        #expect(frames(row).map(\.minX) == [0, 100, 240, 0, 200, 0])
        #expect(frames(row).map(\.minY) == [0, 0, 0, 52, 52, 104])
    }

    @Test("A piece told to fill takes what its own line has left")
    func aFillerTakesWhatItsLineHasLeft() {
        var pieces = chips()
        pieces[1].flowFill = FlowFill(sizeBefore: pieces[1].frame.size)
        let row = GroupFlow.flowing(group(pieces, layout: wrappingRow(width: 300)))
        // Its line holds 80 and 60 beside it and two gaps of 10, so it takes
        // the 140 that is left rather than the 120 it was drawn at.
        #expect(frames(row)[1].width == 140)
        #expect(frames(row).map(\.minX) == [0, 90, 240, 0, 150, 0])
    }

    @Test("Each line is as tall as the tallest thing on it")
    func eachLineIsAsTallAsWhatIsOnIt() {
        let pieces = [box("Tall", CGRect(x: 0, y: 0, width: 200, height: 60)),
                      box("Short", CGRect(x: 400, y: 0, width: 200, height: 20)),
                      box("Last", CGRect(x: 800, y: 0, width: 200, height: 30))]
        let row = GroupFlow.flowing(group(pieces, layout: wrappingRow(width: 200)))
        #expect(frames(row).map(\.minY) == [0, 72, 104])
        // 60 + 12 + 20 + 12 + 30
        #expect(row.localBounds.height == 134)
    }

    @Test("A shorter piece answers the Vertical rows inside its own line")
    func aShorterPieceIsPlacedInsideItsLine() {
        let pieces = [box("Tall", CGRect(x: 0, y: 0, width: 100, height: 60)),
                      box("Short", CGRect(x: 400, y: 0, width: 100, height: 20)),
                      box("Next", CGRect(x: 800, y: 0, width: 200, height: 40))]
        let row = GroupFlow.flowing(group(pieces, layout: wrappingRow(width: 210),
                                          contents: LayerPlacement(vertical: .center)))
        // The first two share a line 60 tall, so the short one centres in it;
        // the third starts the next line under both.
        #expect(frames(row).map(\.minY) == [0, 20, 72])
    }

    // MARK: - Dragging a piece around a wrapped row

    @Test("A wrapped row reads line by line, not left to right")
    func aWrappedRowReadsLineByLine() {
        let row = GroupFlow.flowing(group(chips(), layout: wrappingRow(width: 300)))
        let boxes = row.children.map(\.frame)
        var layout = wrappingRow(width: 300)
        #expect(GroupFlow.flowOrder(boxes, layout: layout) == [0, 1, 2, 3, 4, 5])
        // Running the flow again over what it just made leaves everything
        // exactly where it is, so a wrapped row does not shuffle itself.
        layout.wraps = true
        let again = GroupFlow.flowing(group(row.children, layout: layout))
        #expect(frames(again) == boxes)
    }

    @Test("A point picks its slot by the line it falls on")
    func aPointPicksItsSlotByLine() {
        let row = GroupFlow.flowing(group(chips(), layout: wrappingRow(width: 300)))
        let layout = wrappingRow(width: 300)
        let items = GroupFlow.arrangedItems(of: row)
        // Between the first two chips on the top line.
        #expect(GroupFlow.slot(at: CGPoint(x: 85, y: 20), among: items, layout: layout) == 1)
        // The same X, one line down, lands after everything above it.
        #expect(GroupFlow.slot(at: CGPoint(x: 85, y: 72), among: items, layout: layout) == 4)
        // Past the end of the last line.
        #expect(GroupFlow.slot(at: CGPoint(x: 280, y: 124), among: items, layout: layout) == 6)
    }

    // MARK: - Turning it on and off in a document

    @Test("Turning wrapping off puts the row back, and one undo takes it back again")
    func oneUndoTakesTheChangeBack() {
        var layout = wrappingRow(width: 300)
        layout.wraps = false
        var history = History(document: PhotonzDocument(
            canvasSize: CGSize(width: 800, height: 600),
            layers: [group(chips(), layout: layout)]))
        let id = history.current.layers[0].id
        history.perform {
            $0.updateGroupLayout(id: id) { $0.wraps = true }
            $0.reflowLayouts()
        }
        #expect(history.current.layer(id: id)?.children.map(\.frame.minY) == [0, 0, 0, 52, 52, 104])
        history.undo()
        #expect(history.current.layer(id: id)?.children.map(\.frame.minY) == [0, 0, 0, 0, 0, 0])
    }

    // MARK: - Saving and reopening

    @Test("Wrapping survives a save and a reopen")
    func wrappingRoundTrips() throws {
        let layout = wrappingRow(width: 300, gap: 8, rowGap: 16, padding: GroupPadding(12))
        let data = try JSONEncoder().encode(layout)
        #expect(try JSONDecoder().decode(GroupLayout.self, from: data) == layout)
    }

    @Test("A row that does not wrap writes nothing about wrapping")
    func aRowThatDoesNotWrapWritesNothing() throws {
        let written = try JSONEncoder().encode(GroupLayout(kind: .stack, direction: .row,
                                                           width: 300))
        #expect(!String(decoding: written, as: UTF8.self).contains("wrap"))
    }

    @Test("A document saved before rows could wrap opens on one line")
    func anOlderDocumentOpensOnOneLine() throws {
        let older = Data(#"{"kind":"stack","direction":"row","columns":3,"gap":12,"rowGap":12,"padding":8,"width":300}"#.utf8)
        let layout = try JSONDecoder().decode(GroupLayout.self, from: older)
        #expect(layout.wraps == false)
        #expect(layout.couldWrap)
    }

    // MARK: - What the panel offers

    @Test("A copy reads out that it wraps, and how far apart its lines are")
    func aCopyReadsOutItsWrapping() {
        let rows = wrappingRow(width: 300, rowGap: 16)
            .followedReadout(clipsContents: false)
        #expect(rows.contains { $0.title == "Wrap" && $0.value == "On" })
        #expect(rows.contains { $0.title == "Line gap" && $0.value == "16" })
    }

    @Test("A row with nothing to wrap against reads out neither")
    func aRowWithNothingToWrapAgainstReadsOutNeither() {
        var layout = GroupLayout(kind: .stack, direction: .row, gap: 12)
        layout.wraps = true
        let rows = layout.followedReadout(clipsContents: false)
        #expect(!rows.contains { $0.title == "Wrap" })
        #expect(!rows.contains { $0.title == "Line gap" })
    }
}
