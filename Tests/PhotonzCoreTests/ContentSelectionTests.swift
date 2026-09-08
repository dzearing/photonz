import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// The type rows and the shape rows speaking for a whole selection: pick three
/// labels, set the size once, and all three change — the same shape the Color
/// and Effects rows already have.
///
/// The hard part is honesty. Three labels that are all 14pt say 14; three that
/// differ say Mixed. And a selection holding an arrow and a rectangle offers
/// only what BOTH of them have, because a Head Size row over a rectangle is a
/// row that does nothing.
struct ContentSelectionTests {

    // MARK: - Fixtures

    private func label(_ string: String = "Label", font: String = "SF Pro",
                       size: CGFloat = 14, weight: TextWeight = .regular,
                       align: TextAlign? = nil, locked: Bool = false) -> Layer {
        let content = TextContent(string: string, fontName: font, fontSize: size,
                                  weight: weight, alignment: align)
        var layer = Layer(name: string, content: .text(content),
                          frame: CGRect(x: 0, y: 0, width: 80, height: 20))
        layer.isLocked = locked
        return layer
    }

    private func shape(_ kind: AnnotationShape, stroke: CGFloat = 3,
                       arrowhead: CGFloat = 1, radius: CGFloat = 0,
                       caption: String? = nil, captionSize: CGFloat = 20,
                       pinned: Bool = false, locked: Bool = false) -> Layer {
        var content = AnnotationContent(shape: kind, strokeWidth: stroke,
                                        start: .zero, end: CGPoint(x: 40, y: 40))
        content.arrowheadScale = arrowhead
        content.cornerRadius = radius
        content.caption = caption
        content.captionFontSize = captionSize
        content.captionPinned = pinned
        var layer = Layer(name: kind.title, content: .annotation(content),
                          frame: CGRect(x: 0, y: 0, width: 40, height: 40))
        layer.isLocked = locked
        return layer
    }

    private func document(_ layers: [Layer]) -> PhotonzDocument {
        PhotonzDocument(canvasSize: CGSize(width: 400, height: 400), layers: layers)
    }

    // MARK: - What a type row reads

    @Test func labelsSharingASizeReadThatSize() {
        let doc = document([label(size: 14), label(size: 14)])
        let selection = doc.textSelection(layerIDs: doc.layers.map(\.id))
        #expect(selection.count == 2)
        let reading = selection.number { $0.fontSize }
        #expect(reading.value == 14)
        #expect(!reading.isMixed)
    }

    @Test func labelsThatDifferReadMixed() {
        let doc = document([label(size: 14), label(size: 24)])
        let reading = doc.textSelection(layerIDs: doc.layers.map(\.id)).number { $0.fontSize }
        #expect(reading.isMixed)
        // The menu still has to open somewhere: the first picked layer's.
        #expect(reading.value == 14)
    }

    @Test func fontsAndWeightsReadTheSameWay() {
        let doc = document([label(font: "SF Pro", weight: .bold),
                            label(font: "Menlo", weight: .bold)])
        let selection = doc.textSelection(layerIDs: doc.layers.map(\.id))
        #expect(selection.reading { $0.fontName }.isMixed)
        #expect(selection.reading { $0.weight }.value == .bold)
        #expect(!selection.reading { $0.weight }.isMixed)
    }

    @Test func alignmentReadsTheOneThatIsDrawnNotTheOneThatIsStored() {
        // Nil means the left edge, which is where text has always started. Two
        // labels, one stored nil and one stored left, are drawn the same way,
        // so the row must not call them Mixed.
        let doc = document([label(align: nil), label(align: .left)])
        let selection = doc.textSelection(layerIDs: doc.layers.map(\.id))
        #expect(!selection.reading { $0.usedAlignment }.isMixed)
        #expect(selection.reading { $0.usedAlignment }.value == .left)
    }

    @Test func oneLabelIsNeverMixed() {
        let doc = document([label(size: 32)])
        #expect(doc.textSelection(layerIDs: doc.layers.map(\.id)).number { $0.fontSize }.value == 32)
        #expect(!doc.textSelection(layerIDs: doc.layers.map(\.id)).number { $0.fontSize }.isMixed)
    }

