import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// A picture arriving from OUTSIDE the layers list — dragged in from the
/// Finder, off the Library shelf — and the promise the panel makes about it
/// before you let go: which slot in the stack it will take, and how big it
/// will be when it gets there.
@Suite("A picture held over the layers list")
struct PanelIncomingDropTests {

    private func leaf(_ name: String, _ frame: CGRect = CGRect(x: 0, y: 0, width: 10, height: 10)) -> Layer {
        Layer(name: name, content: .text(TextContent(string: name)), frame: frame)
    }

    private func group(_ name: String, origin: CGPoint = .zero, _ children: [Layer]) -> Layer {
        Layer(name: name, content: .group(GroupContent(children: children)),
              frame: CGRect(origin: origin, size: .zero))
    }

    private func doc(_ layers: [Layer], canvas: CGSize = CGSize(width: 200, height: 200)) -> PhotonzDocument {
        PhotonzDocument(canvasSize: canvas, layers: layers)
    }

    private func id(_ document: PhotonzDocument, _ name: String) -> UUID {
        document.allLayers.first { $0.name == name }?.id ?? UUID()
    }

    private func row(_ document: PhotonzDocument, _ name: String) -> LayerPanelRow {
        document.panelRows(expanded: document.openableGroupIDs).first { $0.id == id(document, name) }!
    }

    // MARK: - What the line under the pointer promises

