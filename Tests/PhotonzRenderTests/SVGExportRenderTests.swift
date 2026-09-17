import AppKit
import CoreGraphics
import Foundation
import PhotonzCore
import PhotonzRender
import Testing

/// The written file, checked by RENDERING IT BACK and comparing it to the
/// app's own render of the same document — never by reading the text
/// (`docs/design/svg-export.md`).
///
/// macOS can rasterize an SVG through `NSImage`, so "does this file draw what
/// the canvas draws" is a question that can actually be asked here rather than
/// asserted by eye.
@Suite("An exported SVG draws what the canvas draws")
struct SVGExportRenderTests {

    static let canvas = CGSize(width: 200, height: 160)

    // MARK: - Shapes

    @Test func aPathComesBackAsTheSameShape() throws {
        let document = PhotonzDocument(canvasSize: Self.canvas, layers: [
            Self.pathLayer(fill: "#2E6BFF", stroke: "#101820", width: 6)
        ])
        try Self.expectTheSamePicture(of: document, name: "path")
    }

    @Test func aRoundedBoxAnOvalAndALineComeBackTheSame() throws {
        var box = AnnotationContent(shape: .rectangle, strokeWidth: 0, colorHex: "#FF9500",
                                    start: .zero, end: CGPoint(x: 90, y: 60),
                                    cornerRadii: CornerRadii(14), fillColorHex: "#FF9500")
        box.strokePosition = .inside
        let oval = AnnotationContent(shape: .ellipse, strokeWidth: 0, colorHex: "#34C759",
                                     start: .zero, end: CGPoint(x: 70, y: 50),
                                     fillColorHex: "#34C759")
        let line = AnnotationContent(shape: .line, strokeWidth: 5, colorHex: "#1C1C1E",
                                     start: CGPoint(x: 0, y: 0), end: CGPoint(x: 80, y: 40))
        let document = PhotonzDocument(canvasSize: Self.canvas, layers: [
            Layer(name: "Box", content: .annotation(box),
                  frame: CGRect(x: 10, y: 10, width: 90, height: 60)),
            Layer(name: "Oval", content: .annotation(oval),
                  frame: CGRect(x: 115, y: 15, width: 70, height: 50)),
            Layer(name: "Line", content: .annotation(line),
                  frame: CGRect(x: 20, y: 100, width: 80, height: 40))
        ])
        try Self.expectTheSamePicture(of: document, name: "shapes")
    }

    // MARK: - The marks a redline is made of

    @Test func anArrowComesBackAsShapes() throws {
        let arrow = AnnotationContent(shape: .arrow, strokeWidth: 5, colorHex: "#FF3B30")
        let document = PhotonzDocument(canvasSize: Self.canvas, layers: [
            AnnotationBuilder.layer(content: arrow, from: CGPoint(x: 30, y: 130),
                                    to: CGPoint(x: 160, y: 40))
        ])
        try Self.expectTheSamePicture(of: document, name: "arrow")
    }

    @Test func anOpenHeadAndADotComeBackAsShapes() throws {
        var open = AnnotationContent(shape: .arrow, strokeWidth: 4, colorHex: "#0A84FF")
        open.arrowheadStyle = .open
        var dot = AnnotationContent(shape: .arrow, strokeWidth: 4, colorHex: "#34C759")
        dot.arrowheadStyle = .hollowDot
        let document = PhotonzDocument(canvasSize: Self.canvas, layers: [
            AnnotationBuilder.layer(content: open, from: CGPoint(x: 25, y: 110),
                                    to: CGPoint(x: 80, y: 40)),
            AnnotationBuilder.layer(content: dot, from: CGPoint(x: 115, y: 40),
                                    to: CGPoint(x: 165, y: 110))
        ])
        try Self.expectTheSamePicture(of: document, name: "arrow-endings")
    }

    /// The caption is the piece of this that is TYPE: its plate is sized from
    /// the words in it and its letters go out as outlines like any other.
    @Test func anArrowsCaptionComesBackAsShapes() throws {
        var arrow = AnnotationContent(shape: .arrow, strokeWidth: 5, colorHex: "#FF3B30")
        arrow.captionFontSize = 14
        arrow.caption = "16 px"
        let document = PhotonzDocument(canvasSize: CGSize(width: 320, height: 220), layers: [
            AnnotationBuilder.layer(content: arrow, from: CGPoint(x: 150, y: 170),
                                    to: CGPoint(x: 270, y: 60))
        ])
        // The canvas lifts the plate off the picture with a soft shadow and the
        // file leaves it out on purpose, because Apple's SVG reader would put
        // it somewhere else entirely (`SVGExport.Writer.Plate`). That halo is
        // the whole of the difference allowed here.
        try Self.expectTheSamePicture(of: document, name: "arrow-caption")
    }

    @Test func aHighlightComesBackAsShapes() throws {
        // Over white, where multiplying and painting straight over agree, so
        // the mark's place and its colour are what is being judged. Apple's SVG
        // reader honours no blend mode at all (`docs/design/svg-export.md`).
        let store = ImageStore()
        let white = SolidImage.make(size: CGSize(width: 200, height: 160), hex: "#FFFFFF")!
        var document = PhotonzDocument.withBaseImage(store.register(white))
        let mark = AnnotationContent(shape: .highlight, strokeWidth: 0, colorHex: "#FFD60A",
                                     start: .zero, end: CGPoint(x: 120, y: 26))
        document.layers.append(Layer(name: "Mark", content: .annotation(mark),
                                     frame: CGRect(x: 30, y: 50, width: 120, height: 26)))
        try Self.expectTheSamePicture(of: document, name: "highlight", store: store)
    }

