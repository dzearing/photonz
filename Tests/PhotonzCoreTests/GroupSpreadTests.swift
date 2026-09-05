import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// A row that pushes its contents to its two ends
/// (`docs/design/ui-building.md`, "A group can arrange its own contents").
///
/// The thing this answers: a nav bar is a logo on the left and buttons on the
/// right, and until now a stack could only hold ONE gap, so the only way to
/// build that was to nudge the pieces apart by hand and watch the stack put
/// them back. A stack that has been given a size of its own can now share the
/// room it has left over between its rows instead, which is the same choice
/// anybody who has written a stylesheet already knows as space-between.
///
/// The rule that keeps it small: **there is only room to spread where the
/// group is bigger than its contents**. A stack that is as big as what is
/// inside it has nothing left over, so spreading it is not offered at all
/// rather than offered and silently doing nothing.
@Suite("A row can push its contents to its two ends")
struct GroupSpreadTests {

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

    /// A row stack with a size of its own, spreading the room it has left.
    private func spreadingRow(width: CGFloat?, gap: CGFloat = 12,
                              padding: GroupPadding = .none) -> GroupLayout {
        var layout = GroupLayout(kind: .stack, direction: .row, gap: gap,
                                 padding: padding, width: width)
        layout.spreadsGap = true
        return layout
    }

    private func pieces(_ count: Int, width: CGFloat = 100, height: CGFloat = 40) -> [Layer] {
        (0..<count).map { index in
            box("Piece \(index)", CGRect(x: CGFloat(index) * 200, y: 0,
                                         width: width, height: height))
        }
    }

    // MARK: - The room goes between the rows

