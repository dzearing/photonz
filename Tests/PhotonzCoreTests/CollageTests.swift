import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

@Suite("Collage cell geometry")
struct CollageCellFrameTests {

    @Test func fourItemGridSplitsIntoTwoByTwo() {
        let frames = Collage.cellFrames(count: 4, in: CGSize(width: 1000, height: 1000),
                                        template: .grid, gutter: 20)
        #expect(frames.count == 4)
        // 2 cols × 2 rows, cell = (1000 - 3*20) / 2 = 470.
        #expect(frames[0] == CGRect(x: 20, y: 20, width: 470, height: 470))
        #expect(frames[1] == CGRect(x: 510, y: 20, width: 470, height: 470))
        #expect(frames[2] == CGRect(x: 20, y: 510, width: 470, height: 470))
        #expect(frames[3] == CGRect(x: 510, y: 510, width: 470, height: 470))
    }

    @Test func threeItemGridCentersTheShortLastRow() {
        let frames = Collage.cellFrames(count: 3, in: CGSize(width: 1000, height: 1000),
                                        template: .grid, gutter: 20)
        #expect(frames.count == 3)
        // cols = ceil(sqrt 3) = 2, rows = 2; the lone last-row cell centers.
        #expect(frames[2].midX == 500)
        #expect(frames[2].width == frames[0].width)
        #expect(frames[2].minY == frames[0].maxY + 20)
    }

    @Test func rowLaysOutLeftToRightFullHeight() {
        let frames = Collage.cellFrames(count: 3, in: CGSize(width: 1000, height: 500),
                                        template: .row, gutter: 10)
        #expect(frames.count == 3)
        // width = (1000 - 4*10) / 3 = 320, height = 500 - 2*10 = 480.
        #expect(frames[0] == CGRect(x: 10, y: 10, width: 320, height: 480))
        #expect(frames[1].minX == 340)
        #expect(frames[2].maxX == 990)
        #expect(frames.allSatisfy { $0.height == 480 })
    }

    @Test func columnStacksTopToBottomFullWidth() {
        let frames = Collage.cellFrames(count: 2, in: CGSize(width: 400, height: 900),
                                        template: .column, gutter: 20)
        #expect(frames.count == 2)
        // height = (900 - 3*20) / 2 = 420, width = 400 - 2*20 = 360.
        #expect(frames[0] == CGRect(x: 20, y: 20, width: 360, height: 420))
        #expect(frames[1] == CGRect(x: 20, y: 460, width: 360, height: 420))
    }

    @Test func singleItemFillsCanvasMinusGutter() {
        for template in CollageTemplate.allCases {
            let frames = Collage.cellFrames(count: 1, in: CGSize(width: 600, height: 400),
                                            template: template, gutter: 16)
            #expect(frames == [CGRect(x: 16, y: 16, width: 568, height: 368)])
        }
    }

    @Test func zeroOrNegativeCountYieldsNoFrames() {
        #expect(Collage.cellFrames(count: 0, in: CGSize(width: 100, height: 100),
                                   template: .grid, gutter: 10).isEmpty)
        #expect(Collage.cellFrames(count: -2, in: CGSize(width: 100, height: 100),
                                   template: .row, gutter: 10).isEmpty)
    }

    @Test func oversizedGutterStillYieldsPositiveCells() {
        let frames = Collage.cellFrames(count: 4, in: CGSize(width: 100, height: 100),
                                        template: .grid, gutter: 500)
        #expect(frames.count == 4)
        #expect(frames.allSatisfy { $0.width > 0 && $0.height > 0 })
    }
}

@Suite("Collage fill crop")
struct CollageFillCropTests {

    @Test func wideContentIntoSquareCellCropsWidthCentered() {
        let content = CGRect(x: 0, y: 0, width: 200, height: 100)
        let crop = Collage.fillCrop(of: content, matchingAspect: 1)
        #expect(crop == CGRect(x: 50, y: 0, width: 100, height: 100))
    }

    @Test func tallContentIntoWideCellCropsHeightCentered() {
        let content = CGRect(x: 0, y: 0, width: 100, height: 300)
        let crop = Collage.fillCrop(of: content, matchingAspect: 2)
        #expect(crop == CGRect(x: 0, y: 125, width: 100, height: 50))
    }

    @Test func matchingAspectLeavesContentUntouched() {
        let content = CGRect(x: 10, y: 20, width: 160, height: 90)
        let crop = Collage.fillCrop(of: content, matchingAspect: 160.0 / 90.0)
        #expect(abs(crop.minX - 10) < 0.001 && abs(crop.minY - 20) < 0.001)
        #expect(abs(crop.width - 160) < 0.001 && abs(crop.height - 90) < 0.001)
    }

