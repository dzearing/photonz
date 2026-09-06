import Foundation
import CoreGraphics
import Testing
@testable import PhotonzCore

/// The knobs panel speaking for several copies at once: pick five buttons and
/// set them together, rather than five times over
/// (`docs/design/mocks/shared/UX-PATTERNS.md` §4, "What a control DOES for
/// several picked things").
struct ComponentKnobSelectionTests {

    private func box(_ name: String, _ rect: CGRect, fill: String) -> Layer {
        var content = AnnotationContent(shape: .rectangle, start: .zero,
                                        end: CGPoint(x: rect.width, y: rect.height))
        content.colorHex = "#112244"
        content.fillColorHex = fill
        return Layer(name: name, content: .annotation(content), frame: rect)
    }

    private func text(_ name: String, _ string: String, _ rect: CGRect) -> Layer {
        Layer(name: name, content: .text(TextContent(string: string)), frame: rect)
    }

    /// A component "Button" with all four kinds of knob on it: a wording, a
    /// show-or-hide, a choice, and a colour.
    private struct Fixture {
        var doc: PhotonzDocument
        var componentID: UUID
        var wording: UUID
        var show: UUID
        var choice: UUID
        var fill: UUID
    }

    private func fixture() -> Fixture {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 900, height: 700),
                                  layers: [box("Box", CGRect(x: 10, y: 10, width: 160, height: 40),
                                                fill: "#3366FF"),
                                           text("Label", "Save", CGRect(x: 24, y: 18, width: 60, height: 20)),
                                           box("Tick", CGRect(x: 130, y: 18, width: 16, height: 16),
                                               fill: "#FFFFFF"),
                                           box("Cross", CGRect(x: 130, y: 18, width: 16, height: 16),
                                               fill: "#000000")])
        let boxID = doc.layers[0].id
        let labelID = doc.layers[1].id
        let icon = doc.groupLayers(ids: [doc.layers[2].id, doc.layers[3].id], name: "Icon")!
        let main = doc.groupLayers(ids: [boxID, labelID, icon.id], name: "Button")!
        let componentID = doc.makeComponent(id: main.id)!
        let wording = doc.addComponentProperty(componentID: componentID, target: labelID, kind: .text)!
        let show = doc.addComponentProperty(componentID: componentID, target: icon.id, kind: .visible)!
        let choice = doc.addComponentProperty(componentID: componentID, target: icon.id, kind: .variant)!
        let fill = doc.addComponentProperty(componentID: componentID, target: boxID,
                                            kind: .color, slot: .fill)!
        return Fixture(doc: doc, componentID: componentID, wording: wording, show: show,
                       choice: choice, fill: fill)
    }

    private func twoCopies(_ f: inout Fixture) -> (UUID, UUID) {
        let a = f.doc.insertComponentInstance(of: f.componentID, at: CGPoint(x: 300, y: 300))!
        let b = f.doc.insertComponentInstance(of: f.componentID, at: CGPoint(x: 300, y: 420))!
        return (a, b)
    }

    // MARK: - The section is on screen and speaks for all of them

    /// Two copies of one component keep the section, with the knobs the
    /// original exposes, in the original's order.
    @Test func twoCopiesOfOneComponentShowThatComponentsKnobs() {
        var f = fixture()
        let (a, b) = twoCopies(&f)
        let selection = f.doc.componentKnobSelection(layerIDs: [a, b])
        #expect(selection.componentID == f.componentID)
        #expect(selection.instances == [a, b])
        #expect(selection.count == 2)
        #expect(selection.componentName == "Button")
        #expect(selection.properties.map(\.id) == [f.wording, f.show, f.choice, f.fill])
        #expect(selection.hasDifferentComponents == false)
        #expect(selection.reachNote == nil)
    }

    /// One copy is the same reading, so the panel has ONE path for one copy and
    /// for five rather than two that can drift apart.
    @Test func oneCopyIsTheSameReading() {
        var f = fixture()
        let (a, _) = twoCopies(&f)
        let selection = f.doc.componentKnobSelection(layerIDs: [a])
        #expect(selection.instances == [a])
        #expect(selection.properties.count == 4)
        #expect(selection.reachNote == nil)
    }

    /// Nothing picked, or nothing picked that is a copy, is the "none" row of
    /// the table: there is no section at all.
    @Test func nothingPickedThatIsACopyBringsNoSection() {
        var f = fixture()
        _ = twoCopies(&f)
        let plain = f.doc.layers.first { $0.instanceOf == nil && !$0.isMainComponent }?.id
        let selection = f.doc.componentKnobSelection(layerIDs: [plain].compactMap { $0 })
        #expect(selection.isEmpty)
        #expect(selection.hasDifferentComponents == false)
        #expect(selection.properties.isEmpty)
    }

    // MARK: - What each knob reads

    /// Copies that agree read the value they share.
    @Test func copiesThatAgreeReadTheValueTheyShare() {
        var f = fixture()
        let (a, b) = twoCopies(&f)
        let selection = f.doc.componentKnobSelection(layerIDs: [a, b])
        #expect(selection.reading(f.wording) == .agreed(.text("Save")))
        #expect(selection.reading(f.show) == .agreed(.visible(true)))
    }

    /// Copies that differ read Mixed, whichever kind of knob it is.
    @Test func copiesThatDifferReadMixed() {
        var f = fixture()
        let (a, b) = twoCopies(&f)
        let tookWording = f.doc.setInstanceOverride(instance: a, property: f.wording,
                                                    value: .text("Go"))
        let tookShow = f.doc.setInstanceOverride(instance: a, property: f.show,
                                                 value: .visible(false))
        #expect(tookWording)
        #expect(tookShow)
        let selection = f.doc.componentKnobSelection(layerIDs: [a, b])
        #expect(selection.reading(f.wording) == .mixed)
        #expect(selection.reading(f.show) == .mixed)
        // ...and the ones they still agree on are not dragged into it.
        #expect(selection.reading(f.fill) != .mixed)
    }

    /// A choice reads Mixed when the copies show different shapes, and reads
    /// the shape they share otherwise.
    @Test func aChoiceReadsTheShapeTheyShareOrMixed() {
        var f = fixture()
        let (a, b) = twoCopies(&f)
        let options = f.doc.componentVariantOptions(componentID: f.componentID, propertyID: f.choice)
        #expect(options.count == 2)
        let tookA = f.doc.setInstanceOverride(instance: a, property: f.choice,
                                              value: .variant(options[1].id))
        #expect(tookA)
        #expect(f.doc.componentKnobSelection(layerIDs: [a, b]).reading(f.choice) == .mixed)
        let tookB = f.doc.setInstanceOverride(instance: b, property: f.choice,
                                              value: .variant(options[1].id))
        #expect(tookB)
        #expect(f.doc.componentKnobSelection(layerIDs: [a, b]).reading(f.choice)
                == .agreed(.variant(options[1].id)))
    }

    /// A knob any picked copy has answered for itself is a knob with a way
    /// back, which is what puts the revert control on the row.
    @Test func aKnobOneCopyHasAnsweredOffersTheWayBack() {
        var f = fixture()
        let (a, b) = twoCopies(&f)
        #expect(f.doc.componentKnobSelection(layerIDs: [a, b]).overriddenProperties.isEmpty)
        _ = f.doc.setInstanceOverride(instance: a, property: f.wording, value: .text("Go"))
        #expect(f.doc.componentKnobSelection(layerIDs: [a, b]).overriddenProperties == [f.wording])
    }

    // MARK: - Setting reaches every copy it speaks for

    /// Setting a knob sets every picked copy, and says how many it reached.
    @Test func settingAKnobReachesEveryPickedCopy() {
        var f = fixture()
        let (a, b) = twoCopies(&f)
        let reached = f.doc.setInstanceOverride(instances: [a, b], property: f.wording,
                                                value: .text("Go"))
        #expect(reached == 2)
        f.doc.syncComponentInstances()
        #expect(f.doc.componentKnobSelection(layerIDs: [a, b]).reading(f.wording)
                == .agreed(.text("Go")))
    }

    /// ...and the way back reaches all of them too.
    @Test func theWayBackReachesEveryPickedCopy() {
        var f = fixture()
        let (a, b) = twoCopies(&f)
        _ = f.doc.setInstanceOverride(instances: [a, b], property: f.wording, value: .text("Go"))
        let putBack = f.doc.clearInstanceOverride(instances: [a, b], property: f.wording)
        #expect(putBack == 2)
        #expect(f.doc.componentKnobSelection(layerIDs: [a, b]).overriddenProperties.isEmpty)
        #expect(f.doc.componentKnobSelection(layerIDs: [a, b]).reading(f.wording)
                == .agreed(.text("Save")))
    }

    /// A locked copy is not repainted by a command aimed at the copies beside
    /// it, and the row says it is speaking for fewer than were picked.
    @Test func aLockedCopyIsLeftOutAndSaidSo() {
        var f = fixture()
        let (a, b) = twoCopies(&f)
        f.doc.updateLayer(id: b) { $0.isLocked = true }
        let selection = f.doc.componentKnobSelection(layerIDs: [a, b])
        #expect(selection.instances == [a])
        #expect(selection.selectionCount == 2)
        #expect(selection.reachNote != nil)
        let reached = f.doc.setInstanceOverride(instances: [a, b], property: f.wording,
                                                value: .text("Go"))
        #expect(reached == 1)
    }

    // MARK: - Things that are not copies of this component

    /// A rectangle picked beside two copies has no knobs at all, so it is not a
    /// copy that disagrees: the section stays, speaks for the two, and says so.
    @Test func somethingWithNoKnobsIsNotDisagreement() {
        var f = fixture()
        let (a, b) = twoCopies(&f)
        f.doc.layers.append(box("Loose", CGRect(x: 600, y: 600, width: 40, height: 40),
                                fill: "#FF0000"))
        let loose = f.doc.layers.last!.id
        let selection = f.doc.componentKnobSelection(layerIDs: [a, b, loose])
        #expect(selection.componentID == f.componentID)
        #expect(selection.instances == [a, b])
        #expect(selection.selectionCount == 3)
        #expect(selection.reachNote
                == "2 of the 3 selected layers are copies of Button. "
                + "The knobs below change those.")
    }

    /// Copies of two different components have no knob in common: the section
    /// stays and says so in one sentence rather than going blank or averaging
    /// two originals' knobs together.
    @Test func copiesOfTwoComponentsSayWhyThereAreNoKnobs() {
        var f = fixture()
        let (a, _) = twoCopies(&f)
        var other = box("Chip", CGRect(x: 500, y: 40, width: 60, height: 24), fill: "#00AA55")
        other.name = "Chip"
        f.doc.layers.append(other)
        let chip = f.doc.groupLayers(ids: [f.doc.layers.last!.id], name: "Chip")!
        let chipComponent = f.doc.makeComponent(id: chip.id)!
        let chipCopy = f.doc.insertComponentInstance(of: chipComponent, at: CGPoint(x: 600, y: 300))!

        let selection = f.doc.componentKnobSelection(layerIDs: [a, chipCopy])
        #expect(selection.hasDifferentComponents)
        #expect(selection.componentID == nil)
        #expect(selection.properties.isEmpty)
        #expect(selection.isEmpty)
        #expect(ComponentKnobSelection.differentComponentsNote
                == "These copies come from different components. "
                + "Pick copies of one component to set their knobs together.")
    }

    /// The copies keep the order they were given, so the row reads the same way
    /// twice running and one undo step lands the same way every time.
    @Test func copiesKeepTheOrderTheyWereGiven() {
        var f = fixture()
        let (a, b) = twoCopies(&f)
        #expect(f.doc.componentKnobSelection(layerIDs: [b, a]).instances == [b, a])
    }

    // MARK: - The rows that report what a copy owns

    /// One copy picked keeps its own words; several picked count instead, so a
    /// row that was there for one copy does not vanish on the second.
    @Test func theOwnSizeRowCountsWhenSeveralArePicked() {
        var f = fixture()
        let (a, b) = twoCopies(&f)
        #expect(f.doc.instanceOwnSizeLabel(instances: [a, b]) == nil)
        f.doc.updateLayer(id: a) { $0.setInstanceSize(InstanceSize(width: 240)) }
        #expect(f.doc.instanceOwnSizeLabel(instances: [a]) == f.doc.instanceOwnSizeLabel(instance: a))
        #expect(f.doc.instanceOwnSizeLabel(instances: [a, b]) == "1 of the 2 copies has its own size")
        f.doc.updateLayer(id: b) { $0.setInstanceSize(InstanceSize(width: 260)) }
        #expect(f.doc.instanceOwnSizeLabel(instances: [a, b]) == "All 2 have their own size")
    }

    /// The same for the look a copy keeps for itself.
    @Test func theOwnLookRowCountsWhenSeveralArePicked() {
        var f = fixture()
        let (a, b) = twoCopies(&f)
        #expect(f.doc.instanceOwnLookLabel(instances: [a, b]) == nil)
        f.doc.updateLayer(id: a) { $0.style.opacity = 0.25 }
        #expect(f.doc.instanceOwnLookLabel(instances: [a]) == "Opacity")
        #expect(f.doc.instanceOwnLookLabel(instances: [a, b])
                == "1 of the 2 copies has a look of its own")
        let putBack = f.doc.clearInstanceStyleOverrides(instances: [a, b])
        #expect(putBack == 1)
        #expect(f.doc.instanceOwnLookLabel(instances: [a, b]) == nil)
    }

    // MARK: - Detaching what is picked

    /// Detach reaches every picked copy in one step, rather than dimming the
    /// moment a second copy is picked.
    @Test func detachReachesEveryPickedCopy() {
        var f = fixture()
        let (a, b) = twoCopies(&f)
        #expect(f.doc.canDetachInstance(ids: [a, b]))
        let detached = f.doc.detachInstances(ids: [a, b])
        #expect(detached == 2)
        #expect(f.doc.layer(id: a)?.isComponentInstance == false)
        #expect(f.doc.layer(id: b)?.isComponentInstance == false)
    }

    /// A locked copy, and anything picked that is not a copy at all, is left
    /// alone.
    @Test func detachLeavesOutWhatItCannotTouch() {
        var f = fixture()
        let (a, b) = twoCopies(&f)
        f.doc.updateLayer(id: b) { $0.isLocked = true }
        #expect(f.doc.detachableInstances(ids: [a, b]) == [a])
        let detached = f.doc.detachInstances(ids: [a, b])
        #expect(detached == 1)
        #expect(f.doc.layer(id: b)?.isComponentInstance == true)
    }

    /// What the word on screen says after several copies were detached.
    @Test func theDetachedNoticeCountsTheCopies() {
        let one = CopyConfirmation(subject: .componentDetached(component: "Button", count: 1),
                                        shownAt: Date())
        #expect(one.detail == "It no longer follows Button")
        let many = CopyConfirmation(subject: .componentDetached(component: "Button", count: 3),
                                         shownAt: Date())
        #expect(many.detail == "3 copies no longer follow Button")
    }
}
