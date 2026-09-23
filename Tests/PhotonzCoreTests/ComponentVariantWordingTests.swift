import Foundation
import CoreGraphics
import Testing
@testable import PhotonzCore

/// The app has ONE word for the looks a component holds, and the author owns
/// it.
///
/// Until this landed the panel let you call the property State and then went on
/// saying Variant in four other places: the Add menu, the Layer menu, the
/// button that pushes one edit to the other drawings, and the notice on the
/// canvas. Somebody who had just typed State over the box was then asked to
/// work out that "Other Variants Already Match" was about their States. The
/// task's own acceptance says it plainly: the words used are the same in the
/// panel, the menus, the canvas label and the tutorial, so nothing is called
/// two things.
struct ComponentVariantWordingTests {

    // MARK: - More than one of them

    /// The author types one word and the app has to say it in the plural too,
    /// so the plural is worked out rather than asked for. English is only
    /// regular enough for this because the word is a short noun somebody typed
    /// into a name box.
    @Test func moreThanOneOfTheAuthorsWord() {
        #expect(ComponentNaming.plural("Variant") == "Variants")
        #expect(ComponentNaming.plural("State") == "States")
        #expect(ComponentNaming.plural("Type") == "Types")
        #expect(ComponentNaming.plural("Size") == "Sizes")
        // A word already ending in a hiss takes -es rather than a second s.
        #expect(ComponentNaming.plural("Status") == "Statuses")
        #expect(ComponentNaming.plural("Box") == "Boxes")
        #expect(ComponentNaming.plural("Pitch") == "Pitches")
        #expect(ComponentNaming.plural("Finish") == "Finishes")
        // A consonant before a final y turns it into -ies; a vowel does not.
        #expect(ComponentNaming.plural("Category") == "Categories")
        #expect(ComponentNaming.plural("Day") == "Days")
    }

    // MARK: - The word every sentence uses

    /// Nobody has renamed anything yet, so every sentence says Variant.
    @Test func theWordBeforeAnybodyNamesIt() {
        let wording = ComponentVariantWording(nil)
        #expect(wording.one == "Variant")
        #expect(wording.many == "Variants")
        #expect(wording.addRow(hasAny: false) == "A second Variant")
        #expect(wording.addRow(hasAny: true) == "Another Variant")
        #expect(wording.addCommand == "Add Variant")
    }

    /// The author called it State, so every sentence says State.
    @Test func theWordTheAuthorChose() {
        let wording = ComponentVariantWording("State")
        #expect(wording.one == "State")
        #expect(wording.many == "States")
        #expect(wording.addRow(hasAny: true) == "Another State")
        #expect(wording.addCommand == "Add State")
    }

    /// A blank name is not a name, so it falls back rather than leaving the
    /// menu reading "Add ".
    @Test func aBlankNameFallsBack() {
        #expect(ComponentVariantWording("   ").one == "Variant")
    }

    // MARK: - It reaches the sentences a person actually reads

    private func box(_ name: String, _ rect: CGRect) -> Layer {
        Layer(name: name, content: .annotation(AnnotationContent(shape: .rectangle,
                                                                 start: .zero,
                                                                 end: CGPoint(x: rect.width, y: rect.height))),
              frame: rect)
    }

    /// A button with four looks, its property called State, and one piece
    /// inside each drawing.
    private func buttonWithFourStates() -> (doc: PhotonzDocument, componentID: UUID) {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 1400, height: 900),
                                  layers: [box("Face", CGRect(x: 10, y: 10, width: 120, height: 40))])
        let main = doc.groupLayers(ids: [doc.layers[0].id], name: "Button")!
        let componentID = doc.makeComponent(id: main.id)!
        doc.addComponentVersion(componentID: componentID, name: "Hover")
        doc.addComponentVersion(componentID: componentID, name: "Pressed")
        doc.addComponentVersion(componentID: componentID, name: "Disabled")
        let renamed = doc.renameComponentVariantProperty(of: componentID, to: "State")
        #expect(renamed)
        return (doc, componentID)
    }

    /// The button that pushes one edit onto the other drawings says State,
    /// because the list it sits under says State.
    @Test func theApplyRowSaysTheAuthorsWord() throws {
        let (doc, componentID) = buttonWithFourStates()
        let versions = doc.componentVersions(of: componentID)
        let piece = try #require(doc.layer(id: versions[0].layerID)?.children.first)
        let plan = try #require(doc.componentVersionApply(from: piece.id))
        #expect(plan.propertyName == "State")
        // Nothing has been edited yet, so every other drawing already matches.
        #expect(plan.title == "Other States Already Match")
        #expect(plan.help.contains("every other State"))
    }

    /// ...and with three drawings to reach it counts them in the same word.
    @Test func theApplyRowCountsInTheAuthorsWord() throws {
        var (doc, componentID) = buttonWithFourStates()
        let versions = doc.componentVersions(of: componentID)
        let piece = try #require(doc.layer(id: versions[0].layerID)?.children.first)
        doc.updateLayer(id: piece.id) { $0.style.opacity = 0.4 }
        let plan = try #require(doc.componentVersionApply(from: piece.id))
        #expect(plan.title == "Apply to 3 Other States")
    }

    /// The notice on the canvas says State too, so the word does not change
    /// between the panel and the thing that pops up when you use it.
    @Test func theCanvasNoticeSaysTheAuthorsWord() {
        let added = CopyConfirmation(
            subject: .componentVersionAdded(version: "Disabled", component: "Button",
                                            property: "State"),
            shownAt: Date(timeIntervalSince1970: 0))
        #expect(added.title == "State added")
        #expect(added.detail == "Disabled is now its own drawing of Button on the canvas")
        let gone = CopyConfirmation(
            subject: .componentVersionGone(count: 2, version: nil, property: "State"),
            shownAt: Date(timeIntervalSince1970: 0))
        #expect(gone.title == "State deleted")
        #expect(gone.detail == "2 copies moved to another State")
    }

    /// A look nobody has named is named after the property it belongs to, so a
    /// component whose question is State never grows an option called
    /// "Variant 4".
    @Test func anUnnamedLookIsNamedAfterTheProperty() {
        var (doc, componentID) = buttonWithFourStates()
        doc.addComponentVersion(componentID: componentID)
        let names = doc.componentVersions(of: componentID).map(\.name)
        #expect(names == ["Default", "Hover", "Pressed", "Disabled", "State 5"])
    }

    /// ...and while nobody has renamed the property, it is still Variant 2.
    @Test func anUnnamedLookOnAnUnnamedPropertyIsStillAVariant() {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 1400, height: 900),
                                  layers: [box("Face", CGRect(x: 10, y: 10, width: 120, height: 40))])
        let main = doc.groupLayers(ids: [doc.layers[0].id], name: "Button")!
        let componentID = doc.makeComponent(id: main.id)!
        doc.addComponentVersion(componentID: componentID)
        #expect(doc.componentVersions(of: componentID).map(\.name) == ["Default", "Variant 2"])
    }
}
