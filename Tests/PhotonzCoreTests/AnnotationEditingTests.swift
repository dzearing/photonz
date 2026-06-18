import CoreGraphics
import Foundation
import PhotonzCore
import Testing

private func arrowLayer(from start: CGPoint = CGPoint(x: 10, y: 50),
                        to end: CGPoint = CGPoint(x: 110, y: 50),
                        strokeWidth: CGFloat = 4) -> Layer {
    let content = AnnotationContent(shape: .arrow, strokeWidth: strokeWidth, colorHex: "#FF3B30")
    return AnnotationBuilder.layer(content: content, from: start, to: end)
}

private func annotation(_ layer: Layer) -> AnnotationContent? {
    layer.annotation
}

@Suite("AnnotationBuilder.updating")
struct AnnotationUpdatingTests {

    @Test func rebuildsFrameLikeAFreshDragButKeepsIdentity() {
        var layer = arrowLayer()
        layer.style.opacity = 0.5
        layer.name = "My Arrow"
        let updated = AnnotationBuilder.updating(layer, start: CGPoint(x: 20, y: 60),
                                                 end: CGPoint(x: 80, y: 120))
        guard let content = annotation(layer) else {
            Issue.record("expected annotation content")
            return
        }
        let fresh = AnnotationBuilder.layer(content: content,
                                            from: CGPoint(x: 20, y: 60),
                                            to: CGPoint(x: 80, y: 120))
        #expect(updated.id == layer.id)
        #expect(updated.name == "My Arrow")
        #expect(updated.style == layer.style)
        #expect(updated.frame == fresh.frame)
        #expect(annotation(updated)?.start == annotation(fresh)?.start)
        #expect(annotation(updated)?.end == annotation(fresh)?.end)
    }

    @Test func docSpaceEndpointsLandWhereRequested() {
        let layer = arrowLayer()
        let updated = AnnotationBuilder.updating(layer, start: CGPoint(x: 30, y: 40),
                                                 end: CGPoint(x: 200, y: 90))
        #expect(updated.annotationEndpoint(.start) == CGPoint(x: 30, y: 40))
        #expect(updated.annotationEndpoint(.end) == CGPoint(x: 200, y: 90))
    }

    @Test func nonAnnotationLayersPassThroughUnchanged() {
        let layer = Layer(name: "Image", content: .image(ImageRef(pixelSize: CGSize(width: 10, height: 10))),
                          frame: CGRect(x: 0, y: 0, width: 10, height: 10))
        let updated = AnnotationBuilder.updating(layer, start: .zero, end: CGPoint(x: 5, y: 5))
        #expect(updated == layer)
    }
}

@Suite("AnnotationBuilder.resized")
struct AnnotationResizedTests {

    // The 3.2 gotcha: setting only the frame distorts/clips. Resizing must
    // scale the endpoints with the frame and re-pad for the (unchanged) stroke.
    @Test func downscaledArrowKeepsFullRenderPadding() {
        let layer = arrowLayer(from: CGPoint(x: 0, y: 100), to: CGPoint(x: 200, y: 100))
        let half = CGRect(x: layer.frame.minX, y: layer.frame.minY,
                          width: layer.frame.width / 2, height: layer.frame.height / 2)
        let resized = AnnotationBuilder.resized(layer, to: half)
        guard let content = annotation(resized) else {
            Issue.record("expected annotation content")
            return
        }
        let pad = content.renderPadding
        // Endpoints sit at least the render padding inside the frame on every side.
        for p in [content.start, content.end] {
            #expect(p.x >= pad && p.x <= resized.frame.width - pad)
            #expect(p.y >= pad && p.y <= resized.frame.height - pad)
        }
        #expect(content.strokeWidth == 4) // stroke width is style, not geometry
    }

