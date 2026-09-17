import Foundation
import CoreGraphics
import Testing
@testable import PhotonzCore

/// A copy keeps following the original on the sides of its room it did not
/// touch (`docs/design/ui-building.md`, step C6).
///
/// Every other knob is one fact, so answering it is all or nothing: a copy
/// either says its own words or says the original's. Room is four facts behind
/// one knob, and answering it all or nothing turned out to be a decision nobody
/// made on purpose. Typing 40 into Left froze top, right and bottom at whatever
/// the original happened to be that afternoon, so making the component roomier
/// later skipped every copy anybody had ever nudged, and nothing on screen said
/// why.
///
/// Answered by the user on 2026-09-13, "Untouched sides keep following": a side
/// is the copy's own only once somebody types in it, and every other side goes
/// on following.
struct ComponentRoomFollowingTests {

    private func text(_ name: String, _ string: String, _ rect: CGRect) -> Layer {
        Layer(name: name, content: .text(TextContent(string: string)), frame: rect)
    }

    /// The shape of a real control: 10 of room above and below, 16 beside.
    private static let buttonRoom = GroupPadding(top: 10, right: 16, bottom: 10, left: 16)

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

    private func room(_ doc: PhotonzDocument, in root: UUID, named name: String) -> GroupPadding? {
        piece(doc, in: root, named: name)?.group?.layout?.usedPadding
    }

    private func room(_ doc: PhotonzDocument, of id: UUID) -> GroupPadding? {
        doc.layer(id: id)?.group?.layout?.usedPadding
    }

    /// A button, a room knob on the row inside it, and one copy of it.
    private func withCopy() -> (doc: PhotonzDocument, main: UUID, componentID: UUID,
                                rowID: UUID, knob: UUID, copy: UUID) {
        var c = withButton()
        let knob = c.doc.addComponentProperty(componentID: c.componentID, target: c.rowID,
                                              kind: .number, numberSlot: .padding)!
        let copy = c.doc.insertComponentInstance(of: c.componentID, at: CGPoint(x: 400, y: 40))!
        c.doc.syncComponentInstances()
        return (c.doc, c.main, c.componentID, c.rowID, knob, copy)
    }

    // MARK: - The answer itself

