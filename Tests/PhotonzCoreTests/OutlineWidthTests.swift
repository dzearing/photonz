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

    @Test func onlyALineAndAnArrowAreTheirOwnStroke() {
        // A box and an oval wear a ring like everything else does: their edge
        // is a Border in the Effects list (`OutlineRetirementTests`). A line and
        // an arrow ARE their stroke, so theirs stays where it was.
        for shape in [AnnotationShape.line, .arrow] {
            let layer = Layer(name: "S", content: .annotation(AnnotationContent(shape: shape)),
                              frame: CGRect(x: 0, y: 0, width: 10, height: 10))
            #expect(layer.drawsItsOwnOutline, "\(shape) IS its stroke")
        }
        for shape in [AnnotationShape.rectangle, .ellipse, .highlight] {
            let layer = Layer(name: "S", content: .annotation(AnnotationContent(shape: shape)),
                              frame: CGRect(x: 0, y: 0, width: 10, height: 10))
            #expect(!layer.drawsItsOwnOutline, "\(shape) wears a ring")
        }
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
        // On the box's edge, which is a Border in its Effects list.
        #expect(doc.layer(id: a.id)?.style.borderWidth == 5)
        #expect(doc.layer(id: b.id)?.style.borderWidth == 5)
    }



    @Test func pullingItToZeroTakesTheOutlineOffAltogether() {
        let box = rectangle(strokeWidth: 0, style: border(6))
        var doc = document([box])
        doc.setOutlineWidth(layerIDs: [box.id], to: 0)
        #expect(doc.layer(id: box.id)?.style.borderWidth == 0)
    }

    @Test func aLockedShapeIsLeftExactlyAsItIs() {
        let box = rectangle(strokeWidth: 3, locked: true)
        var doc = document([box])
        #expect(doc.setOutlineWidth(layerIDs: [box.id], to: 9) == 0)
        #expect(doc.layer(id: box.id)?.style.borderWidth == 3)
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

    // MARK: - A path drawn with the Pen

    private func pen(strokeWidth: CGFloat = 4, locked: Bool = false,
                     closed: Bool = false) -> Layer {
        let content = PathContent(anchors: [PathAnchor(point: .zero),
                                            PathAnchor(point: CGPoint(x: 40, y: 0)),
                                            PathAnchor(point: CGPoint(x: 40, y: 30))],
                                  isClosed: closed,
                                  strokeWidth: strokeWidth)
        var layer = Layer(name: "Path", content: .path(content),
                          frame: CGRect(x: 0, y: 0, width: 40, height: 30))
        layer.isLocked = locked
        return layer
    }

    private func line(strokeWidth: CGFloat) -> Layer {
        Layer(name: "Line",
              content: .annotation(AnnotationContent(shape: .line, strokeWidth: strokeWidth,
                                                     start: .zero, end: CGPoint(x: 50, y: 0))),
              frame: CGRect(x: 0, y: 0, width: 50, height: 1))
    }

    @Test func aPathHasALineOfItsOwnToSet() {
        // Its stroke IS the drawing: a ring round its box would be a rectangle
        // round something that is not one.
        #expect(pen().hasOutlineThickness)
        #expect(pen().drawsItsOwnOutline)
    }

    @Test func theThicknessRowReadsThePathsOwnWeight() {
        let path = pen(strokeWidth: 4)
        let doc = document([path])
        #expect(doc.outlineThicknessSelection(layerIDs: [path.id]).reading.value == 4)
    }

    @Test func itReadsTheThinnerWeightAPathOnAnIconFrameArrivesAt() {
        // A 24 pixel icon frame starts a path at one point, not four
        // (`IconStrokeWeight`). The row has to show that, not the tool default.
        let path = pen(strokeWidth: 1)
        let doc = document([path])
        #expect(doc.outlineThicknessSelection(layerIDs: [path.id]).reading.value == 1)
    }

    @Test func twoPathsThatDisagreeReadMixed() {
        let a = pen(strokeWidth: 2)
        let b = pen(strokeWidth: 8)
        let doc = document([a, b])
        #expect(doc.outlineThicknessSelection(layerIDs: [a.id, b.id]).reading.isMixed)
    }

    @Test func onePullSetsTheWeightOnEveryPickedPath() {
        let a = pen(strokeWidth: 2)
        let b = pen(strokeWidth: 8)
        var doc = document([a, b])
        #expect(doc.setOutlineWidth(layerIDs: [a.id, b.id], to: 5) == 2)
        #expect(doc.layer(id: a.id)?.path?.strokeWidth == 5)
        #expect(doc.layer(id: b.id)?.path?.strokeWidth == 5)
    }

    @Test func aPathAndALinePickedTogetherTakeOnePull() {
        let path = pen(strokeWidth: 2)
        let stroke = line(strokeWidth: 2)
        var doc = document([path, stroke])
        let selection = doc.outlineThicknessSelection(layerIDs: [path.id, stroke.id])
        #expect(selection.layerIDs == [path.id, stroke.id])
        #expect(selection.reading.value == 2)
        #expect(doc.setOutlineWidth(layerIDs: selection.layerIDs, to: 6) == 2)
        #expect(doc.layer(id: path.id)?.path?.strokeWidth == 6)
        #expect(doc.layer(id: stroke.id)?.annotation?.strokeWidth == 6)
    }

    @Test func aLockedPathIsLeftExactlyAsItIs() {
        let path = pen(strokeWidth: 3, locked: true)
        var doc = document([path])
        #expect(doc.outlineThicknessSelection(layerIDs: [path.id]).isEmpty)
        #expect(doc.setOutlineWidth(layerIDs: [path.id], to: 9) == 0)
        #expect(doc.layer(id: path.id)?.path?.strokeWidth == 3)
    }

    @Test func aWidthBelowZeroIsClampedOnAPathToo() {
        let path = pen(strokeWidth: 3)
        var doc = document([path])
        doc.setOutlineWidth(layerIDs: [path.id], to: -3)
        #expect(doc.layer(id: path.id)?.path?.strokeWidth == 0)
    }

    @Test func aPathKeepsTheColourItsLineIsDrawnIn() {
        // The row above the slider is the colour. Pulling the weight must not
        // repaint it.
        var content = PathContent(anchors: [PathAnchor(point: .zero),
                                            PathAnchor(point: CGPoint(x: 10, y: 10))])
        content.paint = Paint(hex: "#2D7FF9")
        let path = Layer(name: "Path", content: .path(content),
                         frame: CGRect(x: 0, y: 0, width: 10, height: 10))
        var doc = document([path])
        doc.setOutlineWidth(layerIDs: [path.id], to: 7)
        #expect(doc.layer(id: path.id)?.path?.paint.hex == "#2D7FF9")
    }

    // MARK: - Who else the row reaches, and who it still does not

    @Test func aHighlightIsStillOfferedNoThickness() {
        let mark = Layer(name: "Mark",
                         content: .annotation(AnnotationContent(shape: .highlight)),
                         frame: CGRect(x: 0, y: 0, width: 40, height: 40))
        let doc = document([mark])
        #expect(doc.outlineThicknessSelection(layerIDs: [mark.id]).isEmpty)
    }

    @Test func aPictureIsStillOfferedNoThickness() {
        let picture = Layer(name: "Shot",
                            content: .image(ImageRef(pixelSize: CGSize(width: 40, height: 40))),
                            frame: CGRect(x: 0, y: 0, width: 40, height: 40),
                            style: border(4))
        let doc = document([picture])
        #expect(doc.outlineThicknessSelection(layerIDs: [picture.id]).isEmpty)
    }

    @Test func aBoxStillReadsTheRingItActuallyWears() {
        // The same selection the shape rows have always read, so the one row
        // widening to reach paths cannot change what a box shows.
        let box = rectangle(strokeWidth: 0, style: border(6))
        let doc = document([box])
        #expect(doc.outlineThicknessSelection(layerIDs: [box.id]).reading.value == 6)
    }
}