    @Test func aHighlightSaysItPaintsThroughWhatIsUnderIt() throws {
        let mark = AnnotationContent(shape: .highlight, strokeWidth: 0, colorHex: "#FFD60A",
                                     start: .zero, end: CGPoint(x: 120, y: 26))
        let document = PhotonzDocument(canvasSize: Self.canvas, layers: [
            Layer(name: "Mark", content: .annotation(mark),
                  frame: CGRect(x: 30, y: 50, width: 120, height: 26))
        ])
        let file = SVGExporter.export(document, store: ImageStore()).text
        #expect(file.contains("mix-blend-mode:multiply"))
        #expect(!file.contains("<image"))
    }

    @Test func aMeasurementComesBackAsShapes() throws {
        var content = MeasureContent(start: CGPoint(x: 40, y: 110), end: CGPoint(x: 210, y: 110),
                                     mode: .horizontal)
        content.labelScale = 0.7
        let layer = MeasureBuilder.layer(content: content, from: CGPoint(x: 40, y: 110),
                                         to: CGPoint(x: 210, y: 110))
        let document = PhotonzDocument(canvasSize: CGSize(width: 320, height: 220),
                                       layers: [layer])
        try Self.expectTheSamePicture(of: document, name: "measure", tolerance: 2)
    }

    @Test func aVerticalMeasurementComesBackAsShapes() throws {
        var content = MeasureContent(start: CGPoint(x: 120, y: 40), end: CGPoint(x: 120, y: 180),
                                     mode: .vertical)
        content.labelScale = 0.7
        let layer = MeasureBuilder.layer(content: content, from: CGPoint(x: 120, y: 40),
                                         to: CGPoint(x: 120, y: 180))
        let document = PhotonzDocument(canvasSize: CGSize(width: 320, height: 220),
                                       layers: [layer])
        try Self.expectTheSamePicture(of: document, name: "measure-vertical", tolerance: 2)
    }

    @Test func anAlignmentCheckComesBackAsShapes() throws {
        // A guide down three left edges, one of which is out by six: the
        // dashed run, the ticks, the bracket round the offender and the
        // verdict chip, all of it shapes.
        var content = MeasureContent(start: CGPoint(x: 90, y: 40), end: CGPoint(x: 90, y: 190),
                                     mode: .vertical)
        content.labelScale = 0.6
        content.alignment = AlignmentCheck(items: [
            AlignmentItem(edge: 90, spanStart: 50, spanEnd: 80),
            AlignmentItem(edge: 96, spanStart: 100, spanEnd: 130),
            AlignmentItem(edge: 90, spanStart: 150, spanEnd: 180)
        ], tolerance: 1)
        let layer = MeasureBuilder.layer(content: content, from: CGPoint(x: 90, y: 40),
                                         to: CGPoint(x: 90, y: 190))
        let document = PhotonzDocument(canvasSize: CGSize(width: 320, height: 240),
                                       layers: [layer])
        try Self.expectTheSamePicture(of: document, name: "alignment-check")
    }

    /// A readout that has been moved off the line it measures keeps a leader
    /// back to it, and the caliper draws whole instead of stopping on a plate
    /// that is no longer there (UX-PATTERNS D14).
    @Test func aMovedReadoutKeepsItsLeader() throws {
        var content = MeasureContent(start: CGPoint(x: 60, y: 140), end: CGPoint(x: 230, y: 140),
                                     mode: .horizontal)
        content.labelScale = 0.6
        content.labelPlacement = .clearNegative
        content.labelCrossReach = 46
        content.labelPinned = true
        let layer = MeasureBuilder.layer(content: content, from: CGPoint(x: 60, y: 140),
                                         to: CGPoint(x: 230, y: 140))
        let document = PhotonzDocument(canvasSize: CGSize(width: 320, height: 240),
                                       layers: [layer])
        try Self.expectTheSamePicture(of: document, name: "measure-moved-readout")
    }

    // MARK: - A file that moves

    @Test func anAnimatedFileStillDrawsTheIconWhereTheLapStarts() throws {
        var content = Self.bowedSquare().normalized()
        content.fillColorHex = "#FFD60A"
        content.colorHex = "#1C1C1E"
        content.strokeWidth = 4
        var layer = Layer(name: "Bell", content: .path(content),
                          frame: CGRect(origin: CGPoint(x: 40, y: 30), size: content.bounds.size))
        // Hanging from its mount, which is the case a wrong pivot ruins.
        layer.motions = [LayerMotion(property: .rotation, from: .number(-14), to: .number(14),
                                     timing: MotionTiming(startMS: 0, durationMS: 800),
                                     curve: .easeInOutSine, repeats: .foreverThereAndBack,
                                     pivot: MotionPivot(unit: CGPoint(x: 0.5, y: 0)))]
        let document = PhotonzDocument(canvasSize: Self.canvas, layers: [layer])
        try Self.expectTheSamePicture(of: document, name: "swinging",
                                      animation: .moving(cycleMS: document.motionCycleLengthMS))
    }