    @Test("Two rows in a stack with a width of its own go to its two ends")
    func twoRowsGoToTheEnds() {
        let bar = GroupFlow.flowing(group(pieces(2), layout: spreadingRow(width: 640)))
        #expect(frames(bar) == [CGRect(x: 0, y: 0, width: 100, height: 40),
                                CGRect(x: 540, y: 0, width: 100, height: 40)])
        // The box is the size it was given, not the size its contents make.
        #expect(bar.localBounds.width == 640)
    }

    @Test("Three rows share the leftover room equally")
    func threeRowsShareTheRoom() {
        let bar = GroupFlow.flowing(group(pieces(3), layout: spreadingRow(width: 640)))
        #expect(frames(bar).map(\.minX) == [0, 270, 540])
    }

    @Test("A column spreads down the same way a row spreads across")
    func aColumnSpreadsDown() {
        var layout = GroupLayout(kind: .stack, direction: .column, gap: 12, height: 400)
        layout.spreadsGap = true
        let stack = GroupFlow.flowing(group(pieces(3), layout: layout))
        #expect(frames(stack).map(\.minY) == [0, 180, 360])
    }

    @Test("The room at the edges is kept, and the ends land inside it")
    func theRoomAtTheEdgesIsKept() {
        let bar = GroupFlow.flowing(
            group(pieces(2), layout: spreadingRow(width: 640, padding: GroupPadding(20))))
        #expect(frames(bar).map(\.minX) == [20, 520])
        #expect(frames(bar).map(\.maxX) == [120, 620])
        #expect(frames(bar).map(\.minY) == [20, 20])
    }

    @Test("Uneven room on the two ends is kept as it was typed")
    func unevenRoomAtTheTwoEnds() {
        let room = GroupPadding(top: 0, right: 40, bottom: 0, left: 10)
        let bar = GroupFlow.flowing(
            group(pieces(2), layout: spreadingRow(width: 640, padding: room)))
        #expect(frames(bar).map(\.minX) == [10, 500])
        #expect(frames(bar).map(\.maxX) == [110, 600])
    }

    @Test("The other axis is still the placement rows', not the flow's")
    func theCrossAxisIsUntouched() {
        var layout = spreadingRow(width: 640)
        layout.height = 100
        let bar = GroupFlow.flowing(
            group(pieces(2), layout: layout,
                  contents: LayerPlacement(horizontal: .left, vertical: .center)))
        #expect(frames(bar) == [CGRect(x: 0, y: 30, width: 100, height: 40),
                                CGRect(x: 540, y: 30, width: 100, height: 40)])
    }

    @Test("A row hidden takes no room, and the rest spread over what it left")
    func aHiddenRowTakesNoRoom() {
        var children = pieces(3)
        children[1].isVisible = false
        let bar = GroupFlow.flowing(group(children, layout: spreadingRow(width: 640)))
        #expect(bar.children[0].frame.minX == 0)
        #expect(bar.children[2].frame.minX == 540)
    }

    @Test("The surface behind a bar fills it while the pieces on it go to the ends")
    func theSurfaceBehindABarIsNotSpread() {
        let bar = GroupFlow.flowing(
            group([box("Background", CGRect(x: 0, y: 0, width: 320, height: 48),
                       placement: .fill)] + pieces(2),
                  layout: spreadingRow(width: 640)))
        #expect(bar.children[0].frame == CGRect(x: 0, y: 0, width: 640, height: 40))
        #expect(bar.children.dropFirst().map(\.frame.minX) == [0, 540])
    }

    // MARK: - Where there is nothing to spread

    @Test("A stack that is the size of its contents keeps the gap it was typed")
    func aHuggingStackKeepsItsGap() {
        let bar = GroupFlow.flowing(group(pieces(2), layout: spreadingRow(width: nil)))
        #expect(frames(bar).map(\.minX) == [0, 112])
        #expect(bar.localBounds.width == 212)
    }

    @Test("A stack that hugs is not offered the choice, and one with a size is")
    func onlyASizedStackIsOfferedTheChoice() {
        #expect(GroupLayout(kind: .stack, direction: .row).couldSpread == false)
        #expect(GroupLayout(kind: .stack, direction: .row, width: 640).couldSpread)
        // The flow axis is the one that has to have the room: a row told how
        // TALL it is still has nothing left over across.
        #expect(GroupLayout(kind: .stack, direction: .row, height: 48).couldSpread == false)
        #expect(GroupLayout(kind: .stack, direction: .column, height: 400).couldSpread)
        // A grid already shares its width out between its columns, so there is
        // no second way to say it, and a group that arranges nothing has no
        // gap at all.
        #expect(GroupLayout(kind: .grid, width: 640).couldSpread == false)
        #expect(GroupLayout.free(width: 640).couldSpread == false)
    }

    @Test("A floor holding a stack open is room to spread as much as a size is")
    func aSmallestWidthMakesRoomToSpread() {
        var layout = spreadingRow(width: nil)
        layout.minWidth = 640
        #expect(layout.couldSpread)
        let bar = GroupFlow.flowing(group(pieces(2), layout: layout))
        #expect(frames(bar).map(\.minX) == [0, 540])
    }

    @Test("One row on its own sits at the near edge, with nothing to spread against")
    func oneRowSitsAtTheNearEdge() {
        let bar = GroupFlow.flowing(
            group(pieces(1), layout: spreadingRow(width: 640, padding: GroupPadding(16))))
        #expect(frames(bar).map(\.minX) == [16])
    }

    @Test("Contents too big for the room sit tight against each other")
    func contentsTooBigSitTight() {
        let bar = GroupFlow.flowing(group(pieces(2), layout: spreadingRow(width: 120)))
        #expect(frames(bar).map(\.minX) == [0, 100])
    }

    @Test("A grid is not spread by it, whatever the flag says")
    func aGridIsUntouched() {
        var layout = GroupLayout(kind: .grid, columns: 2, gap: 10, rowGap: 10, width: 640)
        layout.spreadsGap = true
        let cells = GroupFlow.flowing(group(pieces(2), layout: layout))
        // 640 across two columns with 10 between them: cells of 315.
        #expect(frames(cells).map(\.minX) == [0, 325])
    }

    // MARK: - Turning it back into a number

    @Test("Turning it back to a number restores the number that was there")
    func turningItBackRestoresTheNumber() {
        var layout = spreadingRow(width: 640, gap: 12)
        #expect(layout.gap == 12)
        layout.spreadsGap = false
        #expect(layout.usedGap == 12)
        let bar = GroupFlow.flowing(group(pieces(2), layout: layout))
        #expect(frames(bar).map(\.minX) == [0, 112])
    }

    @Test("Typing a gap while it spreads keeps the number for when it stops")
    func typingAGapWhileSpreadingKeepsIt() {
        var document = PhotonzDocument(canvasSize: CGSize(width: 800, height: 600),
                                       layers: [group(pieces(2),
                                                      layout: spreadingRow(width: 640))])
        let id = document.layers[0].id
        document.updateGroupLayout(id: id) { $0.gap = 24 }
        document.reflowLayouts()
        #expect(document.layer(id: id)?.workingLayout.gap == 24)
        // It is still spreading, so the number is held rather than used.
        #expect(document.layer(id: id)?.children.map(\.frame.minX) == [0, 540])
        document.updateGroupLayout(id: id) { $0.spreadsGap = false }
        document.reflowLayouts()
        #expect(document.layer(id: id)?.children.map(\.frame.minX) == [0, 124])
    }

    // MARK: - Saving and reopening

    @Test("Spreading survives a save and a reopen")
    func spreadingRoundTrips() throws {
        let layout = spreadingRow(width: 640, gap: 8, padding: GroupPadding(12))
        let data = try JSONEncoder().encode(layout)
        #expect(try JSONDecoder().decode(GroupLayout.self, from: data) == layout)
    }

    @Test("Every number a layout carries survives a save and a reopen")
    func everyNumberRoundTrips() throws {
        var layout = GroupLayout(kind: .grid, direction: .row, columns: 4, gap: 7,
                                 rowGap: 9, padding: GroupPadding(top: 1, right: 2,
                                                                  bottom: 3, left: 4),
                                 width: 300, height: 200,
                                 minWidth: 100, maxWidth: 400,
                                 minHeight: 50, maxHeight: 500)
        layout.spreadsGap = true
        let data = try JSONEncoder().encode(layout)
        #expect(try JSONDecoder().decode(GroupLayout.self, from: data) == layout)
    }

    @Test("A document saved before rows could spread opens holding its gap, and unchanged")
    func anOlderDocumentOpensUnchanged() throws {
        let older = Data(#"{"kind":"stack","direction":"row","columns":3,"gap":12,"rowGap":12,"padding":8}"#.utf8)
        let layout = try JSONDecoder().decode(GroupLayout.self, from: older)
        #expect(layout.spreadsGap == false)
        #expect(layout.usedGap == 12)
    }

    @Test("A layout that holds one gap writes nothing about spreading")
    func aLayoutThatDoesNotSpreadWritesNothing() throws {
        let written = try JSONEncoder().encode(GroupLayout(kind: .stack, width: 640))
        #expect(!String(decoding: written, as: UTF8.self).contains("spread"))
    }

    @Test("Switching between Free, Stack and Grid keeps the choice")
    func switchingArrangementKeepsTheChoice() {
        var document = PhotonzDocument(canvasSize: CGSize(width: 800, height: 600),
                                       layers: [group(pieces(2),
                                                      layout: spreadingRow(width: 640))])
        let id = document.layers[0].id
        document.setGroupLayout(id: id, kind: .grid)
        #expect(document.layer(id: id)?.workingLayout.spreadsGap == true)
        document.setGroupLayout(id: id, kind: .stack)
        #expect(document.layer(id: id)?.workingLayout.spreadsGap == true)
        #expect(document.layer(id: id)?.workingLayout.gap == 12)
    }
}
