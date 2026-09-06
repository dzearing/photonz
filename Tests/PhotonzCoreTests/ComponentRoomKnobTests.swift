import Foundation
import CoreGraphics
import Testing
@testable import PhotonzCore

/// Room that differs side to side, offered as ONE knob
/// (`docs/design/ui-building.md`, step C6).
///
/// A room knob used to be offered only while all four sides agreed, because the
/// knob read one number and four numbers are not one number. Almost no real
/// control is built that way: a button keeps 10 above and below and 16 beside,
/// and every starter component except the card is the same, so the whole
/// starter set had no room knob at all.
///
/// So the room knob carries four sides rather than one number, and a copy meets
/// it in the control the canvas already uses for room: one field reading
/// `10/16/10/16`, four sides behind a chevron, and typing one number over the
/// closed field levelling all four. Nothing else about a number knob changes: a
/// gap, a rounding and a thickness are still one number each.
struct ComponentRoomKnobTests {

    // MARK: - A button whose room differs side to side

    private func text(_ name: String, _ string: String, _ rect: CGRect) -> Layer {
        Layer(name: name, content: .text(TextContent(string: string)), frame: rect)
    }

    /// The shape of a real control: 10 of room above and below, 16 beside.
    private static let buttonRoom = GroupPadding(top: 10, right: 16, bottom: 10, left: 16)

    /// A component "Button" whose outermost layer is a stack holding a label,
    /// with a second stack "Row" inside it kept at the same uneven room, so
    /// there is a room to expose on the component ITSELF and one on a layer
    /// inside it.
    private func withButton() -> (doc: PhotonzDocument, main: UUID, componentID: UUID,
                                  rowID: UUID) {
        var doc = PhotonzDocument(
            canvasSize: CGSize(width: 800, height: 600),
            layers: [text("Label", "Save", CGRect(x: 20, y: 20, width: 60, height: 20)),
                     text("Badge", "3", CGRect(x: 100, y: 20, width: 20, height: 20))])
        let row = doc.groupLayers(ids: [doc.layers[0].id, doc.layers[1].id], name: "Row")!
        doc.setGroupLayout(id: row.id, kind: .stack)
        doc.updateGroupLayout(id: row.id) { $0.gap = 8; $0.padding = Self.buttonRoom }
        let main = doc.groupLayers(ids: [row.id], name: "Button")!
        doc.setGroupLayout(id: main.id, kind: .stack)
        doc.updateGroupLayout(id: main.id) { $0.gap = 8; $0.padding = Self.buttonRoom }
        let componentID = doc.makeComponent(id: main.id)!
        return (doc, main.id, componentID, row.id)
    }

    private func piece(_ doc: PhotonzDocument, in root: UUID, named name: String) -> Layer? {
        doc.layer(id: root)?.selfAndDescendants.first { $0.name == name }
    }

    /// The room a layer is actually working to.
    private func room(_ doc: PhotonzDocument, of id: UUID) -> GroupPadding? {
        doc.layer(id: id)?.group?.layout?.usedPadding
    }

    private func room(_ doc: PhotonzDocument, in root: UUID, named name: String) -> GroupPadding? {
        piece(doc, in: root, named: name)?.group?.layout?.usedPadding
    }

    // MARK: - What is offered

    /// The whole point: a button whose room differs side to side is offered a
    /// room knob, on the layer inside it and on the component itself.
    @Test func roomThatDiffersSideToSideIsOffered() {
        let c = withButton()
        let candidates = c.doc.componentPropertyCandidates(componentID: c.componentID)
        #expect(candidates.first { $0.layerID == c.rowID }?.numberSlots.contains(.padding) == true)
        #expect(candidates.first { $0.layerID == c.main }?.numberSlots == [.gap, .padding])
    }

    /// A group that has been given no layout at all still has no room to
    /// offer: nothing has been arranged, so there is nothing keeping room.
    @Test func aGroupWithNoLayoutOffersNoRoom() {
        var doc = PhotonzDocument(
            canvasSize: CGSize(width: 800, height: 600),
            layers: [text("Label", "Save", CGRect(x: 20, y: 20, width: 60, height: 20))])
        let main = doc.groupLayers(ids: [doc.layers[0].id], name: "Plain")!
        let componentID = doc.makeComponent(id: main.id)!
        let candidates = doc.componentPropertyCandidates(componentID: componentID)
        #expect(candidates.first { $0.layerID == main.id } == nil)
    }

    // MARK: - What a copy shows before anybody answers