    // MARK: - Who the type rows reach

    @Test func onlyTheTextLayersAreCounted() {
        let doc = document([label(), shape(.rectangle), label()])
        let selection = doc.textSelection(layerIDs: doc.layers.map(\.id))
        #expect(selection.count == 2)
        #expect(selection.selectionCount == 3)
        #expect(selection.note == "Applies to 2 of the 3 selected layers.")
    }

    @Test func aLockedLabelIsLeftAlone() {
        let doc = document([label(size: 14), label(size: 40, locked: true)])
        let selection = doc.textSelection(layerIDs: doc.layers.map(\.id))
        #expect(selection.count == 1)
        #expect(!selection.number { $0.fontSize }.isMixed)
    }

    @Test func reachingEverythingSaysNothing() {
        let doc = document([label(), label()])
        #expect(doc.textSelection(layerIDs: doc.layers.map(\.id)).note == nil)
    }

    @Test func theMenuOffersEverySizeThePickedLabelsWear() {
        let doc = document([label(size: 14), label(size: 37), label(size: 14)])
        let selection = doc.textSelection(layerIDs: doc.layers.map(\.id))
        #expect(selection.fontSizes == [14, 37])
        #expect(selection.fontNames == ["SF Pro"])
    }

    // MARK: - Which shape rows a selection offers

    /// Corners are not here: rounding lives in the one Corner Radius row that
    /// speaks for everything picked (see `CornerRadiusSelectionTests`).
    @Test func oneRectangleOffersItsThickness() {
        let doc = document([shape(.rectangle)])
        let rows = doc.shapeSelection(layerIDs: doc.layers.map(\.id)).rows
        #expect(rows == [.thickness])
    }

    @Test func oneArrowOffersThicknessCaptionAndHead() {
        let doc = document([shape(.arrow)])
        let rows = doc.shapeSelection(layerIDs: doc.layers.map(\.id)).rows
        #expect(rows == [.thickness, .caption, .headStyle, .headSize])
    }

    @Test func anArrowWithACaptionOffersItsLabelSize() {
        let doc = document([shape(.arrow, caption: "Login")])
        let rows = doc.shapeSelection(layerIDs: doc.layers.map(\.id)).rows
        #expect(rows.contains(.labelSize))
    }

    @Test func twoArrowsOfferWhatBothHave() {
        let doc = document([shape(.arrow, caption: "One"), shape(.arrow, caption: "Two")])
        let rows = doc.shapeSelection(layerIDs: doc.layers.map(\.id)).rows
        #expect(rows == [.thickness, .labelSize, .labelCorners, .headStyle, .headSize])
    }

    @Test func aCaptionIsNotOfferedOverMoreThanOneArrow() {
        // A caption is what the arrow SAYS, not how it looks. One field over
        // three arrows could only give all three the same words.
        let doc = document([shape(.arrow, caption: "One"), shape(.arrow, caption: "Two")])
        #expect(!doc.shapeSelection(layerIDs: doc.layers.map(\.id)).rows.contains(.caption))
    }

    @Test func anArrowAndARectangleOfferOnlyThickness() {
        let doc = document([shape(.arrow), shape(.rectangle)])
        let rows = doc.shapeSelection(layerIDs: doc.layers.map(\.id)).rows
        #expect(rows == [.thickness])
    }

    @Test func aHighlightBringsNoSettingsOfItsOwn() {
        let doc = document([shape(.highlight)])
        #expect(doc.shapeSelection(layerIDs: doc.layers.map(\.id)).rows.isEmpty)
    }

    @Test func aHighlightPickedWithABoxDoesNotTakeTheBoxesRowsAway() {
        // A highlight has no settings besides its color, so it sits the section
        // out rather than emptying it — the way an unshadowed layer sits the
        // shadow rows out.
        let doc = document([shape(.rectangle), shape(.highlight)])
        let selection = doc.shapeSelection(layerIDs: doc.layers.map(\.id))
        #expect(selection.rows == [.thickness])
        #expect(selection.count == 1)
        #expect(selection.note == "Applies to 1 of the 2 selected layers.")
    }

