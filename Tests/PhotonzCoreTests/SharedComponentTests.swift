import Foundation
import CoreGraphics
import Testing
@testable import PhotonzCore

/// A component put on the shared shelf is there in every document, and the
/// copies in every document follow it (the decision "One shelf the whole app
/// shares", resolved 2026-09-09).
///
/// The shelf holds the drawing; a document holds its own original of it,
/// marked as following the shelf. Editing that original anywhere publishes it,
/// and every other document takes it on the next look. A document whose shared
/// original has gone keeps its drawing and says the link broke.
struct SharedComponentTests {

    // MARK: - A document with a component in it

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

    /// An empty second document, the file you start tomorrow.
    private func blankDocument() -> PhotonzDocument {
        PhotonzDocument(canvasSize: CGSize(width: 800, height: 600), layers: [])
    }

    // MARK: - Putting one on the shelf

    @Test func aComponentIsNotSharedUntilYouSaySo() {
        let c = withComponent()
        #expect(c.doc.layer(id: c.main)?.isSharedComponent == false)
        #expect(c.doc.sharedComponentIDs.isEmpty)
    }

    @Test func sharingMarksTheOriginalAndHandsBackItsDrawing() {
        var c = withComponent()
        let shared = c.doc.shareComponent(componentID: c.componentID)
        #expect(shared?.id == c.componentID)
        #expect(shared?.name == "Button")
        #expect(c.doc.layer(id: c.main)?.isSharedComponent == true)
        #expect(c.doc.sharedComponentIDs == [c.componentID])
        // The drawing travels with its corner at zero: where it sits is each
        // document's own business.
        #expect(shared?.drawings.count == 1)
        #expect(shared?.drawings.first?.frame.origin == .zero)
        #expect(shared?.drawings.first?.children.map(\.name) == ["Box", "Label"])
    }

    @Test func sharingCarriesEveryVersionOfIt() {
        var c = withComponent()
        c.doc.addComponentVersion(componentID: c.componentID)
        let shared = c.doc.shareComponent(componentID: c.componentID)
        #expect(shared?.drawings.count == 2)
        // ...and both of its originals are marked, so editing either publishes.
        #expect(c.doc.mainComponents.filter(\.isSharedComponent).count == 2)
    }

    @Test func takingItOffTheShelfLeavesTheDrawingWhereItIs() {
        var c = withComponent()
        c.doc.shareComponent(componentID: c.componentID)
        c.doc.unshareComponent(componentID: c.componentID)
        #expect(c.doc.layer(id: c.main)?.isSharedComponent == false)
        #expect(c.doc.sharedComponentIDs.isEmpty)
        // The component is still here and still has its pieces.
        #expect(c.doc.layer(id: c.main)?.children.count == 2)
    }

    // MARK: - The shelf itself

    @Test func theShelfListsWhatIsOnIt() {
        var c = withComponent()
        var shelf = SharedComponentShelf()
        shelf.put(c.doc.shareComponent(componentID: c.componentID)!)
        #expect(shelf.components.count == 1)
        #expect(shelf.component(id: c.componentID)?.name == "Button")
        let entry = shelf.entries.first
        #expect(entry?.id == c.componentID.uuidString)
        #expect(entry?.scope == .components)
        #expect(entry?.name == "Button")
        #expect(entry?.detail == SharedComponentShelf.shelfDetail)
    }

    @Test func puttingTheSameComponentBackReplacesItInPlace() {
        var c = withComponent()
        var shelf = SharedComponentShelf()
        shelf.put(c.doc.shareComponent(componentID: c.componentID)!)
        c.doc.renameComponent(componentID: c.componentID, to: "Primary Button")
        shelf.put(c.doc.sharedComponent(componentID: c.componentID)!)
        #expect(shelf.components.count == 1)
        #expect(shelf.component(id: c.componentID)?.name == "Primary Button")
    }

