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




    // MARK: - The rows a selection gets

    @Test func aRectangleGetsFillAndNothingElse() {
        let box = shape(.rectangle, fillHex: "#00FF00")
        let doc = document([box])
        let rows = doc.layerPartRows(layerIDs: [box.id])
        // A shadow is countable, so it is not a fixed row that is off nearly
        // all the time: it arrives from the plus at the foot of the list
        // (`AppearanceListTests`). Nor is the box's edge here any more — it is
        // a Border in that same list (`OutlineRetirementTests`).
        #expect(rows.map(\.title) == ["Fill"])
        #expect(rows.map(\.hasSwitch) == [true])
        #expect(rows[0].isOn)
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





    // MARK: - A highlight, which was offered the same name twice


    @Test func aHighlightsWashIsAColorRatherThanAnOutline() {
        // A highlight IS its wash, the way an arrow is its line: there is no
        // switching it off, and the stroke width it carries is never painted.
        let wash = shape(.highlight)
        let doc = document([wash])
        let rows = doc.layerPartRows(layerIDs: [wash.id])
        #expect(rows.map(\.title) == ["Color"])
        let ink = rows[0]
        #expect(ink.slot == .stroke)
        #expect(ink.part == nil)
        #expect(!ink.hasSwitch)
    }



    // MARK: - Two kinds of line picked together, which was two rows called Outline






    @Test func aTextBlockPickedWithABoxGetsTheirTwoColours() throws {
        let box = shape(.rectangle, fillHex: "#00FF00")
        let caption = Layer(name: "Caption",
                            content: .text(TextContent(string: "Hi")),
                            frame: CGRect(x: 0, y: 0, width: 80, height: 20),
                            style: border(1))
        let doc = document([box, caption])
        let rows = doc.layerPartRows(layerIDs: [box.id, caption.id])
        // No Outline row on either of them: a box's edge and a label's are both
        // Borders in the Effects list (`OutlineRetirementTests`).
        #expect(rows.map(\.title) == ["Fill", "Text"])
    }

    @Test func aLoneTextBlockGetsItsInk() {
        let caption = Layer(name: "Caption",
                            content: .text(TextContent(string: "Hi")),
                            frame: CGRect(x: 0, y: 0, width: 80, height: 20))
        let doc = document([caption])
        #expect(doc.layerPartRows(layerIDs: [caption.id]).map(\.title) == ["Text"])
    }

    @Test func aLoneArrowIsStillJustAColor() {
        let arrow = shape(.arrow)
        let doc = document([arrow])
        #expect(doc.layerPartRows(layerIDs: [arrow.id]).map(\.title) == ["Color"])
    }

    @Test func anEllipseStillGetsItsFill() {
        let oval = shape(.ellipse, fillHex: "#00FF00")
        let doc = document([oval])
        #expect(doc.layerPartRows(layerIDs: [oval.id]).map(\.title) == ["Fill"])
    }

    @Test func nothingIsCalledABorderAnyMore() {
        let shot = picture(style: border(3))
        let doc = document([shot])
        let titles = doc.layerPartRows(layerIDs: [shot.id]).map(\.title)
        #expect(!titles.contains("Border"))
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



}