    @Test func aFileThatFadesAndRepaintsStillDrawsWhatItStartsAs() throws {
        var content = Self.bowedSquare().normalized()
        content.fillColorHex = "#34C759"
        content.colorHex = "#34C759"
        content.strokeWidth = 0
        var layer = Layer(name: "Blob", content: .path(content),
                          frame: CGRect(origin: CGPoint(x: 30, y: 25), size: content.bounds.size))
        layer.style.opacity = 1
        layer.motions = [
            LayerMotion(property: .opacity, from: .number(60), to: .number(100),
                        timing: MotionTiming(startMS: 0, durationMS: 500),
                        curve: .linear, repeats: .foreverThereAndBack),
            LayerMotion(property: .color, from: .color("#34C759"), to: .color("#FF375F"),
                        timing: MotionTiming(startMS: 0, durationMS: 500),
                        curve: .linear, repeats: .foreverThereAndBack)
        ]
        let document = PhotonzDocument(canvasSize: Self.canvas, layers: [layer])
        try Self.expectTheSamePicture(of: document, name: "fading",
                                      animation: .moving(cycleMS: document.motionCycleLengthMS))
    }

    @Test func aBoxKeepsTheLineRoundIt() throws {
        // A drawn rectangle's edge is a Border in the Effects list
        // (`OutlineRetirement.swift`), so this is the everyday case.
        let box = AnnotationContent(shape: .rectangle, strokeWidth: 6, colorHex: "#0A84FF",
                                    start: .zero, end: CGPoint(x: 120, y: 80),
                                    cornerRadii: CornerRadii(10), fillColorHex: "#FFD60A")
        let document = PhotonzDocument(canvasSize: Self.canvas, layers: [
            Layer(name: "Box", content: .annotation(box),
                  frame: CGRect(x: 20, y: 20, width: 120, height: 80))
        ])
        try Self.expectTheSamePicture(of: document, name: "bordered-box")
    }

    @Test func aGroupKeepsItsNestingAndItsOrder() throws {
        let lower = Self.pathLayer(fill: "#5856D6", stroke: "#FFFFFF", width: 4,
                                   at: CGPoint(x: 0, y: 0))
        let upper = Self.pathLayer(fill: "#FF2D55", stroke: "#FFFFFF", width: 4,
                                   at: CGPoint(x: 30, y: 20))
        let group = Layer(name: "Icon",
                          content: .group(GroupContent(children: [lower, upper])),
                          frame: CGRect(x: 25, y: 20, width: 0, height: 0))
        try Self.expectTheSamePicture(of: PhotonzDocument(canvasSize: Self.canvas, layers: [group]),
                                      name: "group")
    }

    @Test func aLineDrawnInsideTheShapeStaysInside() throws {
        var content = Self.bowedSquare().normalized()
        content.fillColorHex = "#FFFFFF"
        content.colorHex = "#FF375F"
        content.strokeWidth = 10
        content.strokePosition = .inside
        let document = PhotonzDocument(canvasSize: Self.canvas, layers: [
            Layer(name: "Inside", content: .path(content),
                  frame: CGRect(origin: CGPoint(x: 30, y: 20), size: content.bounds.size))
        ])
        try Self.expectTheSamePicture(of: document, name: "inside-line")
    }

    @Test func aLineDrawnOutsideTheShapeStaysOutside() throws {
        var content = Self.bowedSquare().normalized()
        content.fillColorHex = "#FFFFFF"
        content.colorHex = "#0A84FF"
        content.strokeWidth = 10
        content.strokePosition = .outside
        let document = PhotonzDocument(canvasSize: Self.canvas, layers: [
            Layer(name: "Outside", content: .path(content),
                  frame: CGRect(origin: CGPoint(x: 30, y: 20), size: content.bounds.size))
        ])
        try Self.expectTheSamePicture(of: document, name: "outside-line")
    }

    @Test func aShapeWithAHoleInItKeepsTheHole() throws {
        // One ring inside another, counted evenly, which is how an icon gets a
        // hole punched in it.
        var content = PathContent(anchors: [
            PathAnchor(point: CGPoint(x: 0, y: 0)),
            PathAnchor(point: CGPoint(x: 100, y: 0)),
            PathAnchor(point: CGPoint(x: 100, y: 100)),
            PathAnchor(point: CGPoint(x: 0, y: 100))
        ], isClosed: true)
        content.fillColorHex = "#5E5CE6"
        content.strokeWidth = 0
        content.fillRule = .evenOdd
        // The hole, as a second ring inside the first.
        content.anchors += [
            PathAnchor(point: CGPoint(x: 30, y: 30)),
            PathAnchor(point: CGPoint(x: 70, y: 30)),
            PathAnchor(point: CGPoint(x: 70, y: 70)),
            PathAnchor(point: CGPoint(x: 30, y: 70))
        ]
        let document = PhotonzDocument(canvasSize: Self.canvas, layers: [
            Layer(name: "Holed", content: .path(content),
                  frame: CGRect(x: 30, y: 20, width: 100, height: 100))
        ])
        try Self.expectTheSamePicture(of: document, name: "hole")
    }

    // MARK: - An icon drawn in a frame

    /// An icon frame with one shape on it that hangs off the edge, which is
    /// what the frame is for: the file has to cut it at the same place the
    /// canvas does.
    static func iconFrame(radius: CGFloat = 0,
                          at origin: CGPoint = CGPoint(x: 20, y: 20),
                          motions: [LayerMotion] = []) -> Layer {
        var content = bowedSquare().normalized()
        content.fillColorHex = "#2E6BFF"
        content.colorHex = "#2E6BFF"
        content.strokeWidth = 0
        var shape = Layer(name: "Shape", content: .path(content),
                          frame: CGRect(origin: CGPoint(x: 40, y: 20), size: content.bounds.size))
        shape.motions = motions
        var frame = Layer(name: "Icon",
                          content: .group(GroupContent(children: [shape], isFrame: true,
                                                       backgroundHex: "#FFFFFF")),
                          frame: CGRect(origin: origin, size: CGSize(width: 100, height: 80)))
        frame.style.cornerRadii = CornerRadii(radius)
        return frame
    }

