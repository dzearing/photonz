import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// A group turns like anything else: the knob is offered on it, the angle is a
/// number you can read and type, and everything that draws or hits the group
/// swings about the centre of the box its contents make rather than about the
/// anchor its frame really is.
@Suite("A group turns")
struct GroupTurnTests {

    private func box(_ rect: CGRect, name: String = "Box") -> Layer {
        Layer(name: name, content: .annotation(AnnotationContent(shape: .rectangle)), frame: rect)
    }

    /// A group whose anchor is nowhere near the middle of what it holds: the
    /// case that tells a pivot on the anchor apart from a pivot on the box.
    private func offsetGroup(rotation: CGFloat = 0, isFrame: Bool = false) -> Layer {
        var content = GroupContent(children: [box(CGRect(x: 100, y: 100, width: 40, height: 20))])
        content.isFrame = isFrame
        return Layer(name: "Group", content: .group(content),
                     frame: CGRect(x: 0, y: 0, width: 0, height: 0),
                     transform: LayerTransform(rotation: rotation))
    }

    // MARK: The pivot

    @Test("A group turns about the middle of the box its contents make, not about its anchor")
    func pivotIsTheBoxNotTheAnchor() {
        let group = offsetGroup()
        #expect(group.localBounds == CGRect(x: 100, y: 100, width: 40, height: 20))
        #expect(group.turnPivot == CGPoint(x: 120, y: 110))
        #expect(group.turnBox == CGRect(x: 100, y: 100, width: 40, height: 20))
    }

    @Test("A layer that is not a group keeps the pivot it always had")
    func aLeafPivotsWhereItAlwaysDid() {
        let layer = box(CGRect(x: 10, y: 20, width: 100, height: 50))
        #expect(layer.turnPivot == CGPoint(x: 60, y: 45))
        #expect(layer.turnBox == layer.withoutSlack(layer.frame))
    }

    @Test("A quarter turn puts the group's corners where the turned box is")
    func cornersFollowTheTurn() {
        let corners = offsetGroup(rotation: .pi / 2).transformedCorners
        // 40x20 about (120, 110) becomes 20x40: x from 110 to 130, y from 90 to 130.
        let xs = corners.map(\.x), ys = corners.map(\.y)
        #expect(abs(xs.min()! - 110) < 0.001)
        #expect(abs(xs.max()! - 130) < 0.001)
        #expect(abs(ys.min()! - 90) < 0.001)
        #expect(abs(ys.max()! - 130) < 0.001)
    }

    @Test("The rotate knob floats off the turned top edge, not off the upright one")
    func theKnobFollowsTheTurn() {
        let upright = offsetGroup().rotateKnobPoint(zoom: 1)
        #expect(upright == CGPoint(x: 120, y: 100 - 18))
        // Turned a quarter clockwise, the top edge has swung round to the
        // right of the box, and the knob goes with it.
        let turned = offsetGroup(rotation: .pi / 2).rotateKnobPoint(zoom: 1)
        #expect(abs(turned!.x - (130 + 18)) < 0.001)
        #expect(abs(turned!.y - 110) < 0.001)
    }

    // MARK: Clicking one

