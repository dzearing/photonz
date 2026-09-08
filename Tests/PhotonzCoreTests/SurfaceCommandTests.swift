import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// The one way in to "be the surface behind the rest"
/// (`docs/design/ui-building.md`, "Stretch inside a hugging container means
/// surface").
///
/// Being the surface was only ever reachable by stretching a piece one way and
/// then the other, and only the second of those two picks said what it was
/// about to do. Inside a STACK it was not reachable at all: the stack owns the
/// direction it runs, so its menu never offered the second Stretch. This is the
/// reading behind the row that says it in one step, in the Layout section and
/// in the Layer menu: whether it is on, whether it is live, and what it says
/// when it is not.
@Suite("Making a piece the surface behind the rest")
struct SurfaceCommandTests {

    // MARK: - Building blocks

    private func box(_ name: String, _ frame: CGRect,
                     placement: LayerPlacement? = nil) -> Layer {
        Layer(name: name, content: .image(ImageRef(pixelSize: frame.size)),
              frame: frame, placement: placement)
    }

    private func group(_ name: String, _ children: [Layer], layout: GroupLayout?,
                       contentPlacement: LayerPlacement? = nil) -> Layer {
        var content = GroupContent(children: children)
        content.layout = layout
        content.contentPlacement = contentPlacement
        return Layer(name: name, content: .group(content), frame: .zero)
    }

    /// Three pieces in a group with the given layout.
    private func document(layout: GroupLayout?,
                          contentPlacement: LayerPlacement? = nil) -> PhotonzDocument {
        var document = PhotonzDocument(canvasSize: CGSize(width: 1000, height: 1000))
        let children = (0..<3).map { index in
            box("Piece \(index)",
                CGRect(x: CGFloat(index) * 200, y: CGFloat(index) * 100, width: 100, height: 40))
        }
        document.layers = [group("Card", children, layout: layout,
                                 contentPlacement: contentPlacement)]
        return document
    }

    private func pieces(_ document: PhotonzDocument) -> [UUID] {
        document.layers[0].children.map(\.id)
    }

    private func isSurface(_ document: PhotonzDocument, _ id: UUID) -> Bool {
        let container = document.containingGroup(of: id)
        return document.layer(id: id)?.resolvedPlacement(in: container).isSurface == true
    }

    private static let row = GroupLayout(kind: .stack, direction: .row, gap: 12, width: 800)
    private static let column = GroupLayout(kind: .stack, direction: .column, gap: 12,
                                            height: 500)
    private static let grid = GroupLayout(kind: .grid, direction: .row, gap: 12, width: 800)

    // MARK: - Why this row has to exist

    @Test("A stack owns the direction it runs, so its own menus can never make a surface")
    func theStackNeverOffersTheSecondStretch() {
        let ordinary = ResolvedPlacement(horizontal: .left, vertical: .top,
                                         followsHorizontal: true, followsVertical: true)
        let down = PlacementEditing(arrangement: Self.column, placing: ordinary)
        #expect(down.canSetVertical == false)
        let across = PlacementEditing(arrangement: Self.row, placing: ordinary)
        #expect(across.canSetHorizontal == false)
    }

    // MARK: - What the row reads

    @Test("A piece in a stack is offered it, unticked and with nothing to explain")
    func offeredInAStack() {
        let document = document(layout: Self.column)
        let command = document.surfaceCommand(layerIDs: [pieces(document)[1]])
        #expect(command.isEnabled)
        #expect(!command.isOn)
        #expect(command.reason == nil)
        #expect(command.layers == [pieces(document)[1]])
    }

    @Test("Pieces that agree are not mixed")
    func notMixedWhenTheyAgree() {
        let document = document(layout: Self.column)
        #expect(!document.surfaceCommand(layerIDs: pieces(document)).isMixed)
    }

    @Test("A piece in a grid is offered it too")
    func offeredInAGrid() {
        let document = document(layout: Self.grid)
        #expect(document.surfaceCommand(layerIDs: [pieces(document)[0]]).isEnabled)
    }

    @Test("A piece already stretched both ways reads as ticked")
    func alreadyTheSurfaceReadsTicked() {
        let document = document(layout: Self.column)
        var edited = document
        edited.setSurface(ids: [pieces(document)[1]], true)
        #expect(edited.surfaceCommand(layerIDs: [pieces(document)[1]]).isOn)
    }

    @Test("Several pieces are all reached, and one that is not the surface unticks it")
    func severalPieces() {
        var document = document(layout: Self.column)
        let ids = pieces(document)
        document.setSurface(ids: [ids[0]], true)
        let command = document.surfaceCommand(layerIDs: [ids[0], ids[1]])
        #expect(command.layers == [ids[0], ids[1]])
        #expect(!command.isOn)
        #expect(command.isMixed)
        #expect(command.isEnabled)
    }

    @Test("A piece stretched the way its stack runs reads as spanning, not as one of the pieces")
    func spanningReadsAsItself() {
        var document = document(layout: Self.column)
        let id = pieces(document)[1]
        document.setPlacement(id: id, vertical: .stretch)
        let command = document.surfaceCommand(layerIDs: [id])
        #expect(!command.isOn)
        #expect(command.isSpanning)
        #expect(command.isEnabled)
    }

    @Test("An ordinary piece is not spanning, and neither is the surface")
    func ordinaryAndSurfaceAreNotSpanning() {
        var document = document(layout: Self.column)
        let id = pieces(document)[1]
        #expect(!document.surfaceCommand(layerIDs: [id]).isSpanning)
        document.setSurface(ids: [id], true)
        #expect(!document.surfaceCommand(layerIDs: [id]).isSpanning)
    }