    @Test func aFrameCutsOffWhatSticksOutOfItJustAsTheCanvasDoes() throws {
        let document = PhotonzDocument(canvasSize: Self.canvas, layers: [Self.iconFrame()])
        try Self.expectTheSamePicture(of: document, name: "frame-clip")
    }

    @Test func aFrameWithRoundedCornersCutsRound() throws {
        let document = PhotonzDocument(canvasSize: Self.canvas,
                                       layers: [Self.iconFrame(radius: 16)])
        try Self.expectTheSamePicture(of: document, name: "frame-rounded", tolerance: 2)
    }

    @Test func anIconDrawnInAFrameLeavesAsShapesThatMove() throws {
        let motion = LayerMotion(property: .position,
                                 from: .point(CGPoint(x: 40, y: 20)),
                                 to: .point(CGPoint(x: 10, y: 20)),
                                 timing: MotionTiming(startMS: 0, durationMS: 600),
                                 curve: .linear, repeats: .forever)
        var whole = PhotonzDocument(canvasSize: Self.canvas,
                                    layers: [Self.iconFrame(motions: [motion])])
        whole.motionCycleMS = 1200
        let document = try #require(whole.frameDocument(id: whole.layers[0].id))
        let result = SVGExporter.export(document, store: ImageStore(),
                                        animation: .moving(cycleMS: document.motionCycleLengthMS))
        // The whole point: shapes that move, not one photograph of the icon.
        #expect(result.text.contains("<animateTransform"))
        #expect(!result.text.contains("base64"))
        #expect(result.fallbacks.isEmpty)
        #expect(result.unmoved.isEmpty)
        #expect(document.motionCycleLengthMS == 1200)
        try Self.expectTheSamePicture(of: document, name: "frame-moving",
                                      animation: .moving(cycleMS: 1200))
    }

    // MARK: - Gradients

    @Test func aGradientFillAndAGradientOutlineSurviveTheTrip() throws {
        var fill = Paint(hex: "#FF375F")
        fill.becoming(.linear)
        fill.angle = 135
        var edge = Paint(hex: "#0A84FF")
        edge.becoming(.linear)
        edge.angle = 45
        var content = Self.bowedSquare().normalized()
        content.fill = fill
        content.paint = edge
        content.strokeWidth = 8
        content.strokePosition = .center
        let document = PhotonzDocument(canvasSize: Self.canvas, layers: [
            Layer(name: "Ramped", content: .path(content),
                  frame: CGRect(origin: CGPoint(x: 30, y: 20), size: content.bounds.size))
        ])
        try Self.expectTheSamePicture(of: document, name: "gradient")
    }

    @Test func aGradientSpreadingFromAPointSurvivesToo() throws {
        var fill = Paint(hex: "#30D158")
        fill.becoming(.radial)
        var content = Self.bowedSquare().normalized()
        content.fill = fill
        content.strokeWidth = 0
        let document = PhotonzDocument(canvasSize: Self.canvas, layers: [
            Layer(name: "Spread", content: .path(content),
                  frame: CGRect(origin: CGPoint(x: 30, y: 20), size: content.bounds.size))
        ])
        try Self.expectTheSamePicture(of: document, name: "radial")
    }

    // MARK: - Text

    @Test func wordsComeBackAsTheirOwnOutlines() throws {
        let words = TextContent(string: "Icon", fontName: "Helvetica", fontSize: 40,
                                colorHex: "#111111")
        let document = PhotonzDocument(canvasSize: Self.canvas, layers: [
            Layer(name: "Label", content: .text(words),
                  frame: CGRect(x: 20, y: 50, width: 160, height: 50))
        ])
        // Type is the one place the two rasterizers genuinely differ: CoreText
        // smooths the glyphs it draws and the SVG carries their outlines, so
        // the edges are allowed to disagree by a shade. The shapes have to land
        // in the same place, which a whole canvas averaging under one part in
        // 255 is what says.
        try Self.expectTheSamePicture(of: document, name: "text")
    }

    // MARK: - What has no vector answer

    @Test func aShapeWearingAShadowThrowsTheSameShadowInTheFile() throws {
        var layer = Self.pathLayer(fill: "#FFD60A", stroke: "#1C1C1E", width: 4)
        layer.style.effects = [.shadow(ShadowStyle(radius: 6,
                                                   offset: CGSize(width: 6, height: 10),
                                                   colorHex: "#000000", opacity: 0.6))]
        let document = PhotonzDocument(canvasSize: Self.canvas, layers: [layer])
        let result = SVGExporter.export(document, store: ImageStore())
        #expect(result.fallbacks.isEmpty)
        #expect(!result.text.contains("<image "))
        try Self.expectTheSamePicture(of: document, name: "shadowed")
        // ...and the shadow is really in the file, rather than the file
        // happening to be close enough to a shape with no shadow at all.
        try Self.expectADifferentPicture(of: document, from: Self.withoutEffects(document),
                                         name: "shadowed")
    }