    @Test("A click lands on a turned group where the turn put it")
    func aTurnedGroupIsHitWhereItNowDraws() {
        let document = PhotonzDocument(canvasSize: CGSize(width: 400, height: 400),
                                       layers: [offsetGroup(rotation: .pi / 2)])
        // The turned box runs x 110...130, y 90...130. A point near its top,
        // which is empty canvas while the group is upright.
        let turnedOnly = CGPoint(x: 120, y: 95)
        #expect(document.hitTestPath(turnedOnly) == [0, 0])
        // ...and one click on it picks the whole group, as it always did.
        #expect(document.selectionTarget(at: turnedOnly, inside: nil)?.id
                == document.layers[0].id)
        // ...and where it used to be, out on the arm the turn swept away from.
        let uprightOnly = CGPoint(x: 136, y: 110)
        #expect(document.hitTestPath(uprightOnly) == nil)
    }

    @Test("Clicking a turned group reaches the piece inside it")
    func theWalkStillReachesAPiece() {
        var group = offsetGroup(rotation: .pi / 2)
        group.children.append(box(CGRect(x: 100, y: 100, width: 10, height: 20), name: "Edge"))
        let document = PhotonzDocument(canvasSize: CGSize(width: 400, height: 400),
                                       layers: [group])
        // The 10x20 piece sits at the left end of the upright box; a quarter
        // turn clockwise about (120, 110) puts it along the TOP of the turned
        // one, which runs x 110...130, y 90...130.
        #expect(document.hitTestPath(CGPoint(x: 125, y: 95)) == [0, 1])
    }

    @Test("A band catches a turned group by the corners it actually shows")
    func aBandReadsTheTurnedCorners() {
        let turned = offsetGroup(rotation: .pi / 2)
        let document = PhotonzDocument(canvasSize: CGSize(width: 400, height: 400),
                                       layers: [turned])
        // Tight round the TURNED box (20 wide, 40 tall) and nothing more.
        #expect(document.layerIDs(fullyInside: CGRect(x: 105, y: 85, width: 30, height: 50))
                == [turned.id])
        // Tight round the UPRIGHT box, which the turn has left behind.
        #expect(document.layerIDs(fullyInside: CGRect(x: 95, y: 95, width: 50, height: 30)).isEmpty)
    }

    // MARK: A piece inside a turned group

    @Test("Nothing inherits a turn until a container above it has one")
    func anUprightDocumentInheritsNothing() {
        var group = offsetGroup()
        group.children.append(box(CGRect(x: 100, y: 100, width: 10, height: 20), name: "Edge"))
        let document = PhotonzDocument(canvasSize: CGSize(width: 400, height: 400),
                                       layers: [group])
        let piece = group.children[1].id
        #expect(document.inheritedTurn(of: piece).isIdentity)
        #expect(document.turnedContainer(of: piece) == nil)
    }

    @Test("A piece inside a turned group inherits the group's turn, about the group's middle")
    func aPieceInsideATurnedGroupInheritsIt() {
        var group = offsetGroup(rotation: .pi / 2)
        group.children.append(box(CGRect(x: 100, y: 100, width: 10, height: 20), name: "Edge"))
        let document = PhotonzDocument(canvasSize: CGSize(width: 400, height: 400),
                                       layers: [group])
        let piece = group.children[1].id
        #expect(document.turnedContainer(of: piece) == group.id)
        // The piece's own top left, at (100, 100), lands where a quarter turn
        // about (120, 110) puts it: (130, 90).
        let landed = CGPoint(x: 100, y: 100).applying(document.inheritedTurn(of: piece))
        #expect(abs(landed.x - 130) < 0.001)
        #expect(abs(landed.y - 90) < 0.001)
    }

    @Test("A turn two containers up reaches the piece inside, both swings at once")
    func nestedTurnsCompose() {
        let inner = Layer(name: "Badge",
                          content: .group(GroupContent(children: [
                              box(CGRect(x: 0, y: 0, width: 20, height: 20), name: "Dot"),
                          ])),
                          frame: CGRect(x: 100, y: 100, width: 0, height: 0),
                          transform: LayerTransform(rotation: .pi / 2))
        let outer = Layer(name: "Card", content: .group(GroupContent(children: [inner])),
                          frame: CGRect(x: 0, y: 0, width: 0, height: 0),
                          transform: LayerTransform(rotation: .pi / 2))
        let document = PhotonzDocument(canvasSize: CGSize(width: 400, height: 400),
                                       layers: [outer])
        let dot = inner.children[0].id
        // The outermost turned container is the one a drag takes hold of.
        #expect(document.turnedContainer(of: dot) == outer.id)
        // Both boxes are the same 20x20 square about (110, 110), so two
        // quarter turns about that same middle are half a turn: the dot's own
        // top left at (100, 100) lands on (120, 120).
        let landed = CGPoint(x: 100, y: 100).applying(document.inheritedTurn(of: dot))
        #expect(abs(landed.x - 120) < 0.001)
        #expect(abs(landed.y - 120) < 0.001)
    }

    // MARK: The number in the panel

    @Test("A group takes a typed angle, like anything else")
    func aGroupTakesAnAngle() {
        let editing = LayerGeometryEditing(layer: offsetGroup())
        #expect(editing.allows(.rotation))
        #expect(editing.shows(.rotation))
        #expect(editing.fixedReason(for: .rotation) == nil)
    }

    @Test("A group reads back the angle it was turned to")
    func aGroupReadsItsAngle() {
        var group = offsetGroup()
        group.transform.rotation = LayerAngle.radians(fromDegrees: 30)
        let selection = LayerGeometrySelection([
            LayerGeometrySelection.Member(id: group.id, frame: group.localBounds,
                                          editing: LayerGeometryEditing(layer: group),
                                          angle: 30),
        ])
        #expect(selection.reading(.rotation) == .agreed(30))
        #expect(!selection.isReadOnly(.rotation))
    }

    @Test("A screen still holds still, and says why")
    func aScreenDoesNotTurn() {
        let editing = LayerGeometryEditing(layer: offsetGroup(isFrame: true))
        #expect(!editing.allows(.rotation))
        #expect(!editing.shows(.rotation))
        #expect(editing.fixedReason(for: .rotation) == LayerGeometryEditing.screenTurnReason)
    }

    @Test("A locked group reads its angle but does not take one")
    func aLockedGroupReadsOnly() {
        var group = offsetGroup(rotation: .pi / 4)
        group.isLocked = true
        let editing = LayerGeometryEditing(layer: group)
        #expect(!editing.allows(.rotation))
        #expect(editing.shows(.rotation))
        #expect(editing.fixedReason(for: .rotation) == LayerGeometryEditing.lockedReason)
    }
}
