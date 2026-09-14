import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// Letting a saved colour go on a ROW in the layers list.
///
/// A saved text style could already be put down on a row; a colour could not,
/// and aiming one there did nothing and said nothing about why. The reason it
/// was left out is that a row is not a colour well: a well is labelled with the
/// one thing it paints, and a row carries only the layer's name.
///
/// The rule the user chose on 2026-09-13 is the layer's MAIN colour, named
/// before you let go: the part the inspector leads with, which is Fill for a
/// box, Line for an arrow, Text for words, and the Border for a picture that
/// wears a ring. A layer with no colour anywhere refuses in words.
///
/// The sentence is not a second set of words either: the row builds the same
/// `ColorDrop.Target` a swatch builds and reads the same answer back, so what
/// the list promises is exactly what a swatch would have promised.
@Suite("A colour let go on a layer row")
struct ColorRowDropTests {

    private let brandPaint = Paint(hex: "#3B82F6")

    private func box(_ name: String, fillHex: String? = "#00FF00") -> Layer {
        Layer(name: name,
              content: .annotation(AnnotationContent(shape: .rectangle, strokeWidth: 2,
                                                     colorHex: "#FF0000", start: .zero,
                                                     end: CGPoint(x: 100, y: 60),
                                                     fillColorHex: fillHex)),
              frame: CGRect(x: 0, y: 0, width: 100, height: 60))
    }

    private func arrow(_ name: String) -> Layer {
        Layer(name: name,
              content: .annotation(AnnotationContent(shape: .arrow, strokeWidth: 3,
                                                     colorHex: "#FF0000", start: .zero,
                                                     end: CGPoint(x: 100, y: 60))),
              frame: CGRect(x: 0, y: 0, width: 100, height: 60))
    }

    private func words(_ name: String) -> Layer {
        Layer(name: name, content: .text(TextContent(string: "Sign in", colorHex: "#111111")),
              frame: CGRect(x: 0, y: 0, width: 120, height: 30))
    }

    private func picture(_ name: String, borderWidth: CGFloat = 0) -> Layer {
        var style = LayerStyle()
        style.borderWidth = borderWidth
        style.borderColorHex = "#222222"
        return Layer(name: name,
                     content: .image(ImageRef(pixelSize: CGSize(width: 40, height: 40))),
                     frame: CGRect(x: 0, y: 0, width: 40, height: 40),
                     style: style)
    }

