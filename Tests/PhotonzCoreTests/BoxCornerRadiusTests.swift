import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// The ONE curve everything round a layer's box has to follow.
///
/// A rectangle rounds by curving the outline it draws, and until 2026-09-08
/// nothing else knew that: a border somebody added read the layer style's
/// radius, which the Corner Radius row deliberately leaves at nought on a
/// shape, so the ring came out a hard square frame round a rounded box
/// (reported by the user, 2026-09-07). `boxCornerRadius` is what a ring and a
/// mask ask instead.
@Suite("Box corner radius")
struct BoxCornerRadiusTests {

    private let size = CGSize(width: 200, height: 120)

    private func rectangle(radius: CGFloat, stroke: CGFloat,
                           position: BorderPosition = .inside) -> AnnotationContent {
        var annotation = AnnotationContent(shape: .rectangle, strokeWidth: stroke,
                                           start: .zero,
                                           end: CGPoint(x: size.width, y: size.height),
                                           cornerRadii: CornerRadii(radius), fillColorHex: "#FF0000")
        annotation.strokePosition = position
        return annotation
    }

    private func layer(_ annotation: AnnotationContent, style: LayerStyle = LayerStyle()) -> Layer {
        Layer(name: "Box", content: .annotation(annotation),
              frame: CGRect(origin: .zero, size: size), style: style)
    }

    @Test("A rectangle's box curves by its own radius plus half the line inside it")
    func insideOutline() {
        // The stroke rides a path inset by half its width, so the silhouette at
        // the frame is half a width wider than the path's own corner.
        let annotation = rectangle(radius: 20, stroke: 8, position: .inside)
        #expect(annotation.boxCornerRadius(in: size) == 24)
    }

    @Test("A centred line leaves the box curving by the radius itself")
    func centredOutline() {
        let annotation = rectangle(radius: 20, stroke: 8, position: .center)
        #expect(annotation.boxCornerRadius(in: size) == 20)
    }

    @Test("An outside line leaves the box curving by half a width less")
    func outsideOutline() {
        let annotation = rectangle(radius: 20, stroke: 8, position: .outside)
        #expect(annotation.boxCornerRadius(in: size) == 16)
        // ...and never past straight: a fat line round a barely rounded box.
        #expect(rectangle(radius: 1, stroke: 20, position: .outside).boxCornerRadius(in: size) == 0)
    }

    @Test("A line-only shape with no radius curves not at all")
    func noRadius() {
        #expect(rectangle(radius: 0, stroke: 4).boxCornerRadius(in: size) == 0)
    }

    @Test("Rounding past fully round stops at fully round")
    func clampedToHalfTheShortEdge() {
        // The path is inset by half the line, so its own corner tops out at
        // half the SHORT edge of that inset rect: (120 - 8) / 2 = 56, and the
        // silhouette is half a width wider again.
        #expect(rectangle(radius: 999, stroke: 8).boxCornerRadius(in: size) == 60)
    }

    @Test("Only a rectangle has a curve of its own")
    func onlyRectangles() {
        var ellipse = AnnotationContent(shape: .ellipse, strokeWidth: 4, start: .zero,
                                        end: CGPoint(x: size.width, y: size.height))
        ellipse.cornerRadius = 20
        #expect(ellipse.boxCornerRadius(in: size) == 0)
    }

    @Test("A resized shape rounds by what fits the size it is now")
    func resized() {
        let annotation = rectangle(radius: 40, stroke: 0)
        #expect(annotation.boxCornerRadius(in: size) == 40)
        // Pulled down to a sliver, the same radius reads as fully round.
        #expect(annotation.boxCornerRadius(in: CGSize(width: 200, height: 30)) == 15)
    }

    // MARK: - What a whole layer answers

    @Test("A rounded rectangle answers with its own curve, not its style's")
    func layerReadsTheShape() {
        var style = LayerStyle()
        style.cornerRadius = 0
        // 20, not 24: the box's line is a ring hugging the box now rather than
        // a stroke riding a path half its width inside it, so the curve the
        // panel says is the curve you see (`OutlineRetirementTests`).
        #expect(layer(rectangle(radius: 20, stroke: 8), style: style)
            .boxCornerRadius(boxSize: size) == 20)
    }

    @Test("A rectangle rounded by nothing but the old mask keeps reading that mask")
    func legacyMaskedRectangle() {
        // What a document written before the one Corner Radius row looks like:
        // no curve on the shape, a radius on the layer style. It painted a
        // masked corner then and it has to paint one now.
        var style = LayerStyle()
        style.cornerRadius = 14
        #expect(layer(rectangle(radius: 0, stroke: 4), style: style)
            .boxCornerRadius(boxSize: size) == 14)
    }

    @Test("Anything that is not a shape is rounded by its style")
    func picture() {
        var style = LayerStyle()
        style.cornerRadius = 12
        let picture = Layer(name: "Shot", content: .image(ImageRef(pixelSize: size)),
                            frame: CGRect(origin: .zero, size: size), style: style)
        #expect(picture.boxCornerRadius(boxSize: size) == 12)
    }
}