    /// A side nobody has typed in is absent, and an absent side is what
    /// following looks like in the model.
    @Test func anAnswerHoldsOnlyTheSidesSomebodyTyped() {
        var answer = ComponentRoomAnswer()
        #expect(answer.isEmpty)
        #expect(answer.whole == nil)
        answer[.left] = 40
        #expect(!answer.isEmpty)
        #expect(answer.answeredSides == [.left])
        #expect(answer.whole == nil)
        #expect(answer.resolved(over: Self.buttonRoom)
                == GroupPadding(top: 10, right: 16, bottom: 10, left: 40))
    }

    /// All four typed is still a thing a person can say, and it says itself.
    @Test func allFourAnsweredIsAWholeRoom() {
        let answer = ComponentRoomAnswer(GroupPadding(top: 1, right: 2, bottom: 3, left: 4))
        #expect(answer.answeredSides == [.top, .right, .bottom, .left])
        #expect(answer.whole == GroupPadding(top: 1, right: 2, bottom: 3, left: 4))
        #expect(answer.resolved(over: Self.buttonRoom)
                == GroupPadding(top: 1, right: 2, bottom: 3, left: 4))
    }

    // MARK: - Typing one side

    /// The heart of it: a copy typed roomier on the left goes on taking top,
    /// right and bottom from the original, so making the component roomier
    /// above still reaches it.
    @Test func theSidesNobodyTypedGoOnFollowingTheOriginal() {
        var c = withCopy()
        #expect(c.doc.setInstanceRoom(instances: [c.copy], property: c.knob,
                                      side: .left, to: 40) == 1)
        c.doc.syncComponentInstances()
        #expect(room(c.doc, in: c.copy, named: "Row")
                == GroupPadding(top: 10, right: 16, bottom: 10, left: 40))

        c.doc.updateGroupLayout(id: c.rowID) { $0.padding.top = 32 }
        c.doc.syncComponentInstances()
        #expect(room(c.doc, in: c.copy, named: "Row")
                == GroupPadding(top: 32, right: 16, bottom: 10, left: 40))
        #expect(c.doc.instanceValue(instance: c.copy, property: c.knob)?.roomValue
                == GroupPadding(top: 32, right: 16, bottom: 10, left: 40))
    }

    /// The same for the room the component keeps inside its OWN edges, which
    /// lands on the copy's own layout rather than on anything inside it.
    @Test func theCopysOwnEdgesFollowSideBySideToo() {
        var c = withButton()
        let knob = c.doc.addComponentProperty(componentID: c.componentID, target: c.main,
                                              kind: .number, numberSlot: .padding)!
        let copy = c.doc.insertComponentInstance(of: c.componentID, at: CGPoint(x: 400, y: 40))!
        c.doc.syncComponentInstances()
        #expect(c.doc.setInstanceRoom(instances: [copy], property: knob,
                                      side: .right, to: 48) == 1)
        c.doc.syncComponentInstances()
        #expect(room(c.doc, of: copy)
                == GroupPadding(top: 10, right: 48, bottom: 10, left: 16))

        c.doc.updateGroupLayout(id: c.main) { $0.padding.bottom = 26 }
        c.doc.syncComponentInstances()
        #expect(room(c.doc, of: copy)
                == GroupPadding(top: 10, right: 48, bottom: 26, left: 16))
    }

    /// Typing a second side keeps the first, and leaves the two nobody has
    /// touched still following.
    @Test func twoSidesTypedAndTwoStillFollowing() {
        var c = withCopy()
        _ = c.doc.setInstanceRoom(instances: [c.copy], property: c.knob, side: .left, to: 40)
        _ = c.doc.setInstanceRoom(instances: [c.copy], property: c.knob, side: .right, to: 40)
        #expect(c.doc.instanceRoomAnswer(instance: c.copy, property: c.knob)?.answeredSides
                == [.right, .left])

        c.doc.updateGroupLayout(id: c.rowID) { $0.padding = GroupPadding(4) }
        c.doc.syncComponentInstances()
        #expect(room(c.doc, in: c.copy, named: "Row")
                == GroupPadding(top: 4, right: 40, bottom: 4, left: 40))
    }

    /// Typing one number over the CLOSED field is still "all four of them are
    /// this", exactly as it is on the canvas, so it hands the copy all four and
    /// says so.
    @Test func oneNumberOverTheClosedFieldTakesAllFour() {
        var c = withCopy()
        let set = c.doc.setInstanceOverride(instance: c.copy, property: c.knob,
                                            value: .room(GroupPadding(20)))
        #expect(set)
        #expect(c.doc.instanceRoomAnswer(instance: c.copy, property: c.knob)?.answeredSides
                == [.top, .right, .bottom, .left])
        c.doc.updateGroupLayout(id: c.rowID) { $0.padding = GroupPadding(4) }
        c.doc.syncComponentInstances()
        #expect(room(c.doc, in: c.copy, named: "Row") == GroupPadding(20))
    }

    // MARK: - The way back, one side at a time

    /// A side handed back starts following again, and the sides beside it are
    /// left alone.
    @Test func oneSideCanBeHandedBackOnItsOwn() {
        var c = withCopy()
        _ = c.doc.setInstanceRoom(instances: [c.copy], property: c.knob, side: .left, to: 40)
        _ = c.doc.setInstanceRoom(instances: [c.copy], property: c.knob, side: .top, to: 30)

        #expect(c.doc.clearInstanceRoomSide(instances: [c.copy], property: c.knob,
                                            side: .top) == 1)
        c.doc.syncComponentInstances()
        #expect(room(c.doc, in: c.copy, named: "Row")
                == GroupPadding(top: 10, right: 16, bottom: 10, left: 40))

        c.doc.updateGroupLayout(id: c.rowID) { $0.padding.top = 32 }
        c.doc.syncComponentInstances()
        #expect(room(c.doc, in: c.copy, named: "Row")
                == GroupPadding(top: 32, right: 16, bottom: 10, left: 40))
    }

    /// Handing back the LAST side the copy owned leaves it following whole,
    /// with no answer stored and so no way back left to offer.
    @Test func handingBackTheLastSideLeavesNothingStored() {
        var c = withCopy()
        _ = c.doc.setInstanceRoom(instances: [c.copy], property: c.knob, side: .left, to: 40)
        #expect(c.doc.instanceOverrides(instance: c.copy).contains(c.knob))

        #expect(c.doc.clearInstanceRoomSide(instances: [c.copy], property: c.knob,
                                            side: .left) == 1)
        #expect(!c.doc.instanceOverrides(instance: c.copy).contains(c.knob))
        #expect(c.doc.instanceRoomAnswer(instance: c.copy, property: c.knob) == nil)
        c.doc.syncComponentInstances()
        #expect(room(c.doc, in: c.copy, named: "Row") == Self.buttonRoom)
    }

    /// A side nobody owns has nothing to hand back, so the way back is not
    /// offered for it and pressing it changes nothing.
    @Test func aSideStillFollowingHasNothingToHandBack() {
        var c = withCopy()
        _ = c.doc.setInstanceRoom(instances: [c.copy], property: c.knob, side: .left, to: 40)
        #expect(c.doc.componentRoomSideIsOwn(instances: [c.copy], property: c.knob,
                                             side: .left))
        #expect(!c.doc.componentRoomSideIsOwn(instances: [c.copy], property: c.knob,
                                              side: .top))
        #expect(c.doc.clearInstanceRoomSide(instances: [c.copy], property: c.knob,
                                            side: .top) == 0)
    }

    /// The whole knob's way back still puts every side back to following, so
    /// the row's own arrow means what it always meant.
    @Test func theWholeKnobStillHasOneWayBack() {
        var c = withCopy()
        _ = c.doc.setInstanceRoom(instances: [c.copy], property: c.knob, side: .left, to: 40)
        _ = c.doc.setInstanceRoom(instances: [c.copy], property: c.knob, side: .top, to: 30)
        c.doc.clearInstanceOverride(instance: c.copy, property: c.knob)
        c.doc.syncComponentInstances()
        #expect(room(c.doc, in: c.copy, named: "Row") == Self.buttonRoom)
        #expect(c.doc.instanceRoomAnswer(instance: c.copy, property: c.knob) == nil)
    }

    // MARK: - Several copies at once

    /// A side is shown as the copies' own while ANY of them owns it, which is
    /// the same rule the knob's own row uses to decide whether to wear a way
    /// back at all.
    @Test func aSideOwnedByOneOfTwoCopiesOffersItsWayBack() {
        var c = withButton()
        let knob = c.doc.addComponentProperty(componentID: c.componentID, target: c.rowID,
                                              kind: .number, numberSlot: .padding)!
        let one = c.doc.insertComponentInstance(of: c.componentID, at: CGPoint(x: 400, y: 40))!
        let two = c.doc.insertComponentInstance(of: c.componentID, at: CGPoint(x: 400, y: 200))!
        c.doc.syncComponentInstances()
        _ = c.doc.setInstanceRoom(instances: [two], property: knob, side: .left, to: 40)

        let both = [one, two]
        #expect(c.doc.componentRoomSideIsOwn(instances: both, property: knob, side: .left))
        #expect(!c.doc.componentRoomSideIsOwn(instances: both, property: knob, side: .top))
        #expect(c.doc.clearInstanceRoomSide(instances: both, property: knob, side: .left) == 1)
        c.doc.syncComponentInstances()
        #expect(room(c.doc, in: two, named: "Row") == Self.buttonRoom)
    }

    /// Two copies typed on one side each keep their own other three following,
    /// so an edit to the original reaches both of them everywhere else.
    @Test func twoCopiesEachKeepFollowingWhereTheyDidNotType() {
        var c = withButton()
        let knob = c.doc.addComponentProperty(componentID: c.componentID, target: c.rowID,
                                              kind: .number, numberSlot: .padding)!
        let one = c.doc.insertComponentInstance(of: c.componentID, at: CGPoint(x: 400, y: 40))!
        let two = c.doc.insertComponentInstance(of: c.componentID, at: CGPoint(x: 400, y: 200))!
        c.doc.syncComponentInstances()
        _ = c.doc.setInstanceRoom(instances: [one], property: knob, side: .left, to: 40)
        _ = c.doc.setInstanceRoom(instances: [two], property: knob, side: .top, to: 30)

        c.doc.updateGroupLayout(id: c.rowID) { $0.padding = GroupPadding(4) }
        c.doc.syncComponentInstances()
        #expect(room(c.doc, in: one, named: "Row")
                == GroupPadding(top: 4, right: 4, bottom: 4, left: 40))
        #expect(room(c.doc, in: two, named: "Row")
                == GroupPadding(top: 30, right: 4, bottom: 4, left: 4))
    }

    // MARK: - Nothing else moves

    /// Room below nought is still settled to nought on the way in, side by
    /// side, and a side nobody typed stays absent rather than being settled
    /// into existence.
    @Test func roomBelowNoughtIsStillSettledToNought() {
        var c = withCopy()
        _ = c.doc.setInstanceRoom(instances: [c.copy], property: c.knob, side: .left, to: -8)
        #expect(c.doc.instanceRoomAnswer(instance: c.copy, property: c.knob)?.answeredSides
                == [.left])
        #expect(c.doc.instanceValue(instance: c.copy, property: c.knob)?.roomValue
                == GroupPadding(top: 10, right: 16, bottom: 10, left: 0))
    }

    /// Room may still only be typed onto a room knob: a gap knob handed an
    /// answer with sides in it has nowhere to put them.
    @Test func sidesAreStillRefusedOnAKnobThatIsNotRoom() {
        var c = withButton()
        let knob = c.doc.addComponentProperty(componentID: c.componentID, target: c.rowID,
                                              kind: .number, numberSlot: .gap)!
        let copy = c.doc.insertComponentInstance(of: c.componentID, at: CGPoint(x: 400, y: 40))!
        c.doc.syncComponentInstances()
        let set = c.doc.setInstanceOverride(instance: copy, property: knob,
                                            value: .room(ComponentRoomAnswer(left: 20)))
        #expect(!set)
        #expect(c.doc.setInstanceRoom(instances: [copy], property: knob,
                                      side: .left, to: 20) == 0)
        #expect(c.doc.instanceValue(instance: copy, property: knob)?.numberValue == 8)
    }

    // MARK: - Saving, and what was saved before

    /// A copy that owns one side saves and opens owning that one side, still
    /// following on the other three.
    @Test func oneOwnedSideSurvivesSavingAndOpening() throws {
        var c = withCopy()
        _ = c.doc.setInstanceRoom(instances: [c.copy], property: c.knob, side: .left, to: 40)
        let data = try JSONEncoder().encode(c.doc)
        var reopened = try JSONDecoder().decode(PhotonzDocument.self, from: data)
        #expect(reopened.instanceRoomAnswer(instance: c.copy, property: c.knob)?.answeredSides
                == [.left])

        reopened.updateGroupLayout(id: c.rowID) { $0.padding.top = 32 }
        reopened.syncComponentInstances()
        #expect(room(reopened, in: c.copy, named: "Row")
                == GroupPadding(top: 32, right: 16, bottom: 10, left: 40))
    }

    /// A copy answered back when an answer took the whole knob opens owning all
    /// four sides, so nothing anybody already made changes shape on its own the
    /// first time they open it.
    @Test func anAnswerSavedAsAWholeRoomOpensOwningAllFour() throws {
        var c = withCopy()
        let own = GroupPadding(top: 12, right: 28, bottom: 12, left: 28)
        _ = c.doc.setInstanceOverride(instance: c.copy, property: c.knob, value: .room(own))
        let data = try JSONEncoder().encode(c.doc)
        var reopened = try JSONDecoder().decode(PhotonzDocument.self, from: data)
        #expect(reopened.instanceRoomAnswer(instance: c.copy, property: c.knob)?.whole == own)

        reopened.updateGroupLayout(id: c.rowID) { $0.padding = GroupPadding(4) }
        reopened.syncComponentInstances()
        #expect(room(reopened, in: c.copy, named: "Row") == own)
    }

    /// ...and one saved as a single number, from before room carried four sides
    /// at all, opens owning all four of that number.
    @Test func anAnswerSavedAsOneNumberStillOpensOwningAllFour() throws {
        var c = withCopy()
        _ = c.doc.setInstanceOverride(instance: c.copy, property: c.knob, value: .number(24))
        let data = try JSONEncoder().encode(c.doc)
        var reopened = try JSONDecoder().decode(PhotonzDocument.self, from: data)
        reopened.updateGroupLayout(id: c.rowID) { $0.padding = GroupPadding(4) }
        reopened.syncComponentInstances()
        #expect(room(reopened, in: c.copy, named: "Row") == GroupPadding(24))
    }

    /// A copy taken into a shared component at another scale takes its OWN
    /// sides up with it and leaves the ones it is following alone: those are
    /// the original's, and the original is being scaled too.
    @Test func scalingTakesUpOnlyTheSidesTheCopyOwns() {
        var c = withCopy()
        _ = c.doc.setInstanceRoom(instances: [c.copy], property: c.knob, side: .left, to: 40)
        let bigger = c.doc.layer(id: c.copy)!.rescaled(by: 2)
        let answer = bigger.group?.overrides
            .first { $0.property == c.knob }?.value.asRoomAnswer
        #expect(answer?.answeredSides == [.left])
        #expect(answer?[.left] == 80)
    }
}