    @Test func theShelfSurvivesBeingWrittenDownAndReadBack() throws {
        var c = withComponent()
        var shelf = SharedComponentShelf()
        shelf.put(c.doc.shareComponent(componentID: c.componentID)!)
        let data = try JSONEncoder().encode(shelf)
        let read = try JSONDecoder().decode(SharedComponentShelf.self, from: data)
        #expect(read == shelf)
    }

    @Test func aSharedComponentSavesAndOpensStillFollowing() throws {
        var c = withComponent()
        c.doc.shareComponent(componentID: c.componentID)
        let data = try JSONEncoder().encode(c.doc.layers)
        let read = try JSONDecoder().decode([Layer].self, from: data)
        let main = read.first { $0.componentID == c.componentID }
        #expect(main?.isSharedComponent == true)
    }

    @Test func aComponentNobodySharedWritesNothingExtra() throws {
        let c = withComponent()
        let data = try JSONEncoder().encode(c.doc.layers)
        let text = String(decoding: data, as: UTF8.self)
        // A document saved before the shelf existed is byte for byte what it
        // was: the key is only written by a component somebody shared.
        #expect(!text.contains("\"shared\""))
    }

    // MARK: - Using it in another document

    @Test func aSharedComponentDropsIntoADifferentDocument() {
        var c = withComponent()
        let shared = c.doc.shareComponent(componentID: c.componentID)!

        var other = blankDocument()
        let placed = other.adoptSharedComponent(shared, at: CGPoint(x: 400, y: 300))
        #expect(placed != nil)
        let main = other.mainComponent(componentID: c.componentID)
        #expect(main?.id == placed)
        #expect(main?.name == "Button")
        #expect(main?.children.map(\.name) == ["Box", "Label"])
        // It arrives following the shelf, so the next edit anywhere reaches it.
        #expect(main?.isSharedComponent == true)
        // ...centred on where it was let go.
        let box = other.canvasBounds(of: placed!)
        #expect(box?.midX == 400)
        #expect(box?.midY == 300)
    }

    @Test func aSecondDropPlacesACopyRatherThanASecondOriginal() {
        var c = withComponent()
        let shared = c.doc.shareComponent(componentID: c.componentID)!
        var other = blankDocument()
        other.adoptSharedComponent(shared, at: CGPoint(x: 400, y: 300))
        let second = other.adoptSharedComponent(shared, at: CGPoint(x: 400, y: 450))
        #expect(other.mainComponents.count == 1)
        #expect(other.layer(id: second!)?.instanceOf == c.componentID)
    }

    @Test func everyVersionComesAcrossWithIt() {
        var c = withComponent()
        c.doc.addComponentVersion(componentID: c.componentID, name: "Disabled")
        let shared = c.doc.shareComponent(componentID: c.componentID)!
        var other = blankDocument()
        other.adoptSharedComponent(shared, at: CGPoint(x: 400, y: 300))
        #expect(other.componentVersions(of: c.componentID).map(\.name) == ["Default", "Disabled"])
        // The second drawing lands loose beside the first rather than on it.
        let mains = other.mainComponents
        #expect(mains.count == 2)
        #expect(other.parentID(of: mains[1].id) == nil)
        #expect(!mains[0].frame.intersects(mains[1].frame))
    }

    // MARK: - Following an edit

    /// Document A shares a button, document B uses it, A edits it: B follows.
    private func twoDocuments() -> (a: PhotonzDocument, b: PhotonzDocument,
                                    shelf: SharedComponentShelf, componentID: UUID,
                                    aMain: UUID, bMain: UUID, bCopy: UUID) {
        var c = withComponent()
        var shelf = SharedComponentShelf()
        shelf.put(c.doc.shareComponent(componentID: c.componentID)!)
        var b = blankDocument()
        let bMain = b.adoptSharedComponent(shelf.component(id: c.componentID)!,
                                           at: CGPoint(x: 400, y: 200))!
        let copy = b.insertComponentInstance(of: c.componentID, at: CGPoint(x: 400, y: 400))!
        b.syncComponentInstances()
        return (c.doc, b, shelf, c.componentID, c.main, bMain, copy)
    }

