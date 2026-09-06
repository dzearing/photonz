import Foundation
import CoreGraphics
import Testing
@testable import PhotonzCore

/// Versions: one component holds its normal, hover and disabled looks under
/// one name, and each copy picks which one it is showing
/// (`docs/design/ui-building.md`, "A component holds more than one version").
struct ComponentVersionTests {

    private func box(_ name: String, _ rect: CGRect) -> Layer {
        Layer(name: name, content: .annotation(AnnotationContent(shape: .rectangle,
                                                                 start: .zero,
                                                                 end: CGPoint(x: rect.width, y: rect.height))),
              frame: rect)
    }

    private func text(_ name: String, _ string: String, _ rect: CGRect) -> Layer {
        Layer(name: name, content: .text(TextContent(string: string)), frame: rect)
    }

    /// A component "Button" holding a box and a label, sitting at 10,10.
    private func withComponent() -> (doc: PhotonzDocument, main: UUID, componentID: UUID,
                                     boxID: UUID, labelID: UUID) {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 800, height: 600),
                                  layers: [box("Box", CGRect(x: 10, y: 10, width: 120, height: 40)),
                                           text("Label", "Save", CGRect(x: 20, y: 18, width: 60, height: 20))])
        let boxID = doc.layers[0].id
        let labelID = doc.layers[1].id
        let main = doc.groupLayers(ids: [boxID, labelID], name: "Button")!
        let componentID = doc.makeComponent(id: main.id)!
        return (doc, main.id, componentID, boxID, labelID)
    }

    // MARK: - One version until you ask for a second

    @Test func aPlainComponentIsOneVersion() {
        let c = withComponent()
        let versions = c.doc.componentVersions(of: c.componentID)
        #expect(versions.count == 1)
        #expect(versions[0].layerID == c.main)
        // Nothing is named until there is a second one to tell it apart from.
        #expect(c.doc.layer(id: c.main)?.componentVersionName == nil)
        #expect(versions[0].name == ComponentNaming.defaultVersionName)
    }

    @Test func addingAVersionCopiesTheWholeDrawing() {
        var c = withComponent()
        let added = c.doc.addComponentVersion(componentID: c.componentID)
        #expect(added != nil)
        let versions = c.doc.componentVersions(of: c.componentID)
        #expect(versions.count == 2)
        #expect(versions.map(\.name) == ["Default", "Version 2"])
        // The second version is a complete drawing of its own: same pieces,
        // its own layers, so changing one changes nothing in the other.
        let second = c.doc.mainComponent(componentID: c.componentID, version: added)!
        #expect(second.id != c.main)
        #expect(second.children.map(\.name) == ["Box", "Label"])
        let first = Set(c.doc.layer(id: c.main)!.selfAndDescendants.map(\.id))
        #expect(first.isDisjoint(with: Set(second.selfAndDescendants.map(\.id))))
        // ...and it is the same component, so the shelf still shows one tile.
        #expect(second.componentID == c.componentID)
        #expect(c.doc.componentLibraryEntries.count == 1)
    }

    @Test func aNewVersionLandsBesideTheOriginalOnTheCanvas() {
        var c = withComponent()
        let added = c.doc.addComponentVersion(componentID: c.componentID)!
        let second = c.doc.mainComponent(componentID: c.componentID, version: added)!
        // Loose on the canvas rather than inside whatever holds the original,
        // so adding a version never drops a stray button into a screen.
        #expect(c.doc.parentID(of: second.id) == nil)
        let original = c.doc.layer(id: c.main)!
        #expect(second.frame.minX > original.frame.maxX)
        #expect(second.frame.minY == original.frame.minY)
    }

    @Test func everyVersionCarriesTheComponentsName() {
        var c = withComponent()
        c.doc.addComponentVersion(componentID: c.componentID)
        c.doc.renameComponent(componentID: c.componentID, to: "Primary Button")
        let names = c.doc.componentVersions(of: c.componentID)
            .compactMap { c.doc.layer(id: $0.layerID)?.name }
        #expect(names == ["Primary Button", "Primary Button"])
        // The Library still prints one name for the component.
        #expect(c.doc.componentLibraryEntries.map(\.name) == ["Primary Button"])
    }

    @Test func aVersionCanBeRenamed() {
        var c = withComponent()
        let added = c.doc.addComponentVersion(componentID: c.componentID)!
        c.doc.renameComponentVersion(componentID: c.componentID, version: added, to: "Disabled")
        #expect(c.doc.componentVersions(of: c.componentID).map(\.name) == ["Default", "Disabled"])
        // A blank name is refused rather than leaving a nameless row in a menu.
        c.doc.renameComponentVersion(componentID: c.componentID, version: added, to: "   ")
        #expect(c.doc.componentVersions(of: c.componentID).map(\.name) == ["Default", "Disabled"])
    }

    @Test func theShelfTileSaysHowManyVersionsItHolds() {
        var c = withComponent()
        #expect(c.doc.componentLibraryEntries.first?.detail == ComponentNaming.mainDetail)
        c.doc.addComponentVersion(componentID: c.componentID)
        #expect(c.doc.componentLibraryEntries.first?.detail == "2 versions")
        c.doc.insertComponentInstance(of: c.componentID, at: CGPoint(x: 400, y: 300))
        #expect(c.doc.componentLibraryEntries.first?.detail == "2 versions • 1 copy")
    }

    // MARK: - A copy picks one

    @Test func aCopyShowsTheVersionItIsSetTo() {
        var c = withComponent()
        let disabled = c.doc.addComponentVersion(componentID: c.componentID)!
        // Give the second version a piece the first one does not have, which is
        // what "a complete drawing of its own" buys.
        let secondMain = c.doc.mainComponent(componentID: c.componentID, version: disabled)!
        c.doc.updateLayer(id: secondMain.children[1].id) { layer in
            guard case .text(var content) = layer.content else { return }
            content.string = "Off"
            layer.content = .text(content)
        }
        let copy = c.doc.insertComponentInstance(of: c.componentID, at: CGPoint(x: 400, y: 300))!
        c.doc.syncComponentInstances()
        #expect(c.doc.layer(id: copy)!.children[1].words == "Save")

        let took = c.doc.setInstanceVersion(instance: copy, to: disabled)
        #expect(took)
        c.doc.syncComponentInstances()
        #expect(c.doc.layer(id: copy)!.children[1].words == "Off")
        #expect(c.doc.instanceVersion(of: copy) == disabled)
    }

    @Test func switchingOneCopyLeavesTheOthersAlone() {
        var c = withComponent()
        let disabled = c.doc.addComponentVersion(componentID: c.componentID)!
        let secondMain = c.doc.mainComponent(componentID: c.componentID, version: disabled)!
        c.doc.updateLayer(id: secondMain.children[1].id) { layer in
            guard case .text(var content) = layer.content else { return }
            content.string = "Off"
            layer.content = .text(content)
        }
        let one = c.doc.insertComponentInstance(of: c.componentID, at: CGPoint(x: 300, y: 300))!
        let two = c.doc.insertComponentInstance(of: c.componentID, at: CGPoint(x: 500, y: 300))!
        c.doc.setInstanceVersion(instance: one, to: disabled)
        c.doc.syncComponentInstances()
        #expect(c.doc.layer(id: one)!.children[1].words == "Off")
        #expect(c.doc.layer(id: two)!.children[1].words == "Save")
    }

    @Test func aCopyKeepsItsOwnAnswersAcrossASwitch() {
        var c = withComponent()
        let knob = c.doc.addComponentProperty(componentID: c.componentID, target: c.labelID,
                                              kind: .text)!
        let disabled = c.doc.addComponentVersion(componentID: c.componentID)!
        let copy = c.doc.insertComponentInstance(of: c.componentID, at: CGPoint(x: 400, y: 300))!
        let answered = c.doc.setInstanceOverride(instance: copy, property: knob, value: .text("Delete"))
        #expect(answered)
        c.doc.syncComponentInstances()
        #expect(c.doc.layer(id: copy)!.children[1].words == "Delete")

        c.doc.setInstanceVersion(instance: copy, to: disabled)
        c.doc.syncComponentInstances()
        // The duplicate carries the same knob, pointed at its own label, so the
        // wording this copy chose survives the swap rather than snapping back.
        #expect(c.doc.instanceProperties(instance: copy).map(\.id) == [knob])
        #expect(c.doc.layer(id: copy)!.children[1].words == "Delete")
    }

    @Test func aCopyKeepsItsOwnSizeAcrossASwitch() {
        var c = withComponent()
        let disabled = c.doc.addComponentVersion(componentID: c.componentID)!
        let copy = c.doc.insertComponentInstance(of: c.componentID, at: CGPoint(x: 400, y: 300))!
        let box = c.doc.layer(id: copy)!.localBounds
        c.doc.updateLayer(id: copy) {
            $0 = $0.resized(to: CGRect(x: box.minX, y: box.minY, width: 300, height: box.height))
        }
        c.doc.syncComponentInstances()
        let wide = c.doc.layer(id: copy)!.frame.width
        #expect(c.doc.instanceOwnsSize(id: copy))
        c.doc.setInstanceVersion(instance: copy, to: disabled)
        c.doc.syncComponentInstances()
        #expect(c.doc.layer(id: copy)!.frame.width == wide)
    }

    @Test func aCopyIsRefusedAVersionOfSomeOtherComponent() {
        var c = withComponent()
        var other = withComponent()
        let copy = c.doc.insertComponentInstance(of: c.componentID, at: CGPoint(x: 400, y: 300))!
        let stranger = other.doc.addComponentVersion(componentID: other.componentID)!
        #expect(!c.doc.canSetInstanceVersion(instance: copy, to: stranger))
        let refused = c.doc.setInstanceVersion(instance: copy, to: stranger)
        #expect(!refused)
    }

    // MARK: - Editing one version

    @Test func editingAVersionReachesOnlyTheCopiesShowingIt() {
        var c = withComponent()
        let disabled = c.doc.addComponentVersion(componentID: c.componentID)!
        let one = c.doc.insertComponentInstance(of: c.componentID, at: CGPoint(x: 300, y: 300))!
        let two = c.doc.insertComponentInstance(of: c.componentID, at: CGPoint(x: 500, y: 300))!
        c.doc.setInstanceVersion(instance: one, to: disabled)
        var history = History(document: c.doc)
        let secondLabel = history.current
            .mainComponent(componentID: c.componentID, version: disabled)!.children[1].id

        let report = history.perform { doc in
            doc.updateLayer(id: secondLabel) { layer in
                guard case .text(var content) = layer.content else { return }
                content.string = "Off"
                layer.content = .text(content)
            }
        }
        #expect(report.componentSync.updatedInstances == 1)
        #expect(history.current.layer(id: one)!.children[1].words == "Off")
        #expect(history.current.layer(id: two)!.children[1].words == "Save")
        // ...and the edit and every copy that followed it are one undo.
        history.undo()
        #expect(history.current.layer(id: one)!.children[1].words == "Save")
    }

    // MARK: - Losing a version

    @Test func deletingAVersionLeavesItsCopiesOnOneThatExists() {
        var c = withComponent()
        let disabled = c.doc.addComponentVersion(componentID: c.componentID)!
        let copy = c.doc.insertComponentInstance(of: c.componentID, at: CGPoint(x: 400, y: 300))!
        c.doc.setInstanceVersion(instance: copy, to: disabled)
        c.doc.syncComponentInstances()

        let second = c.doc.mainComponent(componentID: c.componentID, version: disabled)!
        c.doc.removeLayers(ids: [second.id])
        let report = c.doc.syncComponentInstances()
        // It lands on a version that still exists rather than on nothing...
        #expect(c.doc.layer(id: copy)!.isComponentInstance)
        #expect(c.doc.instanceVersion(of: copy) == c.doc.componentVersions(of: c.componentID).first?.id)
        #expect(c.doc.layer(id: copy)!.children.map(\.name) == ["Box", "Label"])
        // ...and the app is told, so it can say so.
        #expect(report.strandedInstances == 1)
    }

    @Test func deletingTheLastVersionStillLetsTheCopiesKeepTheirPicture() {
        var c = withComponent()
        let copy = c.doc.insertComponentInstance(of: c.componentID, at: CGPoint(x: 400, y: 300))!
        c.doc.removeLayers(ids: [c.main])
        c.doc.syncComponentInstances()
        #expect(!c.doc.layer(id: copy)!.isComponentInstance)
        #expect(c.doc.layer(id: copy)!.children.map(\.name) == ["Box", "Label"])
    }

    /// A choice made against one version names a shape that version holds. The
    /// next version has its own shapes, so the answer matches nothing there —
    /// and a group with nothing showing is an empty hole on the canvas.
    @Test func aChoiceThatMatchesNothingLeavesTheShapesAlone() {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 800, height: 600),
                                  layers: [box("Toggle", CGRect(x: 10, y: 10, width: 30, height: 18)),
                                           box("Segmented", CGRect(x: 10, y: 10, width: 30, height: 18))])
        let control = doc.groupLayers(ids: Set(doc.layers.map(\.id)), name: "Control")!
        let main = doc.groupLayers(ids: [control.id], name: "Setting")!
        let componentID = doc.makeComponent(id: main.id)!
        let knob = doc.addComponentProperty(componentID: componentID, target: control.id,
                                            kind: .variant)!
        let copy = doc.insertComponentInstance(of: componentID, at: CGPoint(x: 400, y: 300))!
        // An answer naming a shape from somewhere else entirely.
        doc.updateLayer(id: copy) { layer in
            guard var group = layer.group else { return }
            group.overrides = [ComponentOverride(property: knob, value: .variant(UUID()))]
            layer.content = .group(group)
        }
        doc.syncComponentInstances()
        let shown = doc.layer(id: copy)!.children[0].children.filter(\.isVisible)
        #expect(shown.count == 1)
    }

    // MARK: - The knobs belong to the drawing

    @Test func aKnobAddedOnOneVersionLandsOnThatVersion() {
        var c = withComponent()
        let disabled = c.doc.addComponentVersion(componentID: c.componentID)!
        let second = c.doc.mainComponent(componentID: c.componentID, version: disabled)!
        let label = second.children[1].id
        let knob = c.doc.addComponentProperty(componentID: c.componentID, version: disabled,
                                              target: label, kind: .text)
        #expect(knob != nil)
        #expect(c.doc.componentProperties(of: c.componentID, version: disabled).count == 1)
        // ...and not on the version beside it: each drawing carries its own.
        #expect(c.doc.componentProperties(of: c.componentID).isEmpty)
    }

    @Test func aCopysPanelShowsTheKnobsOfTheVersionItIsShowing() {
        var c = withComponent()
        let disabled = c.doc.addComponentVersion(componentID: c.componentID)!
        let second = c.doc.mainComponent(componentID: c.componentID, version: disabled)!
        c.doc.addComponentProperty(componentID: c.componentID, version: disabled,
                                   target: second.children[1].id, kind: .text)
        let copy = c.doc.insertComponentInstance(of: c.componentID, at: CGPoint(x: 400, y: 300))!
        #expect(c.doc.componentKnobSelection(layerIDs: [copy]).properties.isEmpty)
        c.doc.setInstanceVersion(instance: copy, to: disabled)
        let panel = c.doc.componentKnobSelection(layerIDs: [copy])
        #expect(panel.properties.count == 1)
        #expect(panel.version == disabled)
        #expect(panel.versions.count == 2)
    }

    @Test func copiesShowingDifferentVersionsReadMixed() {
        var c = withComponent()
        let disabled = c.doc.addComponentVersion(componentID: c.componentID)!
        let one = c.doc.insertComponentInstance(of: c.componentID, at: CGPoint(x: 300, y: 300))!
        let two = c.doc.insertComponentInstance(of: c.componentID, at: CGPoint(x: 500, y: 300))!
        c.doc.setInstanceVersion(instance: one, to: disabled)
        let panel = c.doc.componentKnobSelection(layerIDs: [one, two])
        #expect(panel.hasVersions)
        #expect(panel.hasMixedVersions)
        #expect(panel.version == nil)
        // ...and setting the row puts every picked copy on one version.
        #expect(c.doc.setInstanceVersion(instances: [one, two], to: disabled) == 2)
        #expect(c.doc.componentKnobSelection(layerIDs: [one, two]).version == disabled)
    }

    // MARK: - Telling two drawings apart in the list

    @Test func aLayersRowPrintsTheVersionOnlyWhileThereAreSeveral() {
        var c = withComponent()
        func rowNames() -> [String?] {
            c.doc.layerRows(expanded: [], selected: []).map(\.versionName)
        }
        #expect(rowNames() == [nil])
        let disabled = c.doc.addComponentVersion(componentID: c.componentID)!
        c.doc.renameComponentVersion(componentID: c.componentID, version: disabled, to: "Disabled")
        #expect(Set(rowNames().compactMap { $0 }) == ["Default", "Disabled"])
        // ...and a component back down to one drawing is a component again.
        let second = c.doc.mainComponent(componentID: c.componentID, version: disabled)!
        c.doc.removeLayers(ids: [second.id])
        #expect(rowNames() == [nil])
    }

    // MARK: - Telling two drawings apart on the canvas

    @Test func theCanvasSaysNothingAboutVersionsUntilThereAreSeveral() {
        var c = withComponent()
        c.doc.insertComponentInstance(of: c.componentID, at: CGPoint(x: 300, y: 300))
        // One version is nothing to tell apart, so no drawing wears a version.
        #expect(c.doc.canvasVersionNames().isEmpty)
    }

    @Test func everyOriginalOnTheCanvasNamesItsVersion() {
        var c = withComponent()
        let disabled = c.doc.addComponentVersion(componentID: c.componentID)!
        c.doc.renameComponentVersion(componentID: c.componentID, version: disabled, to: "Disabled")
        let second = c.doc.mainComponent(componentID: c.componentID, version: disabled)!
        let names = c.doc.canvasVersionNames()
        // Two boxes side by side both called Button: the label says which.
        #expect(names[c.main] == "Default")
        #expect(names[second.id] == "Disabled")
    }

    @Test func aCopyShowingAnotherVersionSaysSoOnTheCanvas() {
        var c = withComponent()
        let disabled = c.doc.addComponentVersion(componentID: c.componentID)!
        c.doc.renameComponentVersion(componentID: c.componentID, version: disabled, to: "Disabled")
        let plain = c.doc.insertComponentInstance(of: c.componentID, at: CGPoint(x: 300, y: 300))!
        let odd = c.doc.insertComponentInstance(of: c.componentID, at: CGPoint(x: 500, y: 300))!
        c.doc.setInstanceVersion(instance: odd, to: disabled)
        let names = c.doc.canvasVersionNames()
        // The odd one out speaks and the ordinary one stays quiet, so a screen
        // built out of twelve plain buttons does not wear twelve labels.
        #expect(names[odd] == "Disabled")
        #expect(names[plain] == nil)
    }

    @Test func aCopyOfAComponentBackToOneVersionIsQuietAgain() {
        var c = withComponent()
        let disabled = c.doc.addComponentVersion(componentID: c.componentID)!
        let copy = c.doc.insertComponentInstance(of: c.componentID, at: CGPoint(x: 300, y: 300))!
        c.doc.setInstanceVersion(instance: copy, to: disabled)
        #expect(c.doc.canvasVersionNames()[copy] == "Version 2")
        let second = c.doc.mainComponent(componentID: c.componentID, version: disabled)!
        c.doc.removeLayers(ids: [second.id])
        #expect(c.doc.canvasVersionNames().isEmpty)
    }

    @Test func aCopyInsideAScreenSaysItsVersionToo() {
        var c = withComponent()
        let disabled = c.doc.addComponentVersion(componentID: c.componentID)!
        c.doc.renameComponentVersion(componentID: c.componentID, version: disabled, to: "Disabled")
        let copy = c.doc.insertComponentInstance(of: c.componentID, at: CGPoint(x: 300, y: 300))!
        c.doc.setInstanceVersion(instance: copy, to: disabled)
        let screen = c.doc.groupLayers(ids: [copy], name: "Home")!
        #expect(c.doc.parentID(of: copy) == screen.id)
        #expect(c.doc.canvasVersionNames()[copy] == "Disabled")
    }

    // MARK: - What a saved document holds

    @Test func aComponentWithOneVersionSavesExactlyAsItAlwaysDid() throws {
        let c = withComponent()
        let data = try JSONEncoder().encode(c.doc)
        let text = String(data: data, encoding: .utf8)!
        #expect(!text.contains("versionID"))
        #expect(!text.contains("versionName"))
        #expect(!text.contains("instanceVersion"))
    }

    @Test func aDocumentWithVersionsComesBackWithThem() throws {
        var c = withComponent()
        let disabled = c.doc.addComponentVersion(componentID: c.componentID)!
        c.doc.renameComponentVersion(componentID: c.componentID, version: disabled, to: "Disabled")
        let copy = c.doc.insertComponentInstance(of: c.componentID, at: CGPoint(x: 400, y: 300))!
        c.doc.setInstanceVersion(instance: copy, to: disabled)

        let data = try JSONEncoder().encode(c.doc)
        let back = try JSONDecoder().decode(PhotonzDocument.self, from: data)
        #expect(back.componentVersions(of: c.componentID).map(\.name) == ["Default", "Disabled"])
        #expect(back.instanceVersion(of: copy) == disabled)
    }
}

private extension Layer {
    /// What a text layer says, so a test can read one piece inside a copy.
    var words: String? {
        if case .text(let content) = content { return content.string }
        return nil
    }
}
