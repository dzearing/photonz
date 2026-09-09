import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// Rounding a shape's corners one at a time.
///
/// Corner Radius rounded all four by the same amount, so a card with a rounded
/// top and a square bottom, a segmented control with round ends, and a speech
/// bubble could only be faked by laying a second shape over the first. The one
/// number is still the way in; opening it into four is a deliberate act.
@Suite("Per corner radius")
struct PerCornerRadiusTests {

    private let size = CGSize(width: 200, height: 120)
    private let roundedTop = CornerRadii(topLeft: 16, topRight: 16, bottomRight: 0, bottomLeft: 0)

    private func rectangle(_ radii: CornerRadii, stroke: CGFloat = 0) -> Layer {
        var annotation = AnnotationContent(shape: .rectangle, strokeWidth: stroke,
                                           start: .zero,
                                           end: CGPoint(x: size.width, y: size.height),
                                           cornerRadii: radii, fillColorHex: "#FF0000")
        annotation.strokePosition = .inside
        return Layer(name: "Box", content: .annotation(annotation),
                     frame: CGRect(origin: .zero, size: size))
    }

    private func picture(_ radii: CornerRadii) -> Layer {
        var style = LayerStyle()
        style.cornerRadii = radii
        return Layer(name: "Shot", content: .image(ImageRef(id: UUID(), pixelSize: size)),
                     frame: CGRect(origin: .zero, size: size), style: style)
    }