    // MARK: - What a shape row reads

    @Test func shapesSharingAThicknessReadIt() {
        let doc = document([shape(.rectangle, stroke: 6), shape(.arrow, stroke: 6)])
        // Read through `outlineWidth`, which finds each shape's line wherever
        // it lives: an arrow's stroke, a box's Border (`OutlineRetirementTests`).
        let reading = doc.shapeSelection(layerIDs: doc.layers.map(\.id)).outlineWidth
        #expect(reading.value == 6)
        #expect(!reading.isMixed)
    }

    @Test func shapesThatDifferReadMixed() {
        let doc = document([shape(.rectangle, stroke: 2), shape(.rectangle, stroke: 8)])
        #expect(doc.shapeSelection(layerIDs: doc.layers.map(\.id)).outlineWidth.isMixed)
    }

    @Test func aLockedShapeIsLeftAlone() {
        let doc = document([shape(.rectangle, stroke: 2), shape(.rectangle, stroke: 8, locked: true)])
        let selection = doc.shapeSelection(layerIDs: doc.layers.map(\.id))
        #expect(selection.count == 1)
        #expect(selection.outlineWidth.value == 2)
    }

    // MARK: - Where the line's width lives

    @Test func aShapeWhoseLineCanBeSwitchedOffKeepsItsWidthInThatPart() {
        // A box and an ellipse have an inside, so the outline is a part with a
        // switch, and its width is that part's own setting.
        let doc = document([shape(.rectangle)])
        #expect(doc.shapeSelection(layerIDs: doc.layers.map(\.id)).widthIsAnOutlineSetting)
        let round = document([shape(.ellipse)])
        #expect(round.shapeSelection(layerIDs: round.layers.map(\.id)).widthIsAnOutlineSetting)
    }

    @Test func anArrowsWidthHasNowhereToHideSoItIsTheShapesOwnThickness() {
        // An arrow IS its line: there is no switch, so no drawer, so the
        // thickness has to be one of the shape's own settings, beside the
        // ending and the head size. Raised on 2026-09-06: making an arrow
        // thicker took three moves through a row called Color.
        for kind in [AnnotationShape.arrow, .line] {
            let doc = document([shape(kind)])
            #expect(!doc.shapeSelection(layerIDs: doc.layers.map(\.id)).widthIsAnOutlineSetting)
        }
    }

    @Test func anArrowPickedWithABoxFollowsTheBox() {
        // One Outline row speaks for both and it switches, so the width is in
        // there reaching both, and the shape section does not offer a second
        // control for the same number.
        let doc = document([shape(.rectangle), shape(.arrow)])
        #expect(doc.shapeSelection(layerIDs: doc.layers.map(\.id)).widthIsAnOutlineSetting)
    }

    // MARK: - What the section is called

    @Test func aSectionOfOneShapeIsNamedAfterIt() {
        let doc = document([shape(.rectangle)])
        #expect(doc.shapeSelection(layerIDs: doc.layers.map(\.id)).title == "Rectangle")
    }

    @Test func aSectionOfSeveralOfOneShapeSaysSo() {
        let doc = document([shape(.ellipse), shape(.ellipse)])
        #expect(doc.shapeSelection(layerIDs: doc.layers.map(\.id)).title == "Ellipses")
    }

    @Test func aSectionOfDifferentShapesIsJustShapes() {
        let doc = document([shape(.arrow), shape(.rectangle)])
        #expect(doc.shapeSelection(layerIDs: doc.layers.map(\.id)).title == "Shapes")
    }

    // MARK: - The label pills a hand has moved

    @Test func onlyThePinnedLabelsCanBePutBack() {
        let doc = document([shape(.arrow, caption: "a", pinned: true),
                            shape(.arrow, caption: "b"),
                            shape(.arrow, caption: "c", pinned: true)])
        let selection = doc.shapeSelection(layerIDs: doc.layers.map(\.id))
        #expect(selection.pinnedCaptionIDs.count == 2)
        #expect(selection.pinnedCaptionIDs == [doc.layers[0].id, doc.layers[2].id])
    }
}
