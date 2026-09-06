import Foundation
import CoreGraphics
import Testing
@testable import PhotonzCore

/// A number as a knob: one original produces a round copy and a square one, a
/// roomy copy and a tight one, and none of them leaves the family
/// (`docs/design/ui-building.md`, step C6).
struct ComponentNumberKnobTests {

    // MARK: - A component to turn knobs on

    private func box(_ name: String, _ rect: CGRect, radius: CGFloat = 0,
                     stroke: CGFloat = 2) -> Layer {
        var content = AnnotationContent(shape: .rectangle, start: .zero,
                                        end: CGPoint(x: rect.width, y: rect.height))
        content.colorHex = "#112244"
        content.fillColorHex = "#3366FF"
        content.cornerRadius = radius
        content.strokeWidth = stroke
        return Layer(name: name, content: .annotation(content), frame: rect)
    }

    private func text(_ name: String, _ string: String, _ rect: CGRect) -> Layer {
        Layer(name: name, content: .text(TextContent(string: string)), frame: rect)
    }

    /// A component "Card" holding a rounded box and a stack "Row" of two
    /// labels, so there is a rounding, a thickness, a gap and a room to expose.
    private func withCard() -> (doc: PhotonzDocument, main: UUID, componentID: UUID,
                                boxID: UUID, rowID: UUID, labelID: UUID) {
        var doc = PhotonzDocument(
            canvasSize: CGSize(width: 800, height: 600),
            layers: [box("Box", CGRect(x: 10, y: 10, width: 200, height: 120), radius: 8),
                     text("Title", "Hello", CGRect(x: 20, y: 20, width: 80, height: 20)),
                     text("Body", "World", CGRect(x: 20, y: 52, width: 80, height: 20))])
        let boxID = doc.layers[0].id
        let titleID = doc.layers[1].id
        let bodyID = doc.layers[2].id
        let row = doc.groupLayers(ids: [titleID, bodyID], name: "Row")!
        doc.setGroupLayout(id: row.id, kind: .stack)
        doc.updateGroupLayout(id: row.id) { $0.gap = 12; $0.padding = GroupPadding(16) }
        let main = doc.groupLayers(ids: [boxID, row.id], name: "Card")!
        let componentID = doc.makeComponent(id: main.id)!
        return (doc, main.id, componentID, boxID, row.id, titleID)
    }

    private func piece(_ doc: PhotonzDocument, in root: UUID, named name: String) -> Layer? {
        doc.layer(id: root)?.selfAndDescendants.first { $0.name == name }
    }

    private func number(_ doc: PhotonzDocument, in root: UUID, named name: String,
                        _ slot: ComponentNumberSlot) -> CGFloat? {
        piece(doc, in: root, named: name)?.number(for: slot)
    }

    // MARK: - Choosing a number as the thing that is adjustable

    /// A layer offers the numbers it actually has, and nothing else. A
    /// rectangle rounds and has a line round it; a stack has a gap and room
    /// inside; a label has neither.
    @Test func aLayerOffersTheNumbersItActuallyHas() {
        let c = withCard()
        let candidates = c.doc.componentPropertyCandidates(componentID: c.componentID)
        let slots = Dictionary(uniqueKeysWithValues: candidates.map { ($0.layerID, $0.numberSlots) })
        #expect(slots[c.boxID] == [.cornerRadius, .thickness])
        // A group has corners to cut off as well as contents to space out, so
        // it offers all three.
        #expect(slots[c.rowID] == [.cornerRadius, .gap, .padding])
        #expect(slots[c.labelID] == [])
        let kinds = Dictionary(uniqueKeysWithValues: candidates.map { ($0.layerID, Set($0.kinds)) })
        #expect(kinds[c.boxID]?.contains(.number) == true)
        #expect(kinds[c.labelID]?.contains(.number) == false)
    }