    /// A copy that has not answered wears the original's four sides, and
    /// follows them when the original's room changes underneath.
    @Test func aCopyThatHasNotAnsweredFollowsAllFourSides() {
        var c = withButton()
        let knob = c.doc.addComponentProperty(componentID: c.componentID, target: c.rowID,
                                              kind: .number, numberSlot: .padding)!
        let copy = c.doc.insertComponentInstance(of: c.componentID, at: CGPoint(x: 400, y: 40))!
        c.doc.syncComponentInstances()
        #expect(room(c.doc, in: copy, named: "Row") == Self.buttonRoom)
        #expect(c.doc.instanceValue(instance: copy, property: knob)?.roomValue == Self.buttonRoom)

        let roomier = GroupPadding(top: 14, right: 24, bottom: 14, left: 24)
        c.doc.updateGroupLayout(id: c.rowID) { $0.padding = roomier }
        c.doc.syncComponentInstances()
        #expect(room(c.doc, in: copy, named: "Row") == roomier)
        #expect(c.doc.instanceValue(instance: copy, property: knob)?.roomValue == roomier)
    }

    /// The same for the room the component keeps inside its OWN edges, which
    /// lands on the copy's own layout rather than on anything inside it.
    @Test func aCopyFollowsTheComponentsOwnFourSides() {
        var c = withButton()
        let knob = c.doc.addComponentProperty(componentID: c.componentID, target: c.main,
                                              kind: .number, numberSlot: .padding)!
        let copy = c.doc.insertComponentInstance(of: c.componentID, at: CGPoint(x: 400, y: 40))!
        c.doc.syncComponentInstances()
        #expect(room(c.doc, of: copy) == Self.buttonRoom)
        #expect(c.doc.instanceValue(instance: copy, property: knob)?.roomValue == Self.buttonRoom)
    }

    // MARK: - Answering

    /// A copy given room of its own wears all four sides of it, and keeps them
    /// when the original's room changes underneath.
    @Test func aCopyKeepsItsOwnFourSides() {
        var c = withButton()
        let knob = c.doc.addComponentProperty(componentID: c.componentID, target: c.rowID,
                                              kind: .number, numberSlot: .padding)!
        let copy = c.doc.insertComponentInstance(of: c.componentID, at: CGPoint(x: 400, y: 40))!
        c.doc.syncComponentInstances()

        let own = GroupPadding(top: 12, right: 28, bottom: 12, left: 28)
        let set = c.doc.setInstanceOverride(instance: copy, property: knob, value: .room(own))
        #expect(set)
        c.doc.syncComponentInstances()
        #expect(room(c.doc, in: copy, named: "Row") == own)

        c.doc.updateGroupLayout(id: c.rowID) { $0.padding = GroupPadding(4) }
        c.doc.syncComponentInstances()
        #expect(room(c.doc, in: copy, named: "Row") == own)
        #expect(room(c.doc, of: c.rowID) == GroupPadding(4))
    }

    /// The same on the component's own edges: the copy's answer lands on the
    /// layout the copy works to.
    @Test func aCopyKeepsItsOwnFourSidesOnItsOwnEdges() {
        var c = withButton()
        let knob = c.doc.addComponentProperty(componentID: c.componentID, target: c.main,
                                              kind: .number, numberSlot: .padding)!
        let copy = c.doc.insertComponentInstance(of: c.componentID, at: CGPoint(x: 400, y: 40))!
        c.doc.syncComponentInstances()

        let own = GroupPadding(top: 20, right: 32, bottom: 20, left: 32)
        let set = c.doc.setInstanceOverride(instance: copy, property: knob, value: .room(own))
        #expect(set)
        c.doc.syncComponentInstances()
        #expect(room(c.doc, of: copy) == own)

        c.doc.updateGroupLayout(id: c.main) { $0.padding = GroupPadding(2) }
        c.doc.syncComponentInstances()
        #expect(room(c.doc, of: copy) == own)
    }

    /// Typing one number over the closed field is what levels all four sides,
    /// exactly as it does on the canvas.
    @Test func oneNumberLevelsAllFourSides() {
        var c = withButton()
        let knob = c.doc.addComponentProperty(componentID: c.componentID, target: c.rowID,
                                              kind: .number, numberSlot: .padding)!
        let copy = c.doc.insertComponentInstance(of: c.componentID, at: CGPoint(x: 400, y: 40))!
        c.doc.syncComponentInstances()
        let set = c.doc.setInstanceOverride(instance: copy, property: knob,
                                            value: .room(GroupPadding(20)))
        #expect(set)
        c.doc.syncComponentInstances()
        #expect(room(c.doc, in: copy, named: "Row") == GroupPadding(20))
    }

