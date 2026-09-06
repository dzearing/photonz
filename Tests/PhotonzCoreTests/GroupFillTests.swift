import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// A piece that takes the room its stack has left over
/// (`docs/design/ui-building.md`, "A group can arrange its own contents").
///
/// The thing this answers: a nav bar is a logo, a search field and a row of
/// buttons, and the search field is whatever is left between the two. Until
/// now every piece in a stack kept the size it was drawn at along the way the
/// stack runs, so the only way to build that was to drag the field to the
/// right width and drag it again the moment the bar changed.
///
/// The rule that keeps it small: **filling is about the flow, not about an
/// axis**. It says "take what the stack has left", so flipping a row to a
/// column goes on meaning the same thing, and it never collides with the
/// Stretch that makes a piece the surface behind everything else.
@Suite("A piece can take the room a row has left over")
struct GroupFillTests {

    // MARK: - Building blocks

    private func box(_ name: String, _ frame: CGRect,
                     placement: LayerPlacement? = nil, fills: Bool = false) -> Layer {
        var layer = Layer(name: name, content: .image(ImageRef(pixelSize: frame.size)),
                          frame: frame, placement: placement)
        if fills { layer.flowFill = FlowFill(sizeBefore: frame.standardized.size) }
        return layer
    }

    private func group(_ children: [Layer], layout: GroupLayout? = nil,
                       contents: LayerPlacement? = nil) -> Layer {
        var content = GroupContent(children: children)
        content.layout = layout
        content.contentPlacement = contents
        return Layer(name: "Group", content: .group(content), frame: .zero)
    }

    private func frames(_ layer: Layer) -> [CGRect] { layer.children.map(\.frame) }

    /// Three pieces side by side, the middle one told to take what is left.
    private func bar(width: CGFloat?, gap: CGFloat = 12,
                     padding: GroupPadding = .none,
                     filling: Set<Int> = [1], count: Int = 3) -> Layer {
        let children = (0..<count).map { index in
            box("Piece \(index)", CGRect(x: CGFloat(index) * 200, y: 0, width: 100, height: 40),
                fills: filling.contains(index))
        }
        return group(children, layout: GroupLayout(kind: .stack, direction: .row, gap: gap,
                                                   padding: padding, width: width))
    }

    // MARK: - The room left over

    @Test("The one piece told to fill takes what the others and the gaps leave")
    func oneFillerTakesTheRest() {
        let laid = GroupFlow.flowing(bar(width: 800))
        // 800 wide, two 100-wide neighbours, two 12-point gaps: 576 left.
        #expect(frames(laid).map(\.width) == [100, 576, 100])
        #expect(frames(laid).map(\.minX) == [0, 112, 700])
    }

    @Test("The room at the edges is taken off before the filler takes its share")
    func paddingComesOffFirst() {
        let laid = GroupFlow.flowing(bar(width: 800, padding: GroupPadding(20)))
        // 800 less 40 of room, less two 100s, less two 12s: 536 left.
        #expect(frames(laid).map(\.width) == [100, 536, 100])
        #expect(frames(laid).map(\.minX) == [20, 132, 680])
        #expect(frames(laid).last?.maxX == 780)
    }

    @Test("Two pieces told to fill split what is left down the middle")
    func twoFillersShareEqually() {
        let laid = GroupFlow.flowing(bar(width: 800, filling: [0, 2]))
        // 800 less the 100 in the middle, less two 12s: 676 between two.
        #expect(frames(laid).map(\.width) == [338, 100, 338])
        #expect(frames(laid).last?.maxX == 800)
    }

    @Test("An odd number of points left over still lands the last piece on the edge")
    func roundingLandsOnTheEdge() {
        let laid = GroupFlow.flowing(bar(width: 801, filling: [0, 2]))
        let widths = frames(laid).map(\.width)
        #expect(widths.allSatisfy { $0 == $0.rounded() })
        #expect(frames(laid).last?.maxX == 801)
    }

    @Test("A filler is never squeezed below nothing")
    func neverBelowNothing() {
        // Three 100s and two gaps need 324; the stack is 200.
        let laid = GroupFlow.flowing(bar(width: 200))
        let middle = frames(laid)[1]
        #expect(middle.width >= 0)
        // A shape that had a size keeps at least a point of it, so it can be
        // grabbed and given a size back.
        #expect(middle.width == 1)
    }

