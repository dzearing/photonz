import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// A copy's Layout section does not say what its Component section already
/// says.
///
/// A copy is shown how its original arranges its contents and refused the
/// typing of it, so its Layout rows are greyed answers. But the room and the
/// gap a card keeps at its OWN edges can also be knobs on that card, and a knob
/// is a real field on the same panel, a few rows above, wearing the very same
/// word. Two rows called Padding holding one number, one of them dead, is the
/// panel saying the same thing twice, and the audit on 2026-09-07 asked about
/// exactly that pair.
///
/// The size rows set the precedent: W and H are two rows up in Position & Size,
/// so the Layout section has never said them again.
struct CopyLayoutReadoutTests {

    private func text(_ name: String, _ string: String, _ rect: CGRect) -> Layer {
        Layer(name: name, content: .text(TextContent(string: string)), frame: rect)
    }

    /// A card that is itself a stack, holding two labels 12 apart with 16 of
    /// room inside its edges, and one copy of it on the canvas.
    private func withCard() -> (doc: PhotonzDocument, componentID: UUID, main: UUID, copy: UUID) {
        var doc = PhotonzDocument(
            canvasSize: CGSize(width: 800, height: 600),
            layers: [text("Title", "Hello", CGRect(x: 20, y: 20, width: 80, height: 20)),
                     text("Body", "World", CGRect(x: 20, y: 52, width: 80, height: 20))])
        let main = doc.groupLayers(ids: [doc.layers[0].id, doc.layers[1].id], name: "Card")!
        doc.setGroupLayout(id: main.id, kind: .stack)
        doc.updateGroupLayout(id: main.id) { $0.gap = 12; $0.padding = GroupPadding(16) }
        let componentID = doc.makeComponent(id: main.id)!
        let copy = doc.insertComponentInstance(of: componentID, at: CGPoint(x: 400, y: 200))!
        return (doc, componentID, main.id, copy)
    }

    // MARK: - Which numbers a copy already carries as knobs

    @Test("A copy with no knobs carries none, and neither does anything that is not a copy")
    func nothingExposed() {
        let c = withCard()
        #expect(c.doc.numberKnobsOnTheCopyItself(instance: c.copy).isEmpty)
        #expect(c.doc.numberKnobsOnTheCopyItself(instance: c.main).isEmpty)
    }

    @Test("The room knob on the card itself is a number the copy carries")
    func theCardsOwnRoomCounts() {
        var c = withCard()
        c.doc.addComponentProperty(componentID: c.componentID, target: c.main,
                                   kind: .number, numberSlot: .padding)
        #expect(c.doc.numberKnobsOnTheCopyItself(instance: c.copy) == [.padding])
    }

    @Test("A knob reaching a piece inside the copy is a different number, and does not count")
    func aKnobOnAPieceInsideDoesNotCount() {
        var c = withCard()
        let inside = c.doc.layer(id: c.main)!.children[0].id
        c.doc.addComponentProperty(componentID: c.componentID, target: inside,
                                   kind: .number, numberSlot: .cornerRadius)
        #expect(c.doc.numberKnobsOnTheCopyItself(instance: c.copy).isEmpty)
    }

    // MARK: - What the greyed rows leave out

    @Test("Without a knob, the copy's Layout section still reads the room and the gap")
    func withoutAKnobTheRowsStay() {
        let c = withCard()
        let titles = c.doc.layer(id: c.copy)!.workingLayout
            .followedReadout(clipsContents: false).map(\.title)
        #expect(titles.contains("Padding"))
        #expect(titles.contains("Gap"))
    }

    @Test("With the room as a knob, the greyed Padding row goes and the gap stays")
    func aKnobbedNumberIsLeftOut() {
        let c = withCard()
        let titles = c.doc.layer(id: c.copy)!.workingLayout
            .followedReadout(clipsContents: false, covered: [.padding]).map(\.title)
        #expect(!titles.contains("Padding"))
        #expect(titles.contains("Gap"))
    }

    @Test("The Layout rows a copy shows follow the knobs its selection reports")
    func theSelectionCarriesTheKnobs() {
        var c = withCard()
        c.doc.addComponentProperty(componentID: c.componentID, target: c.main,
                                   kind: .number, numberSlot: .padding)
        let selection = c.doc.contentsSelection(layerIDs: [c.copy])
        #expect(selection.isFollowed)
        let group = selection.groups.first
        #expect(group?.knobbed == [.padding])
        let titles = group.map {
            $0.layout.followedReadout(clipsContents: false, covered: $0.knobbed).map(\.title)
        }
        #expect(titles?.contains("Padding") == false)
    }
}
