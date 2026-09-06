import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

@Suite("ZoomCalloutBuilder")
struct ZoomCalloutBuilderTests {

    private let canvas = CGSize(width: 400, height: 300)

    @Test func dragBoxBecomesPixelAlignedSource() {
        let layer = ZoomCalloutBuilder.layer(from: CGPoint(x: 20.4, y: 30.7),
                                             to: CGPoint(x: 80.2, y: 90.1), canvas: canvas)
        let callout = layer?.zoomCallout
        #expect(callout != nil)
        if let source = callout?.sourceRect {
            #expect(source.minX == source.minX.rounded() && source.minY == source.minY.rounded())
            #expect(source.width == source.width.rounded() && source.height == source.height.rounded())
            #expect(CGRect(origin: .zero, size: canvas).contains(source))
        }
    }

    @Test func reversedDragNormalizes() {
        let layer = ZoomCalloutBuilder.layer(from: CGPoint(x: 80, y: 90),
                                             to: CGPoint(x: 20, y: 30), canvas: canvas)
        #expect(layer?.zoomCallout?.sourceRect == CGRect(x: 20, y: 30, width: 60, height: 60))
    }

    @Test func sourceClampsToCanvas() {
        let layer = ZoomCalloutBuilder.layer(from: CGPoint(x: -40, y: -40),
                                             to: CGPoint(x: 60, y: 60), canvas: canvas)
        #expect(layer?.zoomCallout?.sourceRect == CGRect(x: 0, y: 0, width: 60, height: 60))
    }

    @Test func frameComesFromPlacementGeometry() {
        let layer = ZoomCalloutBuilder.layer(from: CGPoint(x: 20, y: 30),
                                             to: CGPoint(x: 80, y: 90), canvas: canvas)!
        let expected = Geometry.zoomCalloutPlacement(source: CGRect(x: 20, y: 30, width: 60, height: 60),
                                                     magnification: ZoomCalloutBuilder.defaultMagnification,
                                                     canvas: canvas)
        #expect(layer.frame == expected)
    }

    @Test func aSecondCalloutDoesNotLandOnTheFirst() {
        // Two details magnified one after the other, drawn from nearly the same
        // spot: before this, the second box landed exactly on the first and
        // neither could be read until one was dragged off.
        let first = ZoomCalloutBuilder.layer(from: CGPoint(x: 20, y: 30),
                                             to: CGPoint(x: 80, y: 90), canvas: canvas)!
        let second = ZoomCalloutBuilder.layer(from: CGPoint(x: 22, y: 32),
                                              to: CGPoint(x: 82, y: 92), canvas: canvas,
                                              avoiding: [first.frame])!
        #expect(!second.frame.intersects(first.frame))
        #expect(CGRect(origin: .zero, size: canvas).contains(second.frame))
    }

