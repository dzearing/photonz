import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// Where you let go along a row decides where the piece goes in the row.
///
/// A row packs its contents in the order they READ, and until now a drop had
/// no say in that order: the slot fell out of where the left edge of the piece
/// happened to land once it was centred on the pointer. A badge is 23 wide and
/// a button is 79, so the same gesture put the two in different places, and a
/// button let go in the second gap of a bar landed FIRST in the row — its left
/// edge was back past everything (`queue/audits/2026-09-05-nav-bar-row.json`).
///
/// The pointer decides now: the piece goes in the gap the pointer is nearest,
/// whatever it is carrying.
@Suite("Where you let go in a row decides where the piece goes")
struct RowDropSlotTests {

    // MARK: - A bar with three controls on it

    private func document() -> PhotonzDocument {
        PhotonzDocument(canvasSize: CGSize(width: 900, height: 700))
    }

    /// A nav bar at 400,300 with two badges already added, so there are three
    /// controls in the row and two gaps between them to aim at.
    private func filledBar() -> (History, UUID) {
        var history = History(document: document())
        var barID: UUID?
        history.perform { barID = $0.insertStarterComponent(.navBar, at: CGPoint(x: 400, y: 300)) }
        let bar = barID!
        let box = history.current.canvasBounds(of: bar)!
        // Two badges land on the end, and they are told apart by name: a copy
        // keeps its original's name, so both arrive called "Badge".
        for name in ["One", "Two"] {
            var placed: UUID?
            history.perform {
                placed = $0.insertStarterComponent(.badge, at: CGPoint(x: box.maxX - 20, y: box.midY),
                                                   inside: bar)
            }
            history.perform { $0.updateLayer(id: placed!) { $0.name = name } }
        }
        return (history, bar)
    }

    /// The names of the pieces the bar arranges, left to right on screen.
    private func rowOrder(_ doc: PhotonzDocument, _ barID: UUID) -> [String] {
        guard let bar = doc.layer(id: barID) else { return [] }
        return GroupFlow.arrangedItems(of: bar).map { bar.children[$0.index].name }
    }

    /// A canvas point in the middle of the gap between two named pieces.
    private func gap(_ doc: PhotonzDocument, _ barID: UUID,
                     after first: String, before second: String) -> CGPoint {
        let bar = doc.layer(id: barID)!
        let corner = doc.childOrigin(of: barID)!
        let a = bar.children.first { $0.name == first }!.contentBounds
        let b = bar.children.first { $0.name == second }!.contentBounds
        return CGPoint(x: corner.x + (a.maxX + b.minX) / 2, y: corner.y + a.midY)
    }

    // MARK: - The drop

    /// The case that was wrong: a WIDE piece let go in the second gap. Centred
    /// on the pointer its left edge sits back before the first control, which
    /// is where the row used to put it.
    @Test("A button let go between the back label and the first badge lands between them")
    func aWidePieceLandsInTheGapItWasLetGoIn() {
        var (history, barID) = filledBar()
        #expect(rowOrder(history.current, barID) == ["Back", "One", "Two"])
        let point = gap(history.current, barID, after: "Back", before: "One")
        history.perform { _ = $0.insertStarterComponent(.button, at: point, inside: barID) }
        #expect(rowOrder(history.current, barID) == ["Back", "Button", "One", "Two"])
    }

    @Test("Let go in the second gap, it goes in the second gap")
    func aPieceLandsInTheSecondGap() {
        var (history, barID) = filledBar()
        let point = gap(history.current, barID, after: "One", before: "Two")
        history.perform { _ = $0.insertStarterComponent(.button, at: point, inside: barID) }
        #expect(rowOrder(history.current, barID) == ["Back", "One", "Button", "Two"])
    }

    @Test("Let go before the first piece, it goes first")
    func aPieceLetGoAtTheHeadGoesFirst() {
        var (history, barID) = filledBar()
        let corner = history.current.childOrigin(of: barID)!
        let back = history.current.layer(id: barID)!.children.first { $0.name == "Back" }!
        let point = CGPoint(x: corner.x + back.contentBounds.minX + 1,
                            y: corner.y + back.contentBounds.midY)
        history.perform { _ = $0.insertStarterComponent(.button, at: point, inside: barID) }
        #expect(rowOrder(history.current, barID) == ["Button", "Back", "One", "Two"])
    }

