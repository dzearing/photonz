import Foundation
import CoreGraphics
import Testing
@testable import PhotonzCore

/// ONE Corner Radius on a copy: the knob its original exposes.
///
/// A copy of a Save button read Corner Radius 0 in Appearance, with the slider
/// at the far left, while the Component section under it read Corner radius 18
/// and the button on the canvas was plainly round (found 2026-09-09,
/// `queue/manager/shots/2026-09-09-0238-three-copies.png`). Both numbers were
/// true of different layers — the Appearance row was the copy's own outer mask,
/// the knob is the rectangle inside it — and the copy's outer mask cuts nothing
/// at all while its contents stand off its edges, which they do the moment the
/// component keeps any room inside them.
///
/// So a copy whose original exposes a rounding is left out of that row, and the
/// section says once where the number went. Same rule the Layout section
/// already follows: it leaves out whatever the Component section above it
/// already hands over (`ComponentProperties.numberKnobsOnTheCopyItself`).
struct InstanceRoundingTests {

    // MARK: - A component with a rounding to expose

    private func box(_ name: String, _ rect: CGRect, radius: CGFloat = 0) -> Layer {
        var content = AnnotationContent(shape: .rectangle, start: .zero,
                                        end: CGPoint(x: rect.width, y: rect.height))
        content.colorHex = "#112244"
        content.fillColorHex = "#3366FF"
        content.cornerRadius = radius
        content.strokeWidth = 0
        return Layer(name: name, content: .annotation(content), frame: rect)
    }

    private func text(_ name: String, _ string: String, _ rect: CGRect) -> Layer {
        Layer(name: name, content: .text(TextContent(string: string)), frame: rect)
    }

    /// A "Save button": a rounded box with a label on it, grouped and made a
    /// component, exactly the shape of the drawing the bug was found on.
    private func withButton() -> (doc: PhotonzDocument, main: UUID, componentID: UUID,
                                  boxID: UUID) {
        var doc = PhotonzDocument(
            canvasSize: CGSize(width: 800, height: 600),
            layers: [box("Rectangle", CGRect(x: 20, y: 20, width: 360, height: 120), radius: 18),
                     text("Text", "Save", CGRect(x: 80, y: 60, width: 55, height: 33))])
        let boxID = doc.layers[0].id
        let textID = doc.layers[1].id
        let main = doc.groupLayers(ids: [boxID, textID], name: "Save button")!
        let componentID = doc.makeComponent(id: main.id)!
        return (doc, main.id, componentID, boxID)
    }

    /// The same, with the rounding exposed as a knob and one copy placed.
    private func withCopy(knobNamed name: String? = nil)
    -> (doc: PhotonzDocument, componentID: UUID, main: UUID, copy: UUID, knob: UUID) {
        var c = withButton()
        let knob = c.doc.addComponentProperty(componentID: c.componentID, target: c.boxID,
                                              kind: .number, numberSlot: .cornerRadius,
                                              name: name)!
        let copy = c.doc.insertComponentInstance(of: c.componentID,
                                                 at: CGPoint(x: 400, y: 400))!
        return (c.doc, c.componentID, c.main, copy, knob)
    }

    private func appearance(_ doc: PhotonzDocument, _ ids: [UUID]) -> CornerRadiusSelection {
        doc.cornerRadiusSelection(layerIDs: ids, cornersOnly: true, skippingKnobbedCopies: true)
    }

    // MARK: - Which layers the row speaks for

    /// The bug itself: the row that read 0 over a copy drawn round is not
    /// there at all. The knob is the number.
    @Test func aCopyRoundedByAKnobIsLeftOutOfTheRow() {
        let c = withCopy()
        #expect(c.doc.instanceValue(instance: c.copy, property: c.knob)?.numberValue == 18)
        let row = appearance(c.doc, [c.copy])
        #expect(row.isEmpty)
        // It still knows how many layers are picked, so anything else on the
        // selection can still say what it does and does not reach.
        #expect(row.selectionCount == 1)
    }

    /// A copy whose original exposes NO rounding keeps the row: then it is the
    /// only way to round the thing, and nothing else is claiming the number.
    @Test func aCopyWithNoRoundingKnobKeepsTheRow() {
        var c = withButton()
        let copy = c.doc.insertComponentInstance(of: c.componentID,
                                                 at: CGPoint(x: 400, y: 400))!
        #expect(appearance(c.doc, [copy]).count == 1)
    }

    /// A knob on some OTHER number takes nothing away: a thickness knob has
    /// nothing to say about how round anything is.
    @Test func aKnobOnAnotherNumberLeavesTheRowAlone() {
        var c = withButton()
        _ = c.doc.addComponentProperty(componentID: c.componentID, target: c.boxID,
                                       kind: .number, numberSlot: .thickness)
        let copy = c.doc.insertComponentInstance(of: c.componentID,
                                                 at: CGPoint(x: 400, y: 400))!
        #expect(appearance(c.doc, [copy]).count == 1)
    }