    // MARK: - Down the page

    @Test("A column stack hands its filler the height that is left")
    func fillingDownAColumn() {
        let children = (0..<3).map { index in
            box("Piece \(index)", CGRect(x: 0, y: CGFloat(index) * 100, width: 60, height: 40),
                fills: index == 1)
        }
        let column = group(children, layout: GroupLayout(kind: .stack, direction: .column,
                                                         gap: 10, height: 300))
        let laid = GroupFlow.flowing(column)
        #expect(frames(laid).map(\.height) == [40, 200, 40])
        #expect(frames(laid).map(\.minY) == [0, 50, 260])
    }

    // MARK: - A stack with nothing to spare

    @Test("A stack the size of its contents has nothing to fill, so nothing moves")
    func huggingStackFillsNothing() {
        let laid = GroupFlow.flowing(bar(width: nil))
        #expect(frames(laid).map(\.width) == [100, 100, 100])
    }

    @Test("A floor holding a stack open is room a filler can take")
    func aFloorMakesRoom() {
        var layout = GroupLayout(kind: .stack, direction: .row, gap: 12)
        layout.minWidth = 800
        let children = (0..<3).map { index in
            box("Piece \(index)", CGRect(x: CGFloat(index) * 200, y: 0, width: 100, height: 40),
                fills: index == 1)
        }
        let laid = GroupFlow.flowing(group(children, layout: layout))
        #expect(frames(laid).map(\.width) == [100, 576, 100])
    }

