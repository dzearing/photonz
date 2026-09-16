import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// What you drew, written out as a real SVG: the shapes as shapes
/// (`docs/design/svg-export.md`).
@Suite("Export what you drew as SVG")
struct SVGExportTests {

    // A square with one side bowed out: two straight runs and a curve, which
    // is the smallest shape that proves both survive the trip.
    static func bowedSquare() -> PathContent {
        PathContent(anchors: [
            PathAnchor(point: CGPoint(x: 0, y: 0)),
            PathAnchor(point: CGPoint(x: 100, y: 0), handleOut: CGPoint(x: 40, y: 30)),
            PathAnchor(point: CGPoint(x: 100, y: 100), handleIn: CGPoint(x: 40, y: -30)),
            PathAnchor(point: CGPoint(x: 0, y: 100))
        ], isClosed: true)
    }

    /// A leaf: two points and two curves, the smallest closed shape there is.
    /// The run out bows one way and the run home bows the other.
    static func leaf() -> PathContent {
        PathContent(anchors: [
            PathAnchor(point: CGPoint(x: 0, y: 50), handleIn: CGPoint(x: -30, y: -40),
                       handleOut: CGPoint(x: 30, y: 40), kind: .smooth),
            PathAnchor(point: CGPoint(x: 100, y: 50), handleIn: CGPoint(x: 30, y: 40),
                       handleOut: CGPoint(x: -30, y: -40), kind: .smooth)
        ], isClosed: true)
    }

    static func pathLayer(_ content: PathContent = bowedSquare(),
                          at origin: CGPoint = CGPoint(x: 20, y: 30)) -> Layer {
        Layer(name: "Shape", content: .path(content),
              frame: CGRect(origin: origin, size: CGSize(width: 100, height: 100)))
    }

    static func document(_ layers: [Layer],
                         size: CGSize = CGSize(width: 240, height: 240)) -> PhotonzDocument {
        PhotonzDocument(canvasSize: size, layers: layers)
    }

    /// A picture maker that hands back four bytes and the layer's own box, so
    /// the fallback path can be exercised without a renderer.
    static let stubPicture: SVGExport.PictureMaker = { layer, origin in
        SVGExport.Picture(png: Data([1, 2, 3, 4]),
                          box: CGRect(origin: origin, size: layer.frame.size))
    }

    /// A text outliner that hands back one triangle, standing in for glyphs.
    static let stubOutliner: SVGExport.TextOutliner = { _, _ in "M0 0 L10 0 L5 10 Z" }

    static func write(_ document: PhotonzDocument,
                      picture: SVGExport.PictureMaker? = stubPicture,
                      outlineText: SVGExport.TextOutliner? = stubOutliner) -> SVGExport.Result {
        SVGExport.write(document, picture: picture, outlineText: outlineText)
    }

    // MARK: - The file itself

    @Test func theFileIsAnSVGTheSizeOfTheCanvas() {
        let svg = Self.write(Self.document([Self.pathLayer()])).text
        #expect(svg.hasPrefix("<svg xmlns=\"http://www.w3.org/2000/svg\""))
        #expect(svg.contains("width=\"240\""))
        #expect(svg.contains("height=\"240\""))
        #expect(svg.contains("viewBox=\"0 0 240 240\""))
        #expect(svg.hasSuffix("</svg>\n"))
    }

    @Test func itIsIndentedSoAPersonCanReadIt() {
        let svg = Self.write(Self.document([Self.pathLayer()])).text
        #expect(svg.contains("\n  <path "))
    }

    @Test func nothingWritesADefinitionsBlockItDoesNotNeed() {
        let svg = Self.write(Self.document([Self.pathLayer()])).text
        #expect(!svg.contains("<defs>"))
    }

    // MARK: - A path