    @Test("The top of a row means in front of it, the bottom means behind it")
    func edgesOfAPlainRow() {
        let document = doc([leaf("Bottom"), leaf("Top")])
        let target = row(document, "Top")
        #expect(document.incomingDropProposal(over: target, pointerY: 2, rowHeight: 30)
                == .above(target.id))
        #expect(document.incomingDropProposal(over: target, pointerY: 28, rowHeight: 30)
                == .below(target.id))
    }

    @Test("The middle of a shut group means inside it")
    func middleOfAGroupRow() {
        let document = doc([group("Card", [leaf("Label")])])
        let target = document.panelRows(expanded: []).first!
        #expect(document.incomingDropProposal(over: target, pointerY: 15, rowHeight: 30)
                == .inside(target.id))
    }

    @Test("With groups turned off a group row is just a row")
    func groupRowWithoutInside() {
        let document = doc([group("Card", [leaf("Label")])])
        let target = document.panelRows(expanded: []).first!
        #expect(document.incomingDropProposal(over: target, pointerY: 10, rowHeight: 30,
                                              allowsInside: false) == .above(target.id))
        #expect(document.incomingDropProposal(over: target, pointerY: 20, rowHeight: 30,
                                              allowsInside: false) == .below(target.id))
    }

    @Test("A locked group takes a newcomer beside it but never inside it")
    func lockedGroupRefusesInside() {
        var document = doc([group("Card", [leaf("Label")])])
        document.updateLayer(id: id(document, "Card")) { $0.isLocked = true }
        let target = document.panelRows(expanded: []).first!
        #expect(document.incomingDropProposal(over: target, pointerY: 10, rowHeight: 30)
                == .above(target.id))
        #expect(document.incomingDropProposal(over: target, pointerY: 20, rowHeight: 30)
                == .below(target.id))
    }

    @Test("A row that is not in the document promises nothing")
    func unknownRow() {
        let document = doc([leaf("One")])
        let stranger = LayerPanelRow(id: UUID(), depth: 0, isGroup: false, childCount: 0,
                                     isExpanded: false, parentID: nil)
        #expect(document.incomingDropProposal(over: stranger, pointerY: 2, rowHeight: 30) == nil)
    }

    @Test("A newcomer can land beside a LOCKED layer: the row is locked, the list is not")
    func besideALockedRow() {
        var document = doc([leaf("Background"), leaf("Note")])
        document.updateLayer(id: id(document, "Background")) { $0.isLocked = true }
        let target = row(document, "Background")
        #expect(document.incomingDropProposal(over: target, pointerY: 2, rowHeight: 30)
                == .above(target.id))
    }

    // MARK: - Where it lands when no one row is under the pointer

    @Test("Held over the panel but not over a row, a picture lands on top of the stack")
    func defaultLandingIsTheTopOfTheStack() {
        let document = doc([leaf("Bottom"), leaf("Top")])
        #expect(document.incomingDropOnTop() == .above(id(document, "Top")))
    }

    @Test("A frame under the middle of the canvas takes it instead, because that is where the picture goes")
    func defaultLandingJoinsTheFrameUnderTheMiddle() {
        let frame = Layer.frameLayer(name: "Home", origin: CGPoint(x: 20, y: 20),
                                     size: CGSize(width: 160, height: 160), children: [])
        let document = doc([leaf("Background", CGRect(x: 0, y: 0, width: 200, height: 200)), frame])
        #expect(document.incomingDropOnTop() == .inside(frame.id))
    }

    @Test("An empty document promises nothing: there is no stack to land on")
    func defaultLandingOfAnEmptyDocument() {
        #expect(doc([]).incomingDropOnTop() == nil)
    }

    // MARK: - Putting the newcomer where the line said

    @Test("Above the topmost row puts it on top of everything")
    func insertOnTop() {
        var document = doc([leaf("Bottom"), leaf("Top")])
        let onTop = document.insertLayer(leaf("New"), .above(id(document, "Top")))
        #expect(onTop)
        #expect(document.layers.map(\.name) == ["Bottom", "Top", "New"])
    }

    @Test("Below the bottom row puts it under everything")
    func insertAtTheBottom() {
        var document = doc([leaf("Bottom"), leaf("Top")])
        let atBottom = document.insertLayer(leaf("New"), .below(id(document, "Bottom")))
        #expect(atBottom)
        #expect(document.layers.map(\.name) == ["New", "Bottom", "Top"])
    }

    @Test("Beside a row inside a group joins THAT list, in that group's space")
    func insertBesideAChild() {
        var document = doc([group("Card", origin: CGPoint(x: 40, y: 30), [leaf("Label")])])
        let newcomer = leaf("New", CGRect(x: 50, y: 40, width: 10, height: 10))
        let beside = document.insertLayer(newcomer, .above(id(document, "Label")))
        #expect(beside)
        let card = document.layer(id: id(document, "Card"))!
        #expect(card.children.map(\.name) == ["Label", "New"])
        // Its canvas position is unchanged: the frame it was given was in
        // canvas coordinates and is rewritten into the group's.
        #expect(card.children.last?.frame == CGRect(x: 10, y: 10, width: 10, height: 10))
        #expect(document.canvasBounds(of: id(document, "New")) == CGRect(x: 50, y: 40, width: 10, height: 10))
    }

    @Test("Inside a group puts it on top of what that group already holds")
    func insertInsideAGroup() {
        var document = doc([group("Card", origin: CGPoint(x: 40, y: 30), [leaf("Label")])])
        let inside = document.insertLayer(leaf("New", CGRect(x: 50, y: 40, width: 10, height: 10)),
                                          .inside(id(document, "Card")))
        #expect(inside)
        #expect(document.layer(id: id(document, "Card"))?.children.map(\.name) == ["Label", "New"])
        #expect(document.canvasBounds(of: id(document, "New")) == CGRect(x: 50, y: 40, width: 10, height: 10))
    }

    @Test("Inside a locked group is refused, and the document is left alone")
    func insertInsideALockedGroup() {
        var document = doc([group("Card", [leaf("Label")])])
        document.updateLayer(id: id(document, "Card")) { $0.isLocked = true }
        let before = document.layers
        let intoLocked = document.insertLayer(leaf("New"), .inside(id(document, "Card")))
        #expect(!intoLocked)
        #expect(document.layers == before)
    }

    @Test("Inside a plain layer is refused: it is not a list")
    func insertInsideALeaf() {
        var document = doc([leaf("Note")])
        let intoLeaf = document.insertLayer(leaf("New"), .inside(id(document, "Note")))
        #expect(!intoLeaf)
        #expect(document.layers.count == 1)
    }

    @Test("A newcomer carrying a name the app wrote is numbered, so the list reads")
    func insertUniquelyNames() {
        var document = doc([leaf("Frame")])
        let named = document.insertLayer(leaf("Frame"), .above(id(document, "Frame")))
        #expect(named)
        #expect(document.layers.map(\.name) == ["Frame", "Frame 2"])
    }

    @Test("A name a PERSON chose is left exactly as it arrived")
    func insertKeepsAChosenName() {
        var document = doc([leaf("Hero shot")])
        let named = document.insertLayer(leaf("Hero shot"), .above(id(document, "Hero shot")))
        #expect(named)
        #expect(document.layers.map(\.name) == ["Hero shot", "Hero shot"])
    }

    @Test("Landing beside a row that has gone away changes nothing")
    func insertAgainstAMissingRow() {
        var document = doc([leaf("Note")])
        let missing = document.insertLayer(leaf("New"), .above(UUID()))
        #expect(!missing)
        #expect(document.layers.count == 1)
    }

    // MARK: - How big it arrives

    @Test("A picture landing on the canvas is centred on the canvas")
    func placementAtTheTopOfTheStack() {
        let document = doc([leaf("Background")], canvas: CGSize(width: 200, height: 200))
        let placed = document.placementForIncomingImage(size: CGSize(width: 40, height: 40),
                                                        landingAt: .above(id(document, "Background")))
        #expect(placed == CGRect(x: 80, y: 80, width: 40, height: 40))
    }

    @Test("A picture landing in a frame is centred on THAT frame and fitted to it")
    func placementInsideAFrame() {
        let frame = Layer.frameLayer(name: "Home", origin: CGPoint(x: 20, y: 20),
                                     size: CGSize(width: 100, height: 100), children: [])
        let document = doc([frame], canvas: CGSize(width: 400, height: 400))
        let placed = document.placementForIncomingImage(size: CGSize(width: 200, height: 200),
                                                        landingAt: .inside(frame.id))
        #expect(placed == CGRect(x: 20, y: 20, width: 100, height: 100))
    }

    @Test("A picture landing beside a child of a frame is centred on that frame too")
    func placementBesideAChildOfAFrame() {
        let child = leaf("Button", CGRect(x: 10, y: 10, width: 20, height: 20))
        let frame = Layer.frameLayer(name: "Home", origin: CGPoint(x: 20, y: 20),
                                     size: CGSize(width: 100, height: 100), children: [child])
        let document = doc([frame], canvas: CGSize(width: 400, height: 400))
        let placed = document.placementForIncomingImage(size: CGSize(width: 40, height: 40),
                                                        landingAt: .above(child.id))
        #expect(placed == CGRect(x: 50, y: 50, width: 40, height: 40))
    }

    /// The whole point of the two above: what the panel promised and what the
    /// document did are the same thing.
    @Test("The promise is kept: a picture dropped on a frame's row ends up inside that frame, on screen where it was shown")
    func promiseIsKept() {
        let frame = Layer.frameLayer(name: "Home", origin: CGPoint(x: 20, y: 20),
                                     size: CGSize(width: 100, height: 100), children: [])
        var document = doc([frame], canvas: CGSize(width: 400, height: 400))
        let target = document.panelRows(expanded: []).first!
        let drop = document.incomingDropProposal(over: target, pointerY: 15, rowHeight: 30)!
        let placed = document.placementForIncomingImage(size: CGSize(width: 40, height: 40), landingAt: drop)
        let kept = document.insertLayer(leaf("Shot", placed), drop)
        #expect(kept)
        #expect(document.layer(id: frame.id)?.children.map(\.name) == ["Shot"])
        #expect(document.canvasBounds(of: id(document, "Shot")) == placed)
    }
}