    @Test func calloutsAlreadyOnThePictureAreWhatANewOneAvoids() {
        // What the editor hands to `avoiding`: the callouts already placed, in
        // canvas coordinates, including one drawn inside a frame.
        var document = PhotonzDocument(canvasSize: canvas, layers: [])
        let callout = ZoomCalloutBuilder.layer(from: CGPoint(x: 20, y: 30),
                                               to: CGPoint(x: 80, y: 90), canvas: canvas)!
        document.layers = [Layer.frameLayer(name: "Screen", origin: CGPoint(x: 100, y: 20),
                                            size: CGSize(width: 200, height: 200),
                                            children: [callout])]
        #expect(document.placedZoomCalloutRects
            == [callout.frame.offsetBy(dx: 100, dy: 20)])
        // A hidden callout is not in the way of anything.
        document.layers[0].children[0].isVisible = false
        #expect(document.placedZoomCalloutRects.isEmpty)
    }

    @Test func tinyDragReturnsNil() {
        let layer = ZoomCalloutBuilder.layer(from: CGPoint(x: 20, y: 30),
                                             to: CGPoint(x: 22, y: 31), canvas: canvas)
        #expect(layer == nil)
    }

    @Test func dragOutsideCanvasReturnsNil() {
        let layer = ZoomCalloutBuilder.layer(from: CGPoint(x: -100, y: -100),
                                             to: CGPoint(x: -10, y: -10), canvas: canvas)
        #expect(layer == nil)
    }

    @Test func defaultStyleReadsAsCallout() {
        let layer = ZoomCalloutBuilder.layer(from: CGPoint(x: 20, y: 30),
                                             to: CGPoint(x: 80, y: 90), canvas: canvas)!
        #expect(layer.style.borderWidth > 0)
        #expect(layer.style.cornerRadius > 0)
        #expect(layer.style.shadow != nil)
        #expect(layer.name == "Zoom")
    }

    @Test func frameResizeSyncsMagnification() {
        var layer = ZoomCalloutBuilder.layer(from: CGPoint(x: 20, y: 30),
                                             to: CGPoint(x: 80, y: 90), canvas: canvas)!
        // Source is 60×60 at 2× → frame 120×120. Stretch to 180 wide → 3×.
        layer = layer.resized(to: CGRect(x: 200, y: 100, width: 180, height: 180))
        #expect(layer.zoomCallout?.magnification == 3)
        #expect(layer.frame == CGRect(x: 200, y: 100, width: 180, height: 180))
    }

    @Test func nonCalloutLayersResizeUnchanged() {
        var layer = Layer(name: "Image", content: .image(ImageRef(pixelSize: CGSize(width: 10, height: 10))),
                          frame: CGRect(x: 0, y: 0, width: 10, height: 10))
        layer = layer.resized(to: CGRect(x: 5, y: 5, width: 20, height: 20))
        #expect(layer.frame == CGRect(x: 5, y: 5, width: 20, height: 20))
    }

    @Test func legacyPayloadDecodesToRectangleShape() throws {
        let json = #"{"sourceRect":[[10,10],[20,20]],"magnification":2}"#
        let content = try JSONDecoder().decode(ZoomCalloutContent.self, from: Data(json.utf8))
        #expect(content.shape == .rectangle)
        #expect(content.sourceRect == CGRect(x: 10, y: 10, width: 20, height: 20))
    }

    @Test func shapeRoundTripsThroughCodable() throws {
        var content = ZoomCalloutContent(sourceRect: CGRect(x: 0, y: 0, width: 10, height: 10))
        content.shape = .circle
        let data = try JSONEncoder().encode(content)
        let decoded = try JSONDecoder().decode(ZoomCalloutContent.self, from: data)
        #expect(decoded.shape == .circle)
    }

    @Test func circleEffectiveRadiusIsHalfTheShortSide() {
        var content = ZoomCalloutContent(sourceRect: CGRect(x: 0, y: 0, width: 20, height: 20))
        content.shape = .circle
        #expect(content.effectiveCornerRadius(boxSize: CGSize(width: 60, height: 40), styleRadius: 6) == 20)
    }

    @Test func rectangleEffectiveRadiusFollowsStyle() {
        let content = ZoomCalloutContent(sourceRect: CGRect(x: 0, y: 0, width: 20, height: 20))
        #expect(content.effectiveCornerRadius(boxSize: CGSize(width: 60, height: 40), styleRadius: 6) == 6)
    }

    @Test func magnificationFrameKeepsTheCenter() {
        let layer = ZoomCalloutBuilder.layer(from: CGPoint(x: 20, y: 30),
                                             to: CGPoint(x: 80, y: 90), canvas: canvas)!
        // 60×60 source at 2× → 120×120 frame. At 3× the frame grows to
        // 180×180 around the same center.
        let frame = ZoomCalloutBuilder.frame(for: 3, of: layer)
        #expect(frame.size == CGSize(width: 180, height: 180))
        #expect(frame.midX == layer.frame.midX && frame.midY == layer.frame.midY)
        // Round-tripping through resized(to:) recovers the magnification.
        #expect(layer.resized(to: frame).zoomCallout?.magnification == 3)
    }

    @Test func magnificationFrameOfNonCalloutIsUnchanged() {
        let layer = Layer(name: "Image", content: .image(ImageRef(pixelSize: CGSize(width: 10, height: 10))),
                          frame: CGRect(x: 5, y: 5, width: 10, height: 10))
        #expect(ZoomCalloutBuilder.frame(for: 3, of: layer) == layer.frame)
    }

    @Test func zoomCalloutToolIsNotAnAnnotationTool() {
        #expect(Tool.zoomCallout.annotationShape == nil)
        #expect(!Tool.zoomCallout.createsAnnotationByDrag)
        #expect(AnnotationStyles().content(for: .zoomCallout) == nil)
    }
    // MARK: - The Zoom Callout section's own controls
    //
    // Magnification and shape are the only two things a callout has that no
    // other layer does, and until 2026-09-04 they had nowhere on screen to be
    // set: the popover holding them was reachable only while a drawing tool
    // was in hand, and picking up a drawing tool drops the layer selection.
    // They live in the dock now, and these are the rules the section reads.

    @Test func magnificationRangeStartsAboveOne() {
        // Below 1.25 a callout shows the picture at nearly its own size, which
        // is a box saying nothing; six is where the source is a handful of
        // pixels and the box is a wall.
        #expect(ZoomCalloutBuilder.magnificationRange == 1.25...6)
        #expect(ZoomCalloutBuilder.magnificationRange.contains(ZoomCalloutBuilder.defaultMagnification))
    }

    @Test func rangeStretchesToHoldWhatIsAlreadyThere() {
        // Dragging a corner sets magnification from the frame, so it can land
        // outside what the slider offers. A thumb pinned at the end beside a
        // readout saying 9.4x reads as broken, so the range grows instead.
        #expect(ZoomCalloutBuilder.magnificationRange(including: 9.4) == 1.25...9.4)
        #expect(ZoomCalloutBuilder.magnificationRange(including: 0.5) == 0.5...6)
        // A value already inside changes nothing.
        #expect(ZoomCalloutBuilder.magnificationRange(including: 3) == ZoomCalloutBuilder.magnificationRange)
    }

    @Test func aBrokenMagnificationLeavesTheRangeAlone() {
        #expect(ZoomCalloutBuilder.magnificationRange(including: .nan) == ZoomCalloutBuilder.magnificationRange)
        #expect(ZoomCalloutBuilder.magnificationRange(including: .infinity) == ZoomCalloutBuilder.magnificationRange)
    }

    @Test func magnificationReadsAsATimesNumber() {
        #expect(ZoomCalloutBuilder.magnificationLabel(2) == "2.0\u{00D7}")
        #expect(ZoomCalloutBuilder.magnificationLabel(3.26) == "3.3\u{00D7}")
        #expect(ZoomCalloutBuilder.magnificationLabel(4.5) == "4.5\u{00D7}")
    }

    @Test func calloutShapesSayTheirNames() {
        #expect(ZoomCalloutShape.rectangle.title == "Rectangle")
        #expect(ZoomCalloutShape.circle.title == "Circle")
    }

    @Test func aCalloutRingIsTheLayerOwnBorder() {
        // Which is why the ring's colour has ONE home, the Border row in the
        // Color section, and its thickness has one, the Border slider in
        // Effects. Nothing about a callout needs a second copy of either.
        let style = ZoomCalloutBuilder.defaultStyle
        #expect(style.borderWidth > 0)
        #expect(style.borderColorHex == "#FF3B30")
        let layer = ZoomCalloutBuilder.layer(from: CGPoint(x: 20, y: 30),
                                             to: CGPoint(x: 80, y: 90), canvas: canvas)!
        #expect(layer.colorSlots == [.border])
        #expect(layer.colorHex(for: .border) == "#FF3B30")
    }
}

