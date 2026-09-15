import Foundation
import CoreGraphics
import Testing
@testable import PhotonzCore

/// A component has PROPERTIES, and the set of looks it holds is one of them.
///
/// Before this the panel split one idea in two: an "Adjustable" list of knobs
/// and a "Versions" list of drawings, so somebody looking at a component was
/// asked to learn two invented words for two halves of the same thing. The
/// model here is the one the user asked for on 2026-09-15: a variant is a
/// property of the component, its options are the looks, and a copy answers it
/// the way it answers every other property.
///
/// The list is a LIST on purpose. A real button wants a Type of primary or
/// secondary AND a State of rest or hovered before long, so nothing here may
/// assume a component has exactly one look-changing property.
struct ComponentVariantPropertyTests {

    private func box(_ name: String, _ rect: CGRect) -> Layer {
        Layer(name: name, content: .annotation(AnnotationContent(shape: .rectangle,
                                                                 start: .zero,
                                                                 end: CGPoint(x: rect.width, y: rect.height))),
              frame: rect)
    }

    private func withComponent() -> (doc: PhotonzDocument, main: UUID, componentID: UUID) {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 800, height: 600),
                                  layers: [box("Box", CGRect(x: 10, y: 10, width: 120, height: 40))])
        let main = doc.groupLayers(ids: [doc.layers[0].id], name: "Button")!
        let componentID = doc.makeComponent(id: main.id)!
        return (doc, main.id, componentID)
    }

    // MARK: - One drawing is no property at all

    /// A component with one look has nothing to choose between, so it has no
    /// variant property. That is what keeps the panel of a plain component the
    /// panel it always was instead of a menu with one item in it.
    @Test func aComponentWithOneDrawingHasNoVariantProperty() {
        let c = withComponent()
        #expect(c.doc.componentVariantProperties(of: c.componentID).isEmpty)
    }

    /// A second look makes the property exist, named for what it is until the
    /// author says otherwise, holding both looks as its options.
    @Test func asecondDrawingMakesOneVariantProperty() {
        var c = withComponent()
        _ = c.doc.addComponentVersion(componentID: c.componentID)
        let properties = c.doc.componentVariantProperties(of: c.componentID)
        #expect(properties.count == 1)
        #expect(properties[0].name == ComponentNaming.defaultVariantPropertyName)
        #expect(properties[0].options.map(\.name) == ["Default", "Variant 2"])
    }

    // MARK: - The property carries a name of its own

    /// The author calls it State, or Type, or Size. This is the whole reason a
    /// variant is a property and not a section: a section can only ever be
    /// called one thing.
    @Test func theVariantPropertyCanBeRenamed() {
        var c = withComponent()
        _ = c.doc.addComponentVersion(componentID: c.componentID)
        let renamed = c.doc.renameComponentVariantProperty(of: c.componentID, to: "State")
        #expect(renamed)
        #expect(c.doc.componentVariantProperties(of: c.componentID).first?.name == "State")
    }

    /// Every drawing of the component carries the name, so deleting the first
    /// one does not take it with it.
    @Test func theNameSurvivesDeletingTheDrawingItWasTypedOn() {
        var c = withComponent()
        let second = c.doc.addComponentVersion(componentID: c.componentID)!
        _ = c.doc.renameComponentVariantProperty(of: c.componentID, to: "State")
        _ = c.doc.addComponentVersion(componentID: c.componentID)
        // Away goes the drawing the name was typed on.
        _ = c.doc.removeLayer(id: c.main)
        #expect(c.doc.componentVariantProperties(of: c.componentID).first?.name == "State")
        #expect(c.doc.componentVersion(of: c.componentID, id: second) != nil)
    }

    /// A blank name is refused rather than saved, the way every other name
    /// field in the app refuses one.
    @Test func aBlankNameIsRefused() {
        var c = withComponent()
        _ = c.doc.addComponentVersion(componentID: c.componentID)
        let renamed = c.doc.renameComponentVariantProperty(of: c.componentID, to: "   ")
        #expect(!renamed)
        #expect(c.doc.componentVariantProperties(of: c.componentID).first?.name
                    == ComponentNaming.defaultVariantPropertyName)
    }

    /// Renaming a component that has one drawing does nothing: there is no
    /// property there to name.
    @Test func renamingWithoutASecondDrawingDoesNothing() {
        var c = withComponent()
        let renamed = c.doc.renameComponentVariantProperty(of: c.componentID, to: "State")
        #expect(!renamed)
    }

    // MARK: - It survives a round trip

    @Test func theNameIsSavedAndReadBack() throws {
        var c = withComponent()
        _ = c.doc.addComponentVersion(componentID: c.componentID)
        _ = c.doc.renameComponentVariantProperty(of: c.componentID, to: "State")
        let data = try JSONEncoder().encode(c.doc)
        let back = try JSONDecoder().decode(PhotonzDocument.self, from: data)
        #expect(back.componentVariantProperties(of: c.componentID).first?.name == "State")
    }

    /// A component nobody has renamed writes no key, so a document saved before
    /// the variant property had a name of its own is byte for byte what it was.
    @Test func anUnnamedPropertyWritesNothing() throws {
        var c = withComponent()
        _ = c.doc.addComponentVersion(componentID: c.componentID)
        let data = try JSONEncoder().encode(c.doc)
        #expect(!String(data: data, encoding: .utf8)!.contains("variantName"))
    }

    // MARK: - What the options are called

    /// The default option names are the words the panel now uses everywhere:
    /// the first look is Default and the rest are Variants.
    @Test func optionsAreNamedForTheWordThePanelUses() {
        #expect(ComponentNaming.versionName(at: 0) == "Default")
        #expect(ComponentNaming.versionName(at: 1) == "Variant 2")
        #expect(ComponentNaming.versionName(at: 2) == "Variant 3")
    }

    /// ...and a fresh one steps past the names already taken.
    @Test func aFreshOptionNameStepsPastTheOnesTaken() {
        #expect(ComponentNaming.freshVersionName(taken: ["Default"], count: 1) == "Variant 2")
        #expect(ComponentNaming.freshVersionName(taken: ["Default", "Variant 2"],
                                                 count: 2) == "Variant 3")
    }

    /// The shelf tile counts variants, not versions.
    @Test func theTileCountsVariants() {
        #expect(ComponentNaming.detail(instanceCount: 0, versionCount: 3) == "3 variants")
        #expect(ComponentNaming.detail(instanceCount: 2, versionCount: 3) == "3 variants • 2 copies")
        // One look is just the component, so it says nothing about variants.
        #expect(ComponentNaming.detail(instanceCount: 1, versionCount: 1)
                    == ComponentNaming.detail(instanceCount: 1))
    }
}
