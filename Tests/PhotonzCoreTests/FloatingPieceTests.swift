import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// A piece taken out of the line and placed by hand, in front of the rest.
///
/// A row or a column arranges everything in it, with exactly one exception:
/// the surface, which is painted to the group's own edges and always sits
/// BEHIND. A notification dot on the corner of a card and a New label over the
/// top of one want the other half of that idea — out of the line, in front —
/// and until this the only way to get it was to wrap the card in a second
/// group that arranges nothing.
///
/// These are the rules of that role: the line closes over the piece, the box
/// stops measuring it, it stays exactly where it was dragged, and when the box
/// changes size the piece's own Horizontal and Vertical rules carry it.
@Suite("A piece that floats in front of the line")
struct FloatingPieceTests {

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

    /// A row of two cards and a small dot sitting on the first one.
    private func document(layout: GroupLayout = row) -> PhotonzDocument {
        var document = PhotonzDocument(canvasSize: CGSize(width: 1000, height: 1000))
        let children = [box("Card A", CGRect(x: 0, y: 0, width: 100, height: 60)),
                        box("Card B", CGRect(x: 120, y: 0, width: 100, height: 60)),
                        box("Dot", CGRect(x: 240, y: 0, width: 16, height: 16))]
        document.layers = [group("Row", children, layout: layout)]
        document.reflowLayouts()
        return document
    }

    private func ids(_ document: PhotonzDocument) -> [UUID] {
        document.layers[0].children.map(\.id)
    }

    private func frame(_ document: PhotonzDocument, _ id: UUID) -> CGRect {
        document.layer(id: id)?.frame.standardized ?? .zero
    }

    private static let row = GroupLayout(kind: .stack, direction: .row, gap: 20)
    private static let column = GroupLayout(kind: .stack, direction: .column, gap: 20)
    private static let free = GroupLayout(kind: nil, direction: .row, gap: 0)

    /// The group dragged to a new width, the way its own handle does it.
    private func widen(_ document: inout PhotonzDocument, to width: CGFloat) {
        document.updateLayer(id: document.layers[0].id) { layer in
            guard var content = layer.group else { return }
            content.layout?.width = width
            layer.content = .group(content)
        }
    }

    // MARK: - The reading behind the Role row

    @Test("The row offers a third answer, and it is the one that puts a piece in front")
    func theRowOffersInFront() {
        var document = document()
        let dot = ids(document)[2]
        #expect(document.surfaceCommand(layerIDs: [dot]).role == .arranged)
        document.setFloating(ids: [dot], true)
        let command = document.surfaceCommand(layerIDs: [dot])
        #expect(command.role == .inFront)
        #expect(command.isFloating)
        #expect(command.isOn == false)
        #expect(command.isEnabled)
    }

    @Test("In front and the surface are the two directions of one idea, never both at once")
    func inFrontIsNotTheSurface() {
        var document = document()
        let dot = ids(document)[2]
        document.setFloating(ids: [dot], true)
        document.setPlacement(id: dot, horizontal: .stretch)
        document.setPlacement(id: dot, vertical: .stretch)
        let container = document.containingGroup(of: dot)
        let placement = document.layer(id: dot)?.resolvedPlacement(in: container)
        // Stretched both ways is what makes the SURFACE, and a piece already
        // told to float is in front of everything, so it cannot also be the
        // thing behind everything.
        #expect(placement?.isSurface == false)
        #expect(placement?.floats == true)
        #expect(document.surfaceCommand(layerIDs: [dot]).role == .inFront)
    }

    @Test("Picking the surface takes a floating piece out of the front, and back again")
    func thetwoRolesReplaceEachOther() {
        var document = document()
        let dot = ids(document)[2]
        document.setFloating(ids: [dot], true)
        document.setSurface(ids: [dot], true)
        #expect(document.layer(id: dot)?.floatsInFront == false)
        #expect(document.surfaceCommand(layerIDs: [dot]).role == .surface)
        document.setFloating(ids: [dot], true)
        #expect(document.surfaceCommand(layerIDs: [dot]).role == .inFront)
        let container = document.containingGroup(of: dot)
        #expect(document.layer(id: dot)?.resolvedPlacement(in: container).isSurface == false)
    }