    private func doc(_ layers: [Layer]) -> PhotonzDocument {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 800, height: 600))
        for layer in layers { doc.addLayer(layer) }
        return doc
    }

    /// A document with one saved colour called Brand.
    private func saved(_ doc: inout PhotonzDocument) -> ColorDrop.SavedColor {
        let id = doc.addColorStyle(name: "Brand", colorHex: brandPaint.hex)
        return ColorDrop.SavedColor(id: id, name: "Brand")
    }

    // MARK: - Which part a row leads with

    @Test func aBoxTakesItOnItsFill() {
        let card = box("Card")
        let document = doc([card])
        let drop = document.colorRowDrop(brandPaint, onRow: card.id)
        #expect(drop.answer.lightsUp)
        #expect(drop.answer.note == "Paints Fill with this colour.")
        #expect(drop.slot == .fill)
        #expect(drop.layerIDs == [card.id])
    }

    /// An arrow leads with its shaft, which the panel calls Line. Its head is a
    /// part too, and it keeps the colour it had: the sentence said Line before
    /// the pointer was let go, so a half-recoloured arrow is a choice rather
    /// than a surprise.
    @Test func anArrowTakesItOnItsLine() {
        let pointer = arrow("Arrow")
        let document = doc([pointer])
        let drop = document.colorRowDrop(brandPaint, onRow: pointer.id)
        #expect(drop.answer.note == "Paints Line with this colour.")
        #expect(drop.slot == .stroke)
    }

    @Test func wordsTakeItOnTheirText() {
        let heading = words("Sign in")
        let document = doc([heading])
        let drop = document.colorRowDrop(brandPaint, onRow: heading.id)
        #expect(drop.answer.note == "Paints Text with this colour.")
        #expect(drop.slot == .text)
    }

    /// A picture has no parts list at all: its only colour is the ring in the
    /// Effects list, so that is what the drop names and paints.
    @Test func aPictureWearingARingTakesItOnTheBorder() {
        let shot = picture("Screenshot", borderWidth: 3)
        let document = doc([shot])
        let drop = document.colorRowDrop(brandPaint, onRow: shot.id)
        #expect(drop.answer.note == "Paints Border with this colour.")
        #expect(drop.slot == .border)
    }

    // MARK: - The rows that cannot take one

    @Test func aPictureWithNoRingRefusesAndSaysSo() {
        let shot = picture("Screenshot")
        let document = doc([shot])
        let drop = document.colorRowDrop(brandPaint, onRow: shot.id)
        #expect(!drop.answer.lightsUp)
        #expect(drop.answer.note == "Screenshot has no colour to paint.")
        #expect(drop.slot == nil)
        #expect(drop.layerIDs.isEmpty)
    }

    /// Locked means here what it means everywhere else, and the sentence says
    /// which of the two things is in the way — the same shape the text style
    /// refusal has, because a padlock two rows up is not what somebody carrying
    /// a colour is looking at.
    @Test func aLockedRowRefusesAndNamesTheLock() {
        let card = box("Card")
        var document = doc([card])
        document.updateLayer(id: card.id) { $0.isLocked = true }
        let drop = document.colorRowDrop(brandPaint, onRow: card.id)
        #expect(!drop.answer.lightsUp)
        #expect(drop.answer.note == "Card is locked, so it cannot be painted.")
        #expect(drop.layerIDs.isEmpty)
    }

    /// A row nobody can point at any more — deleted mid-drag, the list rebuilt
    /// under the pointer — is pointing at nothing, so it gets a signpost rather
    /// than a refusal about a layer that is not there.
    @Test func aRowThatIsNotThereSaysWhereAColourGoes() {
        var document = doc([box("Card")])
        let brand = saved(&document)
        let drop = document.colorRowDrop(brandPaint, bringing: brand, onRow: UUID())
        #expect(!drop.answer.lightsUp)
        #expect(drop.answer.note == "Drop this on a layer to paint it with Brand.")
    }

    @Test func aRowAlreadyWearingTheColourSaysSoRatherThanWritingAnUndoStep() {
        let card = box("Card", fillHex: brandPaint.hex)
        let document = doc([card])
        let drop = document.colorRowDrop(brandPaint, onRow: card.id)
        #expect(!drop.answer.lightsUp)
        #expect(drop.answer.note == "Fill is already this colour.")
    }

    // MARK: - A part that is switched off

    /// A box with no fill still leads with Fill: the drop switches it on AND
    /// paints it, in one step, and the sentence promises both before it
    /// happens.
    @Test func aBoxWithNoFillIsSwitchedOnAndPainted() {
        let card = box("Card", fillHex: nil)
        let document = doc([card])
        let drop = document.colorRowDrop(brandPaint, onRow: card.id)
        #expect(drop.answer.lightsUp)
        #expect(drop.answer.note == "Turns Fill on, painted with this colour.")
        #expect(drop.turnsOn == .fill)
    }

    @Test func aPartThatIsAlreadyOnHasNothingToSwitch() {
        let card = box("Card")
        let document = doc([card])
        #expect(document.colorRowDrop(brandPaint, onRow: card.id).turnsOn == nil)
    }

    // MARK: - A saved colour arriving by name

    @Test func aSavedColourIsNamedInTheSentence() {
        let card = box("Card")
        var document = doc([card])
        let brand = saved(&document)
        let drop = document.colorRowDrop(brandPaint, bringing: brand, onRow: card.id)
        #expect(drop.answer.note == "Paints Fill with Brand.")
        #expect(drop.answer.landing?.brings == brand)
    }

    /// With saved colours turned off there is no name to keep, so only the
    /// colour lands and nothing is said about a name that was never going to
    /// stick.
    @Test func withSavedColoursOffOnlyTheColourLands() {
        let card = box("Card")
        var document = doc([card])
        let brand = saved(&document)
        let drop = document.colorRowDrop(brandPaint, bringing: brand, onRow: card.id,
                                         stylesEnabled: false)
        #expect(drop.answer.landing?.brings == nil)
        #expect(drop.answer.note == "Paints Fill with this colour.")
    }

    // MARK: - A crowd

    /// Aiming at a row that is part of what you have picked reaches every
    /// picked layer that leads with the same part, the way the text style row
    /// drop reaches every picked piece of text.
    @Test func aimingAtAPickedRowReachesThePickedCrowd() {
        let one = box("One")
        let two = box("Two")
        let document = doc([one, two])
        let drop = document.colorRowDrop(brandPaint, onRow: one.id, picked: [one.id, two.id])
        #expect(drop.answer.note == "Paints Fill on both of them with this colour.")
        #expect(Set(drop.layerIDs) == Set([one.id, two.id]))
    }

    /// A crowd only gathers layers the drop can actually reach: words lead with
    /// Text and a box leads with Fill, so picking both and aiming at the box
    /// paints the boxes and says so.
    @Test func aCrowdHoldsOnlyTheLayersThatLeadWithTheSamePart() {
        let card = box("Card")
        let heading = words("Sign in")
        let document = doc([card, heading])
        let drop = document.colorRowDrop(brandPaint, onRow: card.id,
                                         picked: [card.id, heading.id])
        #expect(drop.layerIDs == [card.id])
        #expect(drop.answer.note == "Paints Fill with this colour.")
    }

    /// A crowd that disagrees about what it wears has nothing to compare the
    /// arriving colour against, so the no-op refusal must not fire on it: there
    /// is plainly work to do.
    @Test func aCrowdWearingTwoColoursStillTakesOneOfThem() {
        let one = box("One", fillHex: brandPaint.hex)
        let two = box("Two", fillHex: "#123456")
        let document = doc([one, two])
        let drop = document.colorRowDrop(brandPaint, onRow: one.id, picked: [one.id, two.id])
        #expect(drop.answer.lightsUp)
        #expect(Set(drop.layerIDs) == Set([one.id, two.id]))
    }

    /// A locked layer inside the picked crowd sits it out, exactly as it sits
    /// out of what a colour row in the inspector paints.
    @Test func aLockedLayerInTheCrowdSitsOut() {
        let one = box("One")
        let two = box("Two")
        var document = doc([one, two])
        document.updateLayer(id: two.id) { $0.isLocked = true }
        let drop = document.colorRowDrop(brandPaint, onRow: one.id, picked: [one.id, two.id])
        #expect(drop.layerIDs == [one.id])
    }

    /// Aiming at a row nobody picked reaches that row alone: the pointer named
    /// it, so the selection has no say.
    @Test func aimingAtAnUnpickedRowReachesOnlyIt() {
        let one = box("One")
        let two = box("Two")
        let document = doc([one, two])
        let drop = document.colorRowDrop(brandPaint, onRow: two.id, picked: [one.id])
        #expect(drop.layerIDs == [two.id])
    }

    // MARK: - What letting go actually does

    /// The very reading the row answered the pointer with, so nothing can slip
    /// past a refusal and land anyway.
    @Test func lettingGoPaintsThePartTheSentenceNamed() {
        let card = box("Card")
        var document = doc([card])
        let drop = document.colorRowDrop(brandPaint, onRow: card.id)
        #expect(document.paint(drop) == 1)
        #expect(document.layer(id: card.id)?.colorHex(for: .fill) == brandPaint.hex)
    }

    @Test func lettingGoOnAnAbsentPartSwitchesItOnWearingTheColour() {
        let card = box("Card", fillHex: nil)
        var document = doc([card])
        let drop = document.colorRowDrop(brandPaint, onRow: card.id)
        #expect(document.paint(drop) == 1)
        #expect(document.layer(id: card.id)?.colorHex(for: .fill) == brandPaint.hex)
    }

    /// A colour that arrived under a NAME points the part at that name, the
    /// same way the row's own menu does, so the drag is never the quieter,
    /// lossier way to do it.
    @Test func aSavedColourLandsAsTheNameRatherThanACopyOfIt() {
        let card = box("Card")
        var document = doc([card])
        let brand = saved(&document)
        let drop = document.colorRowDrop(brandPaint, bringing: brand, onRow: card.id)
        #expect(document.paint(drop) == 1)
        #expect(document.layer(id: card.id)?.colorStyleID(for: .fill) == brand.id)
    }

    @Test func aRingIsPaintedThroughTheEffectItLivesOn() {
        let shot = picture("Screenshot", borderWidth: 3)
        var document = doc([shot])
        let drop = document.colorRowDrop(brandPaint, onRow: shot.id)
        #expect(document.paint(drop) == 1)
        #expect(document.layer(id: shot.id)?.colorHex(for: .border) == brandPaint.hex)
    }

    /// A refusal paints nothing, whatever a caller does with it.
    @Test func aRefusalPaintsNothing() {
        let shot = picture("Screenshot")
        var document = doc([shot])
        let drop = document.colorRowDrop(brandPaint, onRow: shot.id)
        #expect(document.paint(drop) == 0)
    }

    @Test func aCrowdIsPaintedInOneMove() {
        let one = box("One")
        let two = box("Two")
        var document = doc([one, two])
        let drop = document.colorRowDrop(brandPaint, onRow: one.id, picked: [one.id, two.id])
        #expect(document.paint(drop) == 2)
        #expect(document.layer(id: two.id)?.colorHex(for: .fill) == brandPaint.hex)
    }
}
