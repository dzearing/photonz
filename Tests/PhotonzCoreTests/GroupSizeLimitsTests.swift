import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// The smallest and the largest a container may get
/// (`docs/design/ui-building.md`, "A container closes around its contents").
///
/// The complaint this answers, from the hug audit: "There is no minimum width,
/// so a button with one letter in it is as narrow as one letter plus its
/// room." A group that is the size of its contents can now be given a floor
/// and a ceiling on either axis, so a one letter button is still a button and
/// a card with a very long title stops growing instead of running off the
/// screen.
@Suite("A container can be told the smallest and largest it may get")
struct GroupSizeLimitsTests {

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
        return Layer(name: "Group", content: .group(content),
                     frame: CGRect(origin: .zero, size: .zero))
    }

    private func piece(_ layer: Layer, _ name: String) -> CGRect {
        layer.children.first { $0.name == name }?.frame ?? .null
    }

    private func frames(_ layer: Layer) -> [CGRect] { layer.children.map(\.frame) }

    private func room(_ all: CGFloat) -> GroupPadding { GroupPadding(all) }

    /// A button as the starters draw one: a surface that fills, and a word
    /// sitting in the middle of it, with 16 of room either side.
    private func button(word: CGFloat, layout: GroupLayout) -> Layer {
        group([box("Background", CGRect(x: 0, y: 0, width: 100, height: 36),
                   placement: .fill),
               box("Label", CGRect(x: 16, y: 8, width: word, height: 20))],
              layout: layout,
              contents: LayerPlacement(horizontal: .center, vertical: .center))
    }

    // MARK: - The floor

    @Test("A group that hugs never goes below the smallest width it was given")
    func aFloorHoldsAHuggingGroupOpen() {
        var layout = GroupLayout.free(padding: GroupPadding(top: 8, right: 16,
                                                            bottom: 8, left: 16))
        layout.minWidth = 96
        // One letter, 10 points of it: on its own the button would be 42 wide.
        let held = GroupFlow.flowing(button(word: 10, layout: layout))
        #expect(held.localBounds.size == CGSize(width: 96, height: 36))
    }

    @Test("The room a floor makes goes where the contents say, so a centred word centres")
    func aFloorPlacesTheContentsItHoldsOpen() {
        var layout = GroupLayout.free(padding: GroupPadding(top: 8, right: 16,
                                                            bottom: 8, left: 16))
        layout.minWidth = 96
        let held = GroupFlow.flowing(button(word: 10, layout: layout))
        // 96 wide, 32 of it room, leaves 64 for a 10 wide word: 43 in from the
        // left edge, which is the middle of the pill.
        #expect(piece(held, "Label") == CGRect(x: 43, y: 8, width: 10, height: 20))
        // ...and the surface behind it still takes the whole box.
        #expect(piece(held, "Background") == CGRect(x: 0, y: 0, width: 96, height: 36))
    }

    @Test("A floor that is not reached changes nothing at all")
    func aFloorBelowTheContentsIsNotFelt() {
        let plain = GroupLayout.free(padding: room(8))
        var floored = plain
        floored.minWidth = 20
        floored.minHeight = 20
        let contents = [box("Words", CGRect(x: 0, y: 0, width: 50, height: 30))]
        #expect(frames(GroupFlow.flowing(group(contents, layout: floored)))
                == frames(GroupFlow.flowing(group(contents, layout: plain))))
        #expect(GroupFlow.flowing(group(contents, layout: floored)).localBounds
                == GroupFlow.flowing(group(contents, layout: plain)).localBounds)
    }

    @Test("A group that hugs never goes below the shortest height it was given")
    func aFloorHoldsAHuggingGroupTall() {
        var layout = GroupLayout.free(padding: room(4))
        layout.minHeight = 60
        let held = GroupFlow.flowing(
            group([box("Words", CGRect(x: 0, y: 0, width: 50, height: 12))],
                  layout: layout,
                  contents: LayerPlacement(horizontal: .center, vertical: .center)))
        #expect(held.localBounds.size == CGSize(width: 58, height: 60))
        // 60 tall, 8 of it room, leaves 52 for a 12 tall word: 24 down.
        #expect(piece(held, "Words") == CGRect(x: 4, y: 24, width: 50, height: 12))
    }

    // MARK: - The ceiling

    @Test("A group that hugs never gets past the largest width it was given")
    func aCeilingCapsAHuggingGroup() {
        var layout = GroupLayout.free(padding: GroupPadding(top: 8, right: 16,
                                                            bottom: 8, left: 16))
        layout.maxWidth = 120
        // A long label would make a 332 wide button; the ceiling stops it.
        let capped = GroupFlow.flowing(button(word: 300, layout: layout))
        #expect(capped.localBounds.size == CGSize(width: 120, height: 36))
        // The surface takes the box it is actually allowed rather than the one
        // the words asked for.
        #expect(piece(capped, "Background") == CGRect(x: 0, y: 0, width: 120, height: 36))
        // Contents too big for the room start at the near edge and overhang the
        // far one, which is the honest answer until there is a way to wrap or
        // shrink them, and never off the left of the box where nothing else in
        // the app would look for them.
        #expect(piece(capped, "Label").minX == 16)
    }

    @Test("A group that hugs never gets past the tallest height it was given")
    func aCeilingCapsAHuggingGroupTall() {
        var layout = GroupLayout.free(padding: room(6))
        layout.maxHeight = 40
        let capped = GroupFlow.flowing(
            group([box("Words", CGRect(x: 0, y: 0, width: 50, height: 200))],
                  layout: layout))
        #expect(capped.localBounds.size == CGSize(width: 62, height: 40))
    }

    // MARK: - A stack lays out in the room it is actually allowed

    @Test("A stack held open by a floor lays its rows out across the room the floor made")
    func aStackFillsTheRoomItsFloorMade() {
        var layout = GroupLayout(kind: .stack, direction: .column, gap: 10,
                                 padding: room(8))
        layout.minWidth = 200
        let stack = GroupFlow.flowing(
            group([box("A", CGRect(x: 0, y: 0, width: 40, height: 20)),
                   box("B", CGRect(x: 0, y: 30, width: 40, height: 20))],
                  layout: layout,
                  contents: LayerPlacement(horizontal: .stretch, vertical: .top)))
        #expect(stack.localBounds.size == CGSize(width: 200, height: 8 + 20 + 10 + 20 + 8))
        // Both rows stretch across the room inside the edges of the box the
        // floor made, not across the 40 they used to be.
        #expect(frames(stack) == [CGRect(x: 8, y: 8, width: 184, height: 20),
                                  CGRect(x: 8, y: 38, width: 184, height: 20)])
    }

    @Test("A stack pinned at its ceiling lays its rows out in the room it has")
    func aStackFillsTheRoomItsCeilingLeft() {
        var layout = GroupLayout(kind: .stack, direction: .column, gap: 10,
                                 padding: room(8))
        layout.maxWidth = 120
        let stack = GroupFlow.flowing(
            group([box("A", CGRect(x: 0, y: 0, width: 400, height: 20)),
                   box("B", CGRect(x: 0, y: 30, width: 400, height: 20))],
                  layout: layout,
                  contents: LayerPlacement(horizontal: .stretch, vertical: .top)))
        #expect(stack.localBounds.size == CGSize(width: 120, height: 66))
        // The rows come back INSIDE the ceiling rather than overflowing it
        // quietly: 120 less 8 of room on each side.
        #expect(frames(stack) == [CGRect(x: 8, y: 8, width: 104, height: 20),
                                  CGRect(x: 8, y: 38, width: 104, height: 20)])
    }

    @Test("A grid pinned at its ceiling shares the room it has between its columns")
    func aGridFillsTheRoomItsCeilingLeft() {
        var layout = GroupLayout(kind: .grid, columns: 2, gap: 10, rowGap: 10,
                                 padding: room(8))
        layout.maxWidth = 128
        let grid = GroupFlow.flowing(
            group([box("A", CGRect(x: 0, y: 0, width: 200, height: 20)),
                   box("B", CGRect(x: 210, y: 0, width: 200, height: 20))],
                  layout: layout,
                  contents: LayerPlacement(horizontal: .stretch, vertical: .top)))
        #expect(grid.localBounds.size == CGSize(width: 128, height: 36))
        // 128 less 16 of room is 112, less the 10 between the columns is 102,
        // so each cell is 51.
        #expect(frames(grid) == [CGRect(x: 8, y: 8, width: 51, height: 20),
                                 CGRect(x: 69, y: 8, width: 51, height: 20)])
    }

    @Test("Along the axis a stack flows, the room a floor makes stays at the near edge")
    func aFloorAlongTheFlowPacksAtTheStart() {
        var layout = GroupLayout(kind: .stack, direction: .row, gap: 10, padding: room(8))
        layout.minWidth = 200
        let stack = GroupFlow.flowing(
            group([box("A", CGRect(x: 0, y: 0, width: 30, height: 20)),
                   box("B", CGRect(x: 40, y: 0, width: 30, height: 20))],
                  layout: layout))
        #expect(stack.localBounds.size.width == 200)
        #expect(frames(stack) == [CGRect(x: 8, y: 8, width: 30, height: 20),
                                  CGRect(x: 48, y: 8, width: 30, height: 20)])
    }

    // MARK: - Both numbers at once, and the numbers themselves

    @Test("Where the smallest and the largest cross, the smallest wins")
    func theFloorBeatsTheCeiling() {
        var layout = GroupLayout.free(padding: room(0))
        layout.minWidth = 120
        layout.maxWidth = 40
        let held = GroupFlow.flowing(
            group([box("Words", CGRect(x: 0, y: 0, width: 80, height: 20))], layout: layout))
        #expect(held.localBounds.size.width == 120)
    }

    @Test("A number that is not a real number, or is below nought, is no limit at all")
    func nonsenseNumbersAreNoLimit() {
        var layout = GroupLayout.free()
        layout.minWidth = .nan
        layout.maxWidth = .infinity
        layout.minHeight = -50
        #expect(layout.usedMinWidth == nil)
        #expect(layout.usedMaxWidth == nil)
        #expect(layout.usedMinHeight == 0)
        let plain = GroupFlow.flowing(
            group([box("Words", CGRect(x: 0, y: 0, width: 50, height: 20))], layout: layout))
        #expect(plain.localBounds.size == CGSize(width: 50, height: 20))
    }

    @Test("The limits hold a size that was typed, not only one that was hugged")
    func aFixedSizeIsHeldTheSameWay() {
        var layout = GroupLayout.free(padding: room(0), width: 400, height: 10)
        layout.maxWidth = 200
        layout.minHeight = 44
        let held = GroupFlow.flowing(
            group([box("Words", CGRect(x: 0, y: 0, width: 50, height: 20))], layout: layout))
        #expect(held.localBounds.size == CGSize(width: 200, height: 44))
    }

    @Test("Dragging a group's handle past its ceiling stops at the ceiling")
    func aHandleStopsAtTheCeiling() {
        var layout = GroupLayout.free(padding: room(0))
        layout.maxWidth = 150
        let start = GroupFlow.flowing(
            group([box("Words", CGRect(x: 0, y: 0, width: 50, height: 20))], layout: layout))
        let dragged = LayerScaling.rearranging(
            start, to: CGRect(x: 0, y: 0, width: 600, height: 20))
        #expect(dragged.localBounds.size.width == 150)
        // The number the field shows is the number the box is, so the two can
        // never disagree after a drag.
        #expect(dragged.group?.layout?.usedWidth == 150)
    }

    @Test("Dragging a group's handle below its floor stops at the floor")
    func aHandleStopsAtTheFloor() {
        var layout = GroupLayout.free(padding: room(0))
        layout.minWidth = 80
        let start = GroupFlow.flowing(
            group([box("Words", CGRect(x: 0, y: 0, width: 50, height: 20))], layout: layout))
        let dragged = LayerScaling.rearranging(
            start, to: CGRect(x: 0, y: 0, width: 10, height: 20))
        #expect(dragged.localBounds.size.width == 80)
    }

    // MARK: - Saving and reopening

    @Test("The numbers survive a save and a reopen")
    func theLimitsRoundTrip() throws {
        var layout = GroupLayout(kind: .stack, direction: .row, gap: 4, padding: room(6))
        layout.minWidth = 96
        layout.maxWidth = 320
        layout.minHeight = 44
        layout.maxHeight = 200
        let data = try JSONEncoder().encode(layout)
        #expect(try JSONDecoder().decode(GroupLayout.self, from: data) == layout)
    }

    @Test("A document saved before there were limits opens with none, and unchanged")
    func anOlderDocumentOpensUnchanged() throws {
        let older = Data(#"{"kind":"stack","direction":"column","columns":3,"gap":12,"rowGap":12,"padding":8}"#.utf8)
        let layout = try JSONDecoder().decode(GroupLayout.self, from: older)
        #expect(layout.minWidth == nil)
        #expect(layout.maxWidth == nil)
        #expect(layout.minHeight == nil)
        #expect(layout.maxHeight == nil)
        #expect(layout.limitsWidth == false)
        #expect(layout.limitsHeight == false)
    }

    @Test("A layout with no limits writes no limits, so an untouched file stays the file it was")
    func aLayoutWithNoLimitsWritesNone() throws {
        let written = try JSONEncoder().encode(GroupLayout(kind: .stack))
        let text = String(decoding: written, as: UTF8.self)
        #expect(!text.contains("minWidth"))
        #expect(!text.contains("maxWidth"))
        #expect(!text.contains("minHeight"))
        #expect(!text.contains("maxHeight"))
    }

    @Test("Switching between Free, Stack and Grid keeps the limits that were typed")
    func switchingArrangementKeepsTheLimits() {
        var layout = GroupLayout.free(padding: room(8))
        layout.minWidth = 96
        layout.maxHeight = 200
        var document = PhotonzDocument(canvasSize: CGSize(width: 800, height: 600),
                                       layers: [group([box("A", CGRect(x: 0, y: 0,
                                                                       width: 40, height: 20))],
                                                      layout: layout)])
        let id = document.layers[0].id
        document.setGroupLayout(id: id, kind: .stack)
        #expect(document.layer(id: id)?.group?.layout?.minWidth == 96)
        #expect(document.layer(id: id)?.group?.layout?.maxHeight == 200)
        document.setGroupLayout(id: id, kind: .grid)
        #expect(document.layer(id: id)?.group?.layout?.minWidth == 96)
        document.setGroupLayout(id: id, kind: nil)
        #expect(document.layer(id: id)?.group?.layout?.maxHeight == 200)
    }

    @Test("A limit typed in the inspector reaches the group and holds it")
    func aTypedLimitHoldsTheGroup() {
        var document = PhotonzDocument(canvasSize: CGSize(width: 800, height: 600),
                                       layers: [button(word: 10,
                                                       layout: .free(padding: GroupPadding(
                                                        top: 8, right: 16, bottom: 8, left: 16)))])
        let id = document.layers[0].id
        document.updateGroupLayout(id: id) { $0.minWidth = 96 }
        document.reflowLayouts()
        #expect(document.layer(id: id)?.localBounds.width == 96)
        document.updateGroupLayout(id: id) { $0.minWidth = nil }
        document.reflowLayouts()
        #expect(document.layer(id: id)?.localBounds.width == 42)
    }

    // MARK: - What the section says about them

    @Test("A group with no limits says nothing about them, and one with them says both")
    func theLimitsReadBackInWords() {
        var layout = GroupLayout.free()
        #expect(layout.limitsSentence == nil)
        layout.minWidth = 96
        #expect(layout.limitsSentence == "It never gets narrower than 96.")
        layout.maxHeight = 200
        #expect(layout.limitsSentence == "It never gets narrower than 96 or taller than 200.")
        layout.maxWidth = 320
        layout.minHeight = 44
        #expect(layout.limitsSentence
                == "It never gets narrower than 96 or wider than 320 or shorter than 44 or taller than 200.")
    }
}