    @Test func aShapeWearingABlurComesBackJustAsSoft() throws {
        var layer = Self.pathLayer(fill: "#34C759", stroke: "#0A5C2A", width: 5)
        layer.style.effects = [.blur(BlurEffect(radius: 5))]
        let document = PhotonzDocument(canvasSize: Self.canvas, layers: [layer])
        let result = SVGExporter.export(document, store: ImageStore())
        #expect(result.fallbacks.isEmpty)
        #expect(!result.text.contains("<image "))
        try Self.expectTheSamePicture(of: document, name: "blurred")
        try Self.expectADifferentPicture(of: document, from: Self.withoutEffects(document),
                                         name: "blurred")
    }

    @Test func aContactShadowAndASoftLiftBothLandInTheRightOrder() throws {
        var layer = Self.pathLayer(fill: "#FFFFFF", stroke: "#D1D1D6", width: 2)
        layer.style.effects = [
            .shadow(ShadowStyle(radius: 2, offset: CGSize(width: 0, height: 1),
                                colorHex: "#000000", opacity: 0.5)),
            .shadow(ShadowStyle(radius: 14, offset: CGSize(width: 0, height: 10),
                                colorHex: "#0A2540", opacity: 0.45))
        ]
        let document = PhotonzDocument(canvasSize: Self.canvas, layers: [layer])
        #expect(SVGExporter.export(document, store: ImageStore()).fallbacks.isEmpty)
        try Self.expectTheSamePicture(of: document, name: "two-shadows")
    }

    /// A faded shape keeps its picture: Apple's SVG reader fades anything
    /// filtered twice over, once going in and once coming out, so a half-faded
    /// shape would come back a quarter of itself.
    @Test func aFadedShapeThatThrowsAShadowKeepsItsPicture() throws {
        var layer = Self.pathLayer(fill: "#5856D6", stroke: "#1C1C1E", width: 3)
        layer.style.effects = [.shadow(ShadowStyle(radius: 8,
                                                   offset: CGSize(width: 4, height: 8),
                                                   colorHex: "#000000", opacity: 0.7))]
        layer.style.opacity = 0.45
        let document = PhotonzDocument(canvasSize: Self.canvas, layers: [layer])
        let result = SVGExporter.export(document, store: ImageStore())
        #expect(result.fallbacks.count == 1)
        try Self.expectTheSamePicture(of: document, name: "faded-shadow")
    }

    @Test func aFadedShapeThatIsOnlySoftKeepsItsPictureToo() throws {
        var layer = Self.pathLayer(fill: "#5856D6", stroke: "#1C1C1E", width: 3)
        layer.style.effects = [.blur(BlurEffect(radius: 5))]
        layer.style.opacity = 0.45
        let document = PhotonzDocument(canvasSize: Self.canvas, layers: [layer])
        #expect(SVGExporter.export(document, store: ImageStore()).fallbacks.count == 1)
        try Self.expectTheSamePicture(of: document, name: "faded-blur")
    }

    @Test func aSoftenedShapeThrowsASoftenedShadow() throws {
        var layer = Self.pathLayer(fill: "#FF9500", stroke: "#FF9500", width: 0)
        layer.style.effects = [.blur(BlurEffect(radius: 4)),
                               .shadow(ShadowStyle(radius: 6, offset: CGSize(width: 5, height: 5),
                                                   colorHex: "#000000", opacity: 0.6))]
        let document = PhotonzDocument(canvasSize: Self.canvas, layers: [layer])
        #expect(SVGExporter.export(document, store: ImageStore()).fallbacks.isEmpty)
        try Self.expectTheSamePicture(of: document, name: "soft-and-shadowed")
    }

    /// A ring round the shape is a SECOND element, so the shadow has to be
    /// cast from both at once. It is: the drawing goes inside a viewport of
    /// its own and the filter rides that.
    @Test func aShapeWearingARingAndAShadowGoesOutAsShapes() throws {
        var layer = Self.pathLayer(fill: "#FFD60A", stroke: "#1C1C1E", width: 4)
        layer.style.effects = [
            .border(BorderEffect(width: 3, colorHex: "#FF3B30", position: .outside)),
            .shadow(ShadowStyle(radius: 6, offset: CGSize(width: 6, height: 10),
                                colorHex: "#000000", opacity: 0.6))
        ]
        let document = PhotonzDocument(canvasSize: Self.canvas, layers: [layer])
        let result = SVGExporter.export(document, store: ImageStore())
        #expect(result.fallbacks.isEmpty)
        #expect(!result.text.contains("<image "))
        try Self.expectTheSamePicture(of: document, name: "ringed-shadow")
        try Self.expectADifferentPicture(of: document, from: Self.withoutEffects(document),
                                         name: "ringed-shadow")
    }

    /// A filled box with a line round it is a fill and a stroke, one after the
    /// other, which is the commonest two-piece drawing there is.
    @Test func aFilledBoxWithALineRoundItThrowsItsShadowAsShapes() throws {
        var box = AnnotationContent(shape: .rectangle, strokeWidth: 4, colorHex: "#1C1C1E",
                                    start: .zero, end: CGPoint(x: 90, y: 60),
                                    cornerRadii: CornerRadii(10), fillColorHex: "#FFFFFF")
        box.strokePosition = .center
        var layer = Layer(name: "Card", content: .annotation(box),
                          frame: CGRect(x: 40, y: 40, width: 90, height: 60))
        layer.style.effects = [.shadow(ShadowStyle(radius: 10, offset: CGSize(width: 8, height: 14),
                                                   colorHex: "#000000", opacity: 0.85))]
        let document = PhotonzDocument(canvasSize: Self.canvas, layers: [layer])
        let result = SVGExporter.export(document, store: ImageStore())
        #expect(result.fallbacks.isEmpty)
        #expect(!result.text.contains("<image "))
        try Self.expectTheSamePicture(of: document, name: "card-shadow")
        try Self.expectADifferentPicture(of: document, from: Self.withoutEffects(document),
                                         name: "card-shadow")
    }

