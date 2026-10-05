import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// A component's ORIGINAL lives in the document's component library, never in
/// the picture.
///
/// The user, 2026-10-04, after one drag of a Card put two Cards on the canvas:
/// "when i drag a component to the canvas, why are there 2 copies", and then
/// "how does 'always a copy' translate into 'copy AND original'". A drag puts
/// down one instance and nothing else, the way a library drag does in Figma;
/// the original is kept in the document (instances are filled from it, it is
/// saved, it is what Edit Original opens) but it is not one of the layers the
/// canvas draws, so the canvas, export, copy as image, hit testing and the
/// Layers list never meet it.
struct ComponentLibraryTests {

    private func document(_ size: CGFloat = 1200) -> PhotonzDocument {
        PhotonzDocument(canvasSize: CGSize(width: size, height: size), pixelScale: 1)
    }

    private func box(_ name: String, _ rect: CGRect, hex: String = "#336699") -> Layer {
        var layer = Layer(name: name,
                          content: .annotation(AnnotationContent(shape: .rectangle, start: .zero,
                                                                 end: CGPoint(x: rect.width, y: rect.height))),
                          frame: rect)
        layer.setColorHex(hex, for: .fill)
        return layer
    }

    /// A group "Button" of a box and a label at 100,100, made a component.
    private func withMadeComponent() -> (doc: PhotonzDocument, group: UUID, componentID: UUID, boxID: UUID) {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 800, height: 600),
                                  layers: [box("Box", CGRect(x: 100, y: 100, width: 120, height: 40)),
                                           Layer(name: "Label", content: .text(TextContent(string: "Save")),
                                                 frame: CGRect(x: 110, y: 108, width: 60, height: 20))])
        let ids = Set(doc.layers.map(\.id))
        let boxID = doc.layers[0].id
        guard let group = doc.groupLayers(ids: ids, name: "Button"),
              let componentID = doc.makeComponent(id: group.id)
        else { preconditionFailure("could not make the component") }
        return (doc, group.id, componentID, boxID)
    }

    private let drop = CGPoint(x: 300, y: 300)

    // MARK: - A drop puts down one thing

    @Test func aStarterDropPutsDownOneInstanceAndNothingElse() {
        var doc = document()
        let before = doc.layers.count
        guard let placed = doc.insertStarterComponent(.card, at: drop) else {
            Issue.record("nothing placed"); return
        }
        #expect(doc.layers.count == before + 1)
        #expect(doc.layer(id: placed)?.isComponentInstance == true)
        #expect(!doc.allLayers.contains { $0.isMainComponent })
        #expect(doc.componentOriginals.count == 1)
        #expect(doc.mainComponent(componentID: StarterComponent.card.componentID) != nil)
        // ...and the instance is filled from the original it cannot see.
        #expect(doc.layer(id: placed)?.children.isEmpty == false)
    }

    @Test func everyLaterDropIsOneMoreInstanceAndStillOneOriginal() {
        var doc = document()
        doc.insertStarterComponent(.card, at: drop)
        let before = doc.layers.count
        doc.insertStarterComponent(.card, at: CGPoint(x: 800, y: 800))
        #expect(doc.layers.count == before + 1)
        #expect(doc.componentOriginals.count == 1)
        #expect(doc.instanceCount(of: StarterComponent.card.componentID) == 2)
    }

    @Test func theStarterStillBringsItsStylesAndProperties() {
        var doc = document()
        doc.insertStarterComponent(.card, at: drop)
        #expect(doc.componentProperties(of: StarterComponent.card.componentID).map(\.name)
                == ["Title", "Body", "Picture"])
        let wanted = StarterComponent.card.usedStyles.map(\.name)
        #expect(wanted.allSatisfy { name in doc.colorStyles.contains { $0.name == name } })
    }

    @Test func aSharedComponentDropPutsDownOneInstanceAndKeepsEveryVersionInTheLibrary() {
        var source = withMadeComponent().doc
        let componentID = source.mainComponents[0].componentID ?? UUID()
        source.addComponentVersion(componentID: componentID)
        guard let shared = source.shareComponent(componentID: componentID) else {
            Issue.record("could not share"); return
        }
        var doc = document()
        let before = doc.layers.count
        guard let placed = doc.adoptSharedComponent(shared, at: drop) else {
            Issue.record("nothing placed"); return
        }
        #expect(doc.layers.count == before + 1)
        #expect(doc.layer(id: placed)?.isComponentInstance == true)
        #expect(!doc.allLayers.contains { $0.isMainComponent })
        #expect(doc.componentVersions(of: componentID).count == 2)
    }

    // MARK: - Make Component leaves an instance where the group was

    @Test func parkingAnOriginalLeavesAnInstanceThatDrawsTheSameInTheSamePlace() {
        var c = withMadeComponent()
        let boundsBefore = c.doc.canvasBounds(of: c.group)
        let moved = c.doc.parkOriginals()
        guard let standIn = moved[c.group] else { Issue.record("nothing parked"); return }
        #expect(c.doc.layer(id: standIn)?.instanceOf == c.componentID)
        #expect(c.doc.canvasBounds(of: standIn) == boundsBefore)
        #expect(!c.doc.allLayers.contains { $0.isMainComponent })
        // The original keeps its id, so every knob aimed at it still reaches it.
        #expect(c.doc.componentOriginals.map(\.id) == [c.group])
        #expect(c.doc.mainComponent(componentID: c.componentID)?.id == c.group)
        #expect(c.doc.layer(id: c.group)?.isMainComponent == true)
    }

    @Test func parkingAgainChangesNothing() {
        var c = withMadeComponent()
        c.doc.parkOriginals()
        let once = c.doc
        #expect(c.doc.parkOriginals().isEmpty)
        #expect(c.doc == once)
    }

    @Test func aMainInsideAScreenIsParkedAndItsInstanceStaysInTheScreen() {
        var c = withMadeComponent()
        guard let screen = c.doc.groupLayers(ids: [c.group], name: "Screen") else {
            Issue.record("no screen"); return
        }
        guard let standIn = c.doc.parkOriginals()[c.group] else { Issue.record("nothing parked"); return }
        #expect(c.doc.parentID(of: standIn) == screen.id)
        #expect(c.doc.layer(id: standIn)?.isComponentInstance == true)
        #expect(c.doc.componentOriginals.count == 1)
    }

    // MARK: - The original is still the source

    @Test func editingTheOriginalInTheLibraryReachesEveryInstance() {
        var c = withMadeComponent()
        c.doc.parkOriginals()
        c.doc.insertComponentInstance(of: c.componentID, at: CGPoint(x: 500, y: 400))
        c.doc.updateLayer(id: c.boxID) { $0.setColorHex("#FF0000", for: .fill) }
        c.doc.syncComponentInstances()
        let instances = c.doc.instances(of: c.componentID)
        #expect(instances.count == 2)
        for instance in instances {
            let inner = instance.children.first { $0.name == "Box" }
            #expect(inner?.colorHex(for: .fill) == "#FF0000")
        }
    }

    @Test func renamingAComponentRenamesTheOriginalInTheLibrary() {
        var c = withMadeComponent()
        c.doc.parkOriginals()
        c.doc.renameComponent(componentID: c.componentID, to: "Primary")
        #expect(c.doc.mainComponent(componentID: c.componentID)?.name == "Primary")
    }

    /// The thing you just made a component of is an instance now, so naming
    /// the component names it too; a copy somebody renamed by hand keeps its
    /// own name.
    @Test func renamingAComponentRenamesTheCopiesStillWearingItsName() {
        var c = withMadeComponent()
        let standIn = c.doc.parkOriginals()[c.group] ?? UUID()
        guard let other = c.doc.insertComponentInstance(of: c.componentID, at: CGPoint(x: 500, y: 400)),
              let mine = c.doc.insertComponentInstance(of: c.componentID, at: CGPoint(x: 600, y: 500))
        else { Issue.record("no copies"); return }
        c.doc.updateLayer(id: mine) { $0.name = "Hero button" }
        c.doc.renameComponent(componentID: c.componentID, to: "Primary")
        #expect(c.doc.layer(id: standIn)?.name == "Primary")
        #expect(c.doc.layer(id: other)?.name == "Primary")
        #expect(c.doc.layer(id: mine)?.name == "Hero button")
    }

    @Test func aColorStyleChangeReachesTheOriginalAndItsInstances() {
        var c = withMadeComponent()
        let styleID = c.doc.addColorStyle(name: "Brand", colorHex: "#336699")
        _ = c.doc.bindColorStyle(layerID: c.boxID, slot: .fill, styleID: styleID)
        c.doc.parkOriginals()
        c.doc.syncComponentInstances()
        c.doc.setColorStyleHex(styleID: styleID, hex: "#00AA00")
        c.doc.syncComponentInstances()
        #expect(c.doc.layer(id: c.boxID)?.colorHex(for: .fill) == "#00AA00")
        let inner = c.doc.instances(of: c.componentID).first?.children.first { $0.name == "Box" }
        #expect(inner?.colorHex(for: .fill) == "#00AA00")
    }

    // MARK: - Saving and opening

    @Test func theLibrarySurvivesARoundTrip() throws {
        var doc = document()
        doc.insertStarterComponent(.button, at: drop)
        let data = try JSONEncoder().encode(doc)
        let back = try JSONDecoder().decode(PhotonzDocument.self, from: data)
        #expect(back.componentOriginals == doc.componentOriginals)
        #expect(back == doc)
    }

    @Test func aDocumentSavedWithAnOriginalOnTheCanvasOpensWithAnInstanceInItsPlace() {
        let c = withMadeComponent()
        let bounds = c.doc.canvasBounds(of: c.group)
        let history = History(document: c.doc)
        let opened = history.current
        guard let standIn = opened.instances(of: c.componentID).first else {
            Issue.record("no instance"); return
        }
        #expect(opened.canvasBounds(of: standIn.id) == bounds)
        #expect(opened.componentOriginals.map(\.id) == [c.group])
        #expect(!opened.allLayers.contains { $0.isMainComponent })
    }

    @Test func everyEditParksAnOriginalThatLandsOnTheCanvas() {
        let c = withMadeComponent()
        var history = History(document: PhotonzDocument(canvasSize: c.doc.canvasSize, layers: []))
        let layers = c.doc.layers
        history.perform { $0.layers = layers }
        #expect(!history.current.allLayers.contains { $0.isMainComponent })
        #expect(history.current.componentOriginals.count == 1)
    }

    @Test func anEditingSpaceHistoryLeavesTheOriginalWhereItIs() {
        let c = withMadeComponent()
        let history = History(document: c.doc, parksOriginals: false)
        #expect(history.current.layer(id: c.group)?.isMainComponent == true)
        #expect(history.current.layers.contains { $0.id == c.group })
        #expect(history.current.componentOriginals.isEmpty)
    }

    // MARK: - Edit Original: a space of its own

    @Test func theEditingSpaceHoldsOnlyThatComponentsDrawings() {
        var c = withMadeComponent()
        c.doc.parkOriginals()
        c.doc.insertStarterComponent(.button, at: CGPoint(x: 600, y: 500))
        guard let space = c.doc.editingSpace(forComponent: c.componentID) else {
            Issue.record("no space"); return
        }
        let originalID = c.group
        #expect(space.layers.map(\.id) == [originalID])
        #expect(space.componentOriginals.count == 1)
        // The drawing sits inside the space with room round it.
        guard let bounds = space.canvasBounds(of: originalID) else { Issue.record("no bounds"); return }
        #expect(bounds.minX > 0 && bounds.minY > 0)
        #expect(bounds.maxX < space.canvasSize.width && bounds.maxY < space.canvasSize.height)
        #expect(space.tracks.isEmpty)
        // A page the document's size, so a second version has room beside it.
        #expect(space.canvasSize.width >= c.doc.canvasSize.width)
        #expect(space.canvasSize.height >= c.doc.canvasSize.height)
    }

    /// A component you just made opens where the group stood, so nothing
    /// jumps; a starter, held at the library's origin, opens in the middle.
    @Test func aMadeComponentOpensWhereItStoodAndAStarterInTheMiddle() {
        var c = withMadeComponent()
        let stood = c.doc.canvasBounds(of: c.group)
        c.doc.parkOriginals()
        let space = c.doc.editingSpace(forComponent: c.componentID)
        #expect(space?.canvasBounds(of: c.group) == stood)

        var doc = document(1000)
        doc.insertStarterComponent(.button, at: drop)
        guard let starterSpace = doc.editingSpace(forComponent: StarterComponent.button.componentID),
              let id = starterSpace.layers.first?.id,
              let box = starterSpace.canvasBounds(of: id)
        else { Issue.record("no starter space"); return }
        #expect(abs(box.midX - 500) <= 1)
        #expect(abs(box.midY - 500) <= 1)
    }

    @Test func comingBackFromTheSpaceWritesTheEditAndEveryInstanceFollows() {
        var c = withMadeComponent()
        c.doc.parkOriginals()
        c.doc.insertComponentInstance(of: c.componentID, at: CGPoint(x: 500, y: 400))
        guard var space = c.doc.editingSpace(forComponent: c.componentID) else {
            Issue.record("no space"); return
        }
        space.updateLayer(id: c.boxID) { $0.setColorHex("#FF0000", for: .fill) }
        c.doc.returnFromEditingSpace(space, componentID: c.componentID)
        c.doc.syncComponentInstances()
        #expect(c.doc.layer(id: c.boxID)?.colorHex(for: .fill) == "#FF0000")
        #expect(c.doc.componentOriginals.count == 1)
        for instance in c.doc.instances(of: c.componentID) {
            let inner = instance.children.first { $0.name == "Box" }
            #expect(inner?.colorHex(for: .fill) == "#FF0000")
        }
    }

    @Test func somethingDrawnLooseInTheSpaceJoinsTheOriginal() {
        var c = withMadeComponent()
        c.doc.parkOriginals()
        guard var space = c.doc.editingSpace(forComponent: c.componentID),
              let mainBox = space.canvasBounds(of: c.group) else {
            Issue.record("no space"); return
        }
        let loose = box("Badge", CGRect(x: mainBox.maxX + 10, y: mainBox.minY, width: 20, height: 20))
        space.addLayer(loose)
        c.doc.returnFromEditingSpace(space, componentID: c.componentID)
        let main = c.doc.mainComponent(componentID: c.componentID)
        #expect(main?.children.contains { $0.id == loose.id } == true)
        #expect(!c.doc.layers.contains { $0.id == loose.id })
    }

    @Test func emptyingTheSpaceDoesNotDeleteTheComponent() {
        var c = withMadeComponent()
        c.doc.parkOriginals()
        guard var space = c.doc.editingSpace(forComponent: c.componentID) else {
            Issue.record("no space"); return
        }
        space.removeLayer(id: c.group)
        let before = c.doc.componentOriginals
        c.doc.returnFromEditingSpace(space, componentID: c.componentID)
        #expect(c.doc.componentOriginals == before)
    }

    @Test func aStyleRecolouredInTheSpaceRecoloursTheCanvasToo() {
        var c = withMadeComponent()
        let styleID = c.doc.addColorStyle(name: "Brand", colorHex: "#336699")
        let loose = box("Loose", CGRect(x: 400, y: 400, width: 50, height: 50))
        c.doc.addLayer(loose)
        _ = c.doc.bindColorStyle(layerID: loose.id, slot: .fill, styleID: styleID)
        c.doc.parkOriginals()
        guard var space = c.doc.editingSpace(forComponent: c.componentID) else {
            Issue.record("no space"); return
        }
        space.setColorStyleHex(styleID: styleID, hex: "#00AA00")
        c.doc.returnFromEditingSpace(space, componentID: c.componentID)
        #expect(c.doc.layer(id: loose.id)?.colorHex(for: .fill) == "#00AA00")
        #expect(c.doc.colorStyle(id: styleID)?.colorHex == "#00AA00")
    }
}