/// The zoom callout tool's own memory: which silhouette the next callout is
/// drawn in. Whether the tool draws a box or a circle is a choice you make with
/// the tool in your hand, so it has to survive the drag and the relaunch, the
/// way a shape's colour and an arrow's head size do.
@Suite("CalloutStyles")
struct CalloutStylesTests {

    @Test func startsRectangular() {
        #expect(CalloutStyles().shape == .rectangle)
    }

    @Test func newCalloutTakesTheRememberedShape() {
        var styles = CalloutStyles()
        styles.shape = .circle
        let layer = ZoomCalloutBuilder.layer(from: CGPoint(x: 20, y: 30), to: CGPoint(x: 80, y: 90),
                                             canvas: CGSize(width: 400, height: 300),
                                             shape: styles.shape)
        #expect(layer?.zoomCallout?.shape == .circle)
    }

    @Test func aCalloutIsStillARectangleWhenNobodySaysOtherwise() {
        let layer = ZoomCalloutBuilder.layer(from: CGPoint(x: 20, y: 30), to: CGPoint(x: 80, y: 90),
                                             canvas: CGSize(width: 400, height: 300))
        #expect(layer?.zoomCallout?.shape == .rectangle)
    }

    @Test func startsAtTheMagnificationCalloutsHaveAlwaysBeenDrawnAt() {
        // Two, which is what every callout came out at before the tool had a
        // number of its own: nobody who never touches this notices it exists.
        #expect(CalloutStyles().magnification == ZoomCalloutBuilder.defaultMagnification)
    }