    @Test func endpointsScaleProportionallyWithTheFrame() {
        let layer = arrowLayer(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 100, y: 100))
        let doubled = CGRect(x: layer.frame.minX, y: layer.frame.minY,
                             width: layer.frame.width * 2, height: layer.frame.height * 2)
        let resized = AnnotationBuilder.resized(layer, to: doubled)
        guard let start = resized.annotationEndpoint(.start),
              let end = resized.annotationEndpoint(.end) else {
            Issue.record("expected endpoints")
            return
        }
        // The arrow's doc-space span doubles.
        #expect(abs((end.x - start.x) - 200) < 1e-6)
        #expect(abs((end.y - start.y) - 200) < 1e-6)
    }

    // Box shapes have zero render padding, so the rebuilt frame is exactly
    // the proposed one and the local end tracks the new size.
    @Test func rectangleResizeMatchesTheProposedFrameExactly() {
        let content = AnnotationContent(shape: .rectangle, strokeWidth: 4, colorHex: "#FF3B30")
        let layer = AnnotationBuilder.layer(content: content,
                                            from: CGPoint(x: 10, y: 20), to: CGPoint(x: 110, y: 80))
        let proposed = CGRect(x: 40, y: 50, width: 50, height: 200)
        let resized = AnnotationBuilder.resized(layer, to: proposed)
        #expect(resized.frame == proposed)
        #expect(annotation(resized)?.start == .zero)
        #expect(annotation(resized)?.end == CGPoint(x: 50, y: 200))
    }

    @Test func degenerateOldFrameDoesNotProduceNaN() {
        let content = AnnotationContent(shape: .highlight, strokeWidth: 4, colorHex: "#FFD60A")
        let layer = AnnotationBuilder.layer(content: content,
                                            from: CGPoint(x: 10, y: 30), to: CGPoint(x: 90, y: 30))
        let resized = AnnotationBuilder.resized(layer, to: CGRect(x: 10, y: 30, width: 80, height: 50))
        #expect(resized.frame.width.isFinite && resized.frame.height.isFinite)
        #expect(resized.frame.width >= 1 && resized.frame.height >= 1)
    }

    @Test func layerResizedDispatchesByContent() {
        let arrow = arrowLayer()
        let target = CGRect(x: 0, y: 0, width: 50, height: 30)
        // Annotation: remapped (frame re-padded, so endpoints moved with it).
        #expect(arrow.resized(to: target).annotationEndpoint(.start) != arrow.annotationEndpoint(.start))
        // Image: plain frame assignment.
        let image = Layer(name: "Image", content: .image(ImageRef(pixelSize: CGSize(width: 10, height: 10))),
                          frame: CGRect(x: 0, y: 0, width: 10, height: 10))
        #expect(image.resized(to: target).frame == target)
    }
}

@Suite("AnnotationEndpointDrag")
struct AnnotationEndpointDragTests {

    @Test func draggingEndKeepsStartFixed() {
        let layer = arrowLayer(from: CGPoint(x: 10, y: 50), to: CGPoint(x: 110, y: 50))
        guard var drag = AnnotationEndpointDrag(layer: layer, endpoint: .end) else {
            Issue.record("expected drag")
            return
        }
        drag.update(to: CGPoint(x: 200, y: 200))
        let (start, end) = drag.endpoints(constrained: false)
        #expect(start == CGPoint(x: 10, y: 50))
        #expect(end == CGPoint(x: 200, y: 200))
    }

    @Test func draggingStartKeepsEndFixed() {
        let layer = arrowLayer(from: CGPoint(x: 10, y: 50), to: CGPoint(x: 110, y: 50))
        guard var drag = AnnotationEndpointDrag(layer: layer, endpoint: .start) else {
            Issue.record("expected drag")
            return
        }
        drag.update(to: CGPoint(x: 0, y: 0))
        let (start, end) = drag.endpoints(constrained: false)
        #expect(start == CGPoint(x: 0, y: 0))
        #expect(end == CGPoint(x: 110, y: 50))
    }

    @Test func beforeAnyMovementTheDragReproducesTheLayer() {
        let layer = arrowLayer(from: CGPoint(x: 10, y: 50), to: CGPoint(x: 110, y: 60))
        guard let drag = AnnotationEndpointDrag(layer: layer, endpoint: .end) else {
            Issue.record("expected drag")
            return
        }
        let (start, end) = drag.endpoints(constrained: false)
        #expect(start == CGPoint(x: 10, y: 50))
        #expect(end == CGPoint(x: 110, y: 60))
    }

    @Test func shiftSnapsTheMovedEndpointTo45DegreesAroundTheFixedOne() {
        let layer = arrowLayer(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 200, y: 100))
        guard var drag = AnnotationEndpointDrag(layer: layer, endpoint: .end) else {
            Issue.record("expected drag")
            return
        }
        drag.update(to: CGPoint(x: 200, y: 108)) // ~4.6° off horizontal
        let (start, end) = drag.endpoints(constrained: true)
        #expect(start == CGPoint(x: 100, y: 100))
        #expect(abs(end.y - 100) < 1e-9) // snapped flat, length preserved
        #expect(abs((end.x - 100) - hypot(100, 8)) < 1e-9)
    }

    @Test func nonLineLayersDoNotBuildEndpointDrags() {
        let image = Layer(name: "Image", content: .image(ImageRef(pixelSize: CGSize(width: 10, height: 10))),
                          frame: CGRect(x: 0, y: 0, width: 10, height: 10))
        #expect(AnnotationEndpointDrag(layer: image, endpoint: .end) == nil)
    }
}