    @Test("One of the pieces hands a floating piece back to the line")
    func backToTheLine() {
        var document = document()
        let dot = ids(document)[2]
        document.setFloating(ids: [dot], true)
        document.setFloating(ids: [dot], false)
        #expect(document.surfaceCommand(layerIDs: [dot]).role == .arranged)
        document.reflowLayouts()
        // Back in the line: third along the row, after both cards and the gaps.
        #expect(frame(document, dot).minX == 240)
    }

    @Test("A group that arranges nothing has no line to step out of, so the answer is dead")
    func nothingToStepOutOf() {
        var document = document(layout: Self.free)
        let dot = ids(document)[2]
        let command = document.surfaceCommand(layerIDs: [dot])
        #expect(command.isEnabled == false)
        #expect(command.reason == SurfaceCommand.notArrangedReason)
        // And the flag on the layer means nothing there either.
        document.setFloating(ids: [dot], true)
        let container = document.containingGroup(of: dot)
        #expect(document.layer(id: dot)?.resolvedPlacement(in: container).floats == false)
    }

    @Test("A selection where one floats and the next does not reads as mixed")
    func mixedSelection() {
        var document = document()
        let all = ids(document)
        document.setFloating(ids: [all[2]], true)
        let command = document.surfaceCommand(layerIDs: [all[0], all[2]])
        #expect(command.isMixed)
        #expect(command.role == .mixed)
    }

    // MARK: - The line closes over it

    @Test("The row arranges itself as though the floating piece were not there")
    func theLineClosesOver() {
        var document = document()
        let all = ids(document)
        document.setFloating(ids: [all[2]], true)
        document.reflowLayouts()
        #expect(frame(document, all[0]).minX == 0)
        #expect(frame(document, all[1]).minX == 120)
        // The group is as wide as the two cards and the gap between them, with
        // nothing added for the dot beyond them.
        #expect(document.layers[0].localBounds.width == 220)
    }

    @Test("A floating piece hanging past the corner does not grow the box")
    func itDoesNotGrowTheBox() {
        var document = document()
        let all = ids(document)
        document.setFloating(ids: [all[2]], true)
        document.moveLayer(id: all[2], toParentOrigin: CGPoint(x: 212, y: -8))
        document.reflowLayouts()
        #expect(document.layers[0].localBounds.width == 220)
        #expect(document.layers[0].localBounds.height == 60)
    }

    @Test("A floating piece stays exactly where it was dragged")
    func itStaysWhereYouPutIt() {
        var document = document()
        let all = ids(document)
        document.setFloating(ids: [all[2]], true)
        document.moveLayer(id: all[2], toParentOrigin: CGPoint(x: 86, y: -8))
        document.reflowLayouts()
        document.reflowLayouts()
        #expect(frame(document, all[2]).origin == CGPoint(x: 86, y: -8))
    }

    @Test("A column closes over a floating piece the same way a row does")
    func theSameDownAColumn() {
        var document = document(layout: Self.column)
        let all = ids(document)
        document.setFloating(ids: [all[2]], true)
        document.reflowLayouts()
        #expect(frame(document, all[0]).minY == 0)
        #expect(frame(document, all[1]).minY == 80)
        #expect(document.layers[0].localBounds.height == 140)
    }

    // MARK: - It is in front

    @Test("Taking a piece out of the line puts it in front of the rest")
    func itComesToTheFront() {
        var document = document()
        let all = ids(document)
        // Send the dot to the back first, so there is something to undo.
        document.moveLayer(id: all[2], to: 0)
        #expect(document.layers[0].children.first?.id == all[2])
        document.setFloating(ids: [all[2]], true)
        // Last in the list is nearest the viewer.
        #expect(document.layers[0].children.last?.id == all[2])
        #expect(document.layers[0].children.map(\.id) == [all[0], all[1], all[2]])
    }

    // MARK: - A resize carries it

