import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// One Corner Radius row for everything picked.
///
/// A rectangle rounds by curving the outline it draws; a picture rounds by
/// having its corners masked off. Those are two different fields in the model,
/// and the panel used to show a slider for each, side by side, both labelled
/// Corner Radius. This is the one row that stands for both: it reads whichever
/// number is actually rounding each picked layer, and a drag writes back to
/// whichever field rounds it properly.
struct CornerRadiusSelectionTests {

    // MARK: - Fixtures

    private func rectangle(radius: CGFloat = 0, styleRadius: CGFloat = 0,
                           size: CGFloat = 40, locked: Bool = false) -> Layer {
        var content = AnnotationContent(shape: .rectangle, strokeWidth: 3,
                                        start: .zero, end: CGPoint(x: size, y: size))
        content.cornerRadius = radius
        var layer = Layer(name: "Rectangle", content: .annotation(content),
                          frame: CGRect(x: 0, y: 0, width: size, height: size),
                          style: LayerStyle(cornerRadius: styleRadius))
        layer.isLocked = locked
        return layer
    }

    private func picture(styleRadius: CGFloat = 0, size: CGFloat = 40,
                         locked: Bool = false) -> Layer {
        var layer = Layer(name: "Shot", content: .image(ImageRef(pixelSize: CGSize(width: size, height: size))),
                          frame: CGRect(x: 0, y: 0, width: size, height: size),
                          style: LayerStyle(cornerRadius: styleRadius))
        layer.isLocked = locked
        return layer
    }

    private func document(_ layers: [Layer]) -> PhotonzDocument {
        PhotonzDocument(canvasSize: CGSize(width: 400, height: 400), layers: layers)
    }

    // MARK: - What the row reads

    @Test func rectangleReadsTheCurveOnItsOwnOutline() {
        let rect = rectangle(radius: 8)
        let doc = document([rect])
        #expect(doc.cornerRadiusSelection(layerIDs: [rect.id]).reading.value == 8)
    }

    @Test func pictureReadsTheMaskOnItsCorners() {
        let shot = picture(styleRadius: 12)
        let doc = document([shot])
        #expect(doc.cornerRadiusSelection(layerIDs: [shot.id]).reading.value == 12)
    }

    /// The old two-slider state: someone dragged the Effects one over a
    /// rectangle and chopped its corners off. The row tells the truth about
    /// what is on screen rather than reading zero, so the number can be fixed.
    @Test func rectangleRoundedOnlyByTheOldMaskStillReadsThatNumber() {
        let rect = rectangle(radius: 0, styleRadius: 10)
        let doc = document([rect])
        #expect(doc.cornerRadiusSelection(layerIDs: [rect.id]).reading.value == 10)
    }

    @Test func aRectangleAndAPictureAtTheSameRadiusAgree() {
        let rect = rectangle(radius: 8)
        let shot = picture(styleRadius: 8)
        let selection = document([rect, shot]).cornerRadiusSelection(layerIDs: [rect.id, shot.id])
        #expect(selection.reading.value == 8)
        #expect(!selection.reading.isMixed)
    }

    @Test func differentRadiiReadMixed() {
        let rect = rectangle(radius: 8)
        let shot = picture(styleRadius: 12)
        let selection = document([rect, shot]).cornerRadiusSelection(layerIDs: [rect.id, shot.id])
        #expect(selection.reading.isMixed)
    }

    /// The knob stops at the biggest picked layer's fully round, so a small box
    /// in the selection cannot stop a big one going round.
    @Test func theKnobStopsAtTheBiggestPickedLayersFullyRound() {
        let small = rectangle(size: 40)
        let big = picture(size: 200)
        let selection = document([small, big]).cornerRadiusSelection(layerIDs: [small.id, big.id])
        #expect(selection.limit == 100)
    }

    @Test func lockedLayersAreLeftOutAndTheRowSaysSo() {
        let rect = rectangle(radius: 8)
        let locked = picture(styleRadius: 4, locked: true)
        let selection = document([rect, locked]).cornerRadiusSelection(layerIDs: [rect.id, locked.id])
        #expect(selection.layerIDs == [rect.id])
        #expect(selection.note == "Applies to 1 of the 2 selected layers.")
    }

    @Test func aRowReachingEverythingSaysNothing() {
        let rect = rectangle(radius: 8)
        let shot = picture(styleRadius: 8)
        let selection = document([rect, shot]).cornerRadiusSelection(layerIDs: [rect.id, shot.id])
        #expect(selection.note == nil)
    }

    // MARK: - What a drag writes

    @Test func oneDragRoundsTheOutlineAndMasksThePicture() {
        let rect = rectangle()
        let shot = picture()
        var doc = document([rect, shot])
        #expect(doc.setCornerRadius(layerIDs: [rect.id, shot.id], to: 9) == 2)
        #expect(doc.layer(id: rect.id)?.annotation?.cornerRadius == 9)
        #expect(doc.layer(id: shot.id)?.style.cornerRadius == 9)
    }

    /// Rounding a rectangle takes the old mask off with it: two radii fighting
    /// each other is exactly the state this row exists to end.
    @Test func roundingARectangleClearsTheMaskThatUsedToChopItsCorners() {
        let rect = rectangle(radius: 0, styleRadius: 10)
        var doc = document([rect])
        doc.setCornerRadius(layerIDs: [rect.id], to: 6)
        #expect(doc.layer(id: rect.id)?.annotation?.cornerRadius == 6)
        #expect(doc.layer(id: rect.id)?.style.cornerRadius == 0)
    }

    @Test func aDragNeverReachesALockedLayer() {
        let locked = picture(styleRadius: 4, locked: true)
        var doc = document([locked])
        #expect(doc.setCornerRadius(layerIDs: [locked.id], to: 9) == 0)
        #expect(doc.layer(id: locked.id)?.style.cornerRadius == 4)
    }

    @Test func aNegativeRadiusLandsAsSquareCorners() {
        let shot = picture(styleRadius: 8)
        var doc = document([shot])
        doc.setCornerRadius(layerIDs: [shot.id], to: -3)
        #expect(doc.layer(id: shot.id)?.style.cornerRadius == 0)
    }

    /// An arrow or a line has no corners of its own to curve, so it rounds the
    /// only way it can: the mask, same as a picture.
    @Test func aShapeWithNoCornersOfItsOwnRoundsLikeAPicture() {
        var content = AnnotationContent(shape: .arrow, strokeWidth: 3,
                                        start: .zero, end: CGPoint(x: 40, y: 40))
        content.cornerRadius = 0
        let arrow = Layer(name: "Arrow", content: .annotation(content),
                          frame: CGRect(x: 0, y: 0, width: 40, height: 40))
        var doc = document([arrow])
        doc.setCornerRadius(layerIDs: [arrow.id], to: 5)
        #expect(doc.layer(id: arrow.id)?.style.cornerRadius == 5)
        #expect(doc.layer(id: arrow.id)?.annotation?.cornerRadius == 0)
    }

    // MARK: - The row it replaces

    /// The shape section no longer carries a Corner Radius of its own: there is
    /// one row for it now, and it is the one that speaks for the whole
    /// selection. A rectangle's own section is down to its thickness.
    @Test func theShapeSectionNoLongerOffersItsOwnCornerRadius() {
        let rect = rectangle()
        let doc = document([rect])
        #expect(doc.shapeSelection(layerIDs: [rect.id]).rows == [.thickness])
    }
}