    @Test func editingTheSharedOriginalReachesAnotherOpenDocument() {
        var t = twoDocuments()
        // A widens the button and publishes what it now looks like.
        t.a.updateLayer(id: t.a.layer(id: t.aMain)!.children[0].id) { layer in
            layer.frame.size.width = 200
        }
        t.shelf.put(t.a.sharedComponent(componentID: t.componentID)!)

        let report = t.b.syncSharedComponents(from: t.shelf)
        #expect(report.updatedComponents == 1)
        #expect(report.missing.isEmpty)
        #expect(t.b.layer(id: t.bMain)?.children[0].frame.width == 200)
        // ...and the copy in B follows its original the way it always has.
        t.b.syncComponentInstances()
        #expect(t.b.layer(id: t.bCopy)?.children[0].frame.width == 200)
    }

    @Test func aDocumentOpenedLaterComesUpAlreadyFollowingIt() {
        var t = twoDocuments()
        // B is saved and put away as it is.
        let saved = t.b
        // A edits the button while B is closed.
        t.a.updateLayer(id: t.a.layer(id: t.aMain)!.children[1].id) { layer in
            layer.content = .text(TextContent(string: "Done"))
        }
        t.shelf.put(t.a.sharedComponent(componentID: t.componentID)!)
        // Opening B runs the same sync, so it comes up with the newer drawing.
        var reopened = saved
        let report = reopened.syncSharedComponents(from: t.shelf)
        #expect(report.updatedComponents == 1)
        if case .text(let content) = reopened.layer(id: t.bMain)!.children[1].content {
            #expect(content.string == "Done")
        } else {
            Issue.record("the label should still be text")
        }
    }

    @Test func whereTheCopyOfTheOriginalSitsIsEachDocumentsOwnBusiness() {
        var t = twoDocuments()
        let before = t.b.layer(id: t.bMain)!.frame.origin
        t.a.updateLayer(id: t.aMain) { $0.frame.origin = CGPoint(x: 500, y: 500) }
        t.shelf.put(t.a.sharedComponent(componentID: t.componentID)!)
        t.b.syncSharedComponents(from: t.shelf)
        #expect(t.b.layer(id: t.bMain)?.frame.origin == before)
    }

    @Test func aSyncThatChangesNothingSaysSo() {
        var t = twoDocuments()
        let report = t.b.syncSharedComponents(from: t.shelf)
        #expect(report.isEmpty)
        #expect(report.updatedComponents == 0)
    }

    // MARK: - When the original is gone

    @Test func aDocumentWhoseSharedOriginalIsGoneKeepsItsDrawing() {
        var t = twoDocuments()
        t.shelf.remove(id: t.componentID)
        let report = t.b.syncSharedComponents(from: t.shelf)
        #expect(report.missing == ["Button"])
        // Nothing is lost: the component and its copy draw exactly as before.
        #expect(t.b.layer(id: t.bMain)?.children.map(\.name) == ["Box", "Label"])
        #expect(t.b.layer(id: t.bCopy)?.children.count == 2)
        // ...and it says the link broke, in the same words every other break
        // uses.
        #expect(report.linkBreaks.detail == "1 component no longer follows the shared shelf")
    }

    @Test func aBreakIsSaidOncePerComponentNotOncePerCopy() {
        var t = twoDocuments()
        t.b.insertComponentInstance(of: t.componentID, at: CGPoint(x: 600, y: 400))
        t.shelf.remove(id: t.componentID)
        let report = t.b.syncSharedComponents(from: t.shelf)
        #expect(report.missing.count == 1)
    }

    @Test func aComponentNobodySharedIsNeverReportedMissing() {
        var c = withComponent()
        let report = c.doc.syncSharedComponents(from: SharedComponentShelf())
        #expect(report.isEmpty)
        #expect(report.missing.isEmpty)
    }

