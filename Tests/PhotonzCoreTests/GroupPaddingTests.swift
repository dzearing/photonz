import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// Room on each of a stack's four sides
/// (`docs/design/ui-building.md`, "A group can arrange its own contents").
///
/// One number typed once still means the same room all round, because that is
/// the common case. Underneath there are four, because a real card is 16 in
/// from the left, 12 down from the top and 24 up from the bottom, and a card
/// like that used to be buildable only by nudging pieces the stack then undid.
@Suite("A stack keeps room on each of its four sides")
struct GroupPaddingTests {

    // MARK: - Building blocks

    private func box(_ name: String, _ frame: CGRect) -> Layer {
        Layer(name: name, content: .image(ImageRef(pixelSize: frame.size)), frame: frame)
    }

    private func group(_ children: [Layer], layout: GroupLayout? = nil,
                       contents: LayerPlacement? = nil,
                       origin: CGPoint = .zero) -> Layer {
        var content = GroupContent(children: children)
        content.layout = layout
        content.contentPlacement = contents
        return Layer(name: "Group", content: .group(content),
                     frame: CGRect(origin: origin, size: .zero))
    }

    private func frame(_ children: [Layer], size: CGSize, layout: GroupLayout? = nil,
                       contents: LayerPlacement? = nil) -> Layer {
        var content = GroupContent(children: children, isFrame: true, backgroundHex: "#FFFFFF")
        content.layout = layout
        content.contentPlacement = contents
        return Layer(name: "Screen", content: .group(content),
                     frame: CGRect(origin: .zero, size: size))
    }

    private func frames(_ layer: Layer) -> [CGRect] { layer.children.map(\.frame) }

    private func document(_ layers: [Layer]) -> PhotonzDocument {
        PhotonzDocument(canvasSize: CGSize(width: 800, height: 600), layers: layers)
    }

    /// The card the whole task is about: 16 in from the left, 12 down from the
    /// top, 24 up from the bottom, 8 in from the right.
    private let card = GroupPadding(top: 12, right: 8, bottom: 24, left: 16)

    // MARK: - One number still means all four

    @Test("One number typed once is the room on every side")
    func oneNumberIsAllFourSides() {
        let even = GroupPadding(16)
        #expect(even.top == 16 && even.right == 16 && even.bottom == 16 && even.left == 16)
        #expect(even.uniform == 16)
        #expect(even.isUniform)
    }

    @Test("Four sides that disagree have no one number to show")
    func unevenRoomHasNoSingleNumber() {
        #expect(card.uniform == nil)
        #expect(!card.isUniform)
    }

    @Test("Each side answers to its own name, to read and to set")
    func everySideIsItsOwnNumber() {
        var room = card
        #expect(GroupPadding.Side.allCases.map { room[$0] } == [12, 8, 24, 16])
        #expect(GroupPadding.Side.allCases.map(\.title) == ["Top", "Right", "Bottom", "Left"])
        room[.bottom] = 32
        #expect(room.bottom == 32)
        #expect(room.horizontal == 24)
        #expect(room.vertical == 44)
    }

    @Test("Room below nought is no room at all, and neither is a number that is not one")
    func roomNeverGoesNegative() {
        let odd = GroupPadding(top: -8, right: .infinity, bottom: .nan, left: 10)
        #expect(odd.used == GroupPadding(top: 0, right: 0, bottom: 0, left: 10))
    }

    // MARK: - What the room does to the contents

