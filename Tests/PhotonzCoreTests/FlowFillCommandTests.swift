import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// The menu's side of "take the room the stack has left over"
/// (`docs/design/ui-building.md`, "A group can arrange its own contents").
///
/// The panel has offered this since the flow landed, buried two rows into the
/// Layout section. It is the answer people reach for most while building a bar,
/// so it is also one row in the Layer menu with a key on it, and this is the
/// reading that row goes by: what it is called, whether it is ticked, whether
/// it is live, and what it says when it is not.
@Suite("The menu row for taking the room left over")
struct FlowFillCommandTests {

    // MARK: - Building blocks

    private func box(_ name: String, _ frame: CGRect,
                     placement: LayerPlacement? = nil) -> Layer {
        Layer(name: name, content: .image(ImageRef(pixelSize: frame.size)),
              frame: frame, placement: placement)
    }

    private func group(_ name: String, _ children: [Layer], layout: GroupLayout?) -> Layer {
        var content = GroupContent(children: children)
        content.layout = layout
        return Layer(name: name, content: .group(content), frame: .zero)
    }

    /// Three pieces side by side in a stack of the given layout.
    private func document(layout: GroupLayout?) -> PhotonzDocument {
        var document = PhotonzDocument(canvasSize: CGSize(width: 1000, height: 1000))
        let children = (0..<3).map { index in
            box("Piece \(index)",
                CGRect(x: CGFloat(index) * 200, y: CGFloat(index) * 100, width: 100, height: 40))
        }
        document.layers = [group("Bar", children, layout: layout)]
        return document
    }

    private func pieces(_ document: PhotonzDocument) -> [UUID] {
        document.layers[0].children.map(\.id)
    }

    private static let row = GroupLayout(kind: .stack, direction: .row, gap: 12, width: 800)
    private static let column = GroupLayout(kind: .stack, direction: .column, gap: 12,
                                            height: 500)

    // MARK: - When it is offered

    @Test("A piece in a row that has room is offered it, named after the row")
    func offeredInARow() {
        let document = document(layout: Self.row)
        let command = document.flowFillCommand(layerIDs: [pieces(document)[1]])
        #expect(command.isEnabled)
        #expect(command.title == "Fill the Row")
        #expect(!command.isOn)
        #expect(command.reason == nil)
        #expect(command.layers == [pieces(document)[1]])
    }

    @Test("The same piece down a column is named after the stack")
    func offeredDownAColumn() {
        let document = document(layout: Self.column)
        let command = document.flowFillCommand(layerIDs: [pieces(document)[1]])
        #expect(command.isEnabled)
        #expect(command.title == "Fill the Stack")
    }

    @Test("A piece already taking the room reads as ticked")
    func alreadyFillingReadsTicked() {
        var document = document(layout: Self.row)
        document.setFillsTheFlow(id: pieces(document)[1], true)
        #expect(document.flowFillCommand(layerIDs: [pieces(document)[1]]).isOn)
    }

    @Test("Several pieces in one row are all reached, and one that is not filling unticks it")
    func severalPiecesInOneRow() {
        var document = document(layout: Self.row)
        let ids = pieces(document)
        document.setFillsTheFlow(id: ids[0], true)
        let command = document.flowFillCommand(layerIDs: [ids[0], ids[1]])
        #expect(command.isEnabled)
        #expect(command.layers == [ids[0], ids[1]])
        #expect(!command.isOn)
    }

    @Test("A stack on a screen always has room, whatever its own size says")
    func aStackOnAScreenHasRoom() {
        var document = PhotonzDocument(canvasSize: CGSize(width: 1000, height: 1000))
        let bar = group("Bar", [box("Piece", CGRect(x: 0, y: 0, width: 100, height: 40))],
                        layout: GroupLayout(kind: .stack, direction: .row, gap: 12))
        var screen = GroupContent(children: [bar], isFrame: true)
        screen.layout = GroupLayout(kind: .stack, direction: .column, gap: 0)
        document.layers = [Layer(name: "Screen", content: .group(screen),
                                 frame: CGRect(x: 0, y: 0, width: 400, height: 800))]
        let command = document.flowFillCommand(layerIDs: [document.layers[0].children[0].id])
        #expect(command.isEnabled)
        #expect(command.title == "Fill the Stack")
    }

    // MARK: - When it is not, and what it says instead