    @Test("Let go past the last piece, it still goes on the end")
    func aPieceLetGoPastTheEndGoesLast() {
        var (history, barID) = filledBar()
        let box = history.current.canvasBounds(of: barID)!
        let point = CGPoint(x: box.maxX - 8, y: box.midY)
        history.perform { _ = $0.insertStarterComponent(.button, at: point, inside: barID) }
        #expect(rowOrder(history.current, barID) == ["Back", "One", "Two", "Button"])
    }

    /// A copy off the shelf takes the same slot a starter does: the two drops
    /// are one gesture and they must not disagree.
    @Test("A copy let go in a gap lands in that gap too")
    func aCopyTakesTheSameSlot() {
        var (history, barID) = filledBar()
        history.perform { _ = $0.insertStarterComponent(.button, at: CGPoint(x: 120, y: 620)) }
        let point = gap(history.current, barID, after: "Back", before: "One")
        history.perform {
            _ = $0.insertComponentInstance(of: StarterComponent.button.componentID,
                                           at: point, inside: barID)
        }
        #expect(rowOrder(history.current, barID) == ["Back", "Button", "One", "Two"])
    }

    /// A column reads the same way, down instead of across.
    @Test("Down a column, the piece goes in the gap you let go in")
    func aColumnTakesTheSlotToo() {
        var history = History(document: document())
        var cardID: UUID?
        history.perform { cardID = $0.insertStarterComponent(.card, at: CGPoint(x: 400, y: 300)) }
        guard let cardID, history.current.layer(id: cardID)?.group?.layout?.arranges == true,
              let items = history.current.layer(id: cardID).map({ GroupFlow.arrangedItems(of: $0) }),
              items.count >= 2 else { Issue.record("the card is not a column"); return }
        let card = history.current.layer(id: cardID)!
        let corner = history.current.childOrigin(of: cardID)!
        let first = items[0].box
        let second = items[1].box
        let point = CGPoint(x: corner.x + first.midX,
                            y: corner.y + (first.maxY + second.minY) / 2)
        let names = items.map { card.children[$0.index].name }
        history.perform { _ = $0.insertStarterComponent(.badge, at: point, inside: cardID) }
        #expect(rowOrder(history.current, cardID) == [names[0], "Badge"] + names.dropFirst())
    }

    /// A grid reads row by row, so a point picks its row first and its place
    /// along that row second.
    @Test("In a grid the piece goes where the pointer is, reading row by row")
    func aGridReadsRowByRow() {
        var history = History(document: document())
        var gridID: UUID?
        history.perform { doc in
            // Four boxes in two rows of two, wrapped in a group told to grid.
            let cells = [CGRect(x: 0, y: 0, width: 40, height: 40),
                         CGRect(x: 52, y: 0, width: 40, height: 40),
                         CGRect(x: 0, y: 52, width: 40, height: 40),
                         CGRect(x: 52, y: 52, width: 40, height: 40)]
            let children = zip(["A", "B", "C", "D"], cells).map {
                Layer(name: $0.0, content: .image(ImageRef(pixelSize: $0.1.size)), frame: $0.1)
            }
            var content = GroupContent(children: children)
            content.layout = GroupLayout(kind: .grid, columns: 2, gap: 12)
            let holder = Layer(name: "Grid", content: .group(content),
                               frame: CGRect(x: 200, y: 200, width: 0, height: 0))
            doc.addLayer(holder)
            gridID = holder.id
        }
        guard let gridID, history.current.layer(id: gridID)?.group?.layout?.arranges == true
        else { Issue.record("no grid"); return }
        #expect(rowOrder(history.current, gridID) == ["A", "B", "C", "D"])
        // Let go in the second row, left of its first cell: third in reading order.
        let corner = history.current.childOrigin(of: gridID)!
        let point = CGPoint(x: corner.x + 2, y: corner.y + 60)
        history.perform { _ = $0.insertStarterComponent(.badge, at: point, inside: gridID) }
        #expect(rowOrder(history.current, gridID) == ["A", "B", "Badge", "C", "D"])
    }

    // MARK: - What the drag in the air promises

