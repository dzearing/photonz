import Foundation
import CoreGraphics
import Testing
@testable import PhotonzCore

/// The room a component keeps inside its OWN outermost edges, offered as a knob
/// (`docs/design/ui-building.md`, step C6).
///
/// Every other knob names a layer inside the original. These two name the
/// original itself, because the room a card keeps at its edges and how far
/// apart it holds what it holds are facts about the card and not about any one
/// piece in it. Without them a card built as one group is stuck with one
/// roominess for every copy it will ever have.
struct ComponentRootNumberKnobTests {

    // MARK: - A card that is itself a stack

    private func text(_ name: String, _ string: String, _ rect: CGRect) -> Layer {
        Layer(name: name, content: .text(TextContent(string: string)), frame: rect)
    }

    /// A component "Card" whose OUTERMOST layer is the stack: it holds two
    /// labels 12 apart with 16 of room inside its edges, so the card itself has
    /// a gap and a room to offer.
    private func withCard(kind: GroupLayoutKind? = .stack)
    -> (doc: PhotonzDocument, main: UUID, componentID: UUID, titleID: UUID) {
        var doc = PhotonzDocument(
            canvasSize: CGSize(width: 800, height: 600),
            layers: [text("Title", "Hello", CGRect(x: 20, y: 20, width: 80, height: 20)),
                     text("Body", "World", CGRect(x: 20, y: 52, width: 80, height: 20))])
        let titleID = doc.layers[0].id
        let main = doc.groupLayers(ids: [titleID, doc.layers[1].id], name: "Card")!
        if let kind { doc.setGroupLayout(id: main.id, kind: kind) }
        doc.updateGroupLayout(id: main.id) { $0.gap = 12; $0.padding = GroupPadding(16) }
        let componentID = doc.makeComponent(id: main.id)!
        return (doc, main.id, componentID, titleID)
    }

    private func rootCandidate(_ c: (doc: PhotonzDocument, main: UUID, componentID: UUID,
                                     titleID: UUID)) -> ComponentPropertyCandidate? {
        c.doc.componentPropertyCandidates(componentID: c.componentID)
            .first { $0.layerID == c.main }
    }

    /// The room a copy is actually working to.
    private func room(_ doc: PhotonzDocument, of id: UUID) -> CGFloat? {
        doc.layer(id: id)?.group?.layout?.usedPadding.uniform
    }

    private func gap(_ doc: PhotonzDocument, of id: UUID) -> CGFloat? {
        doc.layer(id: id)?.group?.layout?.usedGap
    }

    // MARK: - What the component itself offers

    /// The card is on the Add menu alongside the layers inside it, offering the
    /// two numbers it holds its contents with.
    @Test func theComponentOffersItsOwnRoomAndGap() {
        let c = withCard()
        let root = rootCandidate(c)
        #expect(root?.numberSlots == [.gap, .padding])
        #expect(root?.kinds == [.number])
        #expect(root?.pathLabel == "Card")
    }

    /// It comes first, because it is the outermost thing: a menu that listed
    /// the pieces and then the whole would read inside out.
    @Test func theComponentItselfComesFirst() {
        let c = withCard()
        #expect(c.doc.componentPropertyCandidates(componentID: c.componentID).first?.layerID == c.main)
    }