    private func document(_ layers: [Layer]) -> PhotonzDocument {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 400, height: 400))
        for layer in layers { doc.layers.append(layer) }
        return doc
    }

    // MARK: - What the row reads and writes

    @Test("A rectangle rounds its own outline, one corner at a time")
    func rectangleTakesFour() {
        var layer = rectangle(.none)
        layer.setRoundedCorners(roundedTop)
        #expect(layer.annotation?.cornerRadii == roundedTop)
        // The mask is still put to nought, so two radii never fight over one box.
        #expect(!layer.style.cornerRadii.isRound)
        #expect(layer.roundedCornerRadii == roundedTop)
    }

    @Test("A picture rounds by its mask, one corner at a time")
    func pictureTakesFour() {
        var layer = picture(.none)
        layer.setRoundedCorners(roundedTop)
        #expect(layer.style.cornerRadii == roundedTop)
        #expect(layer.roundedCornerRadii == roundedTop)
    }

    @Test("One pull over a mixed selection rounds a picture and a box together")
    func onePullReachesBoth() {
        var doc = document([rectangle(.none), picture(.none)])
        let ids = doc.layers.map(\.id)
        #expect(doc.setCornerRadii(layerIDs: ids, to: roundedTop) == 2)
        #expect(doc.layers[0].annotation?.cornerRadii == roundedTop)
        #expect(doc.layers[1].style.cornerRadii == roundedTop)
    }

    @Test("The row reads the four corners each picked layer actually wears")
    func selectionReadsFour() {
        let doc = document([rectangle(roundedTop), picture(roundedTop)])
        let selection = doc.cornerRadiusSelection(layerIDs: doc.layers.map(\.id))
        #expect(selection.radii.value == roundedTop)
        #expect(!selection.radii.isMixed)
        // The slider's knob sits at the roundest corner while they disagree.
        #expect(selection.reading.value == 16)
    }

    @Test("Two layers rounded differently read as mixed")
    func selectionMixed() {
        let doc = document([rectangle(roundedTop), picture(CornerRadii(4))])
        let selection = doc.cornerRadiusSelection(layerIDs: doc.layers.map(\.id))
        #expect(selection.radii.isMixed)
        #expect(selection.radii.value == nil)
    }

    @Test("Whether anything picked has a corner rounded on its own, which is what opens the four")
    func selectionKnowsItIsUneven() {
        let uneven = document([rectangle(roundedTop)])
        #expect(uneven.cornerRadiusSelection(layerIDs: uneven.layers.map(\.id)).hasUnevenCorners)
        let even = document([rectangle(CornerRadii(16))])
        #expect(!even.cornerRadiusSelection(layerIDs: even.layers.map(\.id)).hasUnevenCorners)
    }

    @Test("One corner can be set without touching the other three")
    func oneCorner() {
        var doc = document([rectangle(CornerRadii(16))])
        let ids = doc.layers.map(\.id)
        #expect(doc.setCornerRadius(layerIDs: ids, corner: .bottomRight, to: 0) == 1)
        #expect(doc.layers[0].annotation?.cornerRadii
            == CornerRadii(topLeft: 16, topRight: 16, bottomRight: 0, bottomLeft: 16))
    }

    @Test("Dragging the one slider still flattens the four, which is one undo step")
    func oneNumberFlattens() {
        var doc = document([rectangle(roundedTop)])
        doc.setCornerRadius(layerIDs: doc.layers.map(\.id), to: 8)
        #expect(doc.layers[0].annotation?.cornerRadii == CornerRadii(8))
    }

    @Test("A locked layer keeps its corners")
    func lockedIsLeftAlone() {
        var layer = rectangle(.none)
        layer.isLocked = true
        var doc = document([layer])
        #expect(doc.setCornerRadii(layerIDs: doc.layers.map(\.id), to: roundedTop) == 0)
        #expect(doc.layers[0].annotation?.cornerRadii == CornerRadii.none)
    }

    // MARK: - Everything round the box follows the four

    @Test("The shape's silhouette curves corner by corner, each grown by half the line")
    func silhouetteFollowsFour() {
        var annotation = AnnotationContent(shape: .rectangle, strokeWidth: 8, start: .zero,
                                           end: CGPoint(x: size.width, y: size.height),
                                           cornerRadii: roundedTop, fillColorHex: "#FF0000")
        annotation.strokePosition = .inside
        let box = annotation.boxCornerRadii(in: size)
        #expect(box.topLeft == 20)      // 16 + half the 8 point line
        #expect(box.topRight == 20)
        #expect(box.bottomRight == 0)   // a square corner stays square
        #expect(box.bottomLeft == 0)
    }

    @Test("A ring round the box, and the mask cut out of it, follow the same four")
    func layerBoxFollowsFour() {
        #expect(rectangle(roundedTop).boxCornerRadii(boxSize: size) == roundedTop)
        #expect(picture(roundedTop).boxCornerRadii(boxSize: size) == roundedTop)
    }

    @Test("The outline round a picked layer follows the same four")
    func selectionOutlineFollowsFour() {
        let box = CGRect(origin: .zero, size: size)
        #expect(rectangle(roundedTop).selectionOutlineRadii(box: box) == roundedTop)
        // ...and a shape with no corners at all is still marked with a square.
        var oval = rectangle(roundedTop)
        oval.content = .annotation(AnnotationContent(shape: .ellipse, start: .zero,
                                                     end: CGPoint(x: 200, y: 120)))
        #expect(!oval.selectionOutlineRadii(box: box).isRound)
    }

    @Test("A path with a square bottom keeps its bottom corners")
    func outlinePathKeepsSquareCorners() {
        let box = CGRect(origin: .zero, size: size)
        let path = SelectionOutlineShape.path(box: box, cornerRadii: roundedTop)
        #expect(!path.contains(CGPoint(x: 2, y: 2)))          // rounded off the top
        #expect(path.contains(CGPoint(x: 2, y: size.height - 2)))   // square at the foot
    }

    // MARK: - Magnifying and matching

    @Test("Magnifying a document takes all four corners with it")
    func magnificationScalesFour() {
        var doc = document([picture(roundedTop)])
        doc.canvasSize = CGSize(width: 400, height: 400)
        let big = doc.magnified(by: 2)
        #expect(big.layers[0].style.cornerRadii == roundedTop.scaled(by: 2))
    }

    @Test("A copy whose corners were changed one at a time counts as changed")
    func componentDiffSeesOneCorner() {
        var mine = LayerStyle()
        mine.cornerRadii = CornerRadii(16)
        var theirs = LayerStyle()
        theirs.cornerRadii = roundedTop
        #expect(LayerStyle.differences(mine, theirs).contains(.cornerRadius))
        #expect(mine.taking(.cornerRadius, from: theirs).cornerRadii == roundedTop)
    }

    // MARK: - On disk

    @Test("A shape saved with four different corners opens with them")
    func documentRoundTrip() throws {
        let doc = document([rectangle(roundedTop), picture(roundedTop)])
        let back = try JSONDecoder().decode(PhotonzDocument.self,
                                            from: try JSONEncoder().encode(doc))
        #expect(back.layers[0].annotation?.cornerRadii == roundedTop)
        #expect(back.layers[1].style.cornerRadii == roundedTop)
    }

    @Test("A document saved before this opens unchanged")
    func olderDocumentOpensUnchanged() throws {
        let doc = document([rectangle(CornerRadii(18)), picture(CornerRadii(18))])
        let data = try JSONEncoder().encode(doc)
        let json = String(data: data, encoding: .utf8) ?? ""
        // Still the single number an older build wrote, and an older build reads.
        #expect(json.contains("\"cornerRadius\":18"))
        let back = try JSONDecoder().decode(PhotonzDocument.self, from: data)
        #expect(back.layers[0].annotation?.cornerRadius == 18)
        #expect(back.layers[1].style.cornerRadius == 18)
    }
}