    /// The ORIGINAL keeps its row. Its own section lists the knobs it exposes
    /// by name and kind, not by value, so there is no second number up there to
    /// disagree with.
    @Test func theOriginalKeepsItsRow() {
        let c = withCopy()
        #expect(appearance(c.doc, [c.main]).count == 1)
    }

    /// An ordinary shape picked beside a copy still rounds, and the row says
    /// out loud that it is speaking for one of the two.
    @Test func aShapeBesideACopyStillRounds() {
        var c = withCopy()
        let plain = box("Box", CGRect(x: 600, y: 40, width: 80, height: 80), radius: 4)
        c.doc.layers.append(plain)
        let row = appearance(c.doc, [c.copy, plain.id])
        #expect(row.layerIDs == [plain.id])
        #expect(row.selectionCount == 2)
        #expect(row.note == "Applies to 1 of the 2 selected layers.")
    }

    /// The release that came before Appearance and Effects split is untouched:
    /// it asks for the row without this rule and gets what it always got.
    @Test func theRowThatDoesNotAskIsUnchanged() {
        let c = withCopy()
        #expect(c.doc.cornerRadiusSelection(layerIDs: [c.copy]).count == 1)
    }

    // MARK: - Saying where the number went

    /// A row that simply vanishes is a panel with a hole in it, so the section
    /// says once what rounds this copy and where that control is.
    @Test func theNoteNamesTheKnob() {
        let c = withCopy()
        #expect(c.doc.instanceRoundingNote(layerIDs: [c.copy])
            == "This copy is rounded by its Corner radius knob, in the Component section below.")
    }

    /// Named by whatever the author called it, because that is the word on the
    /// row a person is being sent to.
    @Test func theNoteUsesTheAuthorsOwnWord() {
        let c = withCopy(knobNamed: "Roundness")
        #expect(c.doc.instanceRoundingNote(layerIDs: [c.copy])
            == "This copy is rounded by its Roundness knob, in the Component section below.")
    }

    /// Two roundings exposed, both named.
    @Test func theNoteNamesEveryRoundingKnob() {
        var c = withButton()
        _ = c.doc.addComponentProperty(componentID: c.componentID, target: c.boxID,
                                       kind: .number, numberSlot: .cornerRadius,
                                       name: "Corner radius")
        // A second rounding, on a second box inside the same original.
        let chip = box("Chip", CGRect(x: 30, y: 30, width: 40, height: 40), radius: 6)
        _ = c.doc.addLayer(chip, toGroup: c.main)
        _ = c.doc.addComponentProperty(componentID: c.componentID, target: chip.id,
                                       kind: .number, numberSlot: .cornerRadius,
                                       name: "Chip rounding")
        let copy = c.doc.insertComponentInstance(of: c.componentID,
                                                 at: CGPoint(x: 400, y: 400))!
        #expect(c.doc.instanceRoundingNote(layerIDs: [copy])
            == "This copy is rounded by its Corner radius and Chip rounding knobs, "
                + "in the Component section below.")
    }

    /// Several copies of the one component speak in the plural.
    @Test func severalCopiesSayItOnce() {
        var c = withCopy()
        let second = c.doc.insertComponentInstance(of: c.componentID,
                                                   at: CGPoint(x: 600, y: 400))!
        #expect(c.doc.instanceRoundingNote(layerIDs: [c.copy, second])
            == "These copies are rounded by their Corner radius knob, "
                + "in the Component section below.")
    }

    /// Nothing is said when nothing was left out.
    @Test func nothingIsSaidWhenNothingWasLeftOut() {
        var c = withButton()
        let plain = box("Box", CGRect(x: 600, y: 40, width: 80, height: 80), radius: 4)
        c.doc.layers.append(plain)
        #expect(c.doc.instanceRoundingNote(layerIDs: [plain.id]) == nil)
        #expect(c.doc.instanceRoundingNote(layerIDs: []) == nil)
    }

    // MARK: - The two can never disagree again

    /// The claim the walk makes on screen, made here on the model: over a
    /// picked copy there is exactly ONE number on offer for how round it is,
    /// and it is the one the drawing is wearing.
    @Test func onlyOneNumberIsOnOfferForARoundCopy() {
        let c = withCopy()
        #expect(appearance(c.doc, [c.copy]).isEmpty)
        let drawn = c.doc.layer(id: c.copy)?.selfAndDescendants
            .first { $0.name == "Rectangle" }?.roundedCornerRadius
        #expect(drawn == 18)
        #expect(c.doc.instanceValue(instance: c.copy, property: c.knob)?.numberValue == drawn)
    }

    /// Turning the knob down still rounds the copy, and still leaves one
    /// number: the row does not come back because the knob reached zero.
    @Test func turningTheKnobDownLeavesOneNumberStill() {
        var c = withCopy()
        _ = c.doc.setInstanceOverride(instances: [c.copy], property: c.knob, value: .number(0))
        _ = c.doc.syncComponentInstances()
        #expect(appearance(c.doc, [c.copy]).isEmpty)
        let drawn = c.doc.layer(id: c.copy)?.selfAndDescendants
            .first { $0.name == "Rectangle" }?.roundedCornerRadius
        #expect(drawn == 0)
    }
}