    @Test("A stack that sizes itself starts its contents inside the near edges and grows by both")
    func unevenRoomGrowsAHuggingStack() {
        let stack = GroupFlow.flowing(group([
            box("A", CGRect(x: 0, y: 0, width: 40, height: 20)),
            box("B", CGRect(x: 0, y: 30, width: 40, height: 20)),
        ], layout: GroupLayout(kind: .stack, direction: .column, gap: 10, padding: card)))
        #expect(frames(stack) == [CGRect(x: 16, y: 12, width: 40, height: 20),
                                  CGRect(x: 16, y: 42, width: 40, height: 20)])
        // 16 + 40 + 8 across, and 12 + 20 + 10 + 20 + 24 down.
        #expect(stack.localBounds == CGRect(x: 0, y: 0, width: 64, height: 86))
    }

    @Test("A stack with a size of its own hands its rows the width left between its sides")
    func unevenRoomNarrowsAFixedStack() {
        var layout = GroupLayout(kind: .stack, direction: .column, gap: 10, padding: card)
        layout.width = 320
        let stack = GroupFlow.flowing(group([
            box("A", CGRect(x: 0, y: 0, width: 40, height: 20)),
            box("B", CGRect(x: 0, y: 30, width: 40, height: 20)),
        ], layout: layout, contents: LayerPlacement(horizontal: .stretch)))
        // 320 - 16 left - 8 right = 296, starting 16 in.
        #expect(frames(stack) == [CGRect(x: 16, y: 12, width: 296, height: 20),
                                  CGRect(x: 16, y: 42, width: 296, height: 20)])
    }

    @Test("A row stack runs from the left edge and its rows fill the height between top and bottom")
    func unevenRoomOnARowStack() {
        var layout = GroupLayout(kind: .stack, direction: .row, gap: 10, padding: card)
        layout.height = 100
        let stack = GroupFlow.flowing(group([
            box("A", CGRect(x: 0, y: 0, width: 40, height: 20)),
            box("B", CGRect(x: 60, y: 0, width: 30, height: 20)),
        ], layout: layout, contents: LayerPlacement(vertical: .stretch)))
        // 100 - 12 top - 24 bottom = 64 tall, first item 16 in from the left.
        #expect(frames(stack) == [CGRect(x: 16, y: 12, width: 40, height: 64),
                                  CGRect(x: 66, y: 12, width: 30, height: 64)])
    }

    @Test("A grid starts in its top left corner and shares out what its sides leave")
    func unevenRoomOnAGrid() {
        let tiles = (0..<2).map { box("T\($0)", CGRect(x: CGFloat($0) * 100, y: 0,
                                                       width: 20, height: 20)) }
        let screen = GroupFlow.flowing(frame(tiles, size: CGSize(width: 224, height: 200),
            layout: GroupLayout(kind: .grid, columns: 2, gap: 20, rowGap: 20, padding: card),
            contents: LayerPlacement(horizontal: .stretch)))
        // 224 - 16 left - 8 right - 20 gap = 180, split in two.
        #expect(frames(screen) == [CGRect(x: 16, y: 12, width: 90, height: 20),
                                   CGRect(x: 126, y: 12, width: 90, height: 20)])
    }

    @Test("An empty stack is exactly the room it keeps")
    func anEmptyStackIsItsOwnRoom() {
        let empty = group([], layout: GroupLayout(kind: .stack, padding: card))
        #expect(empty.localBounds.size == CGSize(width: 24, height: 36))
    }

    @Test("A stack with room on its sides flows the same the second time")
    func aPaddedStackSettles() {
        let once = GroupFlow.flowing(group([
            box("A", CGRect(x: 0, y: 0, width: 40, height: 20)),
            box("B", CGRect(x: 9, y: 90, width: 70, height: 30)),
        ], layout: GroupLayout(kind: .stack, direction: .column, gap: 8, padding: card)))
        #expect(frames(GroupFlow.flowing(once)) == frames(once))
    }

    // MARK: - Typing it, and taking it back

    @Test("Room typed on one side re-flows the contents in one undo step")
    func typingOneSideIsOneUndoStep() {
        var history = History(document: document([group([
            box("A", CGRect(x: 0, y: 0, width: 40, height: 20)),
            box("B", CGRect(x: 0, y: 30, width: 40, height: 20)),
        ], layout: GroupLayout(kind: .stack, direction: .column, gap: 10, padding: 16))]))
        let id = history.current.layers[0].id
        let before = history.current.layers[0].localBounds
        _ = history.perform { $0.updateGroupLayout(id: id) { $0.padding[.bottom] = 24 } }
        #expect(history.current.layers[0].group?.layout?.padding
                == GroupPadding(top: 16, right: 16, bottom: 24, left: 16))
        // 16 top + 20 + 10 + 20 + 24 bottom, and the rows never moved sideways.
        #expect(history.current.layers[0].localBounds.height == 90)
        #expect(history.current.layers[0].children.map(\.frame.minX) == [16, 16])
        history.undo()
        #expect(history.current.layers[0].localBounds == before)
        #expect(history.current.layers[0].group?.layout?.padding == GroupPadding(16))
    }

    @Test("A copy of a component keeps the room its stack was given when it is resized")
    func aResizedCopyKeepsItsRoom() {
        var doc = document([group([
            box("A", CGRect(x: 0, y: 0, width: 40, height: 20)),
            box("B", CGRect(x: 0, y: 30, width: 40, height: 20)),
        ], layout: GroupLayout(kind: .stack, direction: .column, gap: 10, padding: card),
           contents: LayerPlacement(horizontal: .stretch))])
        doc.reflowLayouts()
        let main = doc.layers[0].id
        let componentID = doc.makeComponent(id: main)!
        let copy = doc.insertComponentInstance(of: componentID, at: CGPoint(x: 400, y: 300))!
        doc.updateLayer(id: copy) { $0 = $0.resized(to: CGRect(x: 400, y: 300,
                                                               width: 300, height: 200)) }
        doc.reflowLayouts()
        let resized = doc.layer(id: copy)!
        #expect(resized.group?.layout?.padding == card)
        // The rows still start 16 in and 12 down from the copy's own corner,
        // and fill what is left across: 300 - 16 left - 8 right.
        let rows: [CGRect] = resized.children.map(\.frame)
        #expect(rows.map(\.minX) == [CGFloat(16), CGFloat(16)])
        #expect(rows.map(\.width) == [CGFloat(276), CGFloat(276)])
        #expect(rows.first?.minY == CGFloat(12))
    }

    // MARK: - Saving it

    @Test("Even room is still written as the one number older documents hold")
    func evenRoomSavesAsOneNumber() throws {
        var content = GroupContent(children: [])
        content.layout = GroupLayout(kind: .stack, gap: 8, padding: 16)
        let json = try #require(String(data: try JSONEncoder().encode(content), encoding: .utf8))
        #expect(json.contains("\"padding\":16"))
    }

    @Test("A document written before there were four sides opens with the room it had")
    func anOlderDocumentOpensUnchanged() throws {
        let older = """
        {"children":[],"layout":{"kind":"stack","direction":"column","columns":3,\
        "gap":8,"rowGap":12,"padding":16}}
        """
        let back = try JSONDecoder().decode(GroupContent.self, from: Data(older.utf8))
        #expect(back.layout?.padding == GroupPadding(16))
        // ...and it goes back to disk as the same one number, so the file it
        // came from is the file it stays.
        let again = try #require(String(data: try JSONEncoder().encode(back), encoding: .utf8))
        #expect(again.contains("\"padding\":16"))
        #expect(!again.contains("\"bottom\""))
    }

    @Test("A document that never asked for room writes none and reads none")
    func noRoomIsStillNoRoom() throws {
        let older = """
        {"children":[],"layout":{"kind":"stack","gap":8}}
        """
        let back = try JSONDecoder().decode(GroupContent.self, from: Data(older.utf8))
        #expect(back.layout?.padding == GroupPadding.none)
        let again = try #require(String(data: try JSONEncoder().encode(back), encoding: .utf8))
        #expect(again.contains("\"padding\":0"))
    }

    @Test("A whole document with even room saves to the same bytes it opened from")
    func aDocumentWithEvenRoomIsByteForByte() throws {
        // The same encoder a package is written with, so this is the file, not
        // an approximation of it.
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let doc = document([group([
            box("A", CGRect(x: 0, y: 0, width: 40, height: 20)),
            box("B", CGRect(x: 0, y: 30, width: 40, height: 20)),
        ], layout: GroupLayout(kind: .stack, direction: .column, gap: 10, padding: 16))])
        let first = try encoder.encode(doc)
        let again = try encoder.encode(try JSONDecoder().decode(PhotonzDocument.self, from: first))
        #expect(again == first)
        let json = try #require(String(data: first, encoding: .utf8))
        #expect(json.contains("\"padding\" : 16"))
        #expect(!json.contains("\"bottom\""))
    }

    @Test("Uneven room survives being saved and opened again")
    func unevenRoomRoundTrips() throws {
        var content = GroupContent(children: [])
        content.layout = GroupLayout(kind: .stack, gap: 8, padding: card)
        let data = try JSONEncoder().encode(content)
        let back = try JSONDecoder().decode(GroupContent.self, from: data)
        #expect(back.layout?.padding == card)
    }

    // MARK: - Reading the room off a screen somebody spaced by eye

    @Test("Turning a screen's contents into a stack reads the margins they already sit at")
    func inferenceReadsTheMargins() {
        var doc = document([frame([
            box("A", CGRect(x: 24, y: 16, width: 100, height: 20)),
            box("B", CGRect(x: 24, y: 48, width: 100, height: 20)),
        ], size: CGSize(width: 200, height: 300))])
        let id = doc.layers[0].id
        doc.setGroupLayout(id: id, kind: .stack)
        doc.reflowLayouts()
        // The near edges are read off the contents; the far ones mirror them,
        // because the rest of a screen below the last row is not room anybody
        // asked for.
        #expect(doc.layers[0].group?.layout?.padding
                == GroupPadding(top: 16, right: 24, bottom: 16, left: 24))
        #expect(frames(doc.layers[0]) == [CGRect(x: 24, y: 16, width: 100, height: 20),
                                          CGRect(x: 24, y: 48, width: 100, height: 20)])
    }

    @Test("A plain group turned into a stack is keeping no room at all")
    func aPlainGroupStartsWithNoRoom() {
        var doc = document([group([
            box("A", CGRect(x: 10, y: 10, width: 40, height: 20)),
            box("B", CGRect(x: 10, y: 42, width: 40, height: 20)),
        ])])
        let id = doc.layers[0].id
        doc.setGroupLayout(id: id, kind: .stack)
        #expect(doc.layers[0].group?.layout?.padding == GroupPadding.none)
    }

    // MARK: - Saying the four numbers out loud

    // Closing the four side fields while they disagree used to leave the word
    // Mixed on screen and nothing else, so the 24 somebody had just typed at
    // the bottom was not readable anywhere until they opened them again
    // (`queue/audits/2026-09-04-stack-padding.json`, rough 1). The single row
    // writes the four numbers itself now, and the wording lives here so the
    // field and the sentence a copy shows cannot drift apart.

    @Test("The four numbers read clockwise from the top, the way a shorthand does")
    func shorthandReadsClockwiseFromTheTop() {
        #expect(GroupPadding(top: 16, right: 16, bottom: 24, left: 16).shorthand == "16/16/24/16")
    }

    @Test("Room that is the same all round still writes all four")
    func shorthandOfEvenRoomIsStillFour() {
        #expect(GroupPadding(16).shorthand == "16/16/16/16")
    }

    @Test("Half points are written as the whole number the field shows")
    func shorthandRoundsToWholeNumbers() {
        #expect(GroupPadding(top: 16.4, right: 16.6, bottom: 0, left: 8).shorthand == "16/17/0/8")
    }

    @Test("The same four numbers in words, for the tooltip and for a copy's sentence")
    func inWordsNamesEverySide() {
        #expect(GroupPadding(top: 12, right: 16, bottom: 24, left: 16).inWords
                == "12 top, 16 right, 24 bottom, 16 left")
    }
}
