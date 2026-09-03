import Foundation
import CoreGraphics
import Testing
@testable import PhotonzCore

/// Turning what you have selected into a choice, in one act
/// (`docs/design/ui-building.md`, the C6 follow-up).
///
/// Before this the only way to offer a choice was to already know the shape of
/// the answer: group the alternatives by hand, then find that group again in
/// the original's Add menu. These tests pin the one-step version.
struct ComponentChoiceTests {

    private func box(_ name: String, _ rect: CGRect) -> Layer {
        Layer(name: name, content: .annotation(AnnotationContent(shape: .rectangle,
                                                                 start: .zero,
                                                                 end: CGPoint(x: rect.width, y: rect.height))),
              frame: rect)
    }

    /// A component "Row" holding a label box and two alternative buttons that
    /// nobody has grouped: exactly what somebody has on screen the moment they
    /// want a choice.
    private func withLooseAlternatives() -> (doc: PhotonzDocument, main: UUID, componentID: UUID,
                                             labelID: UUID, filledID: UUID, outlineID: UUID) {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 800, height: 600),
                                  layers: [box("Label", CGRect(x: 10, y: 10, width: 120, height: 40)),
                                           box("Filled", CGRect(x: 140, y: 10, width: 80, height: 32)),
                                           box("Outline", CGRect(x: 140, y: 10, width: 80, height: 32))])
        let labelID = doc.layers[0].id
        let filledID = doc.layers[1].id
        let outlineID = doc.layers[2].id
        let main = doc.groupLayers(ids: [labelID, filledID, outlineID], name: "Row")!
        let componentID = doc.makeComponent(id: main.id)!
        return (doc, main.id, componentID, labelID, filledID, outlineID)
    }

    // MARK: - One step

    /// The whole point: two shapes in, a group of alternatives and the knob
    /// that picks between them out, without anybody grouping first.
    @Test func twoShapesBecomeAChoiceInOneStep() {
        var c = withLooseAlternatives()
        #expect(c.doc.canMakeChoice(ids: [c.filledID, c.outlineID]))
        let made = c.doc.makeChoice(ids: [c.filledID, c.outlineID])
        #expect(made != nil)
        // The two shapes now live in a group of their own, inside the original.
        let group = c.doc.layer(id: made!.group)
        #expect(group?.children.map(\.id) == [c.filledID, c.outlineID])
        #expect(c.doc.parentID(of: made!.group) == c.main)
        // ...and the original exposes exactly one knob, a choice, aimed at it.
        let properties = c.doc.componentProperties(of: c.componentID)
        #expect(properties.count == 1)
        #expect(properties.first?.kind == .variant)
        #expect(properties.first?.target == made!.group)
        #expect(made?.options == 2)
    }

    /// A group whose alternatives all draw at once is not a choice, so the
    /// original settles on one the moment the knob exists.
    @Test func exactlyOneAlternativeShowsAfterwards() {
        var c = withLooseAlternatives()
        let made = c.doc.makeChoice(ids: [c.filledID, c.outlineID])!
        let shown = c.doc.layer(id: made.group)?.children.filter(\.isVisible) ?? []
        #expect(shown.count == 1)
        #expect(shown.first?.id == c.filledID)
    }

    /// The knob is met by name on every copy's panel, so it says what it sets.
    /// "Group 2" is a placeholder; "Choice · choice" is the chip said twice.
    @Test func theKnobAndItsGroupAreNamedForWhatTheyAre() {
        var c = withLooseAlternatives()
        let made = c.doc.makeChoice(ids: [c.filledID, c.outlineID])!
        #expect(c.doc.layer(id: made.group)?.name == "Choice")
        #expect(c.doc.componentProperty(componentID: c.componentID, propertyID: made.property)?.name == "Shape")
    }

    /// A second choice in the same component takes names nobody is using, so
    /// two rows are never the same word.
    @Test func aSecondChoiceTakesFreshNames() {
        var c = withLooseAlternatives()
        _ = c.doc.makeChoice(ids: [c.filledID, c.outlineID])!
        // Two more alternatives, drawn later, made into a second choice.
        var doc = c.doc
        let extraA = box("Small", CGRect(x: 300, y: 10, width: 40, height: 20))
        let extraB = box("Large", CGRect(x: 300, y: 10, width: 40, height: 20))
        let addedA = doc.addLayer(extraA, toGroup: c.main)
        let addedB = doc.addLayer(extraB, toGroup: c.main)
        #expect(addedA && addedB)
        let made = doc.makeChoice(ids: [extraA.id, extraB.id])!
        #expect(doc.layer(id: made.group)?.name == "Choice 2")
        #expect(doc.componentProperty(componentID: c.componentID, propertyID: made.property)?.name == "Shape 2")
    }

    /// Somebody who grouped by hand first is not at a dead end: the same act
    /// exposes the group where it stands rather than wrapping it again.
    @Test func aGroupThatAlreadyHoldsAlternativesIsExposedWhereItStands() {
        var c = withLooseAlternatives()
        let control = c.doc.groupLayers(ids: [c.filledID, c.outlineID], name: "Control")!
        let before = c.doc.allLayers.count
        #expect(c.doc.canMakeChoice(ids: [control.id]))
        let made = c.doc.makeChoice(ids: [control.id])!
        #expect(made.group == control.id)
        #expect(c.doc.allLayers.count == before)
        #expect(c.doc.componentProperties(of: c.componentID).first?.target == control.id)
        // A group somebody named keeps its name, and the knob borrows it.
        #expect(c.doc.layer(id: control.id)?.name == "Control")
        #expect(c.doc.componentProperties(of: c.componentID).first?.name == "Control")
    }

    /// The options the knob offers are the alternatives, in the order they are
    /// stacked, and nothing else.
    @Test func theAlternativesAreWhatTheKnobOffers() {
        var c = withLooseAlternatives()
        let made = c.doc.makeChoice(ids: [c.filledID, c.outlineID])!
        let options = c.doc.componentVariantOptions(componentID: c.componentID, propertyID: made.property)
        #expect(options.map(\.id) == [c.filledID, c.outlineID])
    }

    /// End to end: a copy placed afterwards can pick the other alternative,
    /// which is the reason the choice was made at all.
    @Test func aCopyCanPickTheOtherAlternative() {
        var c = withLooseAlternatives()
        let made = c.doc.makeChoice(ids: [c.filledID, c.outlineID])!
        let copy = c.doc.insertComponentInstance(of: c.componentID, at: CGPoint(x: 400, y: 300))!
        c.doc.setInstanceOverride(instance: copy, property: made.property, value: .variant(c.outlineID))
        let value = c.doc.instanceValue(instance: copy, property: made.property)
        #expect(value?.optionValue == c.outlineID)
    }

    // MARK: - When there is no choice to make

    /// Two shapes on the bare canvas have nowhere to hang a knob, so the row
    /// is not offered at all.
    @Test func loneLayersOutsideAnOriginalCannotBecomeAChoice() {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 800, height: 600),
                                  layers: [box("A", CGRect(x: 0, y: 0, width: 10, height: 10)),
                                           box("B", CGRect(x: 20, y: 0, width: 10, height: 10))])
        let ids: Set<UUID> = [doc.layers[0].id, doc.layers[1].id]
        #expect(!doc.canMakeChoice(ids: ids))
        #expect(doc.makeChoice(ids: ids) == nil)
    }

    /// One shape is not a set of alternatives.
    @Test func oneShapeIsNotAChoice() {
        var c = withLooseAlternatives()
        #expect(!c.doc.canMakeChoice(ids: [c.filledID]))
        #expect(c.doc.makeChoice(ids: [c.filledID]) == nil)
    }

    /// The same group is not exposed twice: a second row picking the same
    /// shapes would be two knobs fighting over one group.
    @Test func aGroupAlreadyExposedIsNotOfferedAgain() {
        var c = withLooseAlternatives()
        let made = c.doc.makeChoice(ids: [c.filledID, c.outlineID])!
        #expect(!c.doc.canMakeChoice(ids: [made.group]))
    }

    /// Inside a copy there is nothing to expose: those layers belong to the
    /// original and are rewritten on the next sync.
    @Test func insideACopyThereIsNothingToExpose() {
        var c = withLooseAlternatives()
        let copy = c.doc.insertComponentInstance(of: c.componentID, at: CGPoint(x: 400, y: 300))!
        let inside = c.doc.layer(id: copy)?.children ?? []
        #expect(inside.count >= 2)
        #expect(!c.doc.canMakeChoice(ids: Set(inside.prefix(2).map(\.id))))
    }

    /// Layers from two different lists cannot be grouped, so they cannot
    /// become alternatives either.
    @Test func layersInDifferentListsCannotBecomeAChoice() {
        var c = withLooseAlternatives()
        let control = c.doc.groupLayers(ids: [c.filledID, c.outlineID], name: "Control")!
        // The label sits beside the group, the outline sits inside it.
        #expect(!c.doc.canMakeChoice(ids: [c.labelID, c.outlineID]))
        #expect(c.doc.layer(id: control.id) != nil)
    }
}