    /// Typing ONE side keeps the other three where they were, which is what
    /// lets a copy be roomier beside without leaving its family. The copy had
    /// not answered at all, so the three it keeps are the original's.
    @Test func typingOneSideKeepsTheOtherThree() {
        var c = withButton()
        let knob = c.doc.addComponentProperty(componentID: c.componentID, target: c.rowID,
                                              kind: .number, numberSlot: .padding)!
        let copy = c.doc.insertComponentInstance(of: c.componentID, at: CGPoint(x: 400, y: 40))!
        c.doc.syncComponentInstances()

        let set = c.doc.setInstanceRoom(instances: [copy], property: knob, side: .left, to: 40)
        #expect(set == 1)
        c.doc.syncComponentInstances()
        #expect(room(c.doc, in: copy, named: "Row")
                == GroupPadding(top: 10, right: 16, bottom: 10, left: 40))
    }

    /// Two copies that keep different room each keep their OWN other three
    /// sides when one side is typed for both: the row speaks for both copies
    /// without flattening them into one.
    @Test func typingOneSideOverTwoCopiesKeepsEachOnesOwnThree() {
        var c = withButton()
        let knob = c.doc.addComponentProperty(componentID: c.componentID, target: c.rowID,
                                              kind: .number, numberSlot: .padding)!
        let one = c.doc.insertComponentInstance(of: c.componentID, at: CGPoint(x: 400, y: 40))!
        let two = c.doc.insertComponentInstance(of: c.componentID, at: CGPoint(x: 400, y: 200))!
        c.doc.syncComponentInstances()
        _ = c.doc.setInstanceOverride(instance: two, property: knob,
                                      value: .room(GroupPadding(top: 2, right: 4,
                                                                bottom: 2, left: 4)))

        let set = c.doc.setInstanceRoom(instances: [one, two], property: knob,
                                        side: .top, to: 30)
        #expect(set == 2)
        c.doc.syncComponentInstances()
        #expect(room(c.doc, in: one, named: "Row")
                == GroupPadding(top: 30, right: 16, bottom: 10, left: 16))
        #expect(room(c.doc, in: two, named: "Row")
                == GroupPadding(top: 30, right: 4, bottom: 2, left: 4))
    }

    /// Room below nought is not a thing anybody means, so it is settled to
    /// nought on the way in rather than stored and drawn.
    @Test func roomBelowNoughtIsSettledToNought() {
        var c = withButton()
        let knob = c.doc.addComponentProperty(componentID: c.componentID, target: c.rowID,
                                              kind: .number, numberSlot: .padding)!
        let copy = c.doc.insertComponentInstance(of: c.componentID, at: CGPoint(x: 400, y: 40))!
        c.doc.syncComponentInstances()
        _ = c.doc.setInstanceOverride(instance: copy, property: knob,
                                      value: .room(GroupPadding(top: -8, right: 12,
                                                                bottom: 4, left: 6)))
        #expect(c.doc.instanceValue(instance: copy, property: knob)?.roomValue
                == GroupPadding(top: 0, right: 12, bottom: 4, left: 6))
    }

    /// The way back still works: a copy put back follows the original's four
    /// sides again.
    @Test func revertingFollowsTheOriginalAgain() {
        var c = withButton()
        let knob = c.doc.addComponentProperty(componentID: c.componentID, target: c.rowID,
                                              kind: .number, numberSlot: .padding)!
        let copy = c.doc.insertComponentInstance(of: c.componentID, at: CGPoint(x: 400, y: 40))!
        c.doc.syncComponentInstances()
        _ = c.doc.setInstanceOverride(instance: copy, property: knob,
                                      value: .room(GroupPadding(30)))
        c.doc.syncComponentInstances()
        c.doc.clearInstanceOverride(instance: copy, property: knob)
        c.doc.syncComponentInstances()
        #expect(room(c.doc, in: copy, named: "Row") == Self.buttonRoom)
    }

    // MARK: - What the panel reads over several copies

    /// Two copies wearing the same room agree; one changed side puts the row
    /// on Mixed, the same as every other knob.
    @Test func twoCopiesReadTogetherAndThenDisagree() {
        var c = withButton()
        let knob = c.doc.addComponentProperty(componentID: c.componentID, target: c.rowID,
                                              kind: .number, numberSlot: .padding)!
        let one = c.doc.insertComponentInstance(of: c.componentID, at: CGPoint(x: 400, y: 40))!
        let two = c.doc.insertComponentInstance(of: c.componentID, at: CGPoint(x: 400, y: 200))!
        c.doc.syncComponentInstances()
        var selection = c.doc.componentKnobSelection(layerIDs: [one, two])
        #expect(selection.reading(knob).roomValue == Self.buttonRoom)

        _ = c.doc.setInstanceRoom(instances: [two], property: knob, side: .left, to: 40)
        selection = c.doc.componentKnobSelection(layerIDs: [one, two])
        #expect(selection.reading(knob).isMixed)
        #expect(selection.reading(knob).roomValue == nil)
    }

    /// One side that disagrees does not take the other three away: two copies
    /// that keep the same room beside and different room above still read
    /// their beside numbers, so the row hides nothing it knows.
    @Test func oneSideThatDisagreesLeavesTheOtherThreeReadable() {
        var c = withButton()
        let knob = c.doc.addComponentProperty(componentID: c.componentID, target: c.rowID,
                                              kind: .number, numberSlot: .padding)!
        let one = c.doc.insertComponentInstance(of: c.componentID, at: CGPoint(x: 400, y: 40))!
        let two = c.doc.insertComponentInstance(of: c.componentID, at: CGPoint(x: 400, y: 200))!
        c.doc.syncComponentInstances()
        _ = c.doc.setInstanceRoom(instances: [two], property: knob, side: .top, to: 30)

        let both = [one, two]
        #expect(c.doc.componentRoomSide(instances: both, property: knob, side: .top) == nil)
        #expect(c.doc.componentRoomSide(instances: both, property: knob, side: .left) == 16)
        #expect(c.doc.componentRoomSide(instances: both, property: knob, side: .right) == 16)
        #expect(c.doc.componentRoomSide(instances: both, property: knob, side: .bottom) == 10)
    }

    // MARK: - The other numbers are untouched

    /// A gap is still one number: only room carries four sides.
    @Test func aGapIsStillOneNumber() {
        var c = withButton()
        let knob = c.doc.addComponentProperty(componentID: c.componentID, target: c.rowID,
                                              kind: .number, numberSlot: .gap)!
        let copy = c.doc.insertComponentInstance(of: c.componentID, at: CGPoint(x: 400, y: 40))!
        c.doc.syncComponentInstances()
        #expect(c.doc.instanceValue(instance: copy, property: knob)?.numberValue == 8)
        #expect(c.doc.instanceValue(instance: copy, property: knob)?.roomValue == nil)
        _ = c.doc.setInstanceOverride(instance: copy, property: knob, value: .number(24))
        c.doc.syncComponentInstances()
        #expect(piece(c.doc, in: copy, named: "Row")?.group?.layout?.usedGap == 24)
    }

    /// Room may only be typed onto a room knob: a gap knob handed four sides
    /// has nowhere to put them, so the answer is refused rather than stored.
    @Test func fourSidesAreRefusedOnAKnobThatIsNotRoom() {
        var c = withButton()
        let knob = c.doc.addComponentProperty(componentID: c.componentID, target: c.rowID,
                                              kind: .number, numberSlot: .gap)!
        let copy = c.doc.insertComponentInstance(of: c.componentID, at: CGPoint(x: 400, y: 40))!
        c.doc.syncComponentInstances()
        let set = c.doc.setInstanceOverride(instance: copy, property: knob,
                                            value: .room(GroupPadding(20)))
        #expect(!set)
        #expect(c.doc.instanceValue(instance: copy, property: knob)?.numberValue == 8)
    }

    // MARK: - Saving, and what was saved before

    /// Four sides survive a save and an open.
    @Test func fourSidesSurviveSavingAndOpening() throws {
        var c = withButton()
        let knob = c.doc.addComponentProperty(componentID: c.componentID, target: c.rowID,
                                              kind: .number, numberSlot: .padding)!
        let copy = c.doc.insertComponentInstance(of: c.componentID, at: CGPoint(x: 400, y: 40))!
        c.doc.syncComponentInstances()
        let own = GroupPadding(top: 12, right: 28, bottom: 12, left: 28)
        _ = c.doc.setInstanceOverride(instance: copy, property: knob, value: .room(own))

        let data = try JSONEncoder().encode(c.doc)
        let reopened = try JSONDecoder().decode(PhotonzDocument.self, from: data)
        #expect(reopened.instanceValue(instance: copy, property: knob)?.roomValue == own)
    }

    /// A copy that answered a room knob back when the answer was ONE number
    /// opens as the same room on all four sides, rather than losing its answer.
    @Test func anAnswerSavedAsOneNumberOpensAsFourEqualSides() throws {
        var c = withButton()
        c.doc.updateGroupLayout(id: c.rowID) { $0.padding = GroupPadding(16) }
        let knob = c.doc.addComponentProperty(componentID: c.componentID, target: c.rowID,
                                              kind: .number, numberSlot: .padding)!
        let copy = c.doc.insertComponentInstance(of: c.componentID, at: CGPoint(x: 400, y: 40))!
        c.doc.syncComponentInstances()
        // What an older build stored: one number, on a room knob.
        _ = c.doc.setInstanceOverride(instance: copy, property: knob, value: .number(24))
        c.doc.syncComponentInstances()
        #expect(room(c.doc, in: copy, named: "Row") == GroupPadding(24))
        #expect(c.doc.instanceValue(instance: copy, property: knob)?.roomValue == GroupPadding(24))
    }
}