    @Test("A floating piece held to the right edge keeps its distance from it")
    func theRightEdgeCarriesIt() {
        var document = document(layout: GroupLayout(kind: .stack, direction: .row, gap: 20,
                                                    width: 300))
        let all = ids(document)
        document.setFloating(ids: [all[2]], true)
        document.setPlacement(id: all[2], horizontal: .right)
        document.moveLayer(id: all[2], toParentOrigin: CGPoint(x: 276, y: -8))
        document.reflowLayouts()
        #expect(frame(document, all[2]).minX == 276)
        // The group is dragged 100 wider: the dot travels with the right edge.
        widen(&document, to: 400)
        document.reflowLayouts()
        #expect(frame(document, all[2]).minX == 376)
        #expect(frame(document, all[2]).minY == -8)
    }

    @Test("A floating piece held to the left edge stays put when the box grows")
    func theLeftEdgeHoldsStill() {
        var document = document(layout: GroupLayout(kind: .stack, direction: .row, gap: 20,
                                                    width: 300))
        let all = ids(document)
        document.setFloating(ids: [all[2]], true)
        document.setPlacement(id: all[2], horizontal: .left)
        document.moveLayer(id: all[2], toParentOrigin: CGPoint(x: 8, y: -8))
        document.reflowLayouts()
        widen(&document, to: 400)
        document.reflowLayouts()
        #expect(frame(document, all[2]).minX == 8)
    }

    @Test("A floating piece held to the middle keeps its offset from it")
    func theMiddleCarriesIt() {
        var document = document(layout: GroupLayout(kind: .stack, direction: .row, gap: 20,
                                                    width: 300))
        let all = ids(document)
        document.setFloating(ids: [all[2]], true)
        document.setPlacement(id: all[2], horizontal: .center)
        document.moveLayer(id: all[2], toParentOrigin: CGPoint(x: 142, y: -8))
        document.reflowLayouts()
        widen(&document, to: 400)
        document.reflowLayouts()
        #expect(frame(document, all[2]).minX == 192)
    }

    // MARK: - Placed by hand means placed by hand

    @Test("A floating piece takes a typed X and Y, where everything else in a stack cannot")
    func theNumbersComeBack() {
        var document = document()
        let all = ids(document)
        let container = document.containingGroup(of: all[2])
        let before = LayerGeometryEditing(layer: document.layer(id: all[2])!, in: container)
        #expect(before.canMove == false)
        document.setFloating(ids: [all[2]], true)
        let after = LayerGeometryEditing(layer: document.layer(id: all[2])!, in: container)
        #expect(after.canMove)
        #expect(after.allows(.x))
        #expect(after.allows(.y))
    }

    @Test("A piece taking the room the row has left stops doing that when it floats")
    func fillingStops() {
        var document = document(layout: GroupLayout(kind: .stack, direction: .row, gap: 20,
                                                    width: 400))
        let all = ids(document)
        document.setFillsTheFlow(id: all[2], true)
        #expect(document.layer(id: all[2])?.fillsTheFlow == true)
        document.setFloating(ids: [all[2]], true)
        #expect(document.layer(id: all[2])?.fillsTheFlow == false)
    }

    // MARK: - What it is called

    @Test("The three answers are three different sentences, and the app has one name for each")
    func theNames() {
        #expect(PieceRole.arranged.title == ResolvedPlacement.arrangedTitle)
        #expect(PieceRole.surface.title == ResolvedPlacement.surfaceTitle)
        #expect(PieceRole.inFront.title == ResolvedPlacement.inFrontTitle)
        #expect(PieceRole.spanning.title == ResolvedPlacement.spanningTitle)
        let titles = Set(PieceRole.allCases.map(\.title))
        #expect(titles.count == PieceRole.allCases.count)
        // The menu says the same words in the case a menu wears.
        #expect(FloatingCommand.menuTitle == "In Front of the Rest")
    }

    // MARK: - Documents written before this

    @Test("A document written before this role existed writes not one new key")
    func oldDocumentsAreUntouched() throws {
        let document = document()
        let data = try JSONEncoder().encode(document)
        let text = String(decoding: data, as: UTF8.self)
        #expect(!text.contains("floating"))
    }

    @Test("A floating piece survives a round trip through the file")
    func itSurvivesTheFile() throws {
        var document = document()
        let dot = ids(document)[2]
        document.setFloating(ids: [dot], true)
        let data = try JSONEncoder().encode(document)
        let back = try JSONDecoder().decode(PhotonzDocument.self, from: data)
        #expect(back.layer(id: dot)?.floatsInFront == true)
    }
}