    /// The card's own rounding and the line round it are NOT offered. A copy
    /// already owns those part by part, so a knob for them would be a second
    /// hand on one dial.
    @Test func theComponentsOwnLookIsNotOffered() {
        let c = withCard()
        #expect(rootCandidate(c)?.numberSlots.contains(.cornerRadius) == false)
        #expect(rootCandidate(c)?.kinds.contains(.visible) == false)
        #expect(rootCandidate(c)?.kinds.contains(.variant) == false)
        var doc = c.doc
        #expect(doc.canAddComponentProperty(componentID: c.componentID, target: c.main,
                                            kind: .number, numberSlot: .cornerRadius) == false)
        #expect(doc.addComponentProperty(componentID: c.componentID, target: c.main,
                                         kind: .number, numberSlot: .cornerRadius) == nil)
        #expect(doc.addComponentProperty(componentID: c.componentID, target: c.main,
                                         kind: .visible) == nil)
    }

    /// A card that arranges nothing has room at its edges but no gap: nothing
    /// is being held apart, so a Gap knob would turn a number nobody can see.
    @Test func aCardThatArrangesNothingOffersRoomOnly() {
        let c = withCard(kind: nil)
        #expect(rootCandidate(c)?.numberSlots == [.padding])
    }

    /// A card nobody has given a layout at all offers neither, rather than
    /// offering a number invented for the occasion.
    @Test func aCardWithNoLayoutOffersNothing() {
        var doc = PhotonzDocument(
            canvasSize: CGSize(width: 800, height: 600),
            layers: [text("Title", "Hello", CGRect(x: 20, y: 20, width: 80, height: 20)),
                     text("Body", "World", CGRect(x: 20, y: 52, width: 80, height: 20))])
        let main = doc.groupLayers(ids: Set(doc.layers.map(\.id)), name: "Card")!
        let componentID = doc.makeComponent(id: main.id)!
        let root = doc.componentPropertyCandidates(componentID: componentID)
            .first { $0.layerID == main.id }
        #expect(root == nil)
    }

    /// Exposing the room leaves the gap still on offer, the same way exposing a
    /// box's fill leaves its outline.
    @Test func exposingTheRoomStillOffersTheGap() {
        var c = withCard()
        _ = c.doc.addComponentProperty(componentID: c.componentID, target: c.main,
                                       kind: .number, numberSlot: .padding)
        #expect(rootCandidate(c)?.numberSlots == [.gap])
    }

    /// The knob is named after the number it turns, not after the card.
    @Test func theKnobIsNamedAfterTheNumber() {
        var c = withCard()
        let id = c.doc.addComponentProperty(componentID: c.componentID, target: c.main,
                                            kind: .number, numberSlot: .padding)!
        #expect(c.doc.componentProperty(componentID: c.componentID, propertyID: id)?.name == "Padding")
    }

    // MARK: - What a copy does with it

    /// The scene the rest of these run in: a card offering its room, and two
    /// copies of it out on the canvas.
    private func withTwoCopies() -> (history: History, componentID: UUID, main: UUID,
                                     knob: UUID, first: UUID, second: UUID) {
        var c = withCard()
        let knob = c.doc.addComponentProperty(componentID: c.componentID, target: c.main,
                                              kind: .number, numberSlot: .padding)!
        var history = History(document: c.doc)
        var first: UUID?
        var second: UUID?
        history.perform { $0.insertComponentInstance(of: c.componentID, at: CGPoint(x: 400, y: 200)).map { first = $0 } }
        history.perform { $0.insertComponentInstance(of: c.componentID, at: CGPoint(x: 400, y: 400)).map { second = $0 } }
        return (history, c.componentID, c.main, knob, first!, second!)
    }

    /// A copy arrives showing the card's own room, with nothing answered.
    @Test func aFreshCopyShowsTheOriginalsRoom() {
        let s = withTwoCopies()
        #expect(room(s.history.current, of: s.first) == 16)
        // Room reads as its four sides, even where all four agree
        // (`ComponentRoomKnobTests`).
        #expect(s.history.current.instanceValue(instance: s.first,
                                                property: s.knob)?.roomValue == GroupPadding(16))
        #expect(s.history.current.instanceOverrides(instance: s.first).isEmpty)
    }

    /// A copy given its own room shows it, and the contents move in the SAME
    /// edit rather than staying where the old room put them until the next one.
    @Test func aCopyGivenItsOwnRoomShowsIt() {
        var s = withTwoCopies()
        let before = s.history.current.layer(id: s.first)?.children.first?.frame.origin
        s.history.perform {
            $0.setInstanceOverride(instance: s.first, property: s.knob, value: .number(40))
        }
        #expect(room(s.history.current, of: s.first) == 40)
        // The original is untouched, and so is the copy beside it.
        #expect(room(s.history.current, of: s.main) == 16)
        #expect(room(s.history.current, of: s.second) == 16)
        let after = s.history.current.layer(id: s.first)?.children.first?.frame.origin
        #expect(after != before)
        #expect(after?.x == 40)
    }

    /// ...and it keeps it while the original goes on being edited.
    @Test func aCopyKeepsItsOwnRoomWhenTheOriginalIsEdited() {
        var s = withTwoCopies()
        s.history.perform {
            $0.setInstanceOverride(instance: s.first, property: s.knob, value: .number(40))
        }
        s.history.perform { $0.updateGroupLayout(id: s.main) { $0.padding = GroupPadding(4) } }
        #expect(room(s.history.current, of: s.first) == 40)
        // The one that answered nothing follows the original, which is the
        // whole point of only owning what you answered.
        #expect(room(s.history.current, of: s.second) == 4)
    }

    /// An edit to the original still reaches a copy that has answered the room
    /// knob: everything it did not answer keeps following.
    @Test func anAnsweredCopyStillFollowsEverythingElse() {
        var s = withTwoCopies()
        s.history.perform {
            $0.setInstanceOverride(instance: s.first, property: s.knob, value: .number(40))
        }
        s.history.perform { $0.updateGroupLayout(id: s.main) { $0.gap = 30 } }
        #expect(gap(s.history.current, of: s.first) == 30)
        #expect(room(s.history.current, of: s.first) == 40)
    }

    /// The way back: a copy put back on the original follows it again.
    @Test func puttingTheRoomBackFollowsTheOriginalAgain() {
        var s = withTwoCopies()
        s.history.perform {
            $0.setInstanceOverride(instance: s.first, property: s.knob, value: .number(40))
        }
        s.history.perform { $0.clearInstanceOverride(instance: s.first, property: s.knob) }
        #expect(room(s.history.current, of: s.first) == 16)
        #expect(s.history.current.instanceOverrides(instance: s.first).isEmpty)
    }

    /// A copy that owns its own width and its own room keeps both: they are
    /// different fields of one layout, so neither writes over the other.
    @Test func ownRoomAndOwnWidthLiveTogether() {
        var s = withTwoCopies()
        s.history.perform {
            $0.setInstanceOverride(instance: s.first, property: s.knob, value: .number(40))
            $0.updateLayer(id: s.first) { $0.setInstanceSize(InstanceSize(width: 320)) }
        }
        #expect(room(s.history.current, of: s.first) == 40)
        #expect(s.history.current.layer(id: s.first)?.group?.layout?.width == 320)
    }

    /// Turning the card back into a group that arranges nothing leaves a gap
    /// answer with nothing to write onto. The answer is KEPT, so turning the
    /// stack back on brings it straight back.
    @Test func aGapAnswerWaitsWhileTheCardArrangesNothing() {
        var c = withCard()
        let knob = c.doc.addComponentProperty(componentID: c.componentID, target: c.main,
                                              kind: .number, numberSlot: .gap)!
        var history = History(document: c.doc)
        var copy: UUID?
        history.perform { $0.insertComponentInstance(of: c.componentID, at: CGPoint(x: 400, y: 200)).map { copy = $0 } }
        let id = copy!
        history.perform { $0.setInstanceOverride(instance: id, property: knob, value: .number(30)) }
        #expect(gap(history.current, of: id) == 30)
        history.perform { $0.setGroupLayout(id: c.main, kind: nil) }
        #expect(history.current.instanceOverrides(instance: id).contains(knob))
        history.perform { $0.setGroupLayout(id: c.main, kind: .stack) }
        #expect(gap(history.current, of: id) == 30)
    }

    /// A copy nested inside another component carries its own room out into
    /// every copy of the component that holds it, in the same pass.
    @Test func aNestedCopysOwnRoomReachesTheCopiesAroundIt() {
        var c = withCard()
        let knob = c.doc.addComponentProperty(componentID: c.componentID, target: c.main,
                                              kind: .number, numberSlot: .padding)!
        var history = History(document: c.doc)
        // A card dropped on the canvas, wrapped in a group, made a component of
        // its own: a "Panel" whose one piece is a copy of the card.
        var inner: UUID?
        history.perform { $0.insertComponentInstance(of: c.componentID, at: CGPoint(x: 400, y: 200)).map { inner = $0 } }
        let card = inner!
        var panelID: UUID?
        var panelComponent: UUID?
        history.perform {
            guard let group = $0.groupLayers(ids: [card], name: "Panel") else { return }
            panelID = group.id
            panelComponent = $0.makeComponent(id: group.id)
        }
        let panel = panelComponent!
        // The card inside the panel is given its own room...
        let nested = history.current.layer(id: panelID!)!.children.first!.id
        history.perform { $0.setInstanceOverride(instance: nested, property: knob, value: .number(40)) }
        // ...and a copy of the panel shows it.
        var outer: UUID?
        history.perform { $0.insertComponentInstance(of: panel, at: CGPoint(x: 700, y: 400)).map { outer = $0 } }
        let piece = history.current.layer(id: outer!)?.children.first
        #expect(piece?.group?.layout?.usedPadding.uniform == 40)
    }

    // MARK: - On disk

    /// A knob pointed at the component itself is written and read back like any
    /// other, and a document with none of them is byte for byte what it was.
    @Test func itSurvivesADocumentRoundTrip() throws {
        var c = withCard()
        let knob = c.doc.addComponentProperty(componentID: c.componentID, target: c.main,
                                              kind: .number, numberSlot: .padding)!
        var history = History(document: c.doc)
        var copy: UUID?
        history.perform { $0.insertComponentInstance(of: c.componentID, at: CGPoint(x: 400, y: 200)).map { copy = $0 } }
        let id = copy!
        history.perform { $0.setInstanceOverride(instance: id, property: knob, value: .number(40)) }

        let data = try JSONEncoder().encode(history.current)
        let back = try JSONDecoder().decode(PhotonzDocument.self, from: data)
        #expect(back.componentProperty(componentID: c.componentID, propertyID: knob)?.target == c.main)
        // Stored as one number, read back as the same room on all four sides.
        #expect(back.instanceValue(instance: id, property: knob)?.roomValue == GroupPadding(40))
        #expect(room(back, of: id) == 40)
    }

    /// Duplicating the original mints a second component whose room knob points
    /// at its OWN outermost layer, not back at the first one.
    @Test func aDuplicatedOriginalsKnobPointsAtItself() {
        var c = withCard()
        _ = c.doc.addComponentProperty(componentID: c.componentID, target: c.main,
                                       kind: .number, numberSlot: .padding)
        let made = c.doc.layer(id: c.main)!.reidentified()
        #expect(made.componentProperties.first?.target == made.id)
    }
}