    @Test func aStraightRunWritesStraightAndACurveWritesCurved() {
        let svg = Self.write(Self.document([Self.pathLayer()])).text
        let d = Self.attribute("d", in: svg)
        // Drawn in the layer's own space and placed by the group-free
        // translate on the element, so the outline itself starts at zero.
        #expect(d.hasPrefix("M0 0"))
        #expect(d.contains("L100 0"))      // the straight top edge
        #expect(d.contains("C140 30"))     // the bowed right-hand side
        #expect(d.hasSuffix("Z"))          // closed, because the shape is
    }

    @Test func anOpenPathIsNotClosedAndPaintsNoInside() {
        var open = Self.bowedSquare()
        open.isClosed = false
        let svg = Self.write(Self.document([Self.pathLayer(open)])).text
        #expect(!Self.attribute("d", in: svg).hasSuffix("Z"))
        #expect(svg.contains("fill=\"none\""))
    }

    @Test func aPathKeepsTheFillOutlineAndWidthItHasOnTheCanvas() {
        var content = Self.bowedSquare()
        content.fillColorHex = "#2233FF"
        content.colorHex = "#11AA22"
        content.strokeWidth = 6
        let svg = Self.write(Self.document([Self.pathLayer(content)])).text
        #expect(svg.contains("fill=\"#2233FF\""))
        #expect(svg.contains("stroke=\"#11AA22\""))
        #expect(svg.contains("stroke-width=\"6\""))
    }

    @Test func aShapeWithAHoleKeepsTheRuleThatMakesTheHole() {
        var content = Self.bowedSquare()
        content.fillRule = .evenOdd
        let svg = Self.write(Self.document([Self.pathLayer(content)])).text
        #expect(svg.contains("fill-rule=\"evenodd\""))
    }

    @Test func theFileSaysTopLeftTheWayTheDocumentDoes() {
        // Nothing is flipped on the way out: a shape 30 points down the
        // canvas is 30 points down the file.
        let svg = Self.write(Self.document([Self.pathLayer()])).text
        #expect(svg.contains("translate(20 30)"))
        #expect(!svg.contains("scale(1 -1)"))
    }

    // MARK: - The shapes that are not paths

    @Test func aRoundedRectangleKeepsItsRounding() {
        let box = AnnotationContent(shape: .rectangle, strokeWidth: 0,
                                    start: .zero, end: CGPoint(x: 120, y: 80),
                                    cornerRadii: CornerRadii(12), fillColorHex: "#3355FF")
        let layer = Layer(name: "Box", content: .annotation(box),
                          frame: CGRect(x: 10, y: 10, width: 120, height: 80))
        let svg = Self.write(Self.document([layer])).text
        #expect(svg.contains("<rect "))
        #expect(svg.contains("rx=\"12\""))
        #expect(svg.contains("fill=\"#3355FF\""))
    }

    @Test func cornersRoundedOneAtATimeWriteAsAPath() {
        let box = AnnotationContent(shape: .rectangle, strokeWidth: 0,
                                    start: .zero, end: CGPoint(x: 120, y: 80),
                                    cornerRadii: CornerRadii(topLeft: 20, topRight: 0,
                                                             bottomRight: 0, bottomLeft: 0),
                                    fillColorHex: "#3355FF")
        let layer = Layer(name: "Box", content: .annotation(box),
                          frame: CGRect(x: 0, y: 0, width: 120, height: 80))
        let svg = Self.write(Self.document([layer])).text
        // One rounded corner is not something <rect> can say, so it is a path
        // with one arc in it.
        #expect(!svg.contains("<rect "))
        #expect(Self.attribute("d", in: svg).contains("A20 20"))
    }

    @Test func anEllipseWritesAsAnEllipse() {
        let oval = AnnotationContent(shape: .ellipse, strokeWidth: 0,
                                     start: .zero, end: CGPoint(x: 100, y: 60),
                                     fillColorHex: "#FF9900")
        let layer = Layer(name: "Oval", content: .annotation(oval),
                          frame: CGRect(x: 0, y: 0, width: 100, height: 60))
        let svg = Self.write(Self.document([layer])).text
        #expect(svg.contains("<ellipse "))
        #expect(svg.contains("cx=\"50\""))
        #expect(svg.contains("cy=\"30\""))
        #expect(svg.contains("rx=\"50\""))
        #expect(svg.contains("ry=\"30\""))
    }

