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

    @Test func aShapeWearingAShadowLandsWhereItWasAsAPicture() throws {
        var layer = Self.pathLayer(fill: "#FFD60A", stroke: "#1C1C1E", width: 4)
        layer.style.effects = [.shadow(ShadowStyle(radius: 6,
                                                   offset: CGSize(width: 4, height: 6)))]
        let document = PhotonzDocument(canvasSize: Self.canvas, layers: [layer])
        let result = SVGExporter.export(document, store: ImageStore())
        #expect(result.fallbacks.count == 1)
        try Self.expectTheSamePicture(of: document, name: "shadowed")
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
        #expect(difference <= tolerance,
                "\(name): the exported file draws \(difference) off the canvas's own render",
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