@Suite("AnnotationBuilder.restyled")
struct AnnotationRestyledTests {

    @Test func colorChangeKeepsGeometry() {
        let layer = arrowLayer()
        let restyled = AnnotationBuilder.restyled(layer, colorHex: "#007AFF")
        #expect(annotation(restyled)?.colorHex == "#007AFF")
        #expect(restyled.frame == layer.frame)
        #expect(annotation(restyled)?.start == annotation(layer)?.start)
        #expect(annotation(restyled)?.end == annotation(layer)?.end)
    }

    @Test func strokeWidthChangeRepadsTheFrameAroundFixedEndpoints() {
        // Since 10.4 the arrowhead is fixed (independent of stroke), so the frame
        // only repads once the shaft is thick enough that its own width drives
        // padding past the head — use a heavy stroke so the repad is observable.
        let layer = arrowLayer(from: CGPoint(x: 20, y: 100), to: CGPoint(x: 220, y: 100), strokeWidth: 4)
        let restyled = AnnotationBuilder.restyled(layer, strokeWidth: 30)
        guard let content = annotation(restyled) else {
            Issue.record("expected annotation content")
            return
        }
        #expect(content.strokeWidth == 30)
        // Doc endpoints stay anchored…
        #expect(restyled.annotationEndpoint(.start) == CGPoint(x: 20, y: 100))
        #expect(restyled.annotationEndpoint(.end) == CGPoint(x: 220, y: 100))
        // …while the frame grows to the thicker stroke's render padding.
        let pad = content.renderPadding
        #expect(restyled.frame.minY <= 100 - pad)
        #expect(restyled.frame.maxY >= 100 + pad)
        #expect(restyled.frame != layer.frame)
    }

    @Test func nonAnnotationLayersPassThroughUnchanged() {
        let layer = Layer(name: "Image", content: .image(ImageRef(pixelSize: CGSize(width: 10, height: 10))),
                          frame: CGRect(x: 0, y: 0, width: 10, height: 10))
        #expect(AnnotationBuilder.restyled(layer, colorHex: "#000000") == layer)
    }
}

@Suite("Endpoint handles")
struct AnnotationEndpointHandleTests {

    @Test func linesAndArrowsUseEndpointHandlesEverythingElseDoesNot() {
        for shape in [AnnotationShape.line, .arrow] {
            let content = AnnotationContent(shape: shape, strokeWidth: 4, colorHex: "#FF3B30")
            let layer = AnnotationBuilder.layer(content: content, from: .zero, to: CGPoint(x: 50, y: 50))
            #expect(layer.hasEndpointHandles, "\(shape)")
            #expect(!layer.allowsFrameResize, "\(shape)")
        }
        for shape in [AnnotationShape.rectangle, .ellipse, .highlight] {
            let content = AnnotationContent(shape: shape, strokeWidth: 4, colorHex: "#FF3B30")
            let layer = AnnotationBuilder.layer(content: content, from: .zero, to: CGPoint(x: 50, y: 50))
            #expect(!layer.hasEndpointHandles, "\(shape)")
            #expect(layer.allowsFrameResize, "\(shape)")
        }
    }

    // 3.5 decision: text never frame-resizes (render re-wraps/rescales at frame
    // size, which is unpredictable). Text size changes go through the font picker.
    @Test func textLayersDoNotFrameResize() {
        let layer = Layer(name: "Text", content: .text(TextContent(string: "hi")),
                          frame: CGRect(x: 0, y: 0, width: 100, height: 30))
        #expect(!layer.allowsFrameResize)
        #expect(!layer.hasEndpointHandles)
    }

    @Test func hitFindsTheNearestEndpointWithinScreenTolerance() {
        let layer = arrowLayer(from: CGPoint(x: 10, y: 50), to: CGPoint(x: 110, y: 50))
        #expect(AnnotationEndpoints.hit(at: CGPoint(x: 12, y: 53), layer: layer, zoom: 1) == .start)
        #expect(AnnotationEndpoints.hit(at: CGPoint(x: 108, y: 47), layer: layer, zoom: 1) == .end)
        #expect(AnnotationEndpoints.hit(at: CGPoint(x: 60, y: 50), layer: layer, zoom: 1) == nil)
    }