    /// The other half of the gap: a shadow on a shape drawn INSIDE a frame
    /// that sits anywhere but the canvas corner.
    @Test func aShadowedShapeInsideAFrameGoesOutAsShapes() throws {
        var shape = Self.pathLayer(fill: "#2E6BFF", stroke: "#2E6BFF", width: 0,
                                   at: CGPoint(x: 15, y: 10))
        shape.name = "Inside"
        shape.style.effects = [.shadow(ShadowStyle(radius: 5, offset: CGSize(width: 4, height: 8),
                                                   colorHex: "#000000", opacity: 0.55))]
        let frame = Layer(name: "Icon",
                          content: .group(GroupContent(children: [shape], isFrame: true,
                                                       backgroundHex: "#FFFFFF")),
                          frame: CGRect(x: 25, y: 20, width: 150, height: 130))
        let document = PhotonzDocument(canvasSize: Self.canvas, layers: [frame])
        let result = SVGExporter.export(document, store: ImageStore())
        #expect(result.fallbacks.isEmpty)
        #expect(!result.text.contains("<image "))
        // The whole of the allowance is the SHADE of the shadow where it falls
        // on the frame's opaque surface, and none of it is the placing: the
        // canvas mixes a shadow into what is under it in linear light and
        // every SVG reader mixes it in sRGB, so a 55% black over white comes
        // back 134 where the canvas draws 192. It is not this case: the same
        // shape with no frame at all, over a white canvas, is 2.36 off too,
        // and a shape in a group with nothing under it is 0.002 off.
        try Self.expectTheSamePicture(of: document, name: "framed-shadow", tolerance: 2.5)
        try Self.expectADifferentPicture(of: document, from: Self.withoutEffects(document),
                                         name: "framed-shadow")
    }

    /// The same thing with nothing under it, which is where the placing can be
    /// judged to the last part in 255 rather than through the shade of a
    /// shadow falling on an opaque surface.
    @Test func aShadowedShapeInsideAGroupThatMovesItLandsExactlyWhereItShould() throws {
        var shape = Self.pathLayer(fill: "#2E6BFF", stroke: "#2E6BFF", width: 0,
                                   at: CGPoint(x: 15, y: 10))
        shape.name = "Inside"
        shape.style.effects = [.shadow(ShadowStyle(radius: 8, offset: CGSize(width: 10, height: 14),
                                                   colorHex: "#000000", opacity: 0.8))]
        let holder = Layer(name: "Holder", content: .group(GroupContent(children: [shape])),
                           frame: CGRect(x: 25, y: 20, width: 0, height: 0))
        let document = PhotonzDocument(canvasSize: Self.canvas, layers: [holder])
        let result = SVGExporter.export(document, store: ImageStore())
        #expect(result.fallbacks.isEmpty)
        #expect(!result.text.contains("<image "))
        try Self.expectTheSamePicture(of: document, name: "grouped-shadow")
        try Self.expectADifferentPicture(of: document, from: Self.withoutEffects(document),
                                         name: "grouped-shadow")
    }

    /// Both gaps at once, two groups deep: a ringed shape wearing a shadow,
    /// inside a group, inside a frame, none of them at the canvas corner.
    @Test func aRingedShadowedShapeTwoGroupsDeepGoesOutAsShapes() throws {
        var shape = Self.pathLayer(fill: "#FF9500", stroke: "#1C1C1E", width: 3,
                                   at: CGPoint(x: 10, y: 5))
        shape.name = "Inside"
        shape.style.effects = [
            .border(BorderEffect(width: 2, colorHex: "#34C759", position: .outside)),
            .shadow(ShadowStyle(radius: 5, offset: CGSize(width: 3, height: 6),
                                colorHex: "#000000", opacity: 0.5))
        ]
        let holder = Layer(name: "Holder", content: .group(GroupContent(children: [shape])),
                           frame: CGRect(x: 12, y: 8, width: 0, height: 0))
        let frame = Layer(name: "Icon",
                          content: .group(GroupContent(children: [holder], isFrame: true,
                                                       backgroundHex: "#FFFFFF")),
                          frame: CGRect(x: 18, y: 14, width: 160, height: 130))
        let document = PhotonzDocument(canvasSize: Self.canvas, layers: [frame])
        let result = SVGExporter.export(document, store: ImageStore())
        #expect(result.fallbacks.isEmpty)
        #expect(!result.text.contains("<image "))
        // The whole of the allowance is the SHADE of the shadow where it falls
        // on the frame's opaque surface, and none of it is the placing: the
        // canvas mixes a shadow into what is under it in linear light and
        // every SVG reader mixes it in sRGB, so a 55% black over white comes
        // back 134 where the canvas draws 192. It is not this case: the same
        // shape with no frame at all, over a white canvas, is 2.36 off too,
        // and a shape in a group with nothing under it is 0.002 off.
        try Self.expectTheSamePicture(of: document, name: "deep-shadow", tolerance: 2.5)
        try Self.expectADifferentPicture(of: document, from: Self.withoutEffects(document),
                                         name: "deep-shadow")
    }

