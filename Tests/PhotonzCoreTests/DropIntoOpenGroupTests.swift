import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// A tile let go inside a group you have stepped into joins that group.
///
/// Before this, only a SCREEN adopted a drop, so a bar or a card you were
/// working inside could not be added to from the shelf at all: the new piece
/// landed beside it at the top level, overlapping it but not part of it
/// (`queue/audits/2026-09-05-nav-bar-row.json`, first rough note).
///
/// Being inside is the whole rule. A drop out on bare canvas, or a drop while
/// you are not inside anything, lands exactly where it always did.
@Suite("A tile let go inside an open group joins it")
struct DropIntoOpenGroupTests {

    private func document() -> PhotonzDocument {
        PhotonzDocument(canvasSize: CGSize(width: 900, height: 700))
    }

    private func piece(_ layer: Layer?, _ name: String) -> Layer? {
        layer?.children.first { $0.name == name }
    }

    /// A bar on the canvas at 400,300, and the id of the bar itself.
    private func withBar() -> (History, UUID) {
        var history = History(document: document())
        var barID: UUID?
        history.perform { barID = $0.insertStarterComponent(.navBar, at: CGPoint(x: 400, y: 300)) }
        return (history, barID!)
    }

    /// A point over the right-hand half of the bar, well clear of the back
    /// label: the empty room somebody would aim a new control at.
    private func overTheBar(_ doc: PhotonzDocument, _ barID: UUID) -> CGPoint {
        let box = doc.canvasBounds(of: barID)!
        return CGPoint(x: box.midX + box.width / 4, y: box.midY)
    }

    // MARK: - What the drag in the air says

