import Foundation
import CoreGraphics
import Testing
@testable import PhotonzCore

/// A colour as a knob: one original produces a blue copy and a red copy, and
/// neither of them leaves the family (`docs/design/ui-building.md`, step C6).
struct ComponentColorKnobTests {

    private func box(_ name: String, _ rect: CGRect, fill: String?, stroke: String) -> Layer {
        var content = AnnotationContent(shape: .rectangle, start: .zero,
                                        end: CGPoint(x: rect.width, y: rect.height))
        content.colorHex = stroke
        content.fillColorHex = fill
        return Layer(name: name, content: .annotation(content), frame: rect)
    }

    private func text(_ name: String, _ string: String, _ rect: CGRect) -> Layer {
        Layer(name: name, content: .text(TextContent(string: string)), frame: rect)
    }

    /// A component "Button" holding a filled box and a label.
    private func withComponent() -> (doc: PhotonzDocument, main: UUID, componentID: UUID,
                                     boxID: UUID, labelID: UUID) {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 800, height: 600),
                                  layers: [box("Box", CGRect(x: 10, y: 10, width: 120, height: 40),
                                                fill: "#3366FF", stroke: "#112244"),
                                           text("Label", "Save", CGRect(x: 20, y: 18, width: 60, height: 20))])
        let boxID = doc.layers[0].id
        let labelID = doc.layers[1].id
        let main = doc.groupLayers(ids: [boxID, labelID], name: "Button")!
        let componentID = doc.makeComponent(id: main.id)!
        return (doc, main.id, componentID, boxID, labelID)
    }

    private func piece(_ doc: PhotonzDocument, in root: UUID, named name: String) -> Layer? {
        doc.layer(id: root)?.selfAndDescendants.first { $0.name == name }
    }

    /// What one named piece inside a copy is painted in a slot.
    private func paint(_ doc: PhotonzDocument, in root: UUID, named name: String,
                       slot: ColorSlot) -> Paint? {
        piece(doc, in: root, named: name)?.paint(for: slot)
    }

    private func styleID(_ doc: PhotonzDocument, in root: UUID, named name: String,
                         slot: ColorSlot) -> UUID? {
        piece(doc, in: root, named: name)?.colorStyleID(for: slot)
    }

    // MARK: - Choosing a colour as the thing that is adjustable

    /// A box offers both of its colours, and a label offers its ink. Nothing
    /// that has no colour offers one.
    @Test func aLayerOffersTheColoursItActuallyHas() {
        let c = withComponent()
        let candidates = c.doc.componentPropertyCandidates(componentID: c.componentID)
        let slots = Dictionary(uniqueKeysWithValues: candidates.map { ($0.layerID, $0.colorSlots) })
        #expect(slots[c.boxID] == [.fill, .stroke])
        #expect(slots[c.labelID] == [.text])
        let kinds = Dictionary(uniqueKeysWithValues: candidates.map { ($0.layerID, Set($0.kinds)) })
        #expect(kinds[c.boxID] == [.visible, .color])
        #expect(kinds[c.labelID] == [.text, .visible, .color])
    }

    /// A fill that has been switched off is not a colour anybody can expose:
    /// there is nothing there for a copy to follow.
    @Test func aSlotWithNoColourIsNotOffered() {
        var c = withComponent()
        _ = c.doc.setColorEnabled(layerIDs: [c.boxID], slot: .fill, on: false)
        let candidates = c.doc.componentPropertyCandidates(componentID: c.componentID)
        #expect(candidates.first { $0.layerID == c.boxID }?.colorSlots == [.stroke])
    }

    /// Exposing the fill leaves the outline still on offer: "already exposed"
    /// is about one colour, not about the layer.
    @Test func exposingOneColourStillOffersTheOther() {
        var c = withComponent()
        _ = c.doc.addComponentProperty(componentID: c.componentID, target: c.boxID,
                                       kind: .color, slot: .fill)
        let candidates = c.doc.componentPropertyCandidates(componentID: c.componentID)
        #expect(candidates.first { $0.layerID == c.boxID }?.colorSlots == [.stroke])
    }

    /// A colour knob is named for the PART it paints, never for the layer it
    /// sits on: one box has both a fill and an outline, so two knobs both
    /// called "Box" would be two rows nobody can tell apart.
    @Test func aColourKnobIsNamedAfterThePartItPaints() {
        var c = withComponent()
        let fill = c.doc.addComponentProperty(componentID: c.componentID, target: c.boxID,
                                              kind: .color, slot: .fill)!
        let outline = c.doc.addComponentProperty(componentID: c.componentID, target: c.boxID,
                                                 kind: .color, slot: .stroke)!
        let ink = c.doc.addComponentProperty(componentID: c.componentID, target: c.labelID,
                                             kind: .color, slot: .text)!
        let properties = c.doc.componentProperties(of: c.componentID)
        #expect(properties.first { $0.id == fill }?.name == "Fill")
        #expect(properties.first { $0.id == outline }?.name == "Outline")
        #expect(properties.first { $0.id == ink }?.name == "Text")
        #expect(properties.first { $0.id == fill }?.slot == .fill)
        #expect(properties.first { $0.id == outline }?.slot == .stroke)
    }

    /// Two fills on two different layers are numbered apart rather than
    /// arriving as one name twice.
    @Test func twoFillKnobsAreNamedApart() {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 400, height: 300),
                                  layers: [box("Track", CGRect(x: 0, y: 0, width: 40, height: 20),
                                                fill: "#FF0000", stroke: "#000000"),
                                           box("Knob", CGRect(x: 0, y: 0, width: 20, height: 20),
                                                fill: "#00FF00", stroke: "#000000")])
        let trackID = doc.layers[0].id
        let knobID = doc.layers[1].id
        let main = doc.groupLayers(ids: [trackID, knobID], name: "Switch")!
        let componentID = doc.makeComponent(id: main.id)!
        _ = doc.addComponentProperty(componentID: componentID, target: trackID, kind: .color, slot: .fill)
        _ = doc.addComponentProperty(componentID: componentID, target: knobID, kind: .color, slot: .fill)
        #expect(doc.componentProperties(of: componentID).map(\.name) == ["Fill", "Fill 2"])
    }

    /// A colour knob with no slot named is refused: there is no such thing as
    /// "the colour" of a box that has two.
    @Test func aColourKnobWithoutASlotIsRefused() {
        var c = withComponent()
        #expect(c.doc.addComponentProperty(componentID: c.componentID, target: c.boxID,
                                           kind: .color, slot: nil) == nil)
        #expect(c.doc.componentProperties(of: c.componentID).isEmpty)
    }

    // MARK: - A copy follows until it answers

    @Test func aCopyFollowsTheOriginalUntilItAnswers() {
        var c = withComponent()
        let fill = c.doc.addComponentProperty(componentID: c.componentID, target: c.boxID,
                                              kind: .color, slot: .fill)!
        let copy = c.doc.insertComponentInstance(of: c.componentID, at: CGPoint(x: 300, y: 300))!
        c.doc.syncComponentInstances()
        #expect(c.doc.instanceValue(instance: copy, property: fill)
                == .color(ComponentColorAnswer(paint: Paint(hex: "#3366FF"))))
        #expect(paint(c.doc, in: copy, named: "Box", slot: .fill) == Paint(hex: "#3366FF"))
    }

    /// The rule the whole knob exists for: one blue copy and one red copy, and
    /// repainting the original still reaches the one that never answered.
    @Test func editingTheOriginalRepaintsEveryCopyThatHasNotAnswered() {
        var c = withComponent()
        let fill = c.doc.addComponentProperty(componentID: c.componentID, target: c.boxID,
                                              kind: .color, slot: .fill)!
        let red = c.doc.insertComponentInstance(of: c.componentID, at: CGPoint(x: 300, y: 300))!
        let follower = c.doc.insertComponentInstance(of: c.componentID, at: CGPoint(x: 300, y: 400))!
        _ = c.doc.setInstanceColor(instances: [red], property: fill,
                                   answer: ComponentColorAnswer(paint: Paint(hex: "#FF0000")))
        c.doc.syncComponentInstances()
        #expect(paint(c.doc, in: red, named: "Box", slot: .fill) == Paint(hex: "#FF0000"))

        _ = c.doc.setColorHex(layerIDs: [c.boxID], slot: .fill, hex: "#00AA55")
        c.doc.syncComponentInstances()
        #expect(paint(c.doc, in: follower, named: "Box", slot: .fill) == Paint(hex: "#00AA55"))
        #expect(paint(c.doc, in: red, named: "Box", slot: .fill) == Paint(hex: "#FF0000"))
        // ...and the red one is still a copy, not a detached heap.
        #expect(c.doc.layer(id: red)?.instanceOf == c.componentID)
    }

    /// The way back: a copy put right follows the original again.
    @Test func clearingAColourAnswerPutsTheCopyBack() {
        var c = withComponent()
        let fill = c.doc.addComponentProperty(componentID: c.componentID, target: c.boxID,
                                              kind: .color, slot: .fill)!
        let copy = c.doc.insertComponentInstance(of: c.componentID, at: CGPoint(x: 300, y: 300))!
        _ = c.doc.setInstanceColor(instances: [copy], property: fill,
                                   answer: ComponentColorAnswer(paint: Paint(hex: "#FF0000")))
        c.doc.syncComponentInstances()
        c.doc.clearInstanceOverride(instance: copy, property: fill)
        c.doc.syncComponentInstances()
        #expect(paint(c.doc, in: copy, named: "Box", slot: .fill) == Paint(hex: "#3366FF"))
        #expect(c.doc.instanceOverrides(instance: copy).isEmpty)
    }

    /// Syncing twice produces the same document, or every edit would record an
    /// undo step for a change nobody made.
    @Test func aCopyWithItsOwnColourIsStable() {
        var c = withComponent()
        let fill = c.doc.addComponentProperty(componentID: c.componentID, target: c.boxID,
                                              kind: .color, slot: .fill)!
        let copy = c.doc.insertComponentInstance(of: c.componentID, at: CGPoint(x: 300, y: 300))!
        _ = c.doc.setInstanceColor(instances: [copy], property: fill,
                                   answer: ComponentColorAnswer(paint: Paint(hex: "#FF0000")))
        c.doc.syncComponentInstances()
        let settled = c.doc
        let report = c.doc.syncComponentInstances()
        #expect(c.doc == settled)
        #expect(report.isEmpty)
    }

    /// A gradient is a colour too: a slot that can hold a ramp keeps the ramp.
    @Test func aCopyCanAnswerWithAGradient() {
        var c = withComponent()
        let fill = c.doc.addComponentProperty(componentID: c.componentID, target: c.boxID,
                                              kind: .color, slot: .fill)!
        let copy = c.doc.insertComponentInstance(of: c.componentID, at: CGPoint(x: 300, y: 300))!
        var ramp = Paint(hex: "#FF0000")
        ramp.kind = .linear
        ramp.stops = [GradientStop(hex: "#FF0000", position: 0), GradientStop(hex: "#0000FF", position: 1)]
        _ = c.doc.setInstanceColor(instances: [copy], property: fill,
                                   answer: ComponentColorAnswer(paint: ramp))
        c.doc.syncComponentInstances()
        #expect(paint(c.doc, in: copy, named: "Box", slot: .fill)?.isGradient == true)
    }

    // MARK: - A saved name can be the answer

    /// Pointing a copy at a saved colour and then editing that colour moves the
    /// copy with it, which is the whole reason a name is worth answering with.
    @Test func editingASavedColourMovesEveryCopyThatPointsAtIt() {
        var c = withComponent()
        let fill = c.doc.addComponentProperty(componentID: c.componentID, target: c.boxID,
                                              kind: .color, slot: .fill)!
        let style = c.doc.addColorStyle(name: "Danger", colorHex: "#CC2222", roles: [.surface])
        let copy = c.doc.insertComponentInstance(of: c.componentID, at: CGPoint(x: 300, y: 300))!
        #expect(c.doc.setInstanceColorStyle(instances: [copy], property: fill, styleID: style) == 1)
        c.doc.syncComponentInstances()
        #expect(paint(c.doc, in: copy, named: "Box", slot: .fill) == Paint(hex: "#CC2222"))
        #expect(styleID(c.doc, in: copy, named: "Box", slot: .fill) == style)

        _ = c.doc.setColorStyleHex(styleID: style, hex: "#8800FF")
        c.doc.syncComponentInstances()
        #expect(paint(c.doc, in: copy, named: "Box", slot: .fill) == Paint(hex: "#8800FF"))
        #expect(styleID(c.doc, in: copy, named: "Box", slot: .fill) == style)
    }

    /// Renaming a saved colour never loosens anything: a copy points at the id.
    @Test func renamingASavedColourKeepsEveryCopyPointingAtIt() {
        var c = withComponent()
        let fill = c.doc.addComponentProperty(componentID: c.componentID, target: c.boxID,
                                              kind: .color, slot: .fill)!
        let style = c.doc.addColorStyle(name: "Danger", colorHex: "#CC2222", roles: [.surface])
        let copy = c.doc.insertComponentInstance(of: c.componentID, at: CGPoint(x: 300, y: 300))!
        _ = c.doc.setInstanceColorStyle(instances: [copy], property: fill, styleID: style)
        c.doc.renameColorStyle(id: style, to: "Destructive")
        c.doc.syncComponentInstances()
        #expect(c.doc.instanceValue(instance: copy, property: fill)?.colorValue?.styleID == style)
        #expect(c.doc.colorStyle(id: style)?.name == "Destructive")
    }

    /// Taking a saved colour off the shelf must never repaint anybody's work:
    /// the copy keeps exactly the colour it is wearing and simply owns it.
    @Test func deletingASavedColourLeavesTheCopyItsColour() {
        var c = withComponent()
        let fill = c.doc.addComponentProperty(componentID: c.componentID, target: c.boxID,
                                              kind: .color, slot: .fill)!
        let style = c.doc.addColorStyle(name: "Danger", colorHex: "#CC2222", roles: [.surface])
        let copy = c.doc.insertComponentInstance(of: c.componentID, at: CGPoint(x: 300, y: 300))!
        _ = c.doc.setInstanceColorStyle(instances: [copy], property: fill, styleID: style)
        _ = c.doc.setColorStyleHex(styleID: style, hex: "#8800FF")
        c.doc.deleteColorStyle(id: style)
        c.doc.syncComponentInstances()
        #expect(paint(c.doc, in: copy, named: "Box", slot: .fill) == Paint(hex: "#8800FF"))
        #expect(c.doc.instanceValue(instance: copy, property: fill)?.colorValue?.styleID == nil)
    }

    /// An answer naming a saved colour the document does not have is refused
    /// rather than stored as a claim nothing can honour.
    @Test func anAnswerNamingAnUnknownSavedColourIsRefused() {
        var c = withComponent()
        let fill = c.doc.addComponentProperty(componentID: c.componentID, target: c.boxID,
                                              kind: .color, slot: .fill)!
        let copy = c.doc.insertComponentInstance(of: c.componentID, at: CGPoint(x: 300, y: 300))!
        let answer = ComponentColorAnswer(paint: Paint(hex: "#FF0000"), styleID: UUID())
        #expect(c.doc.setInstanceOverride(instance: copy, property: fill, value: .color(answer)) == false)
        #expect(c.doc.instanceOverrides(instance: copy).isEmpty)
    }

    /// An answer of the wrong kind has nowhere to go.
    @Test func aWordingAnswerCannotLandOnAColourKnob() {
        var c = withComponent()
        let fill = c.doc.addComponentProperty(componentID: c.componentID, target: c.boxID,
                                              kind: .color, slot: .fill)!
        let copy = c.doc.insertComponentInstance(of: c.componentID, at: CGPoint(x: 300, y: 300))!
        #expect(c.doc.setInstanceOverride(instance: copy, property: fill, value: .text("nope")) == false)
    }

    // MARK: - Several copies at once

    /// Copies that agree read as one colour; copies that differ read Mixed, the
    /// same word every other control in the app uses.
    @Test func severalCopiesReadMixedWhenTheyDiffer() {
        var c = withComponent()
        let fill = c.doc.addComponentProperty(componentID: c.componentID, target: c.boxID,
                                              kind: .color, slot: .fill)!
        let a = c.doc.insertComponentInstance(of: c.componentID, at: CGPoint(x: 300, y: 300))!
        let b = c.doc.insertComponentInstance(of: c.componentID, at: CGPoint(x: 300, y: 400))!
        #expect(c.doc.componentColorSelection(instances: [a, b], property: fill).reading
                == .color("#3366FF"))

        _ = c.doc.setInstanceColor(instances: [a], property: fill,
                                   answer: ComponentColorAnswer(paint: Paint(hex: "#FF0000")))
        #expect(c.doc.componentColorSelection(instances: [a, b], property: fill).reading == .mixed)
    }

    /// ...and setting the row sets all of them, which is what stops Mixed being
    /// a dead end.
    @Test func settingTheRowSetsEveryCopyItSpeaksFor() {
        var c = withComponent()
        let fill = c.doc.addComponentProperty(componentID: c.componentID, target: c.boxID,
                                              kind: .color, slot: .fill)!
        let a = c.doc.insertComponentInstance(of: c.componentID, at: CGPoint(x: 300, y: 300))!
        let b = c.doc.insertComponentInstance(of: c.componentID, at: CGPoint(x: 300, y: 400))!
        _ = c.doc.setInstanceColor(instances: [a], property: fill,
                                   answer: ComponentColorAnswer(paint: Paint(hex: "#FF0000")))
        #expect(c.doc.setInstanceColor(instances: [a, b], property: fill,
                                       answer: ComponentColorAnswer(paint: Paint(hex: "#00FF00"))) == 2)
        c.doc.syncComponentInstances()
        #expect(c.doc.componentColorSelection(instances: [a, b], property: fill).reading
                == .color("#00FF00"))
        #expect(paint(c.doc, in: b, named: "Box", slot: .fill) == Paint(hex: "#00FF00"))
    }

    /// Copies all wearing the same saved colour read as that name, not as a
    /// colour, so the row says where the colour came from.
    @Test func copiesWearingOneSavedColourReadAsThatName() {
        var c = withComponent()
        let fill = c.doc.addComponentProperty(componentID: c.componentID, target: c.boxID,
                                              kind: .color, slot: .fill)!
        let style = c.doc.addColorStyle(name: "Danger", colorHex: "#CC2222", roles: [.surface])
        let a = c.doc.insertComponentInstance(of: c.componentID, at: CGPoint(x: 300, y: 300))!
        let b = c.doc.insertComponentInstance(of: c.componentID, at: CGPoint(x: 300, y: 400))!
        _ = c.doc.setInstanceColorStyle(instances: [a, b], property: fill, styleID: style)
        #expect(c.doc.componentColorSelection(instances: [a, b], property: fill).reading
                == .style(style))
    }

    // MARK: - Nothing dangles

    /// A knob whose layer is gone from the original goes with it, and so do the
    /// answers, rather than crashing or leaving a row over nothing.
    @Test func aKnobWhoseLayerIsGoneIsDropped() {
        var c = withComponent()
        let fill = c.doc.addComponentProperty(componentID: c.componentID, target: c.boxID,
                                              kind: .color, slot: .fill)!
        let copy = c.doc.insertComponentInstance(of: c.componentID, at: CGPoint(x: 300, y: 300))!
        _ = c.doc.setInstanceColor(instances: [copy], property: fill,
                                   answer: ComponentColorAnswer(paint: Paint(hex: "#FF0000")))
        c.doc.syncComponentInstances()
        _ = c.doc.removeLayer(id: c.boxID)
        c.doc.syncComponentInstances()
        #expect(c.doc.componentProperties(of: c.componentID).isEmpty)
        #expect(c.doc.instanceOverrides(instance: copy).isEmpty)
        #expect(c.doc.instanceValue(instance: copy, property: fill) == nil)
    }

    /// A colour switched off in the original after the knob was made leaves the
    /// knob with nothing to read, and nothing to write either.
    @Test func aKnobWhoseColourWentAwaySitsOut() {
        var c = withComponent()
        let fill = c.doc.addComponentProperty(componentID: c.componentID, target: c.boxID,
                                              kind: .color, slot: .fill)!
        let copy = c.doc.insertComponentInstance(of: c.componentID, at: CGPoint(x: 300, y: 300))!
        _ = c.doc.setColorEnabled(layerIDs: [c.boxID], slot: .fill, on: false)
        c.doc.syncComponentInstances()
        #expect(c.doc.instanceValue(instance: copy, property: fill) == nil)
        #expect(c.doc.setInstanceColor(instances: [copy], property: fill,
                                       answer: ComponentColorAnswer(paint: Paint(hex: "#FF0000"))) == 0)
        #expect(paint(c.doc, in: copy, named: "Box", slot: .fill) == nil)
    }

    // MARK: - What is on disk

    /// A document written before colour knobs existed opens exactly as it did:
    /// the slot is simply absent, and every old knob still decodes.
    @Test func aKnobSavedBeforeColoursDecodesUnchanged() throws {
        let json = """
        {"id":"1F4A0F4E-0000-4000-8000-000000000001","name":"Label","kind":"text",
         "target":"1F4A0F4E-0000-4000-8000-000000000002"}
        """
        let property = try JSONDecoder().decode(ComponentProperty.self, from: Data(json.utf8))
        #expect(property.kind == .text)
        #expect(property.slot == nil)
        #expect(property.name == "Label")
    }

    /// A colour answer survives a round trip, name and all.
    @Test func aColourAnswerRoundTrips() throws {
        let style = UUID()
        let value = ComponentPropertyValue.color(ComponentColorAnswer(paint: Paint(hex: "#123456"),
                                                                      styleID: style))
        let data = try JSONEncoder().encode(value)
        let back = try JSONDecoder().decode(ComponentPropertyValue.self, from: data)
        #expect(back == value)
        #expect(back.colorValue?.styleID == style)
    }

    /// A whole document with a colour knob and an answer round trips, so the
    /// copy opens the colour it was given.
    @Test func aDocumentWithAColourKnobRoundTrips() throws {
        var c = withComponent()
        let fill = c.doc.addComponentProperty(componentID: c.componentID, target: c.boxID,
                                              kind: .color, slot: .fill)!
        let copy = c.doc.insertComponentInstance(of: c.componentID, at: CGPoint(x: 300, y: 300))!
        _ = c.doc.setInstanceColor(instances: [copy], property: fill,
                                   answer: ComponentColorAnswer(paint: Paint(hex: "#FF0000")))
        c.doc.syncComponentInstances()
        let data = try JSONEncoder().encode(c.doc)
        var back = try JSONDecoder().decode(PhotonzDocument.self, from: data)
        back.syncComponentInstances()
        #expect(back.componentProperties(of: c.componentID).first?.slot == .fill)
        #expect(paint(back, in: copy, named: "Box", slot: .fill) == Paint(hex: "#FF0000"))
    }
}