    @Test func aShadowSpreadWiderThanItsShapeStillGoesOutAsAPicture() throws {
        var layer = Self.pathLayer(fill: "#FFD60A", stroke: "#1C1C1E", width: 4)
        layer.style.effects = [.shadow(ShadowStyle(radius: 6,
                                                   offset: CGSize(width: 4, height: 6),
                                                   spread: 5))]
        let document = PhotonzDocument(canvasSize: Self.canvas, layers: [layer])
        let result = SVGExporter.export(document, store: ImageStore())
        #expect(result.fallbacks.count == 1)
        #expect(result.text.contains("<image "))
        try Self.expectTheSamePicture(of: document, name: "spread-shadow")
    }

    @Test func aPhotographGoesOutAsItsOwnPixels() throws {
        let store = ImageStore()
        let ref = store.register(Self.checkerboard(40, 30))
        let document = PhotonzDocument(canvasSize: Self.canvas, layers: [
            Layer(name: "Photo", content: .image(ref),
                  frame: CGRect(x: 30, y: 30, width: 40, height: 30))
        ])
        try Self.expectTheSamePicture(of: document, name: "photo", store: store)
    }

    /// The whole point of the task: an icon drawn on a blank canvas, written
    /// exactly as Export writes it. The document is built the way the app
    /// builds one (`EditorState.newBlankCanvas`) — a real full-size white
    /// bitmap as a locked Background layer — so this is the same file the
    /// `svg-export-walk` puts on disk.
    @Test func anIconOnABlankCanvasCarriesNoPictureAtAll() throws {
        let store = ImageStore()
        let size = CGSize(width: 900, height: 700)
        let white = try #require(SolidImage.make(size: size, hex: "#FFFFFF"))
        var document = PhotonzDocument.withBaseImage(store.register(white))
        var icon = Self.bowedSquare().normalized()
        icon.fillColorHex = "#2E6BFF"
        icon.colorHex = "#2E6BFF"
        icon.strokeWidth = 0
        document.layers.append(Layer(name: "Icon", content: .path(icon),
                                     frame: CGRect(origin: CGPoint(x: 220, y: 200),
                                                   size: icon.bounds.size)))
        let result = SVGExporter.export(document, store: store)
        #expect(!result.text.contains("base64"),
                "a flat background went out as an embedded picture")
        #expect(result.text.contains("<rect"))
        // It used to be seventeen kilobytes of white; an icon is a few hundred
        // bytes of shapes.
        let bytes = try #require(result.text.data(using: .utf8)).count
        #expect(bytes < 1000, "the file is \(bytes) bytes")
        try Self.expectTheSamePicture(of: document, name: "icon-on-white", store: store)
    }

    @Test func aBackgroundPaintedAnyOtherColourIsARectangleToo() throws {
        let store = ImageStore()
        let green = try #require(SolidImage.make(size: Self.canvas, hex: "#34C759"))
        let document = PhotonzDocument.withBaseImage(store.register(green))
        let result = SVGExporter.export(document, store: store)
        #expect(result.text.contains("fill=\"#34C759\""))
        #expect(!result.text.contains("base64"))
        try Self.expectTheSamePicture(of: document, name: "green-canvas", store: store)
    }

    /// A canvas somebody has drawn pixels onto is not flat any more, and it
    /// must keep every one of them.
    @Test func aBackgroundWithOnePixelPaintedOnItKeepsItsPixels() throws {
        let store = ImageStore()
        let marked = try #require(FlatBitmapTests.white(Int(Self.canvas.width),
                                                        Int(Self.canvas.height),
                                                        mark: CGRect(x: 97, y: 61,
                                                                     width: 1, height: 1)))
        let document = PhotonzDocument.withBaseImage(store.register(marked))
        let result = SVGExporter.export(document, store: store)
        #expect(result.text.contains("base64"))
        try Self.expectTheSamePicture(of: document, name: "marked-canvas", store: store)
    }

    // MARK: - The comparison itself

    /// Renders the document through the real engine, renders the exported file
    /// through the system's own SVG reader, and insists the two agree.
    ///
    /// `tolerance` is the average difference per colour channel allowed over
    /// the whole canvas, out of 255. A handful is antialiasing; anything more
    /// is a shape in the wrong place.
    static func expectTheSamePicture(of document: PhotonzDocument, name: String,
                                     store: ImageStore = ImageStore(),
                                     tolerance: Double = 1,
                                     animation: SVGExport.Animation = .still,
                                     sourceLocation: SourceLocation = #_sourceLocation) throws {
        let renderer = DocumentRenderer()
        // A file that carries the motion still has to DRAW something standing
        // still, for every reader that does not play it. What it draws is the
        // top of the lap, so that is what the canvas is asked for too.
        let canvasShows = animation.isMoving ? document.moved(toMotionTimeMS: 0) : document
        let mine = try #require(renderer.render(canvasShows, store: store),
                                "the app could not draw \(name)", sourceLocation: sourceLocation)
        let result = SVGExporter.export(document, store: store, renderer: renderer,
                                        animation: animation)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("photonz-svg-\(name)-\(UUID().uuidString).svg")
        try result.text.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let theirs = try #require(rasterize(url, size: document.canvasSize),
                                  "the system could not read back \(name)",
                                  sourceLocation: sourceLocation)
        let difference = meanDifference(between: pixels(of: mine, size: document.canvasSize),
                                        and: theirs)
        if ProcessInfo.processInfo.environment["PHOTONZ_SVG_DIFF"] != nil {
            print("SVGDIFF \(name): \(difference)")
        }
        #expect(difference <= tolerance,
                "\(name): the exported file draws \(difference) off the canvas's own render",
                sourceLocation: sourceLocation)
    }

    /// The same document with every blur, shadow and glow taken off it: what
    /// the file would look like if the effects had quietly gone missing.
    static func withoutEffects(_ document: PhotonzDocument) -> PhotonzDocument {
        func strip(_ layers: [Layer]) -> [Layer] {
            layers.map { layer in
                var stripped = layer
                stripped.style.effects = stripped.style.effects.filter { $0.kind == .border }
                // A shadow inside a frame is still an effect that has to be in
                // the file, so the stripping goes all the way down.
                if case .group(var group) = stripped.content {
                    group.children = strip(group.children)
                    stripped.content = .group(group)
                }
                return stripped
            }
        }
        var bare = document
        bare.layers = strip(bare.layers)
        return bare
    }

    /// The exported file of `document` does NOT draw `other`, which is what
    /// says an effect really made it into the file rather than the two
    /// pictures being close enough to pass by luck.
    static func expectADifferentPicture(of document: PhotonzDocument, from other: PhotonzDocument,
                                        name: String, by: Double = 2,
                                        sourceLocation: SourceLocation = #_sourceLocation) throws {
        let renderer = DocumentRenderer()
        let bare = try #require(renderer.render(other, store: ImageStore()),
                                "the app could not draw \(name) without its effects",
                                sourceLocation: sourceLocation)
        let result = SVGExporter.export(document, store: ImageStore(), renderer: renderer)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("photonz-svg-\(name)-bare-\(UUID().uuidString).svg")
        try result.text.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        let theirs = try #require(rasterize(url, size: document.canvasSize),
                                  "the system could not read back \(name)",
                                  sourceLocation: sourceLocation)
        let difference = meanDifference(between: pixels(of: bare, size: document.canvasSize),
                                        and: theirs)
        #expect(difference > by,
                "\(name): the exported file draws only \(difference) away from the same shape with no effects on it, so the effect may not be in the file at all",
                sourceLocation: sourceLocation)
    }

    /// An SVG file drawn at exactly `size`, through whatever the system has.
    static func rasterize(_ url: URL, size: CGSize) -> [UInt8]? {
        guard let image = NSImage(contentsOf: url) else { return nil }
        let width = Int(size.width), height = Int(size.height)
        guard let context = CGContext(data: nil, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)
                                          ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        let previous = NSGraphicsContext.current
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        image.draw(in: CGRect(origin: .zero, size: size),
                   from: .zero, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.current = previous
        guard let drawn = context.makeImage() else { return nil }
        return pixels(of: drawn, size: size)
    }

    /// A picture as straight premultiplied bytes at `size`, whatever it was.
    static func pixels(of image: CGImage, size: CGSize) -> [UInt8] {
        let width = Int(size.width), height = Int(size.height)
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        bytes.withUnsafeMutableBytes { raw in
            guard let context = CGContext(data: raw.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: CGColorSpace(name: CGColorSpace.sRGB)
                                              ?? CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return }
            context.draw(image, in: CGRect(origin: .zero, size: size))
        }
        return bytes
    }

    static func meanDifference(between mine: [UInt8], and theirs: [UInt8]) -> Double {
        guard mine.count == theirs.count, !mine.isEmpty else { return .infinity }
        var total = 0
        for index in mine.indices {
            total += abs(Int(mine[index]) - Int(theirs[index]))
        }
        return Double(total) / Double(mine.count)
    }

    // MARK: - Scenery

    static func bowedSquare() -> PathContent {
        PathContent(anchors: [
            PathAnchor(point: CGPoint(x: 0, y: 0)),
            PathAnchor(point: CGPoint(x: 100, y: 0), handleOut: CGPoint(x: 40, y: 30)),
            PathAnchor(point: CGPoint(x: 100, y: 100), handleIn: CGPoint(x: 40, y: -30)),
            PathAnchor(point: CGPoint(x: 0, y: 100))
        ], isClosed: true)
    }

    /// A drawn path, the way the Pen commits one: stated against its own top
    /// left corner, in a frame exactly the size of the shape
    /// (`PathContent.normalized`).
    static func pathLayer(fill: String, stroke: String, width: CGFloat,
                          at origin: CGPoint = CGPoint(x: 30, y: 20)) -> Layer {
        var content = bowedSquare().normalized()
        content.fillColorHex = fill
        content.colorHex = stroke
        content.strokeWidth = width
        content.strokePosition = .center
        return Layer(name: "Shape", content: .path(content),
                     frame: CGRect(origin: origin, size: content.bounds.size))
    }

    static func checkerboard(_ width: Int, _ height: Int) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                bytesPerRow: width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)
                                    ?? CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        for row in 0..<height {
            for column in 0..<width {
                let dark = (row / 5 + column / 5) % 2 == 0
                context.setFillColor(CGColor(srgbRed: dark ? 0.15 : 0.85,
                                             green: 0.3, blue: dark ? 0.7 : 0.2, alpha: 1))
                context.fill(CGRect(x: column, y: row, width: 1, height: 1))
            }
        }
        return context.makeImage()!
    }
}