    @Test("Held over the bar you are inside, the drop says it would join the bar")
    func theDropTargetIsTheOpenGroup() {
        let (history, barID) = withBar()
        let doc = history.current
        let point = overTheBar(doc, barID)
        #expect(doc.componentDropTarget(of: StarterComponent.badge.componentID,
                                        at: point, inside: barID) == .inside(barID))
    }

    @Test("With nothing open, the same drop still lands loose on the canvas")
    func theDropTargetIsUnchangedWhenNothingIsOpen() {
        let (history, barID) = withBar()
        let doc = history.current
        let point = overTheBar(doc, barID)
        #expect(doc.componentDropTarget(of: StarterComponent.badge.componentID,
                                        at: point) == .canvas)
    }

    @Test("Let go OUTSIDE the open group, it lands on the canvas, not in the group")
    func aDropOutsideTheOpenGroupDoesNotJoinIt() {
        let (history, barID) = withBar()
        let doc = history.current
        #expect(doc.componentDropTarget(of: StarterComponent.badge.componentID,
                                        at: CGPoint(x: 100, y: 600), inside: barID) == .canvas)
    }

    /// A copy may not go inside its own original, open or not: such a thing
    /// draws forever.
    @Test("A copy let go inside its own original is still refused")
    func aCopyInsideItsOwnOriginalIsStillRefused() {
        let (history, barID) = withBar()
        let doc = history.current
        let point = overTheBar(doc, barID)
        #expect(doc.componentDropTarget(of: StarterComponent.navBar.componentID,
                                        at: point, inside: barID) == .refused)
    }

    /// Nothing goes inside a COPY of a component: its contents belong to its
    /// original, so an edit made in there could not be kept.
    @Test("A copy of a component never takes a drop, even named as the open group")
    func nothingGoesInsideACopy() {
        var (history, _) = withBar()
        var copyID: UUID?
        history.perform {
            copyID = $0.insertComponentInstance(of: StarterComponent.navBar.componentID,
                                                at: CGPoint(x: 400, y: 500))
        }
        let doc = history.current
        guard let copyID else { Issue.record("no copy"); return }
        let point = overTheBar(doc, copyID)
        #expect(doc.componentDropTarget(of: StarterComponent.badge.componentID,
                                        at: point, inside: copyID) == .canvas)
    }

    /// A screen INSIDE the group you are standing in is deeper than the group,
    /// so it wins — the innermost room you are in is the one you are in. A
    /// screen the group merely sits on is above you and does not.
    @Test("A screen inside the open group still takes the drop")
    func aScreenInsideTheOpenGroupWins() {
        var history = History(document: document())
        var outerID: UUID?
        var innerFrameID: UUID?
        history.perform { doc in
            let a = doc.addFrame(origin: CGPoint(x: 100, y: 100), size: CGSize(width: 400, height: 400))
            outerID = a.id
            let inner = doc.addFrame(origin: CGPoint(x: 150, y: 150), size: CGSize(width: 100, height: 100))
            innerFrameID = inner.id
            // A screen dropped on a screen is a second screen, so it has to be
            // moved in on purpose to make one that is really nested.
            _ = doc.moveLayer(id: inner.id, toGroup: a.id)
        }
        guard let outerID, let innerFrameID else { Issue.record("no frames"); return }
        let doc = history.current
        // Standing in the outer screen, a point over the inner one joins the
        // inner one.
        #expect(doc.componentDropTarget(of: StarterComponent.badge.componentID,
                                        at: CGPoint(x: 200, y: 200), inside: outerID)
                == .inside(innerFrameID))
        // ...and a point on the outer screen's own room joins the outer one.
        #expect(doc.componentDropTarget(of: StarterComponent.badge.componentID,
                                        at: CGPoint(x: 450, y: 450), inside: outerID)
                == .inside(outerID))
    }

    // MARK: - What the drop actually does

    @Test("A starter let go inside the open bar becomes a child of the bar")
    func aStarterJoinsTheOpenGroup() {
        var (history, barID) = withBar()
        let point = overTheBar(history.current, barID)
        var placed: UUID?
        history.perform { placed = $0.insertStarterComponent(.badge, at: point, inside: barID) }
        guard let placed else { Issue.record("nothing placed"); return }
        #expect(history.current.parentID(of: placed) == barID)
    }

    @Test("A copy let go inside the open bar becomes a child of the bar")
    func aCopyJoinsTheOpenGroup() {
        var (history, barID) = withBar()
        history.perform { _ = $0.insertStarterComponent(.badge, at: CGPoint(x: 100, y: 600)) }
        let point = overTheBar(history.current, barID)
        var placed: UUID?
        history.perform {
            placed = $0.insertComponentInstance(of: StarterComponent.badge.componentID,
                                                at: point, inside: barID)
        }
        guard let placed else { Issue.record("nothing placed"); return }
        #expect(history.current.parentID(of: placed) == barID)
    }

    /// The picture and the result agree: what the drag in the air promised is
    /// where the drop actually put it.
    @Test("The drop lands where the drag in the air said it would")
    func theDropAgreesWithWhatWasPromised() {
        var (history, barID) = withBar()
        let point = overTheBar(history.current, barID)
        #expect(history.current.componentDropTarget(of: StarterComponent.badge.componentID,
                                                    at: point, inside: barID) == .inside(barID))
        var placed: UUID?
        history.perform { placed = $0.insertStarterComponent(.badge, at: point, inside: barID) }
        #expect(placed.flatMap { history.current.parentID(of: $0) } == barID)
    }

    /// The point of joining the bar: the row takes over. The badge lines up
    /// after the back label at the row's own gap, with nothing typed.
    @Test("The row lines the new piece up beside the back label, no numbers typed")
    func theRowLinesTheNewPieceUp() {
        var (history, barID) = withBar()
        let point = overTheBar(history.current, barID)
        history.perform { _ = $0.insertStarterComponent(.badge, at: point, inside: barID) }
        guard let bar = history.current.layer(id: barID),
              let back = piece(bar, "Back"), let badge = piece(bar, "Badge")
        else { Issue.record("the badge did not join the bar"); return }
        #expect(badge.frame.minX == back.contentBounds.maxX + 12)
    }

    /// Acceptance, the other way round: bare canvas is untouched.
    @Test("A tile let go on empty canvas still lands at the top level")
    func bareCanvasIsUnchanged() {
        var (history, barID) = withBar()
        var placed: UUID?
        history.perform {
            placed = $0.insertStarterComponent(.badge, at: CGPoint(x: 100, y: 620), inside: barID)
        }
        guard let placed else { Issue.record("nothing placed"); return }
        #expect(history.current.parentID(of: placed) == nil)
        #expect(history.current.layer(id: barID)?.children.contains { $0.name == "Badge" } == false)
    }

    // MARK: - The box drawn while the drag is still in the air

    /// A row packs its contents from its own edge, so a piece let go over the
    /// right-hand half of a bar lands over on the left with the rest. The
    /// outline has to say so, or it promises somewhere the piece is not going.
    @Test("The box in the air is where the row will actually park the piece")
    func theBoxInTheAirIsWhereTheRowParksIt() {
        var (history, barID) = withBar()
        let point = overTheBar(history.current, barID)
        guard let promised = history.current.componentDropLanding(
            of: StarterComponent.badge.componentID, at: point, inside: barID)
        else { Issue.record("no landing"); return }
        #expect(promised.host == barID)
        var placed: UUID?
        history.perform { placed = $0.insertStarterComponent(.badge, at: point, inside: barID) }
        guard let placed, let landed = history.current.canvasBounds(of: placed)
        else { Issue.record("nothing placed"); return }
        #expect(promised.rect == landed)
        // ...and it really did move away from the pointer, or this proves
        // nothing.
        #expect(promised.rect.midX != point.x)
    }

    @Test("Out on the canvas the box is still the one under the pointer")
    func theBoxOnBareCanvasIsUnderThePointer() {
        let (history, _) = withBar()
        let point = CGPoint(x: 120, y: 620)
        guard let promised = history.current.componentDropLanding(
            of: StarterComponent.badge.componentID, at: point)
        else { Issue.record("no landing"); return }
        #expect(promised.host == nil)
        #expect(promised.rect.midX == point.x)
        #expect(promised.rect.midY == point.y)
    }

    @Test("A drop that would draw forever has no box at all")
    func aRefusedDropHasNoBox() {
        let (history, barID) = withBar()
        let point = overTheBar(history.current, barID)
        #expect(history.current.componentDropLanding(of: StarterComponent.navBar.componentID,
                                                     at: point, inside: barID) == nil)
    }

    /// A plain group's BOX starts wherever its contents happen to start, but
    /// its children are measured from its own corner. Confusing the two puts
    /// the piece down somewhere other than where it was let go.
    @Test("Inside a plain group, the piece lands exactly where you let go of it")
    func aPieceLandsWhereItWasLetGoInsideAPlainGroup() {
        var history = History(document: document())
        var groupID: UUID?
        history.perform { doc in
            let a = doc.addLayer(Layer(name: "A", content: .group(GroupContent(children: [])),
                                       frame: CGRect(x: 200, y: 200, width: 0, height: 0)))
            _ = a
        }
        // A group whose contents start well inside it, so its box and its
        // corner are not the same point.
        history.perform { doc in
            let box = Layer(name: "Box",
                            content: .annotation(AnnotationContent(shape: .rectangle, start: .zero,
                                                                   end: CGPoint(x: 200, y: 200))),
                            frame: CGRect(x: 300, y: 300, width: 200, height: 200))
            doc.addLayer(box)
            groupID = doc.groupLayers(ids: [box.id], name: "Holder")?.id
        }
        guard let groupID else { Issue.record("no group"); return }
        let point = CGPoint(x: 400, y: 400)
        var placed: UUID?
        history.perform { placed = $0.insertStarterComponent(.badge, at: point, inside: groupID) }
        guard let placed, let landed = history.current.canvasBounds(of: placed)
        else { Issue.record("nothing placed"); return }
        #expect(history.current.parentID(of: placed) == groupID)
        // Within the half point a piece of odd width rounds to when it is
        // centred on whole coordinates.
        #expect(abs(landed.midX - point.x) <= 1)
        #expect(abs(landed.midY - point.y) <= 1)
    }

    // MARK: - The container the canvas outlines

    @Test("With nothing open, the container under a point is the screen, as before")
    func theContainerIsTheScreenWhenNothingIsOpen() {
        var history = History(document: document())
        var frameID: UUID?
        history.perform {
            frameID = $0.addFrame(origin: CGPoint(x: 100, y: 100),
                                  size: CGSize(width: 300, height: 300)).id
        }
        let doc = history.current
        #expect(doc.dropHostID(under: CGPoint(x: 200, y: 200)) == frameID)
        #expect(doc.dropHostID(under: CGPoint(x: 600, y: 600)) == nil)
    }

    @Test("A screen the open group sits on does not steal the drop")
    func theOpenGroupBeatsTheScreenItSitsOn() {
        var history = History(document: document())
        var barID: UUID?
        history.perform { doc in
            _ = doc.addFrame(origin: CGPoint(x: 100, y: 100), size: CGSize(width: 600, height: 500))
            barID = doc.insertStarterComponent(.navBar, at: CGPoint(x: 400, y: 300))
        }
        guard let barID else { Issue.record("no bar"); return }
        let doc = history.current
        // The bar landed on the screen, so the screen is its parent...
        #expect(doc.parentID(of: barID) != nil)
        // ...and standing inside the bar, a point on the bar joins the BAR.
        #expect(doc.dropHostID(under: overTheBar(doc, barID), inside: barID) == barID)
    }
}
