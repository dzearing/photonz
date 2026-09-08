import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// The shape of the blue outline that says a layer is picked.
///
/// It was a hard rectangle whatever it was drawn round, so rounding a box right
/// up left the outline standing off the shape at every corner, cutting the
/// curve (seen on the probe, 2026-09-08). It follows the same curve the shape
/// has instead, which is the one `boxCornerRadius` gives every ring and mask.
@Suite("Selection outline shape")
struct SelectionOutlineShapeTests {

    private let box = CGRect(x: 100, y: 50, width: 360, height: 220)

    private func rectangle(radius: CGFloat, stroke: CGFloat = 4,
                           position: BorderPosition = .inside) -> Layer {
        var annotation = AnnotationContent(shape: .rectangle, strokeWidth: stroke,
                                           start: .zero,
                                           end: CGPoint(x: box.width, y: box.height),
                                           cornerRadius: radius, fillColorHex: "#FF0000")
        annotation.strokePosition = position
        return Layer(name: "Rectangle", content: .annotation(annotation), frame: box)
    }

    private func shape(_ kind: AnnotationShape) -> Layer {
        let annotation = AnnotationContent(shape: kind, strokeWidth: 4, start: .zero,
                                           end: CGPoint(x: box.width, y: box.height),
                                           cornerRadius: 0, fillColorHex: "#FF0000")
        return Layer(name: "\(kind)", content: .annotation(annotation), frame: box)
    }

    // MARK: How round the outline is

    @Test("A rounded rectangle's outline follows the shape's own curve")
    func roundedRectangleRadius() {
        // The curve the box itself carries: its edge is a ring hugging the box
        // now, not a stroke riding a path half a width inside it
        // (`OutlineRetirementTests`).
        #expect(rectangle(radius: 49).selectionOutlineRadius(box: box) == 49)
    }

    @Test("A square rectangle's outline stays square")
    func squareRectangleRadius() {
        #expect(rectangle(radius: 0).selectionOutlineRadius(box: box) == 0)
    }

    @Test("An ellipse, a line and an arrow keep the outline they always had")
    func shapesWithoutCorners() {
        for kind in [AnnotationShape.ellipse, .line, .arrow] {
            #expect(shape(kind).selectionOutlineRadius(box: box) == 0, "\(kind)")
        }
    }

    @Test("A picture rounded by its style is outlined round that curve")
    func styleRoundedPicture() {
        var style = LayerStyle()
        style.cornerRadius = 18
        let picture = Layer(name: "Shot", content: .image(ImageRef(id: UUID(), pixelSize: box.size)),
                            frame: box, style: style)
        #expect(picture.selectionOutlineRadius(box: box) == 18)
    }

    // MARK: The path it draws

    @Test("No curve draws the same rectangle it always drew")
    func squarePath() {
        let path = SelectionOutlineShape.path(box: box, cornerRadius: 0)
        #expect(path == CGPath(rect: box, transform: nil))
    }

    @Test("A curved outline stays inside the box and cuts its corners off")
    func roundedPath() {
        let path = SelectionOutlineShape.path(box: box, cornerRadius: 51)
        #expect(path.boundingBox.equalTo(box))
        // A point just inside each corner of the box is OUTSIDE the curve —
        // which is exactly the gap the hard rectangle used to draw across.
        for corner in [CGPoint(x: box.minX + 2, y: box.minY + 2),
                       CGPoint(x: box.maxX - 2, y: box.minY + 2),
                       CGPoint(x: box.maxX - 2, y: box.maxY - 2),
                       CGPoint(x: box.minX + 2, y: box.maxY - 2)] {
            #expect(!path.contains(corner), "\(corner)")
            #expect(CGPath(rect: box, transform: nil).contains(corner), "\(corner)")
        }
        // ...and a point a radius in from the corner is well inside it.
        #expect(path.contains(CGPoint(x: box.minX + 51, y: box.minY + 51)))
        // The edges themselves are untouched: the curve only eats the corners.
        #expect(path.contains(CGPoint(x: box.midX, y: box.minY + 2)))
        #expect(path.contains(CGPoint(x: box.minX + 2, y: box.midY)))
    }

    @Test("Rounding past fully round is fully round, never wider than the box")
    func clampedPath() {
        let path = SelectionOutlineShape.path(box: box, cornerRadius: 999)
        #expect(path.boundingBox.equalTo(box))
        #expect(path.contains(CGPoint(x: box.midX, y: box.midY)))
        #expect(!path.contains(CGPoint(x: box.minX + 2, y: box.minY + 2)))
    }

    @Test("The outline lands where the transform puts it")
    func transformedPath() {
        let moved = SelectionOutlineShape.path(box: box, cornerRadius: 51,
                                               transform: CGAffineTransform(translationX: 10, y: -5))
        #expect(moved.boundingBox.equalTo(box.offsetBy(dx: 10, dy: -5)))
    }

    // MARK: The camera the chrome is drawn through

    @Test("A viewport hands out the same mapping as its own point conversion")
    func documentToView() {
        let viewport = Viewport(documentSize: CGSize(width: 900, height: 600),
                                viewSize: CGSize(width: 1280, height: 900),
                                zoom: 1.56, origin: CGPoint(x: 37, y: -12))
        for p in [CGPoint.zero, CGPoint(x: 340, y: 300), CGPoint(x: 900, y: 600)] {
            let mapped = p.applying(viewport.documentToView)
            let direct = viewport.viewPoint(fromDocument: p)
            #expect(abs(mapped.x - direct.x) < 0.0001)
            #expect(abs(mapped.y - direct.y) < 0.0001)
        }
    }
}