    @Test("Room to fill is offered only where the way the stack runs has some")
    func roomIsOfferedWhereThereIsSome() {
        #expect(GroupLayout(kind: .stack, direction: .row).hasRoomAlongTheFlow == false)
        #expect(GroupLayout(kind: .stack, direction: .row, width: 800).hasRoomAlongTheFlow)
        // A row told how TALL it is still has nothing to spare across.
        #expect(GroupLayout(kind: .stack, direction: .row, height: 44)
            .hasRoomAlongTheFlow == false)
        #expect(GroupLayout(kind: .stack, direction: .column, height: 300).hasRoomAlongTheFlow)
        #expect(GroupLayout(kind: .grid, width: 800).hasRoomAlongTheFlow == false)
        #expect(GroupLayout.free(width: 800).hasRoomAlongTheFlow == false)
    }

    // MARK: - Where filling meets the other two rules

    @Test("A filler takes the room a spreading stack would have shared, and the gap comes back")
    func fillingBeatsSpreading() {
        var layout = GroupLayout(kind: .stack, direction: .row, gap: 12, width: 800)
        layout.spreadsGap = true
        let children = (0..<3).map { index in
            box("Piece \(index)", CGRect(x: CGFloat(index) * 200, y: 0, width: 100, height: 40),
                fills: index == 1)
        }
        let laid = GroupFlow.flowing(group(children, layout: layout))
        #expect(frames(laid).map(\.width) == [100, 576, 100])
        #expect(frames(laid).map(\.minX) == [0, 112, 700])
    }

    @Test("The surface behind everything does not join the sharing")
    func theSurfaceStaysOut() {
        var children = [box("Surface", CGRect(x: 0, y: 0, width: 10, height: 10),
                            placement: .fill)]
        children += (0..<2).map { index in
            box("Piece \(index)", CGRect(x: CGFloat(index) * 200 + 20, y: 0,
                                         width: 100, height: 40),
                fills: index == 1)
        }
        let laid = GroupFlow.flowing(
            group(children, layout: GroupLayout(kind: .stack, direction: .row,
                                                gap: 12, width: 800, height: 40)))
        // Painted to the whole box, not to a share of what is left.
        #expect(frames(laid)[0] == CGRect(x: 0, y: 0, width: 800, height: 40))
        // And the two being arranged split the box between them as if it were
        // not there: 800 less 100 less one 12-point gap.
        #expect(frames(laid)[1].width == 100)
        #expect(frames(laid)[2].width == 688)
    }

    @Test("A hidden piece takes no room, and the filler takes the room it let go of")
    func aHiddenPieceLeavesItsRoom() {
        var children = (0..<3).map { index in
            box("Piece \(index)", CGRect(x: CGFloat(index) * 200, y: 0, width: 100, height: 40),
                fills: index == 1)
        }
        children[2].isVisible = false
        let laid = GroupFlow.flowing(
            group(children, layout: GroupLayout(kind: .stack, direction: .row,
                                                gap: 12, width: 800)))
        #expect(frames(laid)[1].width == 688)
    }

    // MARK: - Words

    @Test("Words told to fill a column take the height they are handed")
    func wordsFillingAColumn() {
        let words = Layer(name: "Label",
                          content: .text(TextContent(string: "Hello", fontSize: 14)),
                          frame: CGRect(x: 0, y: 0, width: 120, height: 20))
        var filler = words
        filler.flowFill = FlowFill(sizeBefore: filler.frame.size)
        let below = box("Piece", CGRect(x: 0, y: 100, width: 60, height: 40))
        let laid = GroupFlow.flowing(
            group([filler, below], layout: GroupLayout(kind: .stack, direction: .column,
                                                       gap: 10, height: 300)))
        // Measured on the words a person can SEE: a text box carries a few
        // points of slack past its last line, which the flow hands back.
        #expect(laid.children[0].contentBounds.height == 250)
        #expect(frames(laid)[1].minY == 260)
    }

    // MARK: - Turning it on and off

    @Test("Turning Fill on records the size it had, and the stack fills it")
    func turningItOnRemembersTheSize() {
        var document = documentWithARow()
        let middle = document.layers[0].children[1].id
        document.setFillsTheFlow(id: middle, true)
        document.reflowLayouts()
        #expect(document.layer(id: middle)?.flowFill?.sizeBefore == CGSize(width: 100, height: 40))
        #expect(document.layer(id: middle)?.frame.width == 576)
    }

    @Test("Turning Fill off gives the piece back the size it had before")
    func turningItOffGivesTheSizeBack() {
        var document = documentWithARow()
        let middle = document.layers[0].children[1].id
        document.setFillsTheFlow(id: middle, true)
        document.reflowLayouts()
        document.setFillsTheFlow(id: middle, false)
        document.reflowLayouts()
        #expect(document.layer(id: middle)?.fillsTheFlow == false)
        #expect(document.layer(id: middle)?.flowFill == nil)
        #expect(document.layer(id: middle)?.frame.width == 100)
    }

    @Test("Turning Fill off down a column gives the height back")
    func turningItOffDownAColumn() {
        let children = (0..<3).map { index in
            box("Piece \(index)", CGRect(x: 0, y: CGFloat(index) * 100, width: 60, height: 40))
        }
        var document = PhotonzDocument(canvasSize: CGSize(width: 1000, height: 1000))
        document.layers = [group(children, layout: GroupLayout(kind: .stack, direction: .column,
                                                               gap: 10, height: 300))]
        let middle = document.layers[0].children[1].id
        document.setFillsTheFlow(id: middle, true)
        document.reflowLayouts()
        #expect(document.layer(id: middle)?.frame.height == 200)
        document.setFillsTheFlow(id: middle, false)
        document.reflowLayouts()
        #expect(document.layer(id: middle)?.frame.height == 40)
    }

    private func documentWithARow() -> PhotonzDocument {
        var document = PhotonzDocument(canvasSize: CGSize(width: 1000, height: 1000))
        document.layers = [bar(width: 800, filling: [])]
        return document
    }

    // MARK: - What the panel is told

    @Test("The row the flow owns offers Fill where the stack has room")
    func theRowOffersFill() {
        let row = PlacementEditing(arrangement: GroupLayout(kind: .stack, direction: .row,
                                                            width: 800))
        #expect(row.canSetHorizontal == false)
        #expect(row.canFill)
        #expect(row.noRoomToFill == nil)
    }

    @Test("The answer names the flow, so it is never the Colour section's Fill")
    func theAnswerNamesTheFlow() {
        #expect(PlacementEditing(arrangement: GroupLayout(kind: .stack, direction: .row,
                                                          width: 800)).fillTitle
                == "Fill the row")
        #expect(PlacementEditing(arrangement: GroupLayout(kind: .stack, direction: .column,
                                                          height: 300)).fillTitle
                == "Fill the stack")
        #expect(PlacementEditing(arrangement: GroupLayout.free()).fillTitle == nil)
    }

    @Test("The size the stack worked out is a number to read, not one to type")
    func theFilledSideIsNotTypeable() {
        let stack = bar(width: 800)
        let piece = stack.children[1]
        let fields = LayerGeometryEditing(layer: piece, in: stack)
        #expect(fields.allows(.width) == false)
        #expect(fields.shows(.width))
        #expect(fields.fixedReason(for: .width) == LayerGeometryEditing.fillingReason)
        // Down the page is still the piece's own answer in a row stack.
        #expect(fields.allows(.height))
    }

    @Test("A piece that is not filling keeps its typed size")
    func aPieceThatIsNotFillingKeepsItsField() {
        let stack = bar(width: 800)
        let fields = LayerGeometryEditing(layer: stack.children[0], in: stack)
        #expect(fields.allows(.width))
    }

    @Test("A hugging stack says why there is nothing to fill instead of offering it")
    func aHuggingStackSaysWhy() {
        let row = PlacementEditing(arrangement: GroupLayout(kind: .stack, direction: .row))
        #expect(row.canFill == false)
        #expect(row.noRoomToFill?.contains("Width") == true)
        let column = PlacementEditing(arrangement: GroupLayout(kind: .stack, direction: .column))
        #expect(column.noRoomToFill?.contains("Height") == true)
    }

    @Test("A screen is a box somebody drew, so a stack on one always has room")
    func aScreenAlwaysHasRoom() {
        let row = PlacementEditing(arrangement: GroupLayout(kind: .stack, direction: .row),
                                   onAScreen: true)
        #expect(row.canFill)
    }

    @Test("A group that arranges nothing asks neither question, so neither offers Fill")
    func afreeGroupOffersNothing() {
        let free = PlacementEditing(arrangement: GroupLayout.free())
        #expect(free.canFill == false)
        #expect(free.noRoomToFill == nil)
        let grid = PlacementEditing(arrangement: GroupLayout(kind: .grid, width: 800))
        #expect(grid.canFill == false)
        #expect(grid.noRoomToFill == nil)
    }

    @Test("The piece stretched both ways is the surface, so it is not asked to fill")
    func theSurfaceIsNotAskedToFill() {
        let surface = LayerPlacement.resolving(child: .fill, container: nil)
        let flow = PlacementEditing(arrangement: GroupLayout(kind: .stack, direction: .row,
                                                             width: 800),
                                    placing: surface)
        #expect(flow.canFill == false)
    }

    @Test("A filler is named in the group's list of pieces with a rule of their own")
    func aFillerIsNamed() {
        let layout = GroupLayout(kind: .stack, direction: .row, gap: 12, width: 800)
        let stack = bar(width: 800)
        let overrides = stack.contentsWithTheirOwnPlacement(arrangement: layout)
        #expect(overrides.count == 1)
        #expect(overrides.first?.name == "Piece 1")
        #expect(overrides.first?.summary == "Takes the room left over")
    }

    // MARK: - Documents from before this existed

    @Test("A layer saved before a piece could fill opens as one that does not")
    func oldDocumentsDoNotFill() throws {
        let layer = box("Piece", CGRect(x: 0, y: 0, width: 100, height: 40))
        var json = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(layer)) as? [String: Any] ?? [:]
        json.removeValue(forKey: "flowFill")
        let data = try JSONSerialization.data(withJSONObject: json)
        let back = try JSONDecoder().decode(Layer.self, from: data)
        #expect(back.fillsTheFlow == false)
    }

    @Test("A piece told to fill is saved and opens still filling")
    func fillingSurvivesASave() throws {
        let layer = box("Piece", CGRect(x: 0, y: 0, width: 100, height: 40), fills: true)
        let back = try JSONDecoder().decode(Layer.self, from: JSONEncoder().encode(layer))
        #expect(back.fillsTheFlow)
        #expect(back.flowFill?.sizeBefore == CGSize(width: 100, height: 40))
    }
}