    @Test func aLineWritesAsALine() {
        let mark = AnnotationContent(shape: .line, strokeWidth: 3, colorHex: "#000000",
                                     start: CGPoint(x: 0, y: 0), end: CGPoint(x: 60, y: 40))
        let layer = Layer(name: "Line", content: .annotation(mark),
                          frame: CGRect(x: 5, y: 5, width: 60, height: 40))
        let svg = Self.write(Self.document([layer])).text
        #expect(svg.contains("<line "))
        #expect(svg.contains("x2=\"60\""))
        #expect(svg.contains("y2=\"40\""))
        #expect(svg.contains("stroke-width=\"3\""))
        // Round is what a line ends in unless somebody says otherwise, and it
        // is written out rather than left to the reader: SVG's own default is
        // a flat end, so a file that did not say would come back chopped.
        #expect(svg.contains("stroke-linecap=\"round\""))
    }

    @Test func aLineCarriesTheEndItWasGiven() {
        var mark = AnnotationContent(shape: .line, strokeWidth: 3, colorHex: "#000000",
                                     start: CGPoint(x: 0, y: 0), end: CGPoint(x: 60, y: 40))
        mark.lineEnd = .square
        let layer = Layer(name: "Line", content: .annotation(mark),
                          frame: CGRect(x: 5, y: 5, width: 60, height: 40))
        #expect(Self.write(Self.document([layer])).text.contains("stroke-linecap=\"square\""))
        mark.lineEnd = .flat
        let flat = Layer(name: "Line", content: .annotation(mark),
                         frame: CGRect(x: 5, y: 5, width: 60, height: 40))
        #expect(Self.write(Self.document([flat])).text.contains("stroke-linecap=\"butt\""))
    }

