import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// A layer is made of parts, and every part works the same way: one switch, one
/// colour, its own settings.
///
/// Raised by the user on 2026-09-06 after failing to find any way to take a
/// rectangle's outline off. There was none: the fill had a checkbox, the
/// outline had nothing at all, and the shadow had a switch of its own in
/// another section. These tests pin the model down.
@Suite("Layer parts")
struct LayerPartsTests {

    private func shape(_ kind: AnnotationShape, strokeWidth: CGFloat = 4,
                       fillHex: String? = nil, style: LayerStyle = LayerStyle(),
                       locked: Bool = false) -> Layer {
        var layer = Layer(name: kind.title,
                          content: .annotation(AnnotationContent(shape: kind,
                                                                 strokeWidth: strokeWidth,
                                                                 colorHex: "#FF0000",
                                                                 start: .zero,
                                                                 end: CGPoint(x: 100, y: 60),
                                                                 fillColorHex: fillHex)),
                          frame: CGRect(x: 0, y: 0, width: 100, height: 60),
                          style: style)
        layer.isLocked = locked
        return layer
    }

    private func picture(style: LayerStyle = LayerStyle()) -> Layer {
        Layer(name: "Shot",
              content: .image(ImageRef(pixelSize: CGSize(width: 40, height: 40))),
              frame: CGRect(x: 0, y: 0, width: 40, height: 40),
              style: style)
    }