    @Test func newCalloutTakesTheRememberedMagnification() {
        var styles = CalloutStyles()
        styles.magnification = 4
        let layer = ZoomCalloutBuilder.layer(from: CGPoint(x: 20, y: 30), to: CGPoint(x: 80, y: 90),
                                             canvas: CGSize(width: 400, height: 300),
                                             magnification: styles.magnification)
        #expect(layer?.zoomCallout?.magnification == 4)
        // ...and the frame it is placed in is that much bigger than the source,
        // so the callout lands at its final size rather than being resized into
        // whatever space is left.
        #expect(layer!.frame.width == layer!.zoomCallout!.sourceRect.width * 4)
    }

    @Test func theToolNumberStaysInsideWhatTheSliderOffers() {
        // A corner pull can leave a PLACED callout at 9.4x, and the slider
        // stretches to show that. The TOOL's own number never does: it is only
        // ever set from the control, so anything outside the range is a corrupt
        // stored value and comes back as something drawable.
        var styles = CalloutStyles()
        styles.magnification = 20
        #expect(styles.magnification == ZoomCalloutBuilder.magnificationRange.upperBound)
        styles.magnification = 0.2
        #expect(styles.magnification == ZoomCalloutBuilder.magnificationRange.lowerBound)
        styles.magnification = .nan
        #expect(styles.magnification == ZoomCalloutBuilder.defaultMagnification)
        #expect(CalloutStyles(magnification: 99).magnification
                == ZoomCalloutBuilder.magnificationRange.upperBound)
    }

    @Test func survivesARoundTripThroughStorage() throws {
        var styles = CalloutStyles()
        styles.shape = .circle
        styles.magnification = 3.5
        let data = try JSONEncoder().encode(styles)
        #expect(try JSONDecoder().decode(CalloutStyles.self, from: data) == styles)
    }

    @Test func aStoredNumberOutsideTheRangeComesBackDrawable() throws {
        let data = Data("{\"shape\":\"circle\",\"magnification\":42}".utf8)
        let styles = try JSONDecoder().decode(CalloutStyles.self, from: data)
        #expect(styles.magnification == ZoomCalloutBuilder.magnificationRange.upperBound)
        #expect(styles.shape == .circle)
    }

    /// A blob written before the tool remembered anything still decodes, and
    /// says rectangle rather than throwing the memory away.
    @Test func emptyStoredBlobDecodesToTheDefault() throws {
        let data = Data("{}".utf8)
        #expect(try JSONDecoder().decode(CalloutStyles.self, from: data) == CalloutStyles())
    }

    /// A memory written when the tool only remembered its silhouette still
    /// decodes, and says two, so an existing install draws exactly what it drew
    /// yesterday until somebody moves the new slider.
    @Test func aMemoryFromBeforeTheNumberExistedStillDecodes() throws {
        let data = Data("{\"shape\":\"circle\"}".utf8)
        let styles = try JSONDecoder().decode(CalloutStyles.self, from: data)
        #expect(styles.shape == .circle)
        #expect(styles.magnification == ZoomCalloutBuilder.defaultMagnification)
    }
}