    @Test func aBorderWritesAsAStrokeRoundTheShape() {
        // A box's edge is a Border in the Effects list
        // (`OutlineRetirement.swift`), so this is how every drawn rectangle
        // arrives.
        let box = AnnotationContent(shape: .rectangle, strokeWidth: 4, colorHex: "#123456",
                                    start: .zero, end: CGPoint(x: 100, y: 100))
        let layer = Layer(name: "Box", content: .annotation(box),
                          frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        let svg = Self.write(Self.document([layer])).text
        #expect(svg.contains("stroke=\"#123456\""))
        #expect(svg.contains("stroke-width=\"4\""))
    }

    // MARK: - Text

    @Test func textWritesAsItsOutlineWithTheWordsKept() {
        let words = TextContent(string: "Hello", fontSize: 20, colorHex: "#FFFFFF")
        let layer = Layer(name: "Label", content: .text(words),
                          frame: CGRect(x: 4, y: 8, width: 80, height: 24))
        let result = Self.write(Self.document([layer]))
        #expect(result.text.contains("<title>Hello</title>"))
        #expect(result.text.contains("M0 0 L10 0 L5 10 Z"))
        #expect(result.fallbacks.isEmpty)
    }

    @Test func wordsWithAnAngleBracketInThemAreEscaped() {
        let words = TextContent(string: "a < b & c")
        let layer = Layer(name: "Label", content: .text(words),
                          frame: CGRect(x: 0, y: 0, width: 80, height: 24))
        let svg = Self.write(Self.document([layer])).text
        #expect(svg.contains("<title>a &lt; b &amp; c</title>"))
    }

    @Test func textWithNothingToOutlineItFallsBackToAPicture() {
        let words = TextContent(string: "Hello")
        let layer = Layer(name: "Label", content: .text(words),
                          frame: CGRect(x: 0, y: 0, width: 80, height: 24))
        let result = Self.write(Self.document([layer]), outlineText: nil)
        #expect(result.text.contains("<image "))
        #expect(result.fallbacks.contains { $0.layerName == "Label" })
    }

    // MARK: - Groups

    @Test func aGroupWritesAsAGroupInTheOrderTheLayersListShows() {
        var lowerShape = Self.bowedSquare()
        lowerShape.fillColorHex = "#111111"
        var upperShape = Self.bowedSquare()
        upperShape.fillColorHex = "#222222"
        let group = Layer(name: "Icon",
                          content: .group(GroupContent(children: [
                              Self.pathLayer(lowerShape, at: .zero),
                              Self.pathLayer(upperShape, at: CGPoint(x: 10, y: 10))
                          ])),
                          frame: CGRect(x: 40, y: 50, width: 0, height: 0))
        let svg = Self.write(Self.document([group])).text
        #expect(svg.contains("<g transform=\"translate(40 50)\">"))
        // Index 0 draws first, so it is written first; the one over it comes
        // second, and the file is nested inside the group.
        let first = svg.range(of: "#111111")
        let second = svg.range(of: "#222222")
        #expect(first != nil && second != nil)
        if let first, let second { #expect(first.lowerBound < second.lowerBound) }
        #expect(svg.contains("\n    <path "))
    }

    @Test func aGroupAtTheOriginGetsNoTransformAtAll() {
        let group = Layer(name: "Icon",
                          content: .group(GroupContent(children: [Self.pathLayer(at: .zero)])),
                          frame: CGRect(x: 0, y: 0, width: 0, height: 0))
        let svg = Self.write(Self.document([group])).text
        #expect(svg.contains("<g>"))
        #expect(!svg.contains("translate(0 0)"))
    }

    @Test func anEmptyGroupIsNotWrittenAtAll() {
        let group = Layer(name: "Empty", content: .group(GroupContent(children: [])),
                          frame: CGRect(x: 10, y: 10, width: 0, height: 0))
        let svg = Self.write(Self.document([group])).text
        #expect(!svg.contains("<g"))
    }

    @Test func aHiddenLayerIsNotWritten() {
        var hidden = Self.pathLayer()
        hidden.isVisible = false
        let svg = Self.write(Self.document([hidden])).text
        #expect(!svg.contains("<path "))
    }

    @Test func aFadedLayerCarriesItsFade() {
        var faded = Self.pathLayer()
        faded.style.opacity = 0.4
        let svg = Self.write(Self.document([faded])).text
        #expect(svg.contains("opacity=\"0.4\""))
    }

    // MARK: - Gradients

    @Test func aGradientFillWritesADefinitionAndPointsAtIt() {
        var content = Self.bowedSquare()
        var fill = Paint(hex: "#FF3B30")
        fill.becoming(.linear)
        content.fill = fill
        let svg = Self.write(Self.document([Self.pathLayer(content)])).text
        #expect(svg.contains("<defs>"))
        #expect(svg.contains("<linearGradient "))
        #expect(svg.contains("gradientUnits=\"userSpaceOnUse\""))
        #expect(svg.contains("fill=\"url(#"))
        #expect(svg.contains("stop-color=\"#FF3B30\""))
    }

    @Test func aGradientOutlineGetsItsOwnDefinition() {
        var content = Self.bowedSquare()
        content.fill = nil
        var ink = Paint(hex: "#00A0FF")
        ink.becoming(.radial)
        content.paint = ink
        let svg = Self.write(Self.document([Self.pathLayer(content)])).text
        #expect(svg.contains("<radialGradient "))
        #expect(svg.contains("stroke=\"url(#"))
    }

    @Test func aColourWithSeeThroughInItWritesItsOpacitySeparately() {
        var content = Self.bowedSquare()
        content.fillColorHex = "#11223380"
        let svg = Self.write(Self.document([Self.pathLayer(content)])).text
        #expect(svg.contains("fill=\"#112233\""))
        #expect(svg.contains("fill-opacity=\"0.502\""))
    }

    @Test func aSweepingGradientHasNoAnswerInSVGSoItFallsBack() {
        var content = Self.bowedSquare()
        var fill = Paint(hex: "#FF3B30")
        fill.becoming(.angular)
        content.fill = fill
        let result = Self.write(Self.document([Self.pathLayer(content)]))
        #expect(result.text.contains("<image "))
        #expect(result.fallbacks.contains { $0.reason.lowercased().contains("sweep") })
    }

    // MARK: - What has no vector answer

    @Test func aPictureGoesOutAsAnEmbeddedPicture() {
        let layer = Layer(name: "Screenshot",
                          content: .image(ImageRef(pixelSize: CGSize(width: 40, height: 40))),
                          frame: CGRect(x: 12, y: 16, width: 40, height: 40))
        let result = Self.write(Self.document([layer]))
        #expect(result.text.contains("<image "))
        #expect(result.text.contains("data:image/png;base64,AQIDBA=="))
        #expect(result.text.contains("x=\"12\""))
        #expect(result.text.contains("y=\"16\""))
        // A picture is a picture, not something that could not be written.
        #expect(result.fallbacks.isEmpty)
    }

    @Test func aLayerWearingAShadowFallsBackAndSaysWhy() {
        var layer = Self.pathLayer()
        layer.style.effects = [.shadow(ShadowStyle())]
        let result = Self.write(Self.document([layer]))
        #expect(result.text.contains("<image "))
        #expect(result.fallbacks.count == 1)
        #expect(result.fallbacks[0].layerName == "Shape")
        #expect(result.fallbacks[0].reason.lowercased().contains("shadow"))
    }

    @Test func whatWillFallBackCanBeAskedForBeforeAnythingIsWritten() {
        var shadowed = Self.pathLayer()
        shadowed.name = "Shadowed"
        shadowed.style.effects = [.shadow(ShadowStyle())]
        let document = Self.document([Self.pathLayer(), shadowed])
        let coming = SVGExport.fallbacks(in: document)
        #expect(coming.count == 1)
        #expect(coming[0].layerName == "Shadowed")
    }

    @Test func aLayerWithNoPictureToFallBackOnIsStillReported() {
        var layer = Self.pathLayer()
        layer.style.effects = [.shadow(ShadowStyle())]
        let result = Self.write(Self.document([layer]), picture: nil)
        #expect(!result.text.contains("<image "))
        #expect(result.fallbacks.count == 1)
    }

    @Test func whatEndsUpAsAPictureIncludesThePhotographs() {
        // The sheet asks this one: a photograph is not a failure, and somebody
        // about to hand the file over still wants to know there is a bitmap in
        // it.
        let photo = Layer(name: "Screenshot",
                          content: .image(ImageRef(pixelSize: CGSize(width: 40, height: 40))),
                          frame: CGRect(x: 0, y: 0, width: 40, height: 40))
        let document = Self.document([Self.pathLayer(), photo])
        let pictured = SVGExport.embeddedPictures(in: document)
        #expect(pictured.map(\.layerName) == ["Screenshot"])
        // ...and it is still not counted as something that went wrong.
        #expect(SVGExport.fallbacks(in: document).isEmpty)
    }

    // MARK: - A picture that is one flat colour

    /// The blank canvas's background: a real bitmap on the canvas, and four
    /// numbers in the file.
    static func flatBackground(_ colour: RGBA = RGBA(r: 1, g: 1, b: 1),
                               size: CGSize = CGSize(width: 240, height: 240))
        -> (layer: Layer, flatImages: [UUID: RGBA]) {
        let ref = ImageRef(pixelSize: size)
        let layer = Layer(name: "Background", content: .image(ref),
                          frame: CGRect(origin: .zero, size: size))
        return (layer, [ref.id: colour])
    }

    @Test func aFlatBackgroundGoesOutAsARectangleRatherThanAPicture() {
        let (background, flat) = Self.flatBackground()
        let result = SVGExport.write(Self.document([background, Self.pathLayer()]),
                                     picture: Self.stubPicture,
                                     outlineText: Self.stubOutliner,
                                     flatImages: flat)
        #expect(!result.text.contains("<image "))
        #expect(!result.text.contains("base64"))
        #expect(result.text.contains("<rect x=\"0\" y=\"0\" width=\"240\" height=\"240\""))
        #expect(result.text.contains("fill=\"#FFFFFF\""))
        #expect(result.fallbacks.isEmpty)
    }

    @Test func aFlatColourKeepsItsOwnColourAndItsSeeThroughness() {
        let (background, flat) = Self.flatBackground(RGBA(r: 0, g: 0.5, b: 1, a: 0.6))
        let result = SVGExport.write(Self.document([background]), flatImages: flat)
        #expect(result.text.contains("fill=\"#0080FF\""))
        #expect(result.text.contains("fill-opacity=\"0.6\""))
    }

    @Test func aFlatColourNobodyCanSeeDrawsNothingAtAll() {
        let (background, flat) = Self.flatBackground(RGBA(r: 1, g: 1, b: 1, a: 0))
        let result = SVGExport.write(Self.document([background]), flatImages: flat)
        #expect(!result.text.contains("<rect"))
        #expect(!result.text.contains("<image "))
    }

    @Test func aRoundedOffFlatPictureKeepsItsCorners() {
        var (background, flat) = Self.flatBackground()
        background.style.cornerRadii = CornerRadii(24)
        let result = SVGExport.write(Self.document([background]), flatImages: flat)
        #expect(result.text.contains("rx=\"24\""))
    }

    @Test func aCroppedFlatPictureStaysAPicture() {
        // A crop can reach past the edge of the bitmap, and what shows there is
        // not the colour inside it.
        var (background, flat) = Self.flatBackground()
        background.crop = CGRect(x: 0, y: 0, width: 0.5, height: 0.5)
        let result = SVGExport.write(Self.document([background]),
                                     picture: Self.stubPicture, flatImages: flat)
        #expect(result.text.contains("<image "))
    }

    @Test func aFlatBackgroundIsNotReportedAsAPhotographRidingAlong() {
        let (background, flat) = Self.flatBackground()
        let document = Self.document([background, Self.pathLayer()])
        #expect(SVGExport.embeddedPictures(in: document, flatImages: flat).isEmpty)
        #expect(SVGExport.fallbacks(in: document, flatImages: flat).isEmpty)
        // ...and with nobody to say the bitmap is flat, it is a picture again.
        #expect(SVGExport.embeddedPictures(in: document).map(\.layerName) == ["Background"])
    }

    @Test func aFlatPictureWearingAShadowIsStillAPicture() {
        var (background, flat) = Self.flatBackground()
        background.style.effects = [.shadow(ShadowStyle())]
        let result = SVGExport.write(Self.document([background]),
                                     picture: Self.stubPicture, flatImages: flat)
        #expect(result.text.contains("<image "))
        #expect(result.fallbacks.count == 1)
    }

    // MARK: - Reading a value back out of the file

    /// The first value of `name` in `svg`, for tests that care what a number
    /// came out as rather than where it sits.
    static func attribute(_ name: String, in svg: String) -> String {
        guard let start = svg.range(of: "\(name)=\"") else { return "" }
        let rest = svg[start.upperBound...]
        guard let end = rest.firstIndex(of: "\"") else { return "" }
        return String(rest[..<end])
    }

    /// A point curved on one side only has to come out of the file as the
    /// shape it is, and the two directions are written differently: the run
    /// with no handle at EITHER end is a plain line, while a run with a handle
    /// at one end only is a curve whose other control point sits on the anchor.
    @Test func aPointCurvedOnOneSideOnlyIsWrittenAsALineAndACurve() {
        // Arrives straight, leaves curving, then arrives curving again.
        let content = PathContent(anchors: [
            PathAnchor(point: CGPoint(x: 0, y: 0)),
            PathAnchor(point: CGPoint(x: 100, y: 0), handleOut: CGPoint(x: 40, y: 0)),
            PathAnchor(point: CGPoint(x: 100, y: 100), handleIn: CGPoint(x: 0, y: -40))
        ])
        let data = SVGExport.pathData(content)
        #expect(data.contains("L100 0"), "the straight side is a line: \(data)")
        #expect(data.contains("C140 0 100 60 100 100"), "the curved side bends: \(data)")

        // The other way round: a run that LEAVES straight into a point that
        // arrives curving is still a curve, with its first control point on
        // the anchor it left.
        let mirrored = PathContent(anchors: [
            PathAnchor(point: CGPoint(x: 0, y: 0), handleOut: CGPoint(x: 30, y: 0)),
            PathAnchor(point: CGPoint(x: 100, y: 0), handleIn: CGPoint(x: -30, y: 0)),
            PathAnchor(point: CGPoint(x: 100, y: 100), handleIn: CGPoint(x: 0, y: -40))
        ])
        let out = SVGExport.pathData(mirrored)
        #expect(!out.contains("L"), "neither run is straight: \(out)")
        #expect(out.contains("C100 0 100 60 100 100"),
                "the control point sits on the anchor the run left: \(out)")
    }

    @Test func aTwoPointLeafIsWrittenAsTwoCurvesAndAClose() {
        // The smallest closed shape there is. It has to come out as a real
        // outline rather than as a line that happens to double back.
        let data = SVGExport.pathData(Self.leaf())
        #expect(data.hasPrefix("M0 50"))
        #expect(data.hasSuffix("Z"))
        // Two runs, both curved: out along one side and home along the other.
        #expect(data.filter { $0 == "C" }.count == 2)
        #expect(!data.contains("L"))
    }
}

/// What KIND of line a path is drawn with has to survive the trip: an icon
/// whose ends are round on the canvas and chopped flat in the file is an icon
/// that cannot be handed over (`docs/design/vector-paths.md`).
@Suite("A path's line style, exported")
struct SVGLineStyleExportTests {