    @Test("Nothing picked leaves the row dead and silent")
    func nothingPicked() {
        let document = document(layout: Self.row)
        let command = document.flowFillCommand(layerIDs: [])
        #expect(!command.isEnabled)
        #expect(command.reason == nil)
        #expect(command.title == FlowFillCommand.defaultTitle)
        #expect(command.layers.isEmpty)
    }

    @Test("A piece loose on the canvas is told it needs a stack")
    func looseOnTheCanvas() {
        var document = PhotonzDocument(canvasSize: CGSize(width: 1000, height: 1000))
        document.layers = [box("Loose", CGRect(x: 0, y: 0, width: 100, height: 40))]
        let command = document.flowFillCommand(layerIDs: [document.layers[0].id])
        #expect(!command.isEnabled)
        #expect(command.reason == FlowFillCommand.notInAStackReason)
    }

    @Test("A piece in a group that arranges nothing is told the same")
    func inAPlainGroup() {
        let document = document(layout: nil)
        let command = document.flowFillCommand(layerIDs: [pieces(document)[1]])
        #expect(!command.isEnabled)
        #expect(command.reason == FlowFillCommand.notInAStackReason)
    }

    @Test("A piece in a grid is told the same: a grid shares its room out already")
    func inAGrid() {
        let document = document(layout: GroupLayout(kind: .grid, direction: .row, columns: 2,
                                                    gap: 12, width: 800))
        let command = document.flowFillCommand(layerIDs: [pieces(document)[1]])
        #expect(!command.isEnabled)
        #expect(command.reason == FlowFillCommand.notInAStackReason)
    }

    @Test("A row as wide as its contents says there is no room and names the number to type")
    func aRowWithNoRoom() {
        let document = document(layout: GroupLayout(kind: .stack, direction: .row, gap: 12))
        let command = document.flowFillCommand(layerIDs: [pieces(document)[1]])
        #expect(!command.isEnabled)
        #expect(command.reason == PlacementEditing.noRoomReason(across: true))
        #expect(command.reason?.contains("Width") == true)
        // Still named after the row it is in, so the dead row is not a puzzle.
        #expect(command.title == "Fill the Row")
    }

    @Test("A column as tall as its contents names Height instead")
    func aColumnWithNoRoom() {
        let document = document(layout: GroupLayout(kind: .stack, direction: .column, gap: 12))
        let command = document.flowFillCommand(layerIDs: [pieces(document)[1]])
        #expect(!command.isEnabled)
        #expect(command.reason?.contains("Height") == true)
    }

    @Test("The piece that spans the group is painted to its edges, so it has nothing to take")
    func theSurfaceHasNothingToTake() {
        var document = document(layout: Self.row)
        let id = pieces(document)[0]
        document.setPlacement(id: id, horizontal: .stretch)
        document.setPlacement(id: id, vertical: .stretch)
        let command = document.flowFillCommand(layerIDs: [id])
        #expect(!command.isEnabled)
        #expect(command.reason == FlowFillCommand.spansTheGroupReason)
    }

    @Test("One piece out of the flow takes the whole row down with it")
    func oneSpanningPieceStopsTheWholeSelection() {
        var document = document(layout: Self.row)
        let ids = pieces(document)
        document.setPlacement(id: ids[0], horizontal: .stretch)
        document.setPlacement(id: ids[0], vertical: .stretch)
        let command = document.flowFillCommand(layerIDs: [ids[0], ids[1]])
        #expect(!command.isEnabled)
        #expect(command.reason == FlowFillCommand.spansTheGroupReason)
    }

    @Test("Pieces picked from two different groups are told they share no place")
    func piecesInDifferentGroups() {
        var document = PhotonzDocument(canvasSize: CGSize(width: 1000, height: 1000))
        document.layers = [
            group("Bar", [box("A", CGRect(x: 0, y: 0, width: 100, height: 40))],
                  layout: Self.row),
            group("Other", [box("B", CGRect(x: 0, y: 200, width: 100, height: 40))],
                  layout: Self.row)]
        let command = document.flowFillCommand(
            layerIDs: [document.layers[0].children[0].id, document.layers[1].children[0].id])
        #expect(!command.isEnabled)
        #expect(command.reason == PlacementSelection.differentContainersNote)
    }

    // MARK: - Turning it off is always reachable