    @Test func composesWithAnExistingCropOffset() {
        // An existing crop rect keeps its own origin; the fill sub-rect nests inside it.
        let existing = CGRect(x: 40, y: 60, width: 400, height: 100)
        let crop = Collage.fillCrop(of: existing, matchingAspect: 1)
        #expect(crop == CGRect(x: 190, y: 60, width: 100, height: 100))
    }
}

@Suite("Collage apply")
struct CollageApplyTests {

    private func imageLayer(name: String, size: CGSize, at origin: CGPoint = .zero) -> Layer {
        Layer(name: name, content: .image(ImageRef(pixelSize: size)),
              frame: CGRect(origin: origin, size: size))
    }

    private func makeDocument() -> (PhotonzDocument, [UUID]) {
        let base = ImageRef(pixelSize: CGSize(width: 1000, height: 1000))
        var doc = PhotonzDocument.withBaseImage(base)
        let a = imageLayer(name: "A", size: CGSize(width: 400, height: 200))
        let b = imageLayer(name: "B", size: CGSize(width: 300, height: 300))
        let c = imageLayer(name: "C", size: CGSize(width: 100, height: 500))
        doc.addLayer(a); doc.addLayer(b); doc.addLayer(c)
        return (doc, [a.id, b.id, c.id])
    }

    @Test func assignsCellsInDocumentOrderBottomToTop() {
        var (doc, ids) = makeDocument()
        // Pass ids intentionally shuffled: document z-order must win.
        Collage.apply(to: &doc, ids: [ids[2], ids[0], ids[1]],
                      template: .row, gutter: 10)
        let frames = Collage.cellFrames(count: 3, in: doc.canvasSize, template: .row, gutter: 10)
        #expect(doc.layers.first { $0.id == ids[0] }?.frame == frames[0])
        #expect(doc.layers.first { $0.id == ids[1] }?.frame == frames[1])
        #expect(doc.layers.first { $0.id == ids[2] }?.frame == frames[2])
    }

    @Test func cropMatchesCellAspectSoContentIsNotDistorted() {
        var (doc, ids) = makeDocument()
        Collage.apply(to: &doc, ids: ids, template: .grid, gutter: 20)
        for id in ids {
            let layer = doc.layers.first { $0.id == id }!
            let crop = layer.crop!
            #expect(abs(crop.width / crop.height - layer.frame.width / layer.frame.height) < 0.01)
        }
    }

    @Test func composesWithExistingCropInsteadOfDiscardingIt() {
        var (doc, ids) = makeDocument()
        // Pre-crop A to its right half (content pixels 200…400).
        let preCrop = CGRect(x: 200, y: 0, width: 200, height: 200)
        doc.updateLayer(id: ids[0]) { $0.crop = preCrop }
        Collage.apply(to: &doc, ids: ids, template: .row, gutter: 10)
        let crop = doc.layers.first { $0.id == ids[0] }!.crop!
        #expect(preCrop.contains(crop))
    }

    @Test func resetsRotationForCleanCells() {
        var (doc, ids) = makeDocument()
        doc.updateLayer(id: ids[1]) { $0.transform = LayerTransform(rotation: .pi / 4) }
        Collage.apply(to: &doc, ids: ids, template: .grid, gutter: 20)
        #expect(doc.layers.first { $0.id == ids[1] }?.transform == .identity)
    }

    @Test func optionalCanvasSizeIsAppliedBeforeLayout() {
        var (doc, ids) = makeDocument()
        Collage.apply(to: &doc, ids: ids, template: .row, gutter: 10,
                      canvasSize: CGSize(width: 1600, height: 900))
        #expect(doc.canvasSize == CGSize(width: 1600, height: 900))
        let frames = Collage.cellFrames(count: 3, in: CGSize(width: 1600, height: 900),
                                        template: .row, gutter: 10)
        #expect(doc.layers.first { $0.id == ids[0] }?.frame == frames[0])
    }

    @Test func ignoresIDsMissingFromTheDocument() {
        var (doc, ids) = makeDocument()
        Collage.apply(to: &doc, ids: ids + [UUID()], template: .row, gutter: 10)
        let frames = Collage.cellFrames(count: 3, in: doc.canvasSize, template: .row, gutter: 10)
        #expect(doc.layers.first { $0.id == ids[2] }?.frame == frames[2])
    }

    @Test func leavesNonParticipantLayersAlone() {
        var (doc, ids) = makeDocument()
        let backgroundFrame = doc.layers[0].frame
        Collage.apply(to: &doc, ids: ids, template: .grid, gutter: 20)
        #expect(doc.layers[0].frame == backgroundFrame)
        #expect(doc.layers[0].crop == nil)
    }
}