    /// Room that is different on each side is offered like any other room: the
    /// knob carries four sides rather than one number, which is what lets a
    /// copy of a button be roomier without turning into a square
    /// (`ComponentRoomKnobTests`).
    @Test func roomThatDiffersSideToSideIsStillOffered() {
        var c = withCard()
        c.doc.updateGroupLayout(id: c.rowID) {
            $0.padding = GroupPadding(top: 8, right: 20, bottom: 8, left: 20)
        }
        let candidates = c.doc.componentPropertyCandidates(componentID: c.componentID)
        #expect(candidates.first { $0.layerID == c.rowID }?.numberSlots
                == [.cornerRadius, .gap, .padding])
    }

    /// Exposing the rounding leaves the thickness still on offer: "already
    /// exposed" is about ONE number, not about the layer, exactly as it is for
    /// a colour.
    @Test func exposingOneNumberStillOffersTheOther() {
        var c = withCard()
        _ = c.doc.addComponentProperty(componentID: c.componentID, target: c.boxID,
                                       kind: .number, numberSlot: .cornerRadius)
        let candidates = c.doc.componentPropertyCandidates(componentID: c.componentID)
        #expect(candidates.first { $0.layerID == c.boxID }?.numberSlots == [.thickness])
        #expect(candidates.first { $0.layerID == c.boxID }?.kinds.contains(.number) == true)
    }

    /// The last number a layer has, once exposed, takes the whole kind off that
    /// layer's row.
    @Test func exposingEveryNumberTakesTheKindOffTheRow() {
        var c = withCard()
        for slot in [ComponentNumberSlot.cornerRadius, .thickness] {
            _ = c.doc.addComponentProperty(componentID: c.componentID, target: c.boxID,
                                           kind: .number, numberSlot: slot)
        }
        let candidates = c.doc.componentPropertyCandidates(componentID: c.componentID)
        #expect(candidates.first { $0.layerID == c.boxID }?.numberSlots == [])
        #expect(candidates.first { $0.layerID == c.boxID }?.kinds.contains(.number) == false)
    }

    /// A number knob with no part named is refused: "the number" of a box that
    /// has a rounding and a thickness is not a thing.
    @Test func aNumberKnobMustSayWhichNumber() {
        var c = withCard()
        let added = c.doc.addComponentProperty(componentID: c.componentID, target: c.boxID,
                                               kind: .number)
        #expect(added == nil)
        #expect(c.doc.componentProperties(of: c.componentID).isEmpty)
    }

    /// A knob is named after the number it turns, not after the layer, because
    /// one box has both a rounding and a thickness.
    @Test func aNumberKnobIsNamedAfterTheNumber() {
        var c = withCard()
        let radius = c.doc.addComponentProperty(componentID: c.componentID, target: c.boxID,
                                                kind: .number, numberSlot: .cornerRadius)!
        let room = c.doc.addComponentProperty(componentID: c.componentID, target: c.rowID,
                                              kind: .number, numberSlot: .padding)!
        let names = Dictionary(uniqueKeysWithValues:
            c.doc.componentProperties(of: c.componentID).map { ($0.id, $0.name) })
        #expect(names[radius] == "Corner radius")
        #expect(names[room] == "Padding")
    }

    // MARK: - What a copy shows before anybody answers

    /// A copy that has not answered shows the original's number, and follows it
    /// when the original changes.
    @Test func aCopyThatHasNotAnsweredFollowsTheOriginal() {
        var c = withCard()
        let knob = c.doc.addComponentProperty(componentID: c.componentID, target: c.boxID,
                                              kind: .number, numberSlot: .cornerRadius)!
        let copy = c.doc.insertComponentInstance(of: c.componentID, at: CGPoint(x: 400, y: 40))!
        c.doc.syncComponentInstances()
        #expect(number(c.doc, in: copy, named: "Box", .cornerRadius) == 8)
        #expect(c.doc.instanceValue(instance: copy, property: knob)?.numberValue == 8)

        _ = c.doc.setCornerRadius(layerIDs: [c.boxID], to: 24)
        c.doc.syncComponentInstances()
        #expect(number(c.doc, in: copy, named: "Box", .cornerRadius) == 24)
        #expect(c.doc.instanceValue(instance: copy, property: knob)?.numberValue == 24)
    }

    // MARK: - Answering

    /// A copy given a number of its own wears it, and keeps it when the
    /// original's own number changes underneath.
    @Test func aCopyKeepsItsOwnNumberWhenTheOriginalChanges() {
        var c = withCard()
        let knob = c.doc.addComponentProperty(componentID: c.componentID, target: c.boxID,
                                              kind: .number, numberSlot: .cornerRadius)!
        let square = c.doc.insertComponentInstance(of: c.componentID, at: CGPoint(x: 400, y: 40))!
        let following = c.doc.insertComponentInstance(of: c.componentID, at: CGPoint(x: 400, y: 240))!
        let squared = c.doc.setInstanceOverride(instance: square, property: knob, value: .number(0))
        #expect(squared)
        c.doc.syncComponentInstances()
        #expect(number(c.doc, in: square, named: "Box", .cornerRadius) == 0)
        #expect(number(c.doc, in: following, named: "Box", .cornerRadius) == 8)

        _ = c.doc.setCornerRadius(layerIDs: [c.boxID], to: 24)
        c.doc.syncComponentInstances()
        #expect(number(c.doc, in: square, named: "Box", .cornerRadius) == 0)
        #expect(number(c.doc, in: following, named: "Box", .cornerRadius) == 24)
    }

    /// The room inside a stack is a knob too, so one card can be roomy and the
    /// next one tight.
    @Test func aCopyCanBeGivenItsOwnRoomInside() {
        var c = withCard()
        let knob = c.doc.addComponentProperty(componentID: c.componentID, target: c.rowID,
                                              kind: .number, numberSlot: .padding)!
        let tight = c.doc.insertComponentInstance(of: c.componentID, at: CGPoint(x: 400, y: 40))!
        let set = c.doc.setInstanceOverride(instance: tight, property: knob, value: .number(4))
        #expect(set)
        c.doc.syncComponentInstances()
        let room = piece(c.doc, in: tight, named: "Row")?.group?.layout?.padding
        #expect(room == GroupPadding(4))
    }

    /// A gap is a knob, and setting one stops the stack spreading, exactly as
    /// typing a gap into the inspector does.
    @Test func aCopyCanBeGivenItsOwnGap() {
        var c = withCard()
        c.doc.updateGroupLayout(id: c.rowID) { $0.spreadsGap = true }
        let knob = c.doc.addComponentProperty(componentID: c.componentID, target: c.rowID,
                                              kind: .number, numberSlot: .gap)!
        let wide = c.doc.insertComponentInstance(of: c.componentID, at: CGPoint(x: 400, y: 40))!
        let set = c.doc.setInstanceOverride(instance: wide, property: knob, value: .number(40))
        #expect(set)
        c.doc.syncComponentInstances()
        let layout = piece(c.doc, in: wide, named: "Row")?.group?.layout
        #expect(layout?.gap == 40)
        #expect(layout?.spreadsGap == false)
    }

    /// A rectangle's rounding is the curve on its own outline; a group's is the
    /// mask over its picture. One knob writes whichever one actually rounds the
    /// layer, so it is never a knob that quietly does nothing.
    @Test func theKnobWritesWhicheverNumberActuallyRounds() {
        var c = withCard()
        let boxKnob = c.doc.addComponentProperty(componentID: c.componentID, target: c.boxID,
                                                 kind: .number, numberSlot: .cornerRadius)!
        let rowKnob = c.doc.addComponentProperty(componentID: c.componentID, target: c.rowID,
                                                 kind: .number, numberSlot: .cornerRadius)!
        let copy = c.doc.insertComponentInstance(of: c.componentID, at: CGPoint(x: 400, y: 40))!
        _ = c.doc.setInstanceOverride(instance: copy, property: boxKnob, value: .number(30))
        _ = c.doc.setInstanceOverride(instance: copy, property: rowKnob, value: .number(6))
        c.doc.syncComponentInstances()
        #expect(piece(c.doc, in: copy, named: "Box")?.annotation?.cornerRadius == 30)
        #expect(piece(c.doc, in: copy, named: "Box")?.style.cornerRadius == 0)
        #expect(piece(c.doc, in: copy, named: "Row")?.style.cornerRadius == 6)
    }

    /// Thickness on a shape is the line it draws itself, and the old border
    /// ring goes with it, so a copy never ends up wearing two rings.
    @Test func thicknessWritesTheOneRing() {
        var c = withCard()
        c.doc.updateLayer(id: c.boxID) { $0.style.borderWidth = 5 }
        let knob = c.doc.addComponentProperty(componentID: c.componentID, target: c.boxID,
                                              kind: .number, numberSlot: .thickness)!
        let copy = c.doc.insertComponentInstance(of: c.componentID, at: CGPoint(x: 400, y: 40))!
        _ = c.doc.setInstanceOverride(instance: copy, property: knob, value: .number(9))
        c.doc.syncComponentInstances()
        #expect(piece(c.doc, in: copy, named: "Box")?.annotation?.strokeWidth == 9)
        #expect(piece(c.doc, in: copy, named: "Box")?.style.borderWidth == 0)
    }

    /// A number below nought is not a thing anybody means, so the model holds
    /// the floor rather than storing it.
    @Test func aNegativeNumberIsClampedRatherThanStored() {
        var c = withCard()
        let knob = c.doc.addComponentProperty(componentID: c.componentID, target: c.boxID,
                                              kind: .number, numberSlot: .cornerRadius)!
        let copy = c.doc.insertComponentInstance(of: c.componentID, at: CGPoint(x: 400, y: 40))!
        let set = c.doc.setInstanceOverride(instance: copy, property: knob, value: .number(-12))
        #expect(set)
        #expect(c.doc.instanceValue(instance: copy, property: knob)?.numberValue == 0)
    }

    /// An answer of the wrong kind has nowhere to go: a number knob does not
    /// take a colour and a colour knob does not take a number.
    @Test func anAnswerOfTheWrongKindIsRefused() {
        var c = withCard()
        let knob = c.doc.addComponentProperty(componentID: c.componentID, target: c.boxID,
                                              kind: .number, numberSlot: .cornerRadius)!
        let copy = c.doc.insertComponentInstance(of: c.componentID, at: CGPoint(x: 400, y: 40))!
        let set = c.doc.setInstanceOverride(instance: copy, property: knob, value: .visible(false))
        #expect(!set)
        #expect(c.doc.instanceOverrides(instance: copy).isEmpty)
    }

    // MARK: - The way back

    /// Clearing a knob puts the copy back on the original's number.
    @Test func clearingPutsTheCopyBackOnTheOriginal() {
        var c = withCard()
        let knob = c.doc.addComponentProperty(componentID: c.componentID, target: c.boxID,
                                              kind: .number, numberSlot: .cornerRadius)!
        let copy = c.doc.insertComponentInstance(of: c.componentID, at: CGPoint(x: 400, y: 40))!
        _ = c.doc.setInstanceOverride(instance: copy, property: knob, value: .number(0))
        c.doc.syncComponentInstances()
        #expect(number(c.doc, in: copy, named: "Box", .cornerRadius) == 0)

        c.doc.clearInstanceOverride(instance: copy, property: knob)
        c.doc.syncComponentInstances()
        #expect(c.doc.instanceOverrides(instance: copy).isEmpty)
        #expect(number(c.doc, in: copy, named: "Box", .cornerRadius) == 8)
    }

    /// Taking the knob away takes every copy's answer with it.
    @Test func removingTheKnobForgetsTheAnswers() {
        var c = withCard()
        let knob = c.doc.addComponentProperty(componentID: c.componentID, target: c.boxID,
                                              kind: .number, numberSlot: .cornerRadius)!
        let copy = c.doc.insertComponentInstance(of: c.componentID, at: CGPoint(x: 400, y: 40))!
        _ = c.doc.setInstanceOverride(instance: copy, property: knob, value: .number(0))
        c.doc.removeComponentProperty(componentID: c.componentID, propertyID: knob)
        c.doc.syncComponentInstances()
        #expect(c.doc.instanceOverrides(instance: copy).isEmpty)
        #expect(number(c.doc, in: copy, named: "Box", .cornerRadius) == 8)
    }

    // MARK: - Several copies at once

    /// Over several copies the row reads the number they share, and Mixed the
    /// moment one of them differs, the way every other control does.
    @Test func theRowReadsMixedWhenTheCopiesDiffer() {
        var c = withCard()
        let knob = c.doc.addComponentProperty(componentID: c.componentID, target: c.boxID,
                                              kind: .number, numberSlot: .cornerRadius)!
        let one = c.doc.insertComponentInstance(of: c.componentID, at: CGPoint(x: 400, y: 40))!
        let two = c.doc.insertComponentInstance(of: c.componentID, at: CGPoint(x: 400, y: 240))!
        var selection = c.doc.componentKnobSelection(layerIDs: [one, two])
        #expect(selection.reading(knob).numberValue == 8)
        #expect(selection.reading(knob).isMixed == false)

        _ = c.doc.setInstanceOverride(instance: two, property: knob, value: .number(0))
        selection = c.doc.componentKnobSelection(layerIDs: [one, two])
        #expect(selection.reading(knob).isMixed)
        #expect(selection.reading(knob).numberValue == nil)
        #expect(selection.isOverridden(knob))
    }

    /// One number, every picked copy, in one step.
    @Test func oneNumberReachesEveryPickedCopy() {
        var c = withCard()
        let knob = c.doc.addComponentProperty(componentID: c.componentID, target: c.boxID,
                                              kind: .number, numberSlot: .cornerRadius)!
        let one = c.doc.insertComponentInstance(of: c.componentID, at: CGPoint(x: 400, y: 40))!
        let two = c.doc.insertComponentInstance(of: c.componentID, at: CGPoint(x: 400, y: 240))!
        let reached = c.doc.setInstanceOverride(instances: [one, two], property: knob, value: .number(2))
        #expect(reached == 2)
        c.doc.syncComponentInstances()
        #expect(number(c.doc, in: one, named: "Box", .cornerRadius) == 2)
        #expect(number(c.doc, in: two, named: "Box", .cornerRadius) == 2)
        let selection = c.doc.componentKnobSelection(layerIDs: [one, two])
        #expect(selection.reading(knob).numberValue == 2)
    }

    // MARK: - On disk

    /// A number knob and its answers survive a save and an open.
    @Test func aNumberKnobSurvivesARoundTrip() throws {
        var c = withCard()
        let knob = c.doc.addComponentProperty(componentID: c.componentID, target: c.rowID,
                                              kind: .number, numberSlot: .padding)!
        let copy = c.doc.insertComponentInstance(of: c.componentID, at: CGPoint(x: 400, y: 40))!
        _ = c.doc.setInstanceOverride(instance: copy, property: knob, value: .number(4))

        let data = try JSONEncoder().encode(c.doc)
        var reopened = try JSONDecoder().decode(PhotonzDocument.self, from: data)
        reopened.syncComponentInstances()
        let property = reopened.componentProperty(componentID: c.componentID, propertyID: knob)
        #expect(property?.kind == .number)
        #expect(property?.numberSlot == .padding)
        // Room stored as one number opens as the same room on all four sides.
        #expect(reopened.instanceValue(instance: copy, property: knob)?.roomValue
                == GroupPadding(4))
        #expect(piece(reopened, in: copy, named: "Row")?.group?.layout?.padding == GroupPadding(4))
    }

    /// A knob written before numbers existed opens exactly as it did: the new
    /// field is absent from the file rather than written as null.
    @Test func aKnobWithNoNumberWritesNothingExtra() throws {
        var c = withCard()
        _ = c.doc.addComponentProperty(componentID: c.componentID, target: c.labelID, kind: .text)
        let data = try JSONEncoder().encode(c.doc)
        let json = String(decoding: data, as: UTF8.self)
        #expect(!json.contains("numberSlot"))
        let reopened = try JSONDecoder().decode(PhotonzDocument.self, from: data)
        #expect(reopened.componentProperties(of: c.componentID).first?.numberSlot == nil)
    }
}
