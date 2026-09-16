import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// The line a layers row says under its name when the row is a component.
///
/// Every copy carries its original's name, so an original with two copies on
/// the page put three rows reading "Save Button" in the list, told apart only
/// by a nine point violet mark. This is the list saying it in words.
struct ComponentRowNoteTests {

    // MARK: - What the words are

    @Test func anOriginalSaysSo() {
        let note = ComponentRowNote.forRow(isMain: true, isInstance: false, rowName: "Save Button",
                                           componentName: "Save Button", versionName: nil)
        #expect(note?.role == .original)
        #expect(note?.text == "Original")
    }

    @Test func aCopySaysSo() {
        let note = ComponentRowNote.forRow(isMain: false, isInstance: true, rowName: "Save Button",
                                           componentName: "Save Button", versionName: nil)
        #expect(note?.role == .copy)
        #expect(note?.text == "Copy")
    }

    @Test func anOrdinaryLayerSaysNothing() {
        #expect(ComponentRowNote.forRow(isMain: false, isInstance: false, rowName: "Box",
                                        componentName: nil, versionName: nil) == nil)
    }

    // MARK: - A copy still says what it follows

    @Test func aCopyWhoseNameNoLongerMatchesNamesTheComponentItFollows() {
        let note = ComponentRowNote.forRow(isMain: false, isInstance: true, rowName: "Cancel",
                                           componentName: "Save Button", versionName: nil)
        #expect(note?.text == "Copy of Save Button")
    }

    @Test func aCopyWearingTheComponentNameDoesNotRepeatIt() {
        // The row already SAYS Save Button on the line above. Repeating it
        // would make the longest line on the row the one that says least.
        let note = ComponentRowNote.forRow(isMain: false, isInstance: true, rowName: "Save Button",
                                           componentName: "Save Button", versionName: nil)
        #expect(note?.text == "Copy")
    }

    @Test func aCopyWhoseOriginalIsUnknownStillSaysItIsACopy() {
        let note = ComponentRowNote.forRow(isMain: false, isInstance: true, rowName: "Save Button",
                                           componentName: nil, versionName: nil)
        #expect(note?.text == "Copy")
    }

    // MARK: - The version line it grew out of is still there

    @Test func aVersionRidesAfterTheWord() {
        let original = ComponentRowNote.forRow(isMain: true, isInstance: false, rowName: "Button",
                                               componentName: "Button", versionName: "Disabled")
        #expect(original?.text == "Original, Disabled")
        let copy = ComponentRowNote.forRow(isMain: false, isInstance: true, rowName: "Button",
                                           componentName: "Button", versionName: "Disabled")
        #expect(copy?.text == "Copy, Disabled")
    }

    @Test func aRenamedCopyOnAVersionSaysBoth() {
        let note = ComponentRowNote.forRow(isMain: false, isInstance: true, rowName: "Cancel",
                                           componentName: "Save Button", versionName: "Disabled")
        #expect(note?.text == "Copy of Save Button, Disabled")
    }

    // MARK: - What hovering it explains

    @Test func eachRoleExplainsItselfInASentence() {
        let original = ComponentRowNote.forRow(isMain: true, isInstance: false, rowName: "Button",
                                               componentName: "Button", versionName: nil)
        #expect(original?.help.contains("original") == true)
        let copy = ComponentRowNote.forRow(isMain: false, isInstance: true, rowName: "Button",
                                           componentName: "Button", versionName: nil)
        #expect(copy?.help.contains("Editing the original") == true)
    }

    // MARK: - No em dashes anywhere in it

    @Test func nothingItSaysUsesAnEmDash() {
        for role in ComponentRowRole.allCases {
            #expect(!role.word.contains("\u{2014}"))
        }
    }
}

/// The same note, gathered on the rows the layers panel actually draws.
struct ComponentRowNoteInTheListTests {

    private func button() -> Layer {
        Layer(name: "Save Button",
              content: .group(GroupContent(children: [
                Layer(name: "Label", content: .text(TextContent(string: "Save changes")),
                      frame: CGRect(x: 0, y: 0, width: 100, height: 20))
              ])),
              frame: CGRect(x: 0, y: 0, width: 240, height: 52))
    }

    private func documentWithOriginalAndTwoCopies() -> PhotonzDocument {
        var document = PhotonzDocument(canvasSize: CGSize(width: 800, height: 600),
                                       layers: [button()])
        let main = document.layers[0].id
        _ = document.makeComponent(id: main)
        let componentID = document.layer(id: main)?.componentID
        _ = document.insertComponentInstance(of: componentID!, at: CGPoint(x: 100, y: 300))
        _ = document.insertComponentInstance(of: componentID!, at: CGPoint(x: 100, y: 420))
        return document
    }

    /// The bug this exists for: three rows, one word each, and only one of
    /// them says Original.
    @Test func theOriginalAndItsTwoCopiesNoLongerReadTheSame() {
        let document = documentWithOriginalAndTwoCopies()
        let rows = document.layerRows(expanded: [], selected: [])
        #expect(rows.map(\.name) == ["Save Button", "Save Button", "Save Button"])
        #expect(rows.compactMap { $0.componentNote?.text }.sorted() == ["Copy", "Copy", "Original"])
        #expect(rows.filter { $0.componentNote?.role == .original }.count == 1)
    }

    @Test func anOrdinaryLayerInTheSameListCarriesNoNote() {
        var document = documentWithOriginalAndTwoCopies()
        document.layers.append(Layer(name: "Backdrop", content: .text(TextContent(string: "Backdrop")),
                                     frame: CGRect(x: 0, y: 0, width: 10, height: 10)))
        let rows = document.layerRows(expanded: [], selected: [])
        #expect(rows.first { $0.name == "Backdrop" }?.componentNote == nil)
    }

    /// Nothing about this renames anything: the note is what the LIST says.
    @Test func nothingInTheDocumentIsRenamed() {
        let document = documentWithOriginalAndTwoCopies()
        #expect(document.allLayers.filter { $0.isComponentRoot }.allSatisfy { $0.name == "Save Button" })
    }

    @Test func aDocumentWithNoComponentsCostsNoNotes() {
        let document = PhotonzDocument(canvasSize: CGSize(width: 100, height: 100),
                                       layers: [button()])
        #expect(document.layerRows(expanded: [], selected: []).allSatisfy { $0.componentNote == nil })
    }
}
