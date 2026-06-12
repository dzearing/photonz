import CoreGraphics
import PhotonzCore
import Testing

@Suite("Tool")
struct ToolTests {

    @Test func annotationShapeMapping() {
        #expect(Tool.arrow.annotationShape == .arrow)
        #expect(Tool.line.annotationShape == .line)
        #expect(Tool.rectangle.annotationShape == .rectangle)
        #expect(Tool.ellipse.annotationShape == .ellipse)
        #expect(Tool.highlight.annotationShape == .highlight)
        #expect(Tool.select.annotationShape == nil)
        #expect(Tool.crop.annotationShape == nil)
        #expect(Tool.text.annotationShape == nil)
    }

    @Test func dragToCreateToolsAreExactlyTheAnnotationTools() {
        for tool in Tool.allCases {
            #expect(tool.createsAnnotationByDrag == (tool.annotationShape != nil))
        }
    }

    // Smart defaults (3.6): arrows/shapes are red, highlight is yellow.
    @Test func defaultContentColors() {
        #expect(Tool.arrow.defaultAnnotation?.colorHex == "#FF3B30")
        #expect(Tool.line.defaultAnnotation?.colorHex == "#FF3B30")
        #expect(Tool.rectangle.defaultAnnotation?.colorHex == "#FF3B30")
        #expect(Tool.ellipse.defaultAnnotation?.colorHex == "#FF3B30")
        #expect(Tool.highlight.defaultAnnotation?.colorHex == "#FFD60A")
        #expect(Tool.select.defaultAnnotation == nil)
        #expect(Tool.text.defaultAnnotation == nil)
    }

    @Test func defaultContentShapesMatchTheTool() {
        for tool in Tool.allCases {
            #expect(tool.defaultAnnotation?.shape == tool.annotationShape)
        }
    }
}

@Suite("AnnotationDrag")
struct AnnotationDragTests {

    @Test func clickDetectionMatchesViewSpaceTolerance() {
        var drag = AnnotationDrag(anchor: CGPoint(x: 10, y: 10))
        drag.update(to: CGPoint(x: 11, y: 11))
        #expect(drag.isClick(atZoom: 1))
        #expect(!drag.isClick(atZoom: 4)) // same doc travel is a real drag when zoomed in
    }

    @Test func unconstrainedEndIsTheRawPointer() {
        var drag = AnnotationDrag(anchor: .zero)
        drag.update(to: CGPoint(x: 30, y: 17))
        #expect(drag.end(constrained: false, shape: .line) == CGPoint(x: 30, y: 17))
        #expect(drag.end(constrained: false, shape: .rectangle) == CGPoint(x: 30, y: 17))
    }

    @Test func constrainedLineSnapsToNearest45Degrees() {
        var drag = AnnotationDrag(anchor: .zero)
        drag.update(to: CGPoint(x: 100, y: 8)) // ~4.6° — snaps to horizontal
        let end = drag.end(constrained: true, shape: .line)
        #expect(abs(end.y) < 1e-9)
        #expect(abs(end.x - hypot(100, 8)) < 1e-9) // length preserved

        drag.update(to: CGPoint(x: 50, y: 46)) // ~42.6° — snaps to the diagonal
        let diag = drag.end(constrained: true, shape: .arrow)
        #expect(abs(diag.x - diag.y) < 1e-9)
    }

    @Test func constrainedDiagonalKeepsDirection() {
        var drag = AnnotationDrag(anchor: CGPoint(x: 100, y: 100))
        drag.update(to: CGPoint(x: 40, y: 158)) // up-left-ish drag in doc coords
        let end = drag.end(constrained: true, shape: .line)
        #expect(end.x < 100 && end.y > 100)
        #expect(abs((100 - end.x) - (end.y - 100)) < 1e-9)
    }

    // ⇧ on box shapes means square, not angle snap — a near-horizontal rect
    // drag must never collapse flat.
    @Test func constrainedBoxShapesBecomeSquare() {
        var drag = AnnotationDrag(anchor: CGPoint(x: 100, y: 100))
        drag.update(to: CGPoint(x: 300, y: 150)) // wide, shallow drag
        for shape in [AnnotationShape.rectangle, .ellipse, .highlight] {
            let end = drag.end(constrained: true, shape: shape)
            #expect(end == CGPoint(x: 300, y: 300), "\(shape) squares off the longer axis")
        }
        drag.update(to: CGPoint(x: 40, y: 90)) // up-left drag keeps its direction
        let end = drag.end(constrained: true, shape: .rectangle)
        #expect(end == CGPoint(x: 40, y: 40))
    }
}