    private func document(_ layers: [Layer]) -> PhotonzDocument {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 400, height: 300))
        for layer in layers { doc.addLayer(layer) }
        return doc
    }

    private func border(_ width: CGFloat) -> LayerStyle {
        var style = LayerStyle()
        style.borderWidth = width
        return style
    }

    // MARK: - Which ring a layer's outline part paints

    @Test func aShapePaintsItsOwnStrokeAndEverythingElseTakesARing() {
        #expect(shape(.rectangle).outlineSlot == .stroke)
        #expect(shape(.arrow).outlineSlot == .stroke)
        #expect(picture().outlineSlot == .border)
        #expect(shape(.highlight).outlineSlot == .border)
    }

    @Test func onlyAShapeWithAnInsideCanHaveItsOutlineSwitchedOff() {
        #expect(shape(.rectangle).outlineIsSwitchable)
        #expect(shape(.ellipse).outlineIsSwitchable)
        // A line IS its line: switching it off is a delete, not a setting.
        #expect(!shape(.line).outlineIsSwitchable)
        #expect(!shape(.arrow).outlineIsSwitchable)
        // ...but a ring round a box is styling, and anything can take one.
        #expect(picture().outlineIsSwitchable)
        #expect(shape(.highlight).outlineIsSwitchable)
    }

    @Test func aHighlightsUnpaintedStrokeWidthIsNotAnOutline() {
        // It carries a stroke width it never draws, so only the ring its
        // styling adds counts as an outline.
        #expect(!shape(.highlight, strokeWidth: 6).hasOutline)
        #expect(shape(.highlight, strokeWidth: 6, style: border(2)).hasOutline)
    }

    // MARK: - The rows a selection gets

    @Test func aRectangleGetsFillAndOutline() {
        let box = shape(.rectangle, fillHex: "#00FF00")
        let doc = document([box])
        let rows = doc.layerPartRows(layerIDs: [box.id])
        // A shadow is countable, so it is not a fixed row that is off nearly
        // all the time: it arrives from the plus at the foot of the list
        // (`AppearanceListTests`).
        #expect(rows.map(\.title) == ["Fill", "Outline"])
        #expect(rows.map(\.hasSwitch) == [true, true])
        #expect(rows[0].isOn)
        #expect(rows[1].isOn)
        // Only the outline has anything under it.
        #expect(rows.map(\.hasSettings) == [false, true])
    }

    @Test func anArrowsOneColorIsNotCalledAnOutlineAndHasNoSwitch() {
        let arrow = shape(.arrow)
        let doc = document([arrow])
        let rows = doc.layerPartRows(layerIDs: [arrow.id])
        // No Outline row at all: the arrow's line IS its colour, and a ring
        // round its bounding box is not something anyone reaches for.
        #expect(rows.map(\.title) == ["Color"])
        let ink = rows[0]
        #expect(ink.part == nil)
        #expect(!ink.hasSwitch)
    }

    @Test func anArrowsWidthIsNotHiddenInADrawerThisRowCannotOpen() {
        // A row with no switch is a colour and nothing else, so it has no
        // drawer to keep a width in. Making an arrow thicker is the commonest
        // thing anyone does to one, and it was two clicks down inside a row
        // called Color. The width is the shape's own Thickness setting now,
        // out where the ending and the head size are.
        let arrow = shape(.arrow)
        let doc = document([arrow])
        let ink = doc.layerPartRows(layerIDs: [arrow.id])[0]
        #expect(ink.widthIDs.isEmpty)
        #expect(!ink.hasSettings)
    }

    @Test func aRectanglesWidthStaysWithTheOutlineItBelongsTo() throws {
        // The other half of the same rule: where the outline is a part that
        // switches off, its width is that part's setting and stays in it.
        let box = shape(.rectangle, fillHex: "#00FF00")
        let doc = document([box])
        let outline = try #require(doc.layerPartRows(layerIDs: [box.id]).first { $0.part == .outline })
        #expect(outline.widthIDs == [box.id])
        #expect(outline.hasSettings)
    }

    @Test func anArrowPickedWithABoxTakesTheBoxesOutlineWidthRow() throws {
        // One row speaks for both, it can be switched off (the box can live
        // without its ring), so the width is in there and reaches both.
        let box = shape(.rectangle, fillHex: "#00FF00")
        let arrow = shape(.arrow)
        let doc = document([box, arrow])
        let rows = doc.layerPartRows(layerIDs: [box.id, arrow.id])
        let outline = try #require(rows.first { $0.slot == .stroke })
        #expect(outline.title == "Outline")
        #expect(outline.widthIDs == [box.id, arrow.id])
    }

    @Test func aPictureGetsAnOutlineItCanSwitchOnAndAShadow() {
        let shot = picture()
        let doc = document([shot])
        let rows = doc.layerPartRows(layerIDs: [shot.id])
        #expect(rows.map(\.title) == ["Outline"])
        // The same model as a rectangle's, on a layer that is not a shape at
        // all: the ring is off, and one switch turns it on.
        #expect(rows[0].part == .outline)
        #expect(rows[0].slot == .border)
        #expect(rows[0].hasSwitch)
        #expect(!rows[0].isOn)
    }

    // MARK: - A highlight, which was offered the same name twice

    @Test func aHighlightIsOfferedOneLineRoundItNotTwo() throws {
        // Reported 2026-09-06: picking a highlight put two rows called Outline
        // one above the other. Both switches wrote the same border width and
        // they painted different colours, so picking either was a guess.
        let wash = shape(.highlight)
        let doc = document([wash])
        let rows = doc.layerPartRows(layerIDs: [wash.id])
        #expect(rows.filter { $0.title == "Outline" }.count == 1)
        let outline = try #require(rows.first { $0.title == "Outline" })
        // The one that is real: the ring the highlight's styling draws.
        #expect(outline.slot == .border)
        #expect(outline.switchIDs == [wash.id])
        #expect(outline.widthIDs == [wash.id])
    }

    @Test func aHighlightsWashIsAColorRatherThanAnOutline() {
        // A highlight IS its wash, the way an arrow is its line: there is no
        // switching it off, and the stroke width it carries is never painted.
        let wash = shape(.highlight)
        let doc = document([wash])
        let rows = doc.layerPartRows(layerIDs: [wash.id])
        #expect(rows.map(\.title) == ["Color", "Outline"])
        let ink = rows[0]
        #expect(ink.slot == .stroke)
        #expect(ink.part == nil)
        #expect(!ink.hasSwitch)
        #expect(ink.widthIDs.isEmpty)
        #expect(!ink.hasSettings)
    }

    @Test func aHighlightsRingIsStillTheSameSwitch() {
        // Dropping the duplicate must not cost the highlight its ring.
        let wash = shape(.highlight)
        var doc = document([wash])
        #expect(doc.setOutlineEnabled(layerIDs: [wash.id], on: true) == 1)
        #expect(doc.layer(id: wash.id)!.style.borderWidth > 0)
        #expect(doc.setOutlineEnabled(layerIDs: [wash.id], on: false) == 1)
        #expect(doc.layer(id: wash.id)!.style.borderWidth == 0)
    }

    @Test func aHighlightPickedWithABoxKeepsItsWashOutOfTheOutline() throws {
        // One row called Outline over both of them: the box's stroke and the
        // highlight's ring are the same line to a person. What must NOT
        // happen is the highlight's wash being painted from it, so the row
        // carries the box under stroke and the highlight under border and
        // paints neither one with the other's colour.
        let box = shape(.rectangle, fillHex: "#00FF00")
        let wash = shape(.highlight)
        let doc = document([box, wash])
        let rows = doc.layerPartRows(layerIDs: [box.id, wash.id])
        #expect(rows.filter { $0.title == "Outline" }.count == 1)
        let outline = try #require(rows.first { $0.part == .outline })
        #expect(outline.colors == [PartColor(slot: .stroke, layerIDs: [box.id]),
                                   PartColor(slot: .border, layerIDs: [wash.id])])
        #expect(outline.switchIDs == [box.id, wash.id])
        // And the wash keeps its own row, the one it has on its own.
        let ink = try #require(rows.first { $0.part == nil && $0.slot == .stroke })
        #expect(ink.title == "Color")
        #expect(ink.colors == [PartColor(slot: .stroke, layerIDs: [wash.id])])
    }

    // MARK: - Two kinds of line picked together, which was two rows called Outline

    @Test func aBoxAndAPictureAreOfferedOneOutlineNotTwo() throws {
        // Reported 2026-09-07: picking a rectangle and a screenshot listed
        // Outline twice, one for the line the shape draws itself and one for
        // the ring the picture wears. They are the same idea to a person.
        let box = shape(.rectangle, fillHex: "#00FF00")
        let shot = picture(style: border(2))
        let doc = document([box, shot])
        let rows = doc.layerPartRows(layerIDs: [box.id, shot.id])
        #expect(rows.filter { $0.title == "Outline" }.count == 1)
        let outline = try #require(rows.first { $0.part == .outline })
        #expect(outline.switchIDs == [box.id, shot.id])
        #expect(outline.onCount == 2)
        #expect(outline.isOn)
        #expect(outline.widthIDs == [box.id, shot.id])
        #expect(outline.reachNote == nil)
    }

    @Test func thatOneRowKnowsWhichColorEachOfThemWears() throws {
        let box = shape(.rectangle, fillHex: "#00FF00")
        let shot = picture(style: border(2))
        let doc = document([box, shot])
        let outline = try #require(doc.layerPartRows(layerIDs: [box.id, shot.id])
            .first { $0.part == .outline })
        #expect(outline.colors == [PartColor(slot: .stroke, layerIDs: [box.id]),
                                   PartColor(slot: .border, layerIDs: [shot.id])])
        #expect(outline.mixesLineKinds)
    }

    @Test func oneSwitchTakesTheLineOffBothKindsAtOnce() {
        let box = shape(.rectangle, fillHex: "#00FF00")
        let shot = picture(style: border(2))
        var doc = document([box, shot])
        let outline = doc.layerPartRows(layerIDs: [box.id, shot.id]).first { $0.part == .outline }!
        #expect(doc.setOutlineEnabled(layerIDs: outline.switchIDs, on: false) == 2)
        #expect(!doc.layer(id: box.id)!.hasOutline)
        #expect(!doc.layer(id: shot.id)!.hasOutline)
    }

    @Test func oneWidthReachesBothKindsOfLine() {
        let box = shape(.rectangle, fillHex: "#00FF00")
        let shot = picture(style: border(2))
        var doc = document([box, shot])
        #expect(doc.outlineWidthReading(layerIDs: [box.id, shot.id]).isMixed)
        #expect(doc.setRingWidth(layerIDs: [box.id, shot.id], to: 6) == 2)
        #expect(doc.layer(id: box.id)?.annotation?.strokeWidth == 6)
        #expect(doc.layer(id: shot.id)?.style.borderWidth == 6)
        let reading = doc.outlineWidthReading(layerIDs: [box.id, shot.id])
        #expect(!reading.isMixed)
        #expect(reading.value == 6)
    }

    @Test func aLockedLayerKeepsItsLineWhateverTheWidthRowDoes() {
        let box = shape(.rectangle, fillHex: "#00FF00", locked: true)
        var doc = document([box])
        #expect(doc.setRingWidth(layerIDs: [box.id], to: 9) == 0)
    }

    @Test func aTextBlockPickedWithABoxAlsoGetsOneOutline() throws {
        // The same duplicate, one layer kind over: a caption wears a ring the
        // way a picture does.
        let box = shape(.rectangle, fillHex: "#00FF00")
        let caption = Layer(name: "Caption",
                            content: .text(TextContent(string: "Hi")),
                            frame: CGRect(x: 0, y: 0, width: 80, height: 20),
                            style: border(1))
        let doc = document([box, caption])
        let rows = doc.layerPartRows(layerIDs: [box.id, caption.id])
        #expect(rows.filter { $0.title == "Outline" }.count == 1)
        // Fill, Outline, Text: the order the parts list documents, with any
        // shadows somebody added coming under them.
        #expect(rows.map(\.title) == ["Fill", "Outline", "Text"])
    }

    @Test func aLoneTextBlockGetsItsInkAndTheRingItCanWear() {
        let caption = Layer(name: "Caption",
                            content: .text(TextContent(string: "Hi")),
                            frame: CGRect(x: 0, y: 0, width: 80, height: 20))
        let doc = document([caption])
        // Outline sits where the parts list says it sits, above Text, so it
        // never moves when a shape joins the selection. It used to sit below,
        // which meant picking a box beside a caption reordered the panel.
        #expect(doc.layerPartRows(layerIDs: [caption.id]).map(\.title)
                == ["Outline", "Text"])
    }

    @Test func aLoneArrowIsStillJustAColor() {
        let arrow = shape(.arrow)
        let doc = document([arrow])
        #expect(doc.layerPartRows(layerIDs: [arrow.id]).map(\.title) == ["Color"])
    }

    @Test func anEllipseStillGetsFillAndOutline() {
        let oval = shape(.ellipse, fillHex: "#00FF00")
        let doc = document([oval])
        let rows = doc.layerPartRows(layerIDs: [oval.id])
        #expect(rows.map(\.title) == ["Fill", "Outline"])
        #expect(rows[1].slot == .stroke)
        #expect(rows[1].widthIDs == [oval.id])
    }

    @Test func nothingIsCalledABorderAnyMore() {
        let shot = picture(style: border(3))
        let doc = document([shot])
        let titles = doc.layerPartRows(layerIDs: [shot.id]).map(\.title)
        #expect(!titles.contains("Border"))
    }

    @Test func aSwitchReadsOffUntilEveryLayerItReachesHasThePart() throws {
        let outlined = shape(.rectangle)
        let plain = shape(.rectangle, strokeWidth: 0, fillHex: "#00FF00")
        let doc = document([outlined, plain])
        let rows = doc.layerPartRows(layerIDs: [outlined.id, plain.id])
        let outline = try #require(rows.first { $0.slot == .stroke })
        #expect(outline.onCount == 1)
        #expect(!outline.isOn)
    }

    @Test func aRowWhosePickedLayersDisagreeSaysMixedRatherThanReadingOff() throws {
        let outlined = shape(.rectangle)
        let plain = shape(.rectangle, strokeWidth: 0, fillHex: "#00FF00")
        let doc = document([outlined, plain])
        let rows = doc.layerPartRows(layerIDs: [outlined.id, plain.id])
        let outline = try #require(rows.first { $0.slot == .stroke })
        #expect(outline.isMixed)
        // And it says how many, in words, because the switch saying Mixed does
        // not say which of them already have the part.
        #expect(outline.reachNote
                == "1 of the 2 selected layers has an outline. "
                + "Switching this on gives the rest one too.")
    }

    @Test func aRowWhosePickedLayersAgreeIsNeverMixed() throws {
        let a = shape(.rectangle, fillHex: "#00FF00")
        let b = shape(.rectangle, fillHex: "#0000FF")
        let doc = document([a, b])
        let rows = doc.layerPartRows(layerIDs: [a.id, b.id])
        // Both outlined, both filled, neither shadowed: nothing to disagree
        // about anywhere in the list.
        #expect(rows.allSatisfy { !$0.isMixed })
        #expect(rows.allSatisfy { $0.reachNote == nil })
        // One layer has nothing to disagree with either.
        #expect(doc.layerPartRows(layerIDs: [a.id]).allSatisfy { !$0.isMixed })
    }

    @Test func aRowThatBothSkipsALayerAndDisagreesSaysBoth() throws {
        let filled = shape(.rectangle, fillHex: "#00FF00")
        let hollow = shape(.rectangle)
        let arrow = shape(.arrow)
        let doc = document([filled, hollow, arrow])
        let rows = doc.layerPartRows(layerIDs: [filled.id, hollow.id, arrow.id])
        let fill = try #require(rows.first { $0.slot == .fill })
        // An arrow has no inside, so the row skips it; of the two it does
        // reach, one is filled and one is not. Both are true and both are said.
        #expect(fill.isMixed)
        #expect(fill.reachNote
                == "Applies to 2 of the 3 selected layers. "
                + "1 of those has a fill. Switching this on gives the rest one too.")
    }

    @Test func aRowThatSkipsALayerWithoutDisagreeingStillSaysOnlyThat() throws {
        let hollow = shape(.rectangle)
        let alsoHollow = shape(.rectangle)
        let arrow = shape(.arrow)
        let doc = document([hollow, alsoHollow, arrow])
        let rows = doc.layerPartRows(layerIDs: [hollow.id, alsoHollow.id, arrow.id])
        let fill = try #require(rows.first { $0.slot == .fill })
        // Neither box is filled, so there is nothing to disagree about: a row
        // that goes on to explain a disagreement nobody has is noise.
        #expect(!fill.isMixed)
        #expect(fill.reachNote == "Applies to 2 of the 3 selected layers.")
    }

    @Test func aShadowIsNotAPartOfTheShapeAtAll() throws {
        var shadowed = picture()
        shadowed.style.shadow = ShadowStyle()
        let plain = picture()
        let doc = document([shadowed, plain, picture()])
        // Appearance is what a shape simply HAS, and a shadow is something you
        // added, so it is not here: it is an entry in the Effects list below
        // (the user's split, 2026-09-07).
        let rows = doc.layerPartRows(layerIDs: doc.layers.map(\.id))
        #expect(rows.allSatisfy { $0.part != .shadow })
        // ...and the row it does have there speaks for the one picture that
        // has a first shadow, and says so, because rows line up by POSITION.
        let effects = doc.layerEffectRows(layerIDs: doc.layers.map(\.id))
        let shadow = try #require(effects.first { $0.kind == .shadow })
        #expect(shadow.switchIDs == [shadowed.id])
        #expect(shadow.reachNote == "Applies to 1 of the 3 selected layers.")
    }

    @Test func aLockedLayerIsLeftOutOfEveryRow() {
        let box = shape(.rectangle, locked: true)
        let doc = document([box])
        #expect(doc.layerPartRows(layerIDs: [box.id]).isEmpty)
    }

    @Test func aRowSaysWhenItLeavesAPickedLayerOut() throws {
        let box = shape(.rectangle, fillHex: "#00FF00")
        let arrow = shape(.arrow)
        let doc = document([box, arrow])
        let rows = doc.layerPartRows(layerIDs: [box.id, arrow.id])
        let fill = try #require(rows.first { $0.slot == .fill })
        #expect(fill.reachNote == "Applies to 1 of the 2 selected layers.")
        // Neither has a shadow yet, so there is no Shadow row to say anything.
        #expect(rows.contains { $0.part == .shadow } == false)
    }

    // MARK: - Switching the outline off, which could not be done at all

    @Test func aRectanglesOutlineComesOffAndItsColorIsKept() {
        let box = shape(.rectangle, fillHex: "#00FF00")
        var doc = document([box])
        #expect(doc.setOutlineEnabled(layerIDs: [box.id], on: false) == 1)
        let after = doc.layer(id: box.id)!
        #expect(!after.hasOutline)
        #expect(after.annotation?.strokeWidth == 0)
        // The colour is exactly where it was, so switching back on brings the
        // same ring back rather than a black one.
        #expect(after.annotation?.colorHex == "#FF0000")
    }

    @Test func switchingItBackOnRestoresTheWidthThePanelRemembers() {
        let box = shape(.rectangle, strokeWidth: 12, fillHex: "#00FF00")
        var doc = document([box])
        doc.setOutlineEnabled(layerIDs: [box.id], on: false)
        doc.setOutlineEnabled(layerIDs: [box.id], on: true, restoring: [box.id: 12])
        #expect(doc.layer(id: box.id)?.annotation?.strokeWidth == 12)
    }

    @Test func withNothingRememberedItComesBackAtTheWidthAFreshOneWears() {
        let box = shape(.rectangle, strokeWidth: 0, fillHex: "#00FF00")
        var doc = document([box])
        doc.setOutlineEnabled(layerIDs: [box.id], on: true)
        #expect(doc.layer(id: box.id)?.annotation?.strokeWidth == AnnotationContent.defaultStrokeWidth)
    }

    @Test func aPicturesRingIsTheSameSwitch() {
        let shot = picture()
        var doc = document([shot])
        #expect(doc.setOutlineEnabled(layerIDs: [shot.id], on: true) == 1)
        #expect(doc.layer(id: shot.id)!.style.borderWidth > 0)
        #expect(doc.setOutlineEnabled(layerIDs: [shot.id], on: false) == 1)
        #expect(doc.layer(id: shot.id)!.style.borderWidth == 0)
    }

    @Test func anArrowRefusesToLoseItsLineAndSaysSoByChangingNothing() {
        let arrow = shape(.arrow)
        var doc = document([arrow])
        #expect(doc.setOutlineEnabled(layerIDs: [arrow.id], on: false) == 0)
        #expect(doc.layer(id: arrow.id)?.annotation?.strokeWidth == 4)
    }

    @Test func aLockedLayerIsNeverSwitched() {
        let box = shape(.rectangle, fillHex: "#00FF00", locked: true)
        var doc = document([box])
        #expect(doc.setOutlineEnabled(layerIDs: [box.id], on: false) == 0)
    }

    @Test func switchingOnWhatIsAlreadyOnChangesNothing() {
        let box = shape(.rectangle)
        var doc = document([box])
        #expect(doc.setOutlineEnabled(layerIDs: [box.id], on: true) == 0)
    }

    @Test func oneSwitchReachesEveryPickedShape() {
        let a = shape(.rectangle, fillHex: "#00FF00")
        let b = shape(.ellipse, fillHex: "#0000FF")
        var doc = document([a, b])
        #expect(doc.setOutlineEnabled(layerIDs: [a.id, b.id], on: false) == 2)
        #expect(doc.layer(id: a.id)!.hasOutline == false)
        #expect(doc.layer(id: b.id)!.hasOutline == false)
    }

    // MARK: - Finding the row that paints one kind of colour

    /// Naming a colour by the kind it is — a menu command, a keyboard step —
    /// has to land on the row a person can actually see. The Appearance list
    /// builds each row knowing WHICH picked layers wear which colour, so the
    /// kind on its own no longer addresses anything: this is the lookup that
    /// turns one back into the other.
    @Test func theRowThatPaintsAKindOfColourIsTheOneOnScreen() {
        let box = shape(.rectangle, fillHex: "#00FF00")
        let doc = document([box])
        let fill = doc.layerPartRow(layerIDs: [box.id], slot: .fill)
        #expect(fill?.title == LayerPart.fill.title)
        #expect(fill?.colors == [PartColor(slot: .fill, layerIDs: [box.id])])
    }

    /// A shape and a picture share ONE Outline row, and asking for either kind
    /// of line finds that same row, ring and stroke together. Saving from it
    /// keeps one colour for both, which is what the single row promises.
    @Test func bothKindsOfLineFindTheOneOutlineRow() {
        let box = shape(.rectangle, fillHex: "#00FF00")
        let shot = picture(style: border(2))
        let doc = document([box, shot])
        let byStroke = doc.layerPartRow(layerIDs: [box.id, shot.id], slot: .stroke)
        let byBorder = doc.layerPartRow(layerIDs: [box.id, shot.id], slot: .border)
        #expect(byStroke == byBorder)
        #expect(byStroke?.title == LayerPart.outline.title)
        #expect(byStroke?.colors.map(\.slot) == [.stroke, .border])
    }

    /// A highlight's wash is a stroke colour that is not a line round
    /// anything, so it gets a row of its own. Asking for a stroke finds that
    /// row rather than the Outline row beside it, because that is the row the
    /// wash is on.
    @Test func aWashIsFoundOnItsOwnRowRatherThanTheOutlineRow() {
        let wash = shape(.highlight)
        let box = shape(.rectangle, fillHex: "#00FF00")
        let doc = document([wash, box])
        let row = doc.layerPartRow(layerIDs: [wash.id, box.id], slot: .stroke)
        #expect(row?.part == nil)
        #expect(row?.colors == [PartColor(slot: .stroke, layerIDs: [wash.id])])
    }

    @Test func nothingPaintsAKindOfColourNobodyPicked() {
        let arrow = shape(.arrow)
        let doc = document([arrow])
        #expect(doc.layerPartRow(layerIDs: [arrow.id], slot: .fill) == nil)
    }

    // MARK: - Letting a colour go on a part that is switched off

    /// A box with no line round it showed an Outline row with an off switch
    /// and an EMPTY colour column, so a colour carried over from Fill had
    /// nowhere to land and the only way to a coloured edge was to find the
    /// switch, flip it, and then repaint whatever came back (reported
    /// 2026-09-07). Letting go of a colour on the row is that whole errand in
    /// one move — and one move is one undo.

    @Test func aColourLetGoOnASwitchedOffOutlineGivesTheBoxALineWearingIt() {
        let box = shape(.rectangle, strokeWidth: 0, fillHex: "#00FF00")
        var doc = document([box])
        #expect(doc.turnOnPart(.outline, layerIDs: [box.id], paint: Paint(hex: "#B0184A")) == 1)
        let after = try! #require(doc.layer(id: box.id))
        #expect(after.hasOutline)
        #expect(after.annotation?.strokeWidth == AnnotationContent.defaultStrokeWidth)
        #expect(after.colorHex(for: .stroke) == "#B0184A")
    }

    @Test func theLineComesBackAtTheWidthItWasTakenAwayAt() {
        let box = shape(.rectangle, strokeWidth: 0, fillHex: "#00FF00")
        var doc = document([box])
        doc.turnOnPart(.outline, layerIDs: [box.id], paint: Paint(hex: "#B0184A"),
                       restoring: [box.id: 12])
        #expect(doc.layer(id: box.id)?.annotation?.strokeWidth == 12)
    }

    /// A ring round a picture is the same part, so it takes a colour the same
    /// way — and it has to gain its width first, because a layer with no ring
    /// has no border colour to paint at all.
    @Test func aPicturesRingTakesAColourTheSameWay() {
        let shot = picture()
        var doc = document([shot])
        #expect(doc.turnOnPart(.outline, layerIDs: [shot.id], paint: Paint(hex: "#0A84FF")) == 1)
        let after = try! #require(doc.layer(id: shot.id))
        #expect(after.style.borderWidth > 0)
        #expect(after.colorHex(for: .border) == "#0A84FF")
    }

    @Test func aColourLetGoOnASwitchedOffFillFillsTheBoxWithIt() {
        let box = shape(.rectangle, fillHex: nil)
        var doc = document([box])
        #expect(doc.turnOnPart(.fill, layerIDs: [box.id], paint: Paint(hex: "#B0184A")) == 1)
        // The colour that landed, not the starting colour the switch would
        // have seeded: the person chose one by letting go of it.
        #expect(doc.layer(id: box.id)?.colorHex(for: .fill) == "#B0184A")
    }

    @Test func aColourLetGoOnASwitchedOffShadowGivesItOneInThatColour() {
        let box = shape(.rectangle, fillHex: "#00FF00")
        var doc = document([box])
        #expect(doc.turnOnPart(.shadow, layerIDs: [box.id], paint: Paint(hex: "#0A84FF")) == 1)
        #expect(doc.layer(id: box.id)?.style.shadow?.colorHex == "#0A84FF")
    }

    /// A row where one box is outlined and the other is not shows the word
    /// Mixed and no swatch either, and its switch resolves to ON for all of
    /// them. A colour let go of on it does the same thing: they all end up
    /// wearing it, in one step.
    @Test func aColourOnAMixedRowGivesEveryOneOfThemTheLine() {
        let bare = shape(.rectangle, strokeWidth: 0, fillHex: "#00FF00")
        let lined = shape(.rectangle, strokeWidth: 6, fillHex: "#00FF00")
        var doc = document([bare, lined])
        let row = try! #require(doc.layerPartRows(layerIDs: [bare.id, lined.id])
            .first { $0.part == .outline })
        #expect(row.isMixed)
        #expect(doc.turnOnPart(.outline, layerIDs: row.switchIDs,
                               paint: Paint(hex: "#B0184A")) == 2)
        #expect(doc.layer(id: bare.id)?.hasOutline == true)
        #expect(doc.layer(id: bare.id)?.colorHex(for: .stroke) == "#B0184A")
        // The one that already had a line keeps the width it had and takes the
        // colour, rather than being reset to a fresh one.
        #expect(doc.layer(id: lined.id)?.annotation?.strokeWidth == 6)
        #expect(doc.layer(id: lined.id)?.colorHex(for: .stroke) == "#B0184A")
    }

    @Test func aLockedLayerTakesNoColourThisWayEither() {
        let box = shape(.rectangle, strokeWidth: 0, fillHex: "#00FF00", locked: true)
        var doc = document([box])
        #expect(doc.turnOnPart(.outline, layerIDs: [box.id], paint: Paint(hex: "#B0184A")) == 0)
        #expect(doc.layer(id: box.id)?.hasOutline == false)
    }

    /// An arrow IS its line, so there is no width to switch on: the colour
    /// simply lands on the ink, which is the only thing the row could mean.
    @Test func anArrowJustTakesTheColourBecauseItHasNoLineToSwitchOn() {
        let arrow = shape(.arrow)
        var doc = document([arrow])
        #expect(doc.turnOnPart(.outline, layerIDs: [arrow.id], paint: Paint(hex: "#B0184A")) == 1)
        #expect(doc.layer(id: arrow.id)?.annotation?.strokeWidth == 4)
        #expect(doc.layer(id: arrow.id)?.colorHex(for: .stroke) == "#B0184A")
    }
}