    @Test func hitToleranceIsInScreenPoints() {
        let layer = arrowLayer(from: CGPoint(x: 10, y: 50), to: CGPoint(x: 110, y: 50))
        let probe = CGPoint(x: 16, y: 50) // 6 doc points from start
        #expect(AnnotationEndpoints.hit(at: probe, layer: layer, zoom: 1) == .start)
        #expect(AnnotationEndpoints.hit(at: probe, layer: layer, zoom: 4) == nil)
    }

    @Test func hitIsNilForLayersWithoutEndpointHandles() {
        let content = AnnotationContent(shape: .rectangle, strokeWidth: 4, colorHex: "#FF3B30")
        let layer = AnnotationBuilder.layer(content: content, from: .zero, to: CGPoint(x: 50, y: 50))
        #expect(AnnotationEndpoints.hit(at: .zero, layer: layer, zoom: 1) == nil)
    }
}

@Suite("Line/arrow hit-testing")
struct SegmentHitTests {

    @Test func distanceToSegmentBasics() {
        let a = CGPoint(x: 0, y: 0), b = CGPoint(x: 100, y: 0)
        #expect(Geometry.distance(from: CGPoint(x: 50, y: 10), toSegmentFrom: a, to: b) == 10)
        #expect(Geometry.distance(from: CGPoint(x: -30, y: 0), toSegmentFrom: a, to: b) == 30)
        #expect(Geometry.distance(from: CGPoint(x: 130, y: 40), toSegmentFrom: a, to: b) == 50)
        // Degenerate segment falls back to point distance.
        #expect(Geometry.distance(from: CGPoint(x: 3, y: 4), toSegmentFrom: a, to: a) == 5)
    }

    @Test func clicksNearTheShaftHitAndEmptyBoundingBoxCornersMiss() {
        // Diagonal arrow: its padded frame is a big box, but only the stroke hits.
        let layer = arrowLayer(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 100, y: 100))
        #expect(layer.contains(canvasPoint: CGPoint(x: 50, y: 53)))
        #expect(!layer.contains(canvasPoint: CGPoint(x: 95, y: 5))) // inside frame, far from stroke
    }

    @Test func hitSlopShrinksWithZoom() {
        let layer = arrowLayer(from: CGPoint(x: 0, y: 100), to: CGPoint(x: 200, y: 100), strokeWidth: 4)
        let probe = CGPoint(x: 100, y: 107) // 7 doc points off the shaft
        #expect(layer.contains(canvasPoint: probe, zoom: 1))   // tolerance 2 + 6 = 8
        #expect(!layer.contains(canvasPoint: probe, zoom: 4))  // tolerance 2 + 1.5
    }

    @Test func boxAnnotationsKeepWholeFrameHitTesting() {
        let content = AnnotationContent(shape: .rectangle, strokeWidth: 4, colorHex: "#FF3B30")
        let layer = AnnotationBuilder.layer(content: content,
                                            from: CGPoint(x: 0, y: 0), to: CGPoint(x: 100, y: 100))
        #expect(layer.contains(canvasPoint: CGPoint(x: 50, y: 50))) // hollow center still grabs
    }

    @Test func defaultArrowheadScaleIsOne() {
        // 10.4: new arrows start at ×1.0 (the head's base proportions), not ×1.5.
        #expect(AnnotationStyles.defaultArrowheadScale == 1.0)
        let styles = AnnotationStyles()
        #expect(styles.arrowheadScale == 1.0)
        let arrow = styles.content(for: .arrow)
        #expect(arrow?.arrowheadScale == 1.0)
    }

    @Test func documentHitTestPassesZoomThrough() {
        let arrow = arrowLayer(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 100, y: 100))
        let doc = PhotonzDocument(canvasSize: CGSize(width: 200, height: 200), layers: [arrow])
        let corner = CGPoint(x: 95, y: 5) // inside the arrow's frame, off the stroke
        #expect(doc.hitTest(corner) == nil)
        #expect(doc.hitTest(CGPoint(x: 50, y: 52), zoom: 1)?.id == arrow.id)
        #expect(doc.hitTest(CGPoint(x: 50, y: 57), zoom: 8) == nil)
    }
}