@Suite("AnnotationBuilder")
struct AnnotationBuilderTests {

    @Test func rectangleLayerFrameIsTheDragBoundingBox() {
        let content = AnnotationContent(shape: .rectangle, strokeWidth: 4, colorHex: "#FF3B30")
        let layer = AnnotationBuilder.layer(content: content,
                                            from: CGPoint(x: 10, y: 20),
                                            to: CGPoint(x: 110, y: 80))
        #expect(layer.frame == CGRect(x: 10, y: 20, width: 100, height: 60))
        guard case .annotation(let a) = layer.content else {
            Issue.record("expected annotation content")
            return
        }
        #expect(a.start == CGPoint(x: 0, y: 0))
        #expect(a.end == CGPoint(x: 100, y: 60))
    }

    @Test func reversedDragPreservesStartEndOrientation() {
        let content = AnnotationContent(shape: .rectangle, strokeWidth: 4, colorHex: "#FF3B30")
        let layer = AnnotationBuilder.layer(content: content,
                                            from: CGPoint(x: 110, y: 80),
                                            to: CGPoint(x: 10, y: 20))
        #expect(layer.frame == CGRect(x: 10, y: 20, width: 100, height: 60))
        guard case .annotation(let a) = layer.content else {
            Issue.record("expected annotation content")
            return
        }
        #expect(a.start == CGPoint(x: 100, y: 60))
        #expect(a.end == CGPoint(x: 0, y: 0))
    }

    @Test func lineFramePadsForRoundCaps() {
        let content = AnnotationContent(shape: .line, strokeWidth: 4, colorHex: "#FF3B30")
        let layer = AnnotationBuilder.layer(content: content,
                                            from: CGPoint(x: 10, y: 10),
                                            to: CGPoint(x: 60, y: 40))
        // Half the stroke (2pt) on every side so caps aren't clipped.
        #expect(layer.frame == CGRect(x: 8, y: 8, width: 54, height: 34))
        guard case .annotation(let a) = layer.content else {
            Issue.record("expected annotation content")
            return
        }
        #expect(a.start == CGPoint(x: 2, y: 2))
        #expect(a.end == CGPoint(x: 52, y: 32))
    }

    @Test func arrowFramePadsForTheArrowheadWings() {
        let content = AnnotationContent(shape: .arrow, strokeWidth: 4, colorHex: "#FF3B30")
        let layer = AnnotationBuilder.layer(content: content,
                                            from: CGPoint(x: 0, y: 50),
                                            to: CGPoint(x: 100, y: 50))
        // Wings reach arrowheadHalfWidth past the shaft; the frame must contain them.
        let pad = Geometry.arrowheadHalfWidth(strokeWidth: 4).rounded(.up)
        #expect(pad > content.strokeWidth / 2)
        #expect(layer.frame.minY <= 50 - pad)
        #expect(layer.frame.maxY >= 50 + pad)
        guard case .annotation(let a) = layer.content else {
            Issue.record("expected annotation content")
            return
        }
        // Local points sit inside the frame by the padding amount.
        #expect(a.start.x == 0 - layer.frame.minX)
        #expect(a.end.x == 100 - layer.frame.minX)
    }

    @Test func degenerateDragStillProducesARasterizableFrame() {
        let content = AnnotationContent(shape: .highlight, strokeWidth: 4, colorHex: "#FFD60A")
        let layer = AnnotationBuilder.layer(content: content,
                                            from: CGPoint(x: 10, y: 30),
                                            to: CGPoint(x: 90, y: 30)) // zero height
        #expect(layer.frame.width >= 1)
        #expect(layer.frame.height >= 1)
    }

    @Test func layerIsNamedAfterTheShape() {
        let content = AnnotationContent(shape: .ellipse, strokeWidth: 4, colorHex: "#FF3B30")
        let layer = AnnotationBuilder.layer(content: content, from: .zero, to: CGPoint(x: 10, y: 10))
        #expect(layer.name == "Ellipse")
    }

    @Test func arrowheadHalfWidthMatchesActualWingExtent() {
        let points = Geometry.arrowhead(start: CGPoint(x: 0, y: 50), end: CGPoint(x: 80, y: 50), strokeWidth: 6)
        let halfWidth = Geometry.arrowheadHalfWidth(strokeWidth: 6)
        #expect(abs(abs(points[1].y - 50) - halfWidth) < 1e-9)
    }
}
