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

@Suite("Collage content")
struct CollageContentTests {

    private func content(slots: Int, filled: [Int: ImageRef] = [:]) -> CollageContent {
        var c = CollageContent(slots: Array(repeating: CollageSlot(), count: slots))
        for (index, ref) in filled { c.slots[index].imageRef = ref }
        return c
    }

    @Test func fillingASlotSetsItsRef() {
        let ref = ImageRef(pixelSize: CGSize(width: 100, height: 50))
        var c = content(slots: 4)
        c.fill(slot: 2, with: ref)
        #expect(c.slots[2].imageRef == ref)
        #expect(c.slots[0].imageRef == nil)
    }

    @Test func fillingOutOfRangeIsIgnored() {
        let ref = ImageRef(pixelSize: CGSize(width: 100, height: 50))
        var c = content(slots: 2)
        c.fill(slot: 5, with: ref)
        c.fill(slot: -1, with: ref)
        #expect(c.slots.allSatisfy { $0.imageRef == nil })
    }

    @Test func swappingSlotsExchangesRefs() {
        let a = ImageRef(pixelSize: CGSize(width: 10, height: 10))
        var c = content(slots: 3, filled: [0: a])
        c.swapSlots(0, 2)
        #expect(c.slots[0].imageRef == nil)
        #expect(c.slots[2].imageRef == a)
    }

    @Test func resizingSlotCountKeepsLeadingSlots() {
        let a = ImageRef(pixelSize: CGSize(width: 10, height: 10))
        let b = ImageRef(pixelSize: CGSize(width: 20, height: 20))
        var c = content(slots: 4, filled: [0: a, 3: b])
        c.setSlotCount(2)
        #expect(c.slots.count == 2)
        #expect(c.slots[0].imageRef == a)
        c.setSlotCount(5)
        #expect(c.slots.count == 5)
        #expect(c.slots[0].imageRef == a)
        #expect(c.slots.suffix(3).allSatisfy { $0.imageRef == nil })
        c.setSlotCount(0) // floor of 1
        #expect(c.slots.count == 1)
    }

    @Test func slotIndexHitTestsInLayerLocalSpace() {
        let layer = Collage.layer(content: content(slots: 4),
                                  frame: CGRect(x: 100, y: 100, width: 1000, height: 1000))
        // Cells: 2×2 with default gutter 24 → cell = (1000 - 72)/2 = 464.
        #expect(layer.collage != nil)
        #expect(Collage.slotIndex(at: CGPoint(x: 130, y: 130), in: layer) == 0)
        #expect(Collage.slotIndex(at: CGPoint(x: 1070, y: 130), in: layer) == 1)
        #expect(Collage.slotIndex(at: CGPoint(x: 130, y: 1070), in: layer) == 2)
        // Dead center of the cross gutter hits nothing.
        #expect(Collage.slotIndex(at: CGPoint(x: 600, y: 600), in: layer) == nil)
        // Outside the layer entirely.
        #expect(Collage.slotIndex(at: CGPoint(x: 0, y: 0), in: layer) == nil)
    }

    @Test func codableRoundTripsIncludingLegacyOptionalFields() throws {
        let ref = ImageRef(pixelSize: CGSize(width: 640, height: 480))
        var c = content(slots: 3, filled: [1: ref])
        c.template = .row
        c.gutter = 12
        c.backdropColorHex = nil
        let data = try JSONEncoder().encode(c)
        let decoded = try JSONDecoder().decode(CollageContent.self, from: data)
        #expect(decoded == c)
    }
}

@Suite("Collage absorb")
struct CollageAbsorbTests {

    private func imageLayer(name: String, size: CGSize, at origin: CGPoint) -> Layer {
        Layer(name: name, content: .image(ImageRef(pixelSize: size)),
              frame: CGRect(origin: origin, size: size))
    }

    @Test func absorbBuildsSlotsInGivenOrderAndUnionFrame() {
        let a = imageLayer(name: "A", size: CGSize(width: 200, height: 100), at: CGPoint(x: 50, y: 50))
        let b = imageLayer(name: "B", size: CGSize(width: 100, height: 300), at: CGPoint(x: 400, y: 20))
        let layer = Collage.layer(absorbing: [a, b])
        #expect(layer != nil)
        guard let layer, let collage = layer.collage else { return }
        #expect(layer.frame == CGRect(x: 50, y: 20, width: 450, height: 300))
        #expect(collage.slots.count == 2)
        #expect(collage.slots[0].imageRef == a.imageRef)
        #expect(collage.slots[1].imageRef == b.imageRef)
    }

    @Test func absorbSkipsNonImageLayers() {
        let a = imageLayer(name: "A", size: CGSize(width: 100, height: 100), at: .zero)
        let text = Layer(name: "T", content: .text(TextContent(string: "hi", fontSize: 12, colorHex: "#000000")),
                         frame: CGRect(x: 0, y: 0, width: 100, height: 40))
        let layer = Collage.layer(absorbing: [a, text])
        #expect(layer?.collage?.slots.count == 1)
    }

    @Test func absorbingNothingYieldsNil() {
        #expect(Collage.layer(absorbing: []) == nil)
    }

    @Test func collageLayerAllowsFrameResizeAndFrameHitTest() {
        let a = imageLayer(name: "A", size: CGSize(width: 100, height: 100), at: .zero)
        let b = imageLayer(name: "B", size: CGSize(width: 100, height: 100), at: CGPoint(x: 200, y: 0))
        guard let layer = Collage.layer(absorbing: [a, b]) else {
            Issue.record("absorb failed"); return
        }
        #expect(layer.allowsFrameResize)
        #expect(!layer.hasEndpointHandles)
        #expect(layer.contains(canvasPoint: CGPoint(x: 150, y: 50)))
        let resized = layer.resized(to: CGRect(x: 0, y: 0, width: 600, height: 400))
        #expect(resized.frame == CGRect(x: 0, y: 0, width: 600, height: 400))
        #expect(resized.collage == layer.collage) // cells derive from frame; content untouched
    }

    @Test func documentRoundTripsACollageLayer() throws {
        let a = imageLayer(name: "A", size: CGSize(width: 100, height: 100), at: .zero)
        guard let layer = Collage.layer(absorbing: [a]) else {
            Issue.record("absorb failed"); return
        }
        var doc = PhotonzDocument.withBaseImage(ImageRef(pixelSize: CGSize(width: 500, height: 500)))
        doc.addLayer(layer)
        let data = try JSONEncoder().encode(doc)
        let decoded = try JSONDecoder().decode(PhotonzDocument.self, from: data)
        #expect(decoded == doc)
    }
}