    @Test("A fill left stranded when the room went away can still be switched off")
    func astrandedFillCanBeCleared() {
        var document = document(layout: Self.row)
        let id = pieces(document)[1]
        document.setFillsTheFlow(id: id, true)
        // The stack loses the width that gave it room to spare.
        document.updateGroupLayout(id: document.layers[0].id) { $0.width = nil }
        let command = document.flowFillCommand(layerIDs: [id])
        #expect(command.isOn)
        // Live, because a rule you cannot see the effect of and cannot take off
        // is worse than a dead row.
        #expect(command.isEnabled)
        #expect(command.reason == PlacementEditing.noRoomReason(across: true))
    }

    @Test("A fill stranded by a stretch both ways can still be switched off")
    func aStrandedFillOnASurfaceCanBeCleared() {
        var document = document(layout: Self.row)
        let id = pieces(document)[1]
        document.setFillsTheFlow(id: id, true)
        document.setPlacement(id: id, horizontal: .stretch)
        document.setPlacement(id: id, vertical: .stretch)
        let command = document.flowFillCommand(layerIDs: [id])
        #expect(command.isOn)
        #expect(command.isEnabled)
        #expect(command.reason == FlowFillCommand.spansTheGroupReason)
    }

    // MARK: - Pressing it twice

    @Test("Pressing it and pressing it again gives the piece back the size it had")
    func pressingItTwiceGivesTheSizeBack() {
        var document = document(layout: Self.row)
        let id = pieces(document)[1]
        var command = document.flowFillCommand(layerIDs: [id])
        _ = document.setFillsTheFlow(ids: command.layers, !command.isOn)
        document.reflowLayouts()
        #expect(document.layer(id: id)?.frame.width == 576)

        command = document.flowFillCommand(layerIDs: [id])
        #expect(command.isOn)
        _ = document.setFillsTheFlow(ids: command.layers, !command.isOn)
        document.reflowLayouts()
        #expect(document.layer(id: id)?.frame.width == 100)
        #expect(document.flowFillCommand(layerIDs: [id]).isOn == false)
    }

    @Test("Pressing it over a mixed selection turns them all on, then all off")
    func pressingItOverAMixedSelection() {
        var document = document(layout: Self.row)
        let ids = pieces(document)
        document.setFillsTheFlow(id: ids[0], true)
        var command = document.flowFillCommand(layerIDs: [ids[0], ids[1]])
        #expect(!command.isOn)
        _ = document.setFillsTheFlow(ids: command.layers, !command.isOn)
        #expect(document.layer(id: ids[0])?.fillsTheFlow == true)
        #expect(document.layer(id: ids[1])?.fillsTheFlow == true)
        command = document.flowFillCommand(layerIDs: [ids[0], ids[1]])
        #expect(command.isOn)
        _ = document.setFillsTheFlow(ids: command.layers, !command.isOn)
        #expect(document.layer(id: ids[0])?.fillsTheFlow == false)
        #expect(document.layer(id: ids[1])?.fillsTheFlow == false)
    }

    // MARK: - The words

    @Test("A live row says what pressing it does, naming the flow it would take from")
    func aLiveRowExplainsItself() {
        let across = document(layout: Self.row)
        #expect(across.flowFillCommand(layerIDs: [pieces(across)[1]]).help
                    == PlacementEditing.fillReason(PlacementEditing.rowNoun))
        let down = document(layout: Self.column)
        #expect(down.flowFillCommand(layerIDs: [pieces(down)[1]]).help
                    == PlacementEditing.fillReason(PlacementEditing.stackNoun))
    }

    @Test("A dead row says why instead")
    func aDeadRowExplainsWhy() {
        let document = document(layout: nil)
        #expect(document.flowFillCommand(layerIDs: [pieces(document)[1]]).help
                    == FlowFillCommand.notInAStackReason)
    }

    @Test("The menu name is the panel's own name, in the menu's own case")
    func theMenuNameMatchesThePanel() {
        #expect(PlacementEditing.fillMenuTitle(across: true) == "Fill the Row")
        #expect(PlacementEditing.fillMenuTitle(across: false) == "Fill the Stack")
        #expect(PlacementEditing.fillTitle(across: true) == "Fill the row")
        #expect(PlacementEditing.fillTitle(across: false) == "Fill the stack")
        #expect(FlowFillCommand.defaultTitle == "Fill the Stack")
    }
}