    @Test("The box in the air is the gap the piece will take")
    func theBoxInTheAirIsTheGapItWillTake() {
        var (history, barID) = filledBar()
        let point = gap(history.current, barID, after: "Back", before: "One")
        guard let promised = history.current.componentDropLanding(
            of: StarterComponent.button.componentID, at: point, inside: barID)
        else { Issue.record("no landing"); return }
        #expect(promised.host == barID)
        #expect(promised.index != nil)
        var placed: UUID?
        history.perform { placed = $0.insertStarterComponent(.button, at: point, inside: barID) }
        guard let placed, let landed = history.current.canvasBounds(of: placed)
        else { Issue.record("nothing placed"); return }
        #expect(promised.rect == landed)
    }

    /// The room really opens: the pieces after the gap move along by the width
    /// of what is coming, and the gap the outline draws is empty.
    @Test("While the drag is in the air the row holds the room open")
    func theRowHoldsTheRoomOpen() {
        let (history, barID) = filledBar()
        let doc = history.current
        let point = gap(doc, barID, after: "Back", before: "One")
        guard let landing = doc.componentDropLanding(of: StarterComponent.button.componentID,
                                                     at: point, inside: barID),
              let held = doc.holdingRoomForComponentDrop(of: StarterComponent.button.componentID,
                                                         at: point, inside: barID)
        else { Issue.record("no room held open"); return }
        // The room is EMPTY: nothing new draws, the gap is just being held.
        #expect(held.layer(id: barID)?.children.filter { $0.style.opacity > 0 }.count
                == doc.layer(id: barID)?.children.count)
        // The badge after the gap really moved along, and it moved clear of the
        // box the outline is drawn in.
        guard let before = doc.canvasBounds(of: badgeID(doc, barID)),
              let after = held.canvasBounds(of: badgeID(doc, barID)) else {
            Issue.record("no badge"); return
        }
        #expect(after.minX > before.minX)
        #expect(after.minX >= landing.rect.maxX)
        // ...and the bar itself is drawn at the size it will be once it has
        // taken the piece, so the dashed outline round it is not left short.
        #expect(landing.hostBox == held.canvasBounds(of: barID))
    }

    @Test("Out on bare canvas nothing is held open")
    func bareCanvasHoldsNothingOpen() {
        let (history, _) = filledBar()
        #expect(history.current.holdingRoomForComponentDrop(
            of: StarterComponent.button.componentID, at: CGPoint(x: 120, y: 620)) == nil)
    }

    private func badgeID(_ doc: PhotonzDocument, _ barID: UUID) -> UUID {
        doc.layer(id: barID)!.children.first { $0.name == "One" }!.id
    }

    // MARK: - A group that arranges nothing is untouched

    @Test("Inside a plain group the piece still lands exactly where you let go")
    func aPlainGroupIsUnchanged() {
        var history = History(document: document())
        var groupID: UUID?
        history.perform { doc in
            let one = Layer(name: "One", content: .image(ImageRef(pixelSize: CGSize(width: 40, height: 20))),
                            frame: CGRect(x: 0, y: 0, width: 40, height: 20))
            let two = Layer(name: "Two", content: .image(ImageRef(pixelSize: CGSize(width: 40, height: 20))),
                            frame: CGRect(x: 120, y: 60, width: 40, height: 20))
            let holder = Layer(name: "Holder", content: .group(GroupContent(children: [one, two])),
                               frame: CGRect(x: 200, y: 200, width: 0, height: 0))
            doc.addLayer(holder)
            groupID = holder.id
        }
        guard let groupID else { Issue.record("no group"); return }
        let point = CGPoint(x: 260, y: 240)
        guard let landing = history.current.componentDropLanding(
            of: StarterComponent.badge.componentID, at: point, inside: groupID)
        else { Issue.record("no landing"); return }
        #expect(landing.host == groupID)
        // Nothing decides an order here, so there is no slot and no room to hold.
        #expect(landing.index == nil)
        #expect(landing.rect.midX == point.x)
        #expect(landing.rect.midY == point.y)
        #expect(history.current.holdingRoomForComponentDrop(
            of: StarterComponent.badge.componentID, at: point, inside: groupID) == nil)
    }
}