    @Test("Picking one of the pieces takes a spanning piece out of it")
    func spanningGoesBack() {
        var document = document(layout: Self.column)
        let id = pieces(document)[1]
        document.setPlacement(id: id, vertical: .stretch)
        document.setSurface(ids: [id], false)
        #expect(!document.surfaceCommand(layerIDs: [id]).isSpanning)
        #expect(document.layer(id: id)?.placement == nil)
    }

    // MARK: - Where it is not on offer

    @Test("A piece in a group that arranges nothing is not offered it, and is told why")
    func notInAnArrangement() {
        let document = document(layout: nil)
        let command = document.surfaceCommand(layerIDs: [pieces(document)[0]])
        #expect(!command.isEnabled)
        #expect(command.reason == SurfaceCommand.notArrangedReason)
    }

    @Test("A piece loose on the canvas is not offered it")
    func looseOnTheCanvas() {
        var document = PhotonzDocument(canvasSize: CGSize(width: 100, height: 100))
        document.layers = [box("Loose", CGRect(x: 0, y: 0, width: 10, height: 10))]
        let command = document.surfaceCommand(layerIDs: [document.layers[0].id])
        #expect(!command.isEnabled)
        #expect(command.reason == SurfaceCommand.notArrangedReason)
    }

    @Test("Nothing picked is a dead row with nothing to explain")
    func nothingPicked() {
        let document = document(layout: Self.column)
        let command = document.surfaceCommand(layerIDs: [])
        #expect(!command.isEnabled)
        #expect(command.reason == nil)
        #expect(command.layers.isEmpty)
    }

    @Test("Pieces in two different groups are not offered it, and are told why")
    func differentContainers() {
        var document = PhotonzDocument(canvasSize: CGSize(width: 1000, height: 1000))
        let one = box("One", CGRect(x: 0, y: 0, width: 10, height: 10))
        let two = box("Two", CGRect(x: 0, y: 0, width: 10, height: 10))
        document.layers = [group("A", [one], layout: Self.column),
                           group("B", [two], layout: Self.column)]
        let command = document.surfaceCommand(layerIDs: [one.id, two.id])
        #expect(!command.isEnabled)
        #expect(command.reason == PlacementSelection.differentContainersNote)
    }

    @Test("Where the group itself says stretch both ways the row is ticked and says who set it")
    func setByTheGroup() {
        let document = document(layout: Self.grid, contentPlacement: .fill)
        let command = document.surfaceCommand(layerIDs: [pieces(document)[0]])
        #expect(command.isOn)
        #expect(!command.isEnabled)
        #expect(command.reason == SurfaceCommand.setByTheGroupReason)
    }

    // MARK: - What it does

    @Test("Turning it on makes the piece the surface, in one edit")
    func turningItOn() {
        var document = document(layout: Self.column)
        let id = pieces(document)[1]
        document.setSurface(ids: [id], true)
        #expect(isSurface(document, id))
        #expect(document.layer(id: id)?.placement?.horizontal == .stretch)
        #expect(document.layer(id: id)?.placement?.vertical == .stretch)
    }

    @Test("Turning it off hands both directions back to the group")
    func turningItOff() {
        var document = document(layout: Self.column)
        let id = pieces(document)[1]
        document.setSurface(ids: [id], true)
        document.setSurface(ids: [id], false)
        #expect(!isSurface(document, id))
        #expect(document.layer(id: id)?.placement == nil)
    }

    @Test("A piece taking the room left over stops when it becomes the surface")
    func fillingStopsAtTheSurface() {
        var document = document(layout: Self.row)
        let id = pieces(document)[1]
        let before = document.layer(id: id)?.frame.size
        document.setFillsTheFlow(id: id, true)
        document.updateLayer(id: id) { $0.frame.size = CGSize(width: 400, height: 40) }
        document.setSurface(ids: [id], true)
        #expect(document.layer(id: id)?.fillsTheFlow == false)
        #expect(document.layer(id: id)?.frame.size == before)
    }

    @Test("Several pieces are all made the surface in one call")
    func severalAtOnce() {
        var document = document(layout: Self.column)
        let ids = pieces(document)
        document.setSurface(ids: [ids[0], ids[1]], true)
        #expect(isSurface(document, ids[0]))
        #expect(isSurface(document, ids[1]))
        #expect(!isSurface(document, ids[2]))
    }

    @Test("Setting what is already set changes nothing")
    func settingWhatIsSet() {
        var document = document(layout: Self.column)
        let id = pieces(document)[0]
        document.setSurface(ids: [id], false)
        #expect(document.layer(id: id)?.placement == nil)
    }

    // MARK: - The words

    @Test("The row says the same name the rest of the app says, in a menu's case")
    func theWords() {
        #expect(ResolvedPlacement.surfaceTitle == "Surface behind the rest")
        #expect(SurfaceCommand.menuTitle == "Surface Behind the Rest")
        #expect(ResolvedPlacement.arrangedTitle == "One of the pieces")
        #expect(ResolvedPlacement.spanningTitle == "Spans the group")
    }

    @Test("A live row says what pressing it gives you, a dead one says why not")
    func theHelp() {
        let document = document(layout: Self.column)
        #expect(document.surfaceCommand(layerIDs: [pieces(document)[0]]).help
                    == SurfaceCommand.makesSurfaceReason)
        let plain = self.document(layout: nil)
        #expect(plain.surfaceCommand(layerIDs: [pieces(plain)[0]]).help
                    == SurfaceCommand.notArrangedReason)
    }
}
