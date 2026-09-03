import Foundation
import CoreGraphics
import Testing
@testable import PhotonzCore

/// Step C6: an original chooses what is adjustable, and every copy can set
/// those without leaving the family (`docs/design/ui-building.md`).
struct ComponentPropertyTests {

    private func box(_ name: String, _ rect: CGRect) -> Layer {
        Layer(name: name, content: .annotation(AnnotationContent(shape: .rectangle,
                                                                 start: .zero,
                                                                 end: CGPoint(x: rect.width, y: rect.height))),
              frame: rect)
    }

    private func text(_ name: String, _ string: String, _ rect: CGRect) -> Layer {
        Layer(name: name, content: .text(TextContent(string: string)), frame: rect)
    }

    /// A component "Setting" holding a box, a text label and a "Control" group
    /// with two alternative shapes in it.
    private func withComponent() -> (doc: PhotonzDocument, main: UUID, componentID: UUID,
                                     boxID: UUID, labelID: UUID, controlID: UUID,
                                     toggleID: UUID, segmentedID: UUID) {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 800, height: 600),
                                  layers: [box("Box", CGRect(x: 10, y: 10, width: 120, height: 40)),
                                           text("Label", "Sharpen", CGRect(x: 20, y: 18, width: 60, height: 20)),
                                           box("Toggle", CGRect(x: 96, y: 18, width: 30, height: 18)),
                                           box("Segmented", CGRect(x: 96, y: 18, width: 30, height: 18))])
        let boxID = doc.layers[0].id
        let labelID = doc.layers[1].id
        let toggleID = doc.layers[2].id
        let segmentedID = doc.layers[3].id
        let control = doc.groupLayers(ids: [toggleID, segmentedID], name: "Control")!
        let main = doc.groupLayers(ids: [boxID, labelID, control.id], name: "Setting")!
        let componentID = doc.makeComponent(id: main.id)!
        return (doc, main.id, componentID, boxID, labelID, control.id, toggleID, segmentedID)
    }

    // MARK: - Choosing what is adjustable

    /// A layer only offers the knobs that mean something for it: wording is a
    /// text layer's alone, and a choice needs a group with alternatives in it.
    @Test func onlyTheKindsThatMeanSomethingAreOffered() {
        let c = withComponent()
        let candidates = c.doc.componentPropertyCandidates(componentID: c.componentID)
        let kinds = Dictionary(uniqueKeysWithValues: candidates.map { ($0.layerID, Set($0.kinds)) })
        #expect(kinds[c.labelID] == [.text, .visible])
        #expect(kinds[c.boxID] == [.visible])
        #expect(kinds[c.controlID] == [.visible, .variant])
        // The original itself is not a knob on itself: a copy's own visibility
        // is already the copy's.
        #expect(kinds[c.main] == nil)
    }

    @Test func aPropertyNamesItselfAfterTheLayerItExposes() {
        var c = withComponent()
        let property = c.doc.addComponentProperty(componentID: c.componentID, target: c.labelID, kind: .text)
        #expect(property != nil)
        let properties = c.doc.componentProperties(of: c.componentID)
        #expect(properties.count == 1)
        #expect(properties[0].name == "Label")
        #expect(properties[0].kind == .text)
        #expect(properties[0].target == c.labelID)
    }

    /// Two knobs on the same layer would both be called "Label", and a copy's
    /// panel would show two rows nobody could tell apart.
    @Test func twoPropertiesOnOneLayerAreNamedApart() {
        var c = withComponent()
        _ = c.doc.addComponentProperty(componentID: c.componentID, target: c.labelID, kind: .text)
        _ = c.doc.addComponentProperty(componentID: c.componentID, target: c.labelID, kind: .visible)
        #expect(c.doc.componentProperties(of: c.componentID).map(\.name) == ["Label", "Label 2"])
    }

    /// A knob is named for what it CONTROLS, never for what the layer happens
    /// to say right now. A wording knob named "Save" reads as a mistake the
    /// moment a copy answers "Cancel", so an unnamed text layer gives its knobs
    /// what they do instead.
    @Test func aKnobOnAnUnnamedTextLayerIsNamedAfterWhatItDoes() {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 400, height: 400),
                                  layers: [box("Box", CGRect(x: 0, y: 0, width: 40, height: 20)),
                                           text(TextBuilder.defaultLayerName, "Save",
                                                CGRect(x: 0, y: 30, width: 80, height: 20))])
        let labelID = doc.layers[1].id
        let group = doc.groupLayers(ids: Set(doc.layers.map(\.id)), name: "Setting")!
        let componentID = doc.makeComponent(id: group.id)!
        let property = doc.addComponentProperty(componentID: componentID, target: labelID, kind: .text)!
        #expect(doc.componentProperty(componentID: componentID, propertyID: property)?.name == "Wording")
        // ...and the words are nowhere in the name, so a copy that says
        // something else does not make the panel contradict itself.
        let copy = doc.insertComponentInstance(of: componentID, at: CGPoint(x: 200, y: 200))!
        let set = doc.setInstanceOverride(instance: copy, property: property, value: .text("Cancel"))
        #expect(set)
        #expect(doc.componentProperty(componentID: componentID, propertyID: property)?.name == "Wording")
        // A show-or-hide knob on the same layer has the same problem, since
        // every text layer in the app is called "Text".
        let shown = doc.addComponentProperty(componentID: componentID, target: labelID, kind: .visible)!
        #expect(doc.componentProperty(componentID: componentID, propertyID: shown)?.name == "Show")
    }

    /// A knob named after its words in a document made before the rule changed
    /// keeps that name. Nothing renames it behind the author's back, and it
    /// still answers to a rename by hand.
    @Test func aKnobNamedBeforeTheRuleChangedKeepsItsName() {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 400, height: 400),
                                  layers: [box("Box", CGRect(x: 0, y: 0, width: 40, height: 20)),
                                           text(TextBuilder.defaultLayerName, "Save",
                                                CGRect(x: 0, y: 30, width: 80, height: 20))])
        let labelID = doc.layers[1].id
        let group = doc.groupLayers(ids: Set(doc.layers.map(\.id)), name: "Setting")!
        let componentID = doc.makeComponent(id: group.id)!
        let property = doc.addComponentProperty(componentID: componentID, target: labelID,
                                                kind: .text, name: "Save")!
        let copy = doc.insertComponentInstance(of: componentID, at: CGPoint(x: 200, y: 200))!
        let set = doc.setInstanceOverride(instance: copy, property: property, value: .text("Cancel"))
        #expect(set)
        doc.syncComponentInstances()
        #expect(doc.componentProperty(componentID: componentID, propertyID: property)?.name == "Save")
        #expect(words(doc, in: copy, named: TextBuilder.defaultLayerName) == "Cancel")
        // Saved and opened again, it is still the name the author had.
        let reopened = try! JSONDecoder().decode(PhotonzDocument.self,
                                                 from: JSONEncoder().encode(doc))
        #expect(reopened.componentProperty(componentID: componentID, propertyID: property)?.name == "Save")
        doc.renameComponentProperty(componentID: componentID, propertyID: property, to: "Label")
        #expect(doc.componentProperty(componentID: componentID, propertyID: property)?.name == "Label")
    }

    /// The words still have a job: they tell the author WHICH text layer a menu
    /// row means, since two unnamed ones both read "Text". They belong in the
    /// menu, where they are read once, not in the name, where they are kept.
    @Test func theAddMenuShowsTheWordsOfAnUnnamedTextLayer() {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 400, height: 400),
                                  layers: [text(TextBuilder.defaultLayerName, "Save",
                                                CGRect(x: 0, y: 0, width: 80, height: 20)),
                                           text(TextBuilder.defaultLayerName, "Cancel",
                                                CGRect(x: 0, y: 30, width: 80, height: 20)),
                                           text("Title", "Rename this file",
                                                CGRect(x: 0, y: 60, width: 80, height: 20))])
        let group = doc.groupLayers(ids: Set(doc.layers.map(\.id)), name: "Bar")!
        let componentID = doc.makeComponent(id: group.id)!
        let rows = doc.componentPropertyCandidates(componentID: componentID)
        #expect(rows.map(\.menuLabel) == ["Text \u{201C}Save\u{201D}", "Text \u{201C}Cancel\u{201D}", "Title"])
    }

    /// A group the Group command made is called "Group", which says nothing on
    /// a copy's panel, so the knob takes what it DOES instead.
    @Test func aKnobOnAnUnnamedGroupIsNamedAfterWhatItDoes() {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 400, height: 400),
                                  layers: [box("A", CGRect(x: 0, y: 0, width: 40, height: 20)),
                                           box("B", CGRect(x: 0, y: 0, width: 80, height: 20)),
                                           box("Edge", CGRect(x: 0, y: 40, width: 40, height: 20))])
        let control = doc.groupLayers(ids: Set(doc.layers.prefix(2).map(\.id)))!
        #expect(control.name == "Group")
        let main = doc.groupLayers(ids: Set(doc.layers.map(\.id)), name: "Row")!
        let componentID = doc.makeComponent(id: main.id)!
        let property = doc.addComponentProperty(componentID: componentID, target: control.id, kind: .variant)!
        #expect(doc.componentProperty(componentID: componentID, propertyID: property)?.name == "Shape")
    }

    @Test func aLayerAlreadyExposedThatWayIsNotOfferedAgain() {
        var c = withComponent()
        _ = c.doc.addComponentProperty(componentID: c.componentID, target: c.labelID, kind: .text)
        let candidates = c.doc.componentPropertyCandidates(componentID: c.componentID)
        let label = candidates.first { $0.layerID == c.labelID }
        #expect(label?.kinds == [.visible])
    }

    @Test func wordingIsRefusedOnALayerWithNoWording() {
        var c = withComponent()
        let ok1 = c.doc.addComponentProperty(componentID: c.componentID, target: c.boxID, kind: .text)
        #expect(ok1 == nil)
        #expect(c.doc.componentProperties(of: c.componentID).isEmpty)
    }

    /// Exposing a choice settles the original on one option, because a choice
    /// between shapes that are all showing at once is not a choice.
    @Test func exposingAChoiceLeavesExactlyOneOptionShowing() {
        var c = withComponent()
        _ = c.doc.addComponentProperty(componentID: c.componentID, target: c.controlID, kind: .variant)
        let control = c.doc.layer(id: c.controlID)!
        #expect(control.children.map(\.isVisible) == [true, false])
    }

    @Test func aChoiceListsOnlyTheShapesTheOriginalHolds() {
        var c = withComponent()
        let property = c.doc.addComponentProperty(componentID: c.componentID, target: c.controlID, kind: .variant)!
        let options = c.doc.componentVariantOptions(componentID: c.componentID, propertyID: property)
        #expect(options.map(\.id) == [c.toggleID, c.segmentedID])
        #expect(options.map(\.name) == ["Toggle", "Segmented"])
    }

    /// Two rectangles drawn one after the other are both called "Rectangle", so
    /// a choice menu of their names is a menu of identical rows.
    @Test func repeatedShapeNamesAreNumberedInTheChoiceMenu() {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 400, height: 400),
                                  layers: [box("Rectangle", CGRect(x: 0, y: 0, width: 40, height: 20)),
                                           box("Rectangle", CGRect(x: 0, y: 0, width: 80, height: 20)),
                                           box("Label", CGRect(x: 0, y: 40, width: 40, height: 20))])
        let control = doc.groupLayers(ids: Set(doc.layers.prefix(2).map(\.id)), name: "Control")!
        let main = doc.groupLayers(ids: Set(doc.layers.map(\.id)), name: "Row")!
        let componentID = doc.makeComponent(id: main.id)!
        let property = doc.addComponentProperty(componentID: componentID, target: control.id, kind: .variant)!
        let labels = doc.componentVariantOptionLabels(componentID: componentID, propertyID: property)
        #expect(labels.map(\.label) == ["Rectangle", "Rectangle 2"])
        // ...and nothing was renamed behind anybody's back.
        #expect(doc.layer(id: control.id)?.children.map(\.name) == ["Rectangle", "Rectangle"])
    }

    @Test func removingAPropertyTakesTheKnobAway() {
        var c = withComponent()
        let property = c.doc.addComponentProperty(componentID: c.componentID, target: c.labelID, kind: .text)!
        c.doc.removeComponentProperty(componentID: c.componentID, propertyID: property)
        #expect(c.doc.componentProperties(of: c.componentID).isEmpty)
    }

    @Test func aPropertyCanBeRenamedAndABlankNameIsRefused() {
        var c = withComponent()
        let property = c.doc.addComponentProperty(componentID: c.componentID, target: c.labelID, kind: .text)!
        c.doc.renameComponentProperty(componentID: c.componentID, propertyID: property, to: "  Caption ")
        #expect(c.doc.componentProperties(of: c.componentID)[0].name == "Caption")
        c.doc.renameComponentProperty(componentID: c.componentID, propertyID: property, to: "   ")
        #expect(c.doc.componentProperties(of: c.componentID)[0].name == "Caption")
    }

    /// A knob whose layer was deleted from the original is a knob that does
    /// nothing, so it goes when the layer does.
    @Test func aPropertyGoesWhenItsLayerDoes() {
        var c = withComponent()
        _ = c.doc.addComponentProperty(componentID: c.componentID, target: c.labelID, kind: .text)
        _ = c.doc.removeLayer(id: c.labelID)
        c.doc.syncComponentInstances()
        #expect(c.doc.componentProperties(of: c.componentID).isEmpty)
    }

    // MARK: - Setting a knob on one copy

    @Test func settingAKnobChangesThatCopyAlone() {
        var c = withComponent()
        let property = c.doc.addComponentProperty(componentID: c.componentID, target: c.labelID, kind: .text)!
        let first = c.doc.insertComponentInstance(of: c.componentID, at: CGPoint(x: 300, y: 300))!
        let second = c.doc.insertComponentInstance(of: c.componentID, at: CGPoint(x: 500, y: 300))!
        let ok2 = c.doc.setInstanceOverride(instance: first, property: property, value: .text("Blur"))
        #expect(ok2)
        c.doc.syncComponentInstances()

        #expect(wording(c.doc, in: first) == "Blur")
        #expect(wording(c.doc, in: second) == "Sharpen")
        // ...and the original is untouched.
        #expect(wording(c.doc, in: c.main) == "Sharpen")
    }

    @Test func showOrHideIsPerCopy() {
        var c = withComponent()
        let property = c.doc.addComponentProperty(componentID: c.componentID, target: c.boxID, kind: .visible)!
        let copy = c.doc.insertComponentInstance(of: c.componentID, at: CGPoint(x: 300, y: 300))!
        let ok3 = c.doc.setInstanceOverride(instance: copy, property: property, value: .visible(false))
        #expect(ok3)
        c.doc.syncComponentInstances()
        #expect(piece(c.doc, in: copy, named: "Box")?.isVisible == false)
        #expect(c.doc.layer(id: c.boxID)?.isVisible == true)
    }

    @Test func aChoiceSwapsWhichShapeShows() {
        var c = withComponent()
        let property = c.doc.addComponentProperty(componentID: c.componentID, target: c.controlID, kind: .variant)!
        let copy = c.doc.insertComponentInstance(of: c.componentID, at: CGPoint(x: 300, y: 300))!
        let ok4 = c.doc.setInstanceOverride(instance: copy, property: property, value: .variant(c.segmentedID))
        #expect(ok4)
        c.doc.syncComponentInstances()
        #expect(piece(c.doc, in: copy, named: "Toggle")?.isVisible == false)
        #expect(piece(c.doc, in: copy, named: "Segmented")?.isVisible == true)
        // The original still shows the shape it was left on.
        #expect(c.doc.layer(id: c.toggleID)?.isVisible == true)
    }

    /// The no-drift rule: a copy can never show something the original does not
    /// define, so an option that is not one of the shapes inside is refused.
    @Test func aChoiceCannotPickAShapeTheOriginalDoesNotHold() {
        var c = withComponent()
        let property = c.doc.addComponentProperty(componentID: c.componentID, target: c.controlID, kind: .variant)!
        let copy = c.doc.insertComponentInstance(of: c.componentID, at: CGPoint(x: 300, y: 300))!
        let ok5 = c.doc.setInstanceOverride(instance: copy, property: property, value: .variant(c.boxID))
        #expect(!ok5)
        let ok6 = c.doc.setInstanceOverride(instance: copy, property: property, value: .variant(UUID()))
        #expect(!ok6)
        #expect(c.doc.instanceOverrides(instance: copy).isEmpty)
    }

    /// A value of the wrong kind for the knob is refused too: wording on a
    /// show-or-hide knob has nowhere to land.
    @Test func aValueOfTheWrongKindIsRefused() {
        var c = withComponent()
        let property = c.doc.addComponentProperty(componentID: c.componentID, target: c.boxID, kind: .visible)!
        let copy = c.doc.insertComponentInstance(of: c.componentID, at: CGPoint(x: 300, y: 300))!
        let ok7 = c.doc.setInstanceOverride(instance: copy, property: property, value: .text("no"))
        #expect(!ok7)
    }

    /// A knob nobody has touched reads the original's own value, which is what
    /// the copy is drawing.
    @Test func anUntouchedKnobReadsTheOriginal() {
        var c = withComponent()
        let property = c.doc.addComponentProperty(componentID: c.componentID, target: c.labelID, kind: .text)!
        let copy = c.doc.insertComponentInstance(of: c.componentID, at: CGPoint(x: 300, y: 300))!
        #expect(c.doc.instanceValue(instance: copy, property: property) == .text("Sharpen"))
        #expect(c.doc.instanceOverrides(instance: copy).isEmpty)
        _ = c.doc.setInstanceOverride(instance: copy, property: property, value: .text("Blur"))
        #expect(c.doc.instanceValue(instance: copy, property: property) == .text("Blur"))
        #expect(c.doc.instanceOverrides(instance: copy) == [property])
    }

    @Test func aKnobCanBePutBackToFollowingTheOriginal() {
        var c = withComponent()
        let property = c.doc.addComponentProperty(componentID: c.componentID, target: c.labelID, kind: .text)!
        let copy = c.doc.insertComponentInstance(of: c.componentID, at: CGPoint(x: 300, y: 300))!
        _ = c.doc.setInstanceOverride(instance: copy, property: property, value: .text("Blur"))
        c.doc.syncComponentInstances()
        c.doc.clearInstanceOverride(instance: copy, property: property)
        c.doc.syncComponentInstances()
        #expect(wording(c.doc, in: copy) == "Sharpen")
        #expect(c.doc.instanceOverrides(instance: copy).isEmpty)
    }

    // MARK: - The link survives

    /// The rule the whole step exists for: an edit to the original still
    /// reaches a copy that has overridden something else.
    @Test func anEditToTheOriginalStillReachesAnOverriddenCopy() {
        var c = withComponent()
        let property = c.doc.addComponentProperty(componentID: c.componentID, target: c.labelID, kind: .text)!
        let copy = c.doc.insertComponentInstance(of: c.componentID, at: CGPoint(x: 300, y: 300))!
        _ = c.doc.setInstanceOverride(instance: copy, property: property, value: .text("Blur"))
        c.doc.syncComponentInstances()

        // Now widen the box in the original.
        c.doc.updateLayer(id: c.boxID) { $0.frame.size.width = 200 }
        c.doc.syncComponentInstances()

        #expect(piece(c.doc, in: copy, named: "Box")?.frame.width == 200)
        // ...and the override held.
        #expect(wording(c.doc, in: copy) == "Blur")
        #expect(c.doc.layer(id: copy)?.instanceOf == c.componentID)
    }

    /// Overriding the very thing the original then changes: the copy keeps its
    /// own answer, which is what "this one is different" has to mean.
    @Test func anOverrideOutranksTheOriginalsOwnValue() {
        var c = withComponent()
        let property = c.doc.addComponentProperty(componentID: c.componentID, target: c.labelID, kind: .text)!
        let copy = c.doc.insertComponentInstance(of: c.componentID, at: CGPoint(x: 300, y: 300))!
        _ = c.doc.setInstanceOverride(instance: copy, property: property, value: .text("Blur"))
        c.doc.updateLayer(id: c.labelID) { layer in
            guard case .text(var t) = layer.content else { return }
            t.string = "Denoise"
            layer.content = .text(t)
        }
        c.doc.syncComponentInstances()
        #expect(wording(c.doc, in: copy) == "Blur")
        #expect(wording(c.doc, in: c.main) == "Denoise")
    }

    /// Syncing twice must produce exactly the same document, or every edit
    /// would record an undo step for a change nobody made.
    @Test func aSyncedCopyIsStable() {
        var c = withComponent()
        let property = c.doc.addComponentProperty(componentID: c.componentID, target: c.controlID, kind: .variant)!
        let copy = c.doc.insertComponentInstance(of: c.componentID, at: CGPoint(x: 300, y: 300))!
        _ = c.doc.setInstanceOverride(instance: copy, property: property, value: .variant(c.segmentedID))
        c.doc.syncComponentInstances()
        let settled = c.doc
        let report = c.doc.syncComponentInstances()
        #expect(c.doc == settled)
        #expect(report.isEmpty)
    }

    /// A knob the original dropped takes the copy's answer with it, rather than
    /// leaving a value keyed to nothing.
    @Test func droppingAKnobDropsWhatCopiesSaidAboutIt() {
        var c = withComponent()
        let property = c.doc.addComponentProperty(componentID: c.componentID, target: c.labelID, kind: .text)!
        let copy = c.doc.insertComponentInstance(of: c.componentID, at: CGPoint(x: 300, y: 300))!
        _ = c.doc.setInstanceOverride(instance: copy, property: property, value: .text("Blur"))
        c.doc.syncComponentInstances()
        c.doc.removeComponentProperty(componentID: c.componentID, propertyID: property)
        c.doc.syncComponentInstances()
        #expect(c.doc.instanceOverrides(instance: copy).isEmpty)
        #expect(wording(c.doc, in: copy) == "Sharpen")
    }

    /// A copy of a copy (Command J) carries the overrides it was made from, or
    /// duplicating a configured button would silently reset it.
    @Test func duplicatingACopyCarriesItsOverrides() {
        var c = withComponent()
        let property = c.doc.addComponentProperty(componentID: c.componentID, target: c.labelID, kind: .text)!
        let copy = c.doc.insertComponentInstance(of: c.componentID, at: CGPoint(x: 300, y: 300))!
        _ = c.doc.setInstanceOverride(instance: copy, property: property, value: .text("Blur"))
        c.doc.syncComponentInstances()
        let twin = c.doc.duplicateLayer(id: copy)!.id
        c.doc.syncComponentInstances()
        #expect(c.doc.instanceOverrides(instance: twin) == [property])
        #expect(wording(c.doc, in: twin) == "Blur")
    }

    /// Duplicating an ORIGINAL makes a second component, and its knobs must
    /// point at its own layers rather than reaching back into the first.
    @Test func duplicatingAnOriginalRepointsItsKnobs() {
        var c = withComponent()
        _ = c.doc.addComponentProperty(componentID: c.componentID, target: c.labelID, kind: .text)
        let twin = c.doc.duplicateLayer(id: c.main)!.id
        let twinComponent = c.doc.layer(id: twin)!.componentID!
        #expect(twinComponent != c.componentID)
        let property = c.doc.componentProperties(of: twinComponent)[0]
        let owned = Set(c.doc.layer(id: twin)!.selfAndDescendants.map(\.id))
        #expect(owned.contains(property.target))
        #expect(property.target != c.labelID)
    }

    // MARK: - Detach

    @Test func detachTurnsACopyIntoOrdinaryLayers() {
        var c = withComponent()
        let property = c.doc.addComponentProperty(componentID: c.componentID, target: c.labelID, kind: .text)!
        let copy = c.doc.insertComponentInstance(of: c.componentID, at: CGPoint(x: 300, y: 300))!
        _ = c.doc.setInstanceOverride(instance: copy, property: property, value: .text("Blur"))
        c.doc.syncComponentInstances()

        #expect(c.doc.canDetachInstance(ids: [copy]))
        let ok8 = c.doc.detachInstance(id: copy)
        #expect(ok8)
        let detached = c.doc.layer(id: copy)!
        #expect(detached.instanceOf == nil)
        #expect(!detached.isComponentInstance)
        #expect(detached.isOpenableGroup)
        // It keeps exactly the picture it was drawing, override and all.
        #expect(wording(c.doc, in: copy) == "Blur")
        #expect(detached.children.map(\.name) == ["Box", "Label", "Control"])
        #expect(c.doc.instanceOverrides(instance: copy).isEmpty)
    }

    @Test func aDetachedCopyStopsFollowingTheOriginal() {
        var c = withComponent()
        let copy = c.doc.insertComponentInstance(of: c.componentID, at: CGPoint(x: 300, y: 300))!
        let ok9 = c.doc.detachInstance(id: copy)
        #expect(ok9)
        c.doc.updateLayer(id: c.boxID) { $0.frame.size.width = 200 }
        c.doc.syncComponentInstances()
        #expect(piece(c.doc, in: copy, named: "Box")?.frame.width == 120)
        // ...and the original has one fewer copy following it.
        #expect(c.doc.instanceCount(of: c.componentID) == 0)
    }

    @Test func detachIsOfferedOnlyForACopy() {
        var c = withComponent()
        let copy = c.doc.insertComponentInstance(of: c.componentID, at: CGPoint(x: 300, y: 300))!
        #expect(!c.doc.canDetachInstance(ids: [c.main]))
        #expect(!c.doc.canDetachInstance(ids: [c.boxID]))
        #expect(!c.doc.canDetachInstance(ids: []))
        #expect(!c.doc.canDetachInstance(ids: [copy, c.main]))
        c.doc.updateLayer(id: copy) { $0.isLocked = true }
        #expect(!c.doc.canDetachInstance(ids: [copy]))
    }

    // MARK: - On disk

    /// A group that exposes nothing and overrides nothing writes neither key,
    /// so a document saved before this step is byte for byte what it was.
    @Test func aPlainGroupWritesNoPropertyKeys() throws {
        let group = GroupContent(children: [])
        let data = try JSONEncoder().encode(group)
        let json = String(decoding: data, as: UTF8.self)
        #expect(!json.contains("properties"))
        #expect(!json.contains("overrides"))
    }

    @Test func knobsAndAnswersRoundTrip() throws {
        var c = withComponent()
        let property = c.doc.addComponentProperty(componentID: c.componentID, target: c.controlID, kind: .variant)!
        let copy = c.doc.insertComponentInstance(of: c.componentID, at: CGPoint(x: 300, y: 300))!
        _ = c.doc.setInstanceOverride(instance: copy, property: property, value: .variant(c.segmentedID))
        c.doc.syncComponentInstances()

        let data = try JSONEncoder().encode(c.doc)
        let reloaded = try JSONDecoder().decode(PhotonzDocument.self, from: data)
        #expect(reloaded == c.doc)
        #expect(reloaded.componentProperties(of: c.componentID).count == 1)
        #expect(reloaded.instanceOverrides(instance: copy) == [property])
    }

    // MARK: - Helpers

    private func piece(_ doc: PhotonzDocument, in root: UUID, named name: String) -> Layer? {
        doc.layer(id: root)?.selfAndDescendants.first { $0.name == name }
    }

    /// The words of one named piece inside a copy.
    private func words(_ doc: PhotonzDocument, in root: UUID, named name: String) -> String? {
        guard let layer = piece(doc, in: root, named: name),
              case .text(let content) = layer.content else { return nil }
        return content.string
    }

    private func wording(_ doc: PhotonzDocument, in root: UUID) -> String? {
        guard let label = piece(doc, in: root, named: "Label"),
              case .text(let content) = label.content else { return nil }
        return content.string
    }
}
