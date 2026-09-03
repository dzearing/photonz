import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// ONE width for the line round a shape.
///
/// A rectangle used to offer two: Thickness in its own section and Border under
/// Effects. Both painted the same ring, in different colors, and the border
/// covered the stroke, so the second one silently won. A shape that draws a line
/// round itself now has one control for it, and a picture, a frame or a
/// highlight — which have no line of their own — keeps the Border row.
@Suite("Outline width")
struct OutlineWidthTests {

    private func rectangle(strokeWidth: CGFloat = 4, colorHex: String = "#FF0000",
                           style: LayerStyle = LayerStyle(),
                           locked: Bool = false) -> Layer {
        var layer = Layer(name: "Box",
                          content: .annotation(AnnotationContent(shape: .rectangle,
                                                                 strokeWidth: strokeWidth,
                                                                 colorHex: colorHex,
                                                                 start: .zero,
                                                                 end: CGPoint(x: 100, y: 60))),
                          frame: CGRect(x: 0, y: 0, width: 100, height: 60),
                          style: style)
        layer.isLocked = locked
        return layer
    }

    private func document(_ layers: [Layer]) -> PhotonzDocument {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 400, height: 300))
        for layer in layers { doc.addLayer(layer) }
        return doc
    }

    private func border(_ width: CGFloat, _ hex: String = "#0000FF") -> LayerStyle {
        var style = LayerStyle()
        style.borderWidth = width
        style.borderColorHex = hex
        return style
    }

    // MARK: - Which layers draw their own outline

    @Test func everyShapeButAHighlightDrawsItsOwnOutline() {
        for shape in [AnnotationShape.rectangle, .ellipse, .line, .arrow] {
            let layer = Layer(name: "S", content: .annotation(AnnotationContent(shape: shape)),
                              frame: CGRect(x: 0, y: 0, width: 10, height: 10))
            #expect(layer.drawsItsOwnOutline, "\(shape) draws a line round itself")
        }
        let highlight = Layer(name: "H", content: .annotation(AnnotationContent(shape: .highlight)),
                              frame: CGRect(x: 0, y: 0, width: 10, height: 10))
        #expect(!highlight.drawsItsOwnOutline)
    }

    @Test func aPictureOrAFrameHasNoOutlineOfItsOwn() {
        let picture = Layer(name: "Shot", content: .image(ImageRef(pixelSize: CGSize(width: 40, height: 40))),
                            frame: CGRect(x: 0, y: 0, width: 10, height: 10))
        #expect(!picture.drawsItsOwnOutline)
        let text = Layer(name: "Label", content: .text(TextContent(string: "hi")),
                         frame: CGRect(x: 0, y: 0, width: 10, height: 10))
        #expect(!text.drawsItsOwnOutline)
    }

    // MARK: - The Border row's reach

    @Test func theBorderRowSkipsShapesAndKeepsEverythingElse() {
        let box = rectangle()
        let picture = Layer(name: "Shot", content: .image(ImageRef(pixelSize: CGSize(width: 40, height: 40))),
                            frame: CGRect(x: 0, y: 0, width: 40, height: 40))
        let doc = document([picture, box])
        let selection = doc.layerStyleSelection(layerIDs: [picture.id, box.id])
        #expect(selection.count == 2)
        #expect(selection.borders.layerIDs == [picture.id])
        // And it says out loud that it is leaving one of them out.
        #expect(selection.borders.note == "Applies to 1 of the 2 selected layers.")
    }

    @Test func aLoneRectangleIsOfferedNoBorderRowAtAll() {
        let box = rectangle()
        let doc = document([box])
        #expect(doc.layerStyleSelection(layerIDs: [box.id]).borders.isEmpty)
    }

    @Test func aHighlightStillGetsABorder() {
        let mark = Layer(name: "Mark",
                         content: .annotation(AnnotationContent(shape: .highlight)),
                         frame: CGRect(x: 0, y: 0, width: 40, height: 40))
        let doc = document([mark])
        #expect(doc.layerStyleSelection(layerIDs: [mark.id]).borders.layerIDs == [mark.id])
    }

    // MARK: - What the Thickness row reads

    @Test func thicknessReadsTheShapesOwnStroke() {
        let box = rectangle(strokeWidth: 7)
        let doc = document([box])
        #expect(doc.shapeSelection(layerIDs: [box.id]).outlineWidth.value == 7)
    }

    @Test func thicknessReadsARingLeftBehindByTheOldBorderSlider() {
        // Drawn before this change: no stroke of its own, a 6pt style border.
        let box = rectangle(strokeWidth: 0, style: border(6))
        let doc = document([box])
        let reading = doc.shapeSelection(layerIDs: [box.id]).outlineWidth
        #expect(reading.value == 6)
        #expect(!reading.isMixed)
    }

    @Test func thicknessReadsTheRingYouCanActuallySeeWhenBothAreSet() {
        // The border is drawn over the stroke, so a wider border is the ring.
        let box = rectangle(strokeWidth: 4, style: border(6))
        let doc = document([box])
        #expect(doc.shapeSelection(layerIDs: [box.id]).outlineWidth.value == 6)
        let thick = rectangle(strokeWidth: 9, style: border(3))
        let doc2 = document([thick])
        #expect(doc2.shapeSelection(layerIDs: [thick.id]).outlineWidth.value == 9)
    }

    @Test func twoShapesThatDisagreeReadMixed() {
        let a = rectangle(strokeWidth: 2)
        let b = rectangle(strokeWidth: 8)
        let doc = document([a, b])
        #expect(doc.shapeSelection(layerIDs: [a.id, b.id]).outlineWidth.isMixed)
    }

    // MARK: - What a pull on it does

    @Test func onePullSetsTheStrokeOnEveryPickedShape() {
        let a = rectangle(strokeWidth: 2)
        let b = rectangle(strokeWidth: 8)
        var doc = document([a, b])
        #expect(doc.setOutlineWidth(layerIDs: [a.id, b.id], to: 5) == 2)
        #expect(doc.layer(id: a.id)?.annotation?.strokeWidth == 5)
        #expect(doc.layer(id: b.id)?.annotation?.strokeWidth == 5)
    }

    @Test func aPullFoldsTheOldBorderOntoTheStrokeColorAndAll() {
        let box = rectangle(strokeWidth: 0, colorHex: "#FF0000", style: border(6, "#0000FF"))
        var doc = document([box])
        doc.setOutlineWidth(layerIDs: [box.id], to: 6)
        let after = doc.layer(id: box.id)
        // One ring, and it is the blue one that was on screen.
        #expect(after?.annotation?.strokeWidth == 6)
        #expect(after?.annotation?.colorHex == "#0000FF")
        #expect(after?.style.borderWidth == 0)
    }

    @Test func aStrokeWiderThanTheOldBorderKeepsItsOwnColor() {
        let box = rectangle(strokeWidth: 9, colorHex: "#FF0000", style: border(3, "#0000FF"))
        var doc = document([box])
        doc.setOutlineWidth(layerIDs: [box.id], to: 9)
        #expect(doc.layer(id: box.id)?.annotation?.colorHex == "#FF0000")
        #expect(doc.layer(id: box.id)?.style.borderWidth == 0)
    }

    @Test func pullingItToZeroTakesTheOutlineOffAltogether() {
        let box = rectangle(strokeWidth: 0, style: border(6))
        var doc = document([box])
        doc.setOutlineWidth(layerIDs: [box.id], to: 0)
        #expect(doc.layer(id: box.id)?.annotation?.strokeWidth == 0)
        #expect(doc.layer(id: box.id)?.style.borderWidth == 0)
    }

    @Test func aLockedShapeIsLeftExactlyAsItIs() {
        let box = rectangle(strokeWidth: 3, locked: true)
        var doc = document([box])
        #expect(doc.setOutlineWidth(layerIDs: [box.id], to: 9) == 0)
        #expect(doc.layer(id: box.id)?.annotation?.strokeWidth == 3)
    }

    @Test func aPictureIsNotAnOutlineTheRowCanSet() {
        let picture = Layer(name: "Shot", content: .image(ImageRef(pixelSize: CGSize(width: 40, height: 40))),
                            frame: CGRect(x: 0, y: 0, width: 40, height: 40),
                            style: border(4))
        var doc = document([picture])
        #expect(doc.setOutlineWidth(layerIDs: [picture.id], to: 9) == 0)
        #expect(doc.layer(id: picture.id)?.style.borderWidth == 4)
    }

    @Test func aWidthBelowZeroIsClamped() {
        let box = rectangle()
        var doc = document([box])
        doc.setOutlineWidth(layerIDs: [box.id], to: -3)
        #expect(doc.layer(id: box.id)?.annotation?.strokeWidth == 0)
    }

    /// Nothing is folded until a hand actually moves the row, so a document
    /// that is only opened and looked at renders exactly as it did before.
    @Test func openingADocumentFoldsNothing() {
        let box = rectangle(strokeWidth: 0, style: border(6))
        let doc = document([box])
        _ = doc.shapeSelection(layerIDs: [box.id]).outlineWidth
        #expect(doc.layer(id: box.id)?.style.borderWidth == 6)
        #expect(doc.layer(id: box.id)?.annotation?.strokeWidth == 0)
    }
}
