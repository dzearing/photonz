import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// Copy Image's clipboard payload (`next-measure-panel`): the picture always,
/// and the spec list as text beside it when the document has something to
/// list. The type order is pinned because it is what image-aware apps read.
@Suite("Composite copy")
struct CompositeCopyTests {

    private func caliper(from start: CGPoint, to end: CGPoint, visible: Bool = true) -> Layer {
        var content = MeasureContent(role: .size)
        content.mode = MeasureContent.dominantAxis(from: start, to: end)
        var layer = MeasureBuilder.layer(content: content, from: start, to: end)
        layer.isVisible = visible
        return layer
    }

    @Test func aDocumentWithNoMeasurementsCarriesNoText() {
        // Exactly what Copy Image copied before: PNG then TIFF, nothing else.
        let doc = PhotonzDocument(canvasSize: CGSize(width: 640, height: 480))
        #expect(CompositeCopy.specListText(document: doc, name: "Shot") == nil)
        #expect(CompositeCopy.representations(specList: nil) == [.png, .tiff])
        #expect(CompositeCopy.visibleMeasurementCount(in: doc) == 0)
    }

    @Test func measurementsPutTheSpecListBesideThePictureAfterTheImageTypes() {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 1280, height: 800))
        doc.addLayer(caliper(from: CGPoint(x: 0, y: 10), to: CGPoint(x: 128, y: 10)))
        doc.addLayer(caliper(from: CGPoint(x: 0, y: 40), to: CGPoint(x: 64, y: 40)))

        let text = CompositeCopy.specListText(document: doc, name: "Capture")
        #expect(text == MeasureSpecList.render(document: doc, name: "Capture"))
        #expect(text?.hasPrefix("Capture · 1280 × 800 px\n") == true)
        // Image types first so image-aware apps take the picture; the string
        // last so only text-only fields fall through to it.
        #expect(CompositeCopy.representations(specList: text) == [.png, .tiff, .text(text ?? "")])
        #expect(CompositeCopy.visibleMeasurementCount(in: doc) == 2)
    }

    @Test func hiddenMeasurementsDoNotEarnAHeaderOnlyList() {
        // A list that would be just the header line says nothing the picture
        // does not, so the clipboard stays picture-only.
        var doc = PhotonzDocument(canvasSize: CGSize(width: 200, height: 100))
        doc.addLayer(caliper(from: CGPoint(x: 0, y: 40), to: CGPoint(x: 64, y: 40), visible: false))
        #expect(CompositeCopy.specListText(document: doc, name: "Shot") == nil)
        #expect(CompositeCopy.visibleMeasurementCount(in: doc) == 0)
    }

    // MARK: - The drawing as SVG

    private static let svg = "<svg xmlns=\"http://www.w3.org/2000/svg\"/>"

    @Test func anSVGRidesAfterThePictureTypes() {
        // The picture types stay first, so an app that wants a picture still
        // takes the picture; the SVG is one more flavour beside them.
        #expect(CompositeCopy.representations(specList: nil, svg: Self.svg)
                == [.png, .tiff, .svg(Self.svg)])
    }

    @Test func theSpecListStaysLastWhenBothRideAlong() {
        // Plain text is what a text-only field falls through to, so it stays
        // the last thing declared whatever else is on the clipboard.
        #expect(CompositeCopy.representations(specList: "list", svg: Self.svg)
                == [.png, .tiff, .svg(Self.svg), .text("list")])
    }

    private static let canvasRef = ImageRef(pixelSize: CGSize(width: 24, height: 24))

    /// A 24 unit icon as New Frame and a blank canvas make one: a flat white
    /// canvas picture with a circle drawn on it.
    private static func icon(_ extra: [Layer] = []) -> (PhotonzDocument, [UUID: RGBA]) {
        let canvas = Layer(name: "Background", content: .image(canvasRef),
                           frame: CGRect(x: 0, y: 0, width: 24, height: 24))
        let circle = Layer(name: "Circle",
                       content: .annotation(AnnotationContent(shape: .ellipse)),
                       frame: CGRect(x: 4, y: 4, width: 16, height: 16))
        let doc = PhotonzDocument(canvasSize: CGSize(width: 24, height: 24),
                                  layers: [canvas, circle] + extra)
        return (doc, [canvasRef.id: RGBA(r: 1, g: 1, b: 1, a: 1)])
    }

    private static func screenshot(at frame: CGRect = CGRect(x: 0, y: 0, width: 24, height: 24))
        -> Layer {
        Layer(name: "Screenshot", content: .image(ImageRef(pixelSize: frame.size)), frame: frame)
    }

    @Test func aDrawingOnABlankCanvasCarriesItsSVG() {
        let (doc, flat) = Self.icon()
        #expect(CompositeCopy.carriesSVG(doc, flatImages: flat))
    }

    @Test func aShapeWearingAnEffectIsStillADrawing() {
        // Export writes a blurred shape too (as a filter, or a picture of
        // that one layer); it is still somebody's drawing, not a photograph.
        var (doc, flat) = Self.icon()
        if let id = doc.layers.last?.id {
            doc.updateLayer(id: id) { $0.style.blendMode = .multiply }
        }
        #expect(CompositeCopy.carriesSVG(doc, flatImages: flat))
    }

    @Test func aScreenshotCopiesAsAPictureOnly() {
        let doc = PhotonzDocument(canvasSize: CGSize(width: 24, height: 24),
                                  layers: [Self.screenshot()])
        #expect(!CompositeCopy.carriesSVG(doc, flatImages: [:]))
    }

    @Test func aScreenshotWithArrowsDrawnOnItIsStillAScreenshot() {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 24, height: 24),
                                  layers: [Self.screenshot()])
        doc.addLayer(Layer(name: "Arrow", content: .annotation(AnnotationContent(shape: .arrow)),
                           frame: CGRect(x: 2, y: 2, width: 10, height: 10)))
        #expect(!CompositeCopy.carriesSVG(doc, flatImages: [:]))
    }

    @Test func aPhotographTuckedInsideAFrameCounts() {
        let photo = Self.screenshot(at: CGRect(x: 2, y: 2, width: 8, height: 8))
        let frame = Layer(name: "Icon",
                          content: .group(GroupContent(children: [photo], isFrame: true)),
                          frame: CGRect(x: 0, y: 0, width: 24, height: 24))
        let (doc, flat) = Self.icon([frame])
        #expect(!CompositeCopy.carriesSVG(doc, flatImages: flat))
    }

    @Test func aHiddenPhotographIsNotOnThePicture() {
        var photo = Self.screenshot(at: CGRect(x: 2, y: 2, width: 8, height: 8))
        photo.isVisible = false
        let (doc, flat) = Self.icon([photo])
        #expect(CompositeCopy.carriesSVG(doc, flatImages: flat))
    }

    @Test func aVideoCopiesAsAPictureOnly() {
        // Even a title card made only of shapes: a document with time is an
        // edit, and Export hands an edit over as a film, not an SVG.
        var (doc, flat) = Self.icon()
        if let id = doc.layers.last?.id {
            doc.updateLayer(id: id) { $0.time = LayerTime(inMS: 0, outMS: 2_000) }
        }
        #expect(doc.hasTime)
        #expect(!CompositeCopy.carriesSVG(doc, flatImages: flat))
    }

    @Test func theSVGMovesWhenTheExportForAWebPageWould() {
        // The same answer the Export sheet's web page destination gives.
        let (still, _) = Self.icon()
        #expect(CompositeCopy.svgAnimation(for: still, motionOn: true) == .still)

        var (spinning, _) = Self.icon()
        if let id = spinning.layers.last?.id {
            spinning.updateLayer(id: id) {
                $0.motions = [LayerMotion(property: .scale, from: .number(100), to: .number(150),
                                          timing: MotionTiming(startMS: 0, durationMS: 800),
                                          curve: .linear, repeats: .forever)]
            }
        }
        #expect(CompositeCopy.svgAnimation(for: spinning, motionOn: true)
                == .moving(cycleMS: spinning.motionCycleLengthMS))
        // A release that does not export motion copies the still drawing.
        #expect(CompositeCopy.svgAnimation(for: spinning, motionOn: false) == .still)
    }

    @Test func theNoticeSaysWhatLanded() {
        let t0 = Date(timeIntervalSinceReferenceDate: 1_000)
        #expect(CopyConfirmation(subject: .image(measurements: 0), shownAt: t0).detail == "Image")
        #expect(CopyConfirmation(subject: .image(measurements: 1), shownAt: t0).detail
                == "Image and spec list with 1 measurement")
        #expect(CopyConfirmation(subject: .image(measurements: 3), shownAt: t0).detail
                == "Image and spec list with 3 measurements")
        #expect(CopyConfirmation(subject: .image(measurements: 3), shownAt: t0).title == "Copied")
    }
}