    private func svg(_ change: (inout PathContent) -> Void) -> String {
        var content = SVGExportTests.bowedSquare()
        content.strokeWidth = 6
        content.colorHex = "#112233"
        change(&content)
        return SVGExportTests.write(
            SVGExportTests.document([SVGExportTests.pathLayer(content)])).text
    }

    @Test("The ends and the corners are written out")
    func endsAndCorners() {
        let file = svg { $0.lineEnd = .square; $0.lineCorner = .round }
        #expect(file.contains("stroke-linecap=\"square\""))
        #expect(file.contains("stroke-linejoin=\"round\""))
    }

    @Test("A flat end and a sliced corner come out in SVG's own words for them")
    func theOtherTwo() {
        let file = svg { $0.lineEnd = .flat; $0.lineCorner = .flat }
        #expect(file.contains("stroke-linecap=\"butt\""))
        #expect(file.contains("stroke-linejoin=\"bevel\""))
    }

    @Test("How far a sharp corner may be carried is written out, because SVG's default is not ours")
    func theLimitTravels() {
        let file = svg { $0.lineCorner = .sharp }
        #expect(file.contains("stroke-miterlimit=\"10\""))
    }

    @Test("A solid line carries no dash pattern at all")
    func solidHasNoDashes() {
        #expect(!svg { _ in }.contains("stroke-dasharray"))
    }

    @Test("A dashed line comes out dashed, in the same marks and gaps the canvas draws")
    func dashesTravel() {
        let file = svg { $0.linePattern = .dashed }
        #expect(file.contains("stroke-dasharray=\"18 12\""))
    }

    @Test("A dotted line comes out dotted")
    func dotsTravel() {
        #expect(svg { $0.linePattern = .dotted }.contains("stroke-dasharray=\"6 12\""))
    }

    @Test("An inside line's dashes are the ones you can see, not the doubled ones it is drawn with")
    func insideLineKeepsItsPattern() {
        let file = svg { $0.linePattern = .dashed; $0.strokePosition = .inside }
        // Drawn at double width and clipped, exactly as the canvas does it —
        // but the marks and gaps are the ones the eye sees.
        #expect(file.contains("stroke-width=\"12\""))
        #expect(file.contains("stroke-dasharray=\"18 12\""))
    }
}