    // MARK: - The colors it paints from

    @Test func theNamedColorsTravelWithIt() {
        var c = withComponent()
        let styleID = c.doc.addColorStyle(name: "Accent", colorHex: "#3B7DF5")
        c.doc.bindColorStyle(layerID: c.boxID, slot: .fill, styleID: styleID)
        let shared = c.doc.shareComponent(componentID: c.componentID)!
        #expect(shared.colorStyles.map(\.name) == ["Accent"])

        var other = blankDocument()
        other.adoptSharedComponent(shared, at: CGPoint(x: 400, y: 300))
        #expect(other.colorStyles.map(\.name) == ["Accent"])
        // ...and the piece inside is still wearing the name, so recoloring
        // Accent in this document repaints it.
        let main = other.mainComponent(componentID: c.componentID)!
        #expect(main.children[0].colorStyleBindings?.first?.styleID == styleID)
    }

    @Test func adocumentThatAlreadyHasThatColorKeepsItsOwn() {
        var c = withComponent()
        let styleID = c.doc.addColorStyle(name: "Accent", colorHex: "#3B7DF5")
        c.doc.bindColorStyle(layerID: c.boxID, slot: .fill, styleID: styleID)
        let shared = c.doc.shareComponent(componentID: c.componentID)!

        // The other document has the same style, painted its own way.
        var other = blankDocument()
        other.colorStyles = [ColorStyle(id: styleID, name: "Accent", colorHex: "#FF2D55",
                                        roles: [.surface])]
        other.adoptSharedComponent(shared, at: CGPoint(x: 400, y: 300))
        #expect(other.colorStyles.count == 1)
        #expect(other.colorStyle(id: styleID)?.colorHex == "#FF2D55")
        // The button arrives painted in THIS document's Accent, so the name it
        // is wearing is true of the color it is wearing.
        let main = other.mainComponent(componentID: c.componentID)!
        #expect(main.children[0].paint(for: .fill)?.hex.uppercased() == "#FF2D55")
        #expect(other.reconcileColorStyles() == 0)
    }

    // MARK: - The starters keep working exactly as they did

    @Test func aStarterIsNotASharedComponent() {
        var doc = blankDocument()
        let placed = doc.insertStarterComponent(.button, at: CGPoint(x: 200, y: 200))
        #expect(placed != nil)
        #expect(doc.layer(id: placed!)?.isSharedComponent == false)
        #expect(doc.sharedComponentIDs.isEmpty)
        // ...so a shelf sync leaves it alone entirely.
        let report = doc.syncSharedComponents(from: SharedComponentShelf())
        #expect(report.isEmpty)
        #expect(doc.starterComponentEntries.count == StarterComponent.allCases.count - 1)
    }

    @Test func aStarterCanBePutOnTheSharedShelfLikeAnythingElse() {
        var doc = blankDocument()
        let placed = doc.insertStarterComponent(.button, at: CGPoint(x: 200, y: 200))!
        let componentID = doc.layer(id: placed)!.componentID!
        let shared = doc.shareComponent(componentID: componentID)
        #expect(shared != nil)
        // It is the same component it always was, so the app's shelf still
        // knows it and there is no second mechanism.
        #expect(StarterComponent(componentID: componentID) == .button)
        #expect(shared?.colorStyles.map(\.name).sorted() == ["Accent", "Surface"])
    }

    @Test func theShelfDoesNotOfferWhatTheDocumentAlreadyHas() {
        var c = withComponent()
        var shelf = SharedComponentShelf()
        shelf.put(c.doc.shareComponent(componentID: c.componentID)!)
        // The document that shared it lists it once, as its own.
        #expect(shelf.entries(notIn: c.doc).isEmpty)
        #expect(c.doc.componentLibraryEntries.count == 1)
        // A document that has never seen it is offered it.
        #expect(shelf.entries(notIn: blankDocument()).count == 1)
    }
}
