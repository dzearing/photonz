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

    // MARK: - Reading a value back out of the file

    /// The first value of `name` in `svg`, for tests that care what a number
    /// came out as rather than where it sits.
    static func attribute(_ name: String, in svg: String) -> String {
        guard let start = svg.range(of: "\(name)=\"") else { return "" }
        let rest = svg[start.upperBound...]
        guard let end = rest.firstIndex(of: "\"") else { return "" }
        return String(rest[..<end])
    }
}
