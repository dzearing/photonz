import Foundation
import CoreGraphics
import Testing
@testable import PhotonzCore

/// Two loose ends of a component asking two questions, Variant and Size
/// (`ComponentVariantProperty`):
///
/// * a copy set to a combination nobody drew shows the nearest drawing, and
///   the moment somebody draws that combination it shows the real one, with
///   nobody picking it again;
/// * a question after the first can be taken away again, and copies fall back
///   to the drawing that gives the answers they still have.
struct ComponentVariantFollowTests {

    private func box(_ name: String, _ rect: CGRect) -> Layer {
        Layer(name: name, content: .annotation(AnnotationContent(shape: .rectangle,
                                                                 start: .zero,
                                                                 end: CGPoint(x: rect.width, y: rect.height))),
              frame: rect)
    }

    /// A Button with Primary and Secondary, and a Size question added from
    /// Primary whose new drawing is called Large: Primary · Default,
    /// Secondary · Default and Primary · Large. Nobody drew Secondary · Large.
    private func buttonWithSize()
        -> (doc: PhotonzDocument, componentID: UUID, size: UUID,
            primary: UUID, secondary: UUID, primaryLarge: UUID) {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 800, height: 600),
                                  layers: [box("Box", CGRect(x: 10, y: 10, width: 120, height: 40))])
        let main = doc.groupLayers(ids: [doc.layers[0].id], name: "Button")!
        let componentID = doc.makeComponent(id: main.id)!
        let secondary = doc.addComponentVersion(componentID: componentID)!
        let primary = doc.componentVersions(of: componentID)[0].id
        doc.renameComponentVersion(componentID: componentID, version: primary, to: "Primary")
        doc.renameComponentVersion(componentID: componentID, version: secondary, to: "Secondary")
        let added = doc.addComponentVariantProperty(componentID: componentID, from: primary)!
        let large = doc.componentVersion(of: componentID, id: added.version)!
        _ = doc.setComponentVariantOption(componentID: componentID, drawing: large.layerID,
                                          property: added.property, to: "Large")
        return (doc, componentID, added.property, primary, secondary, added.version)
    }

    /// Draws Secondary · Large: another Size from Secondary, called Large.
    private func drawSecondaryLarge(_ doc: inout PhotonzDocument, _ componentID: UUID,
                                    size: UUID, secondary: UUID) -> UUID {
        let added = doc.addComponentVariantOption(componentID: componentID, property: size,
                                                  from: secondary)!
        let drawing = doc.componentVersion(of: componentID, id: added)!
        _ = doc.setComponentVariantOption(componentID: componentID, drawing: drawing.layerID,
                                          property: size, to: "Large")
        return added
    }

    // MARK: - A copy follows its look once that look is drawn

    /// The stand-in goes the moment the real drawing exists: the next sync
    /// puts the copy on Secondary · Large and forgets the combination it was
    /// holding on to, because there is nothing left to remember.
    @Test func aCopyFollowsItsLookOnceThatLookIsDrawn() {
        var b = buttonWithSize()
        let copy = b.doc.insertComponentInstance(of: b.componentID, at: CGPoint(x: 400, y: 300),
                                                 version: b.secondary)!
        _ = b.doc.setInstanceVariantAnswer(instances: [copy], property: b.size, option: "Large")
        #expect(b.doc.instanceVersion(of: copy) == b.primaryLarge)

        let secondaryLarge = drawSecondaryLarge(&b.doc, b.componentID, size: b.size,
                                                secondary: b.secondary)
        b.doc.syncComponentInstances()
        #expect(b.doc.instanceVersion(of: copy) == secondaryLarge)
        #expect(b.doc.layer(id: copy)?.group?.instanceAnswers.isEmpty == true)
        #expect(b.doc.instanceVariantAnswers(of: copy) == [b.componentID: "Secondary", b.size: "Large"])
    }

    /// The real flow: the combination is drawn on the Edit Original page and
    /// Done writes it back, and the copy in the document takes it.
    @Test func drawingTheLookInEditOriginalReachesTheCopyOnDone() throws {
        var b = buttonWithSize()
        b.doc.parkOriginals()
        let copy = b.doc.insertComponentInstance(of: b.componentID, at: CGPoint(x: 400, y: 300),
                                                 version: b.secondary)!
        _ = b.doc.setInstanceVariantAnswer(instances: [copy], property: b.size, option: "Large")
        var history = History(document: b.doc)
        #expect(history.current.instanceVersion(of: copy) == b.primaryLarge)

        var space = try #require(b.doc.editingSpace(forComponent: b.componentID))
        let secondaryLarge = drawSecondaryLarge(&space, b.componentID, size: b.size,
                                                secondary: b.secondary)
        history.perform { $0.returnFromEditingSpace(space, componentID: b.componentID) }
        #expect(history.current.instanceVersion(of: copy) == secondaryLarge)
        // ...in the one step Done is, so undo puts the stand-in back.
        history.undo()
        #expect(history.current.instanceVersion(of: copy) == b.primaryLarge)
    }

    /// A copy whose combination is still not drawn keeps its stand-in and the
    /// combination it asked for.
    @Test func aCopyOnAnUndrawnLookKeepsWaiting() {
        var b = buttonWithSize()
        let copy = b.doc.insertComponentInstance(of: b.componentID, at: CGPoint(x: 400, y: 300),
                                                 version: b.secondary)!
        _ = b.doc.setInstanceVariantAnswer(instances: [copy], property: b.size, option: "Large")
        b.doc.syncComponentInstances()
        #expect(b.doc.instanceVersion(of: copy) == b.primaryLarge)
        #expect(b.doc.layer(id: copy)?.group?.instanceAnswers.isEmpty == false)
    }

    // MARK: - Taking a second question away

    /// Size goes: no drawing answers it any more, the drawings that only
    /// differed by it fold into the one giving its first answer, and the
    /// component asks Variant alone again.
    @Test func aSecondQuestionCanBeTakenAway() {
        var b = buttonWithSize()
        let gone = b.doc.removeComponentVariantProperty(componentID: b.componentID, property: b.size)
        #expect(gone != nil)
        let properties = b.doc.componentVariantProperties(of: b.componentID)
        #expect(properties.map(\.name) == ["Variant"])
        #expect(properties[0].options.map(\.name) == ["Primary", "Secondary"])
        #expect(b.doc.componentVersions(of: b.componentID).map(\.id) == [b.primary, b.secondary])
        #expect(b.doc.componentVersions(of: b.componentID).map(\.name) == ["Primary", "Secondary"])
        for main in b.doc.mainComponents where main.componentID == b.componentID {
            #expect(main.group?.variantAnswers.isEmpty == true)
        }
        // It says which drawing each one that went folded into.
        let large = b.doc.layer(id: b.primaryLarge)
        #expect(large == nil)
        #expect(gone?.values.contains { $0 == b.doc.componentVersions(of: b.componentID)[0].layerID } == true)
    }

    /// The first question is not one of the ones that can be taken away:
    /// it is the component's own looks.
    @Test func theFirstQuestionStays() {
        var b = buttonWithSize()
        #expect(b.doc.removeComponentVariantProperty(componentID: b.componentID,
                                                     property: b.componentID) == nil)
        #expect(b.doc.removeComponentVariantProperty(componentID: b.componentID,
                                                     property: UUID()) == nil)
        #expect(b.doc.componentVariantProperties(of: b.componentID).count == 2)
    }

    /// A drawing nobody drew a Default for is kept as the drawing for its
    /// other answers rather than lost: Secondary exists only as Large here.
    @Test func aDrawingThatIsTheOnlyOneForItsAnswersIsKept() {
        var b = buttonWithSize()
        let secondaryLarge = drawSecondaryLarge(&b.doc, b.componentID, size: b.size,
                                                secondary: b.secondary)
        let secondary = b.doc.componentVersion(of: b.componentID, id: b.secondary)!
        b.doc.removeLayers(ids: [secondary.layerID])
        _ = b.doc.removeComponentVariantProperty(componentID: b.componentID, property: b.size)
        #expect(b.doc.componentVersions(of: b.componentID).map(\.id) == [b.primary, secondaryLarge])
        #expect(b.doc.componentVersions(of: b.componentID).map(\.name) == ["Primary", "Secondary"])
    }

    /// Copies fall back to the drawing giving the answers they still have:
    /// one on Primary · Large lands on Primary, one asking for Secondary ·
    /// Large (shown as the Primary · Large stand-in) lands on Secondary.
    @Test func copiesFallBackToTheirRemainingAnswers() {
        var b = buttonWithSize()
        let onLarge = b.doc.insertComponentInstance(of: b.componentID, at: CGPoint(x: 400, y: 300),
                                                    version: b.primaryLarge)!
        let asking = b.doc.insertComponentInstance(of: b.componentID, at: CGPoint(x: 400, y: 400),
                                                   version: b.secondary)!
        _ = b.doc.setInstanceVariantAnswer(instances: [asking], property: b.size, option: "Large")
        _ = b.doc.removeComponentVariantProperty(componentID: b.componentID, property: b.size)
        b.doc.syncComponentInstances()
        #expect(b.doc.instanceVersion(of: onLarge) == b.primary)
        #expect(b.doc.instanceVersion(of: asking) == b.secondary)
        #expect(b.doc.layer(id: asking)?.group?.instanceAnswers.isEmpty == true)
        #expect(b.doc.componentKnobSelection(layerIDs: [asking]).variantRows.map(\.name) == ["Variant"])
    }

    /// The same when the question is taken away on the Edit Original page:
    /// Done brings every copy back onto a drawing that gives its answers,
    /// rather than onto the component's first.
    @Test func takingItAwayInEditOriginalReachesTheCopiesOnDone() throws {
        var b = buttonWithSize()
        b.doc.parkOriginals()
        let onLarge = b.doc.insertComponentInstance(of: b.componentID, at: CGPoint(x: 400, y: 300),
                                                    version: b.primaryLarge)!
        let onSecondaryLarge = b.doc.insertComponentInstance(of: b.componentID,
                                                             at: CGPoint(x: 400, y: 400),
                                                             version: b.secondary)!
        var space = try #require(b.doc.editingSpace(forComponent: b.componentID))
        let secondaryLarge = drawSecondaryLarge(&space, b.componentID, size: b.size,
                                                secondary: b.secondary)
        var history = History(document: b.doc)
        history.perform { $0.returnFromEditingSpace(space, componentID: b.componentID) }
        history.perform { $0.setInstanceVersion(instance: onSecondaryLarge, to: secondaryLarge) }

        var second = try #require(history.current.editingSpace(forComponent: b.componentID))
        _ = second.removeComponentVariantProperty(componentID: b.componentID, property: b.size)
        history.perform { $0.returnFromEditingSpace(second, componentID: b.componentID) }
        #expect(history.current.instanceVersion(of: onLarge) == b.primary)
        #expect(history.current.instanceVersion(of: onSecondaryLarge) == b.secondary)
    }

    /// A document saved after the question went holds no trace of it.
    @Test func nothingOfItIsWritten() throws {
        var b = buttonWithSize()
        _ = b.doc.insertComponentInstance(of: b.componentID, at: CGPoint(x: 400, y: 300),
                                          version: b.primaryLarge)
        _ = b.doc.removeComponentVariantProperty(componentID: b.componentID, property: b.size)
        b.doc.syncComponentInstances()
        let json = try #require(String(data: try JSONEncoder().encode(b.doc), encoding: .utf8))
        #expect(!json.contains("variantAnswers"))
        #expect(!json.contains("instanceAnswers"))
    }
}
