import CoreGraphics
import Foundation
import Testing
import PhotonzCore
@testable import PhotonzRender

@Suite("Lens rendering")
struct LensRenderingTests {

    // MARK: - Pictures to look at

    private func solidImage(width: Int, height: Int, r: UInt8, g: UInt8, b: UInt8) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height,
                                bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255,
                                     blue: CGFloat(b) / 255, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    /// Left half red, right half blue, in top-left document coordinates.
    private func halvesImage(size: Int) -> CGImage {
        let context = CGContext(data: nil, width: size, height: size,
                                bitsPerComponent: 8, bytesPerRow: size * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: size / 2, height: size))
        context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1))
        context.fill(CGRect(x: size / 2, y: 0, width: size / 2, height: size))
        return context.makeImage()!
    }

    /// Alternating black and white columns one point wide: anything that
    /// averages a neighbourhood turns this into flat grey.
    private func stripeImage(size: Int) -> CGImage {
        let context = CGContext(data: nil, width: size, height: size,
                                bitsPerComponent: 8, bytesPerRow: size * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))
        context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
        for x in stride(from: 0, to: size, by: 2) {
            context.fill(CGRect(x: x, y: 0, width: 1, height: size))
        }
        return context.makeImage()!
    }

    private func pixel(_ image: CGImage, x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        let width = image.width
        let height = image.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        let context = CGContext(data: &data, width: width, height: height,
                                bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let offset = (y * width + x) * 4
        return (data[offset], data[offset + 1], data[offset + 2], data[offset + 3])
    }

    private func lensLayer(_ adjustment: LensAdjustment, amount: CGFloat? = nil,
                           frame: CGRect, style: LayerStyle = LayerStyle()) -> Layer {
        var lens = LensContent(adjustment: adjustment)
        if let amount { lens.amount = amount }
        return Layer(name: adjustment.title, content: .lens(lens), frame: frame, style: style)
    }

    /// A 200x200 canvas whose left half is red and right half is blue.
    private func halvesDocument(_ store: ImageStore) -> PhotonzDocument {
        let base = store.register(halvesImage(size: 200))
        var doc = PhotonzDocument.withBaseImage(base)
        doc.canvasSize = CGSize(width: 200, height: 200)
        return doc
    }

    // MARK: - Each adjustment does its one thing

    @Test func greyscaleDrainsTheColourUnderneathAndLeavesTheRestAlone() {
        let store = ImageStore()
        var doc = halvesDocument(store)
        doc.addLayer(lensLayer(.greyscale, amount: 1, frame: CGRect(x: 20, y: 20, width: 60, height: 60)))

        let output = DocumentRenderer().render(doc, store: store)!
        let inside = pixel(output, x: 50, y: 50)
        #expect(abs(Int(inside.r) - Int(inside.g)) < 4 && abs(Int(inside.g) - Int(inside.b)) < 4,
                "inside the lens the red is grey — got \(inside)")
        #expect(inside.r > 16, "grey, not black — got \(inside)")
        let outside = pixel(output, x: 120, y: 50)
        #expect(outside.b > 240 && outside.r < 16, "outside the lens the blue is untouched — got \(outside)")
        let stillRed = pixel(output, x: 10, y: 10)
        #expect(stillRed.r > 240 && stillRed.g < 16, "outside the lens the red is untouched — got \(stillRed)")
    }

    @Test func halfAGreyscaleIsHalfWayThere() {
        let store = ImageStore()
        var doc = halvesDocument(store)
        doc.addLayer(lensLayer(.greyscale, amount: 0.5, frame: CGRect(x: 20, y: 20, width: 60, height: 60)))
        let output = DocumentRenderer().render(doc, store: store)!
        let inside = pixel(output, x: 50, y: 50)
        #expect(inside.r > inside.g && inside.g > 16,
                "still reddish but with some colour drained — got \(inside)")
        #expect(inside.r < 250, "not the untouched red — got \(inside)")
    }

    @Test func invertFlipsWhatIsUnderneath() {
        let store = ImageStore()
        var doc = halvesDocument(store)
        doc.addLayer(lensLayer(.invert, frame: CGRect(x: 20, y: 20, width: 60, height: 60)))
        let output = DocumentRenderer().render(doc, store: store)!
        let inside = pixel(output, x: 50, y: 50)
        #expect(inside.r < 40 && inside.g > 200 && inside.b > 200,
                "red inverts to cyan — got \(inside)")
        #expect(inside.a > 240, "and stays opaque — got \(inside)")
    }

    @Test func brightnessGoesUpAndDown() {
        let store = ImageStore()
        var up = halvesDocument(store)
        up.addLayer(lensLayer(.brightness, amount: 0.4, frame: CGRect(x: 20, y: 20, width: 60, height: 60)))
        let brighter = pixel(DocumentRenderer().render(up, store: store)!, x: 50, y: 50)
        #expect(brighter.g > 40 && brighter.b > 40, "lifting red lifts every channel — got \(brighter)")

        var down = halvesDocument(store)
        down.addLayer(lensLayer(.brightness, amount: -0.4, frame: CGRect(x: 20, y: 20, width: 60, height: 60)))
        let darker = pixel(DocumentRenderer().render(down, store: store)!, x: 50, y: 50)
        #expect(darker.r < 240, "pushing red down darkens it — got \(darker)")
    }

    @Test func blurMixesTheColoursItCovers() {
        let store = ImageStore()
        var doc = halvesDocument(store)
        // Straddles the red/blue boundary at x = 100.
        doc.addLayer(lensLayer(.blur, amount: 12, frame: CGRect(x: 60, y: 60, width: 80, height: 80)))
        let output = DocumentRenderer().render(doc, store: store)!
        let onTheSeam = pixel(output, x: 100, y: 100)
        #expect(onTheSeam.r > 40 && onTheSeam.b > 40,
                "on the seam the blur is part red part blue — got \(onTheSeam)")
        let outside = pixel(output, x: 100, y: 20)
        #expect(outside.b > 240 || outside.r > 240,
                "above the lens the seam is still hard — got \(outside)")
    }

    /// The trap this feature is most likely to fall into: cut the picture to
    /// the box first and the blur mixes the edge with the transparency beyond
    /// it, leaving a dark or see-through rim round the lens.
    @Test func blurLeavesNoDarkRimAtTheEdgeOfTheBox() {
        let store = ImageStore()
        let base = store.register(solidImage(width: 200, height: 200, r: 220, g: 40, b: 40))
        var doc = PhotonzDocument.withBaseImage(base)
        doc.canvasSize = CGSize(width: 200, height: 200)
        doc.addLayer(lensLayer(.blur, amount: 10, frame: CGRect(x: 50, y: 50, width: 100, height: 100)))
        let output = DocumentRenderer().render(doc, store: store)!
        for point in [(51, 51), (148, 51), (51, 148), (148, 148), (100, 51), (51, 100)] {
            let edge = pixel(output, x: point.0, y: point.1)
            #expect(edge.a > 250, "the edge of the lens is opaque at \(point) — got \(edge)")
            #expect(edge.r > 190 && edge.g > 20,
                    "the edge of the lens is the same colour as the picture at \(point) — got \(edge)")
        }
    }

    @Test func pixelateFlattensDetailIntoBlocks() {
        let store = ImageStore()
        let base = store.register(stripeImage(size: 200))
        var doc = PhotonzDocument.withBaseImage(base)
        doc.canvasSize = CGSize(width: 200, height: 200)
        doc.addLayer(lensLayer(.pixelate, amount: 20, frame: CGRect(x: 40, y: 40, width: 80, height: 80)))
        let output = DocumentRenderer().render(doc, store: store)!
        // Inside one block every pixel is the same colour, and it is neither
        // the black stripe nor the white one.
        let a = pixel(output, x: 62, y: 62)
        let b = pixel(output, x: 63, y: 62)
        #expect(a.r == b.r && a.g == b.g && a.b == b.b,
                "neighbouring pixels inside one block match — got \(a) and \(b)")
        #expect(a.r > 40 && a.r < 220, "a block is the average of its stripes — got \(a)")
        // Outside the lens the stripes are still stripes.
        let stripeA = pixel(output, x: 160, y: 62)
        let stripeB = pixel(output, x: 161, y: 62)
        #expect(stripeA.r != stripeB.r, "outside the lens the stripes survive")
    }

    /// The block grid is anchored to the CANVAS, not to the lens, so nudging a
    /// lens one point does not reshuffle every block under it.
    @Test func movingAPixelateLensDoesNotReshuffleItsBlocks() {
        let store = ImageStore()
        let base = store.register(stripeImage(size: 200))
        var doc = PhotonzDocument.withBaseImage(base)
        doc.canvasSize = CGSize(width: 200, height: 200)
        doc.addLayer(lensLayer(.pixelate, amount: 20, frame: CGRect(x: 40, y: 40, width: 120, height: 120)))
        let before = pixel(DocumentRenderer().render(doc, store: store)!, x: 100, y: 100)

        var moved = doc
        moved.layers[1].frame = CGRect(x: 41, y: 41, width: 120, height: 120)
        let after = pixel(DocumentRenderer().render(moved, store: store)!, x: 100, y: 100)
        #expect(before.r == after.r && before.g == after.g && before.b == after.b,
                "the same spot keeps the same block colour — got \(before) then \(after)")
    }

    // MARK: - What a lens may and may not read

    @Test func aLensReadsWhatIsBelowItAndNotWhatIsAboveIt() {
        let store = ImageStore()
        let base = store.register(solidImage(width: 200, height: 200, r: 255, g: 0, b: 0))
        let patch = store.register(solidImage(width: 40, height: 40, r: 0, g: 0, b: 255))
        var doc = PhotonzDocument.withBaseImage(base)
        doc.canvasSize = CGSize(width: 200, height: 200)
        // Blue patch BELOW the lens: the lens greys the blue.
        doc.addLayer(Layer(name: "Below", content: .image(patch),
                           frame: CGRect(x: 20, y: 20, width: 40, height: 40)))
        doc.addLayer(lensLayer(.invert, frame: CGRect(x: 10, y: 10, width: 100, height: 100)))
        // Green patch ABOVE the lens: it must come out untouched green, and it
        // must not have fed the lens.
        let green = store.register(solidImage(width: 20, height: 20, r: 0, g: 255, b: 0))
        doc.addLayer(Layer(name: "Above", content: .image(green),
                           frame: CGRect(x: 80, y: 80, width: 20, height: 20)))

        let output = DocumentRenderer().render(doc, store: store)!
        let overBlue = pixel(output, x: 40, y: 40)
        #expect(overBlue.r > 200 && overBlue.g > 200 && overBlue.b < 40,
                "blue below the lens inverts to yellow — got \(overBlue)")
        let overRed = pixel(output, x: 70, y: 20)
        #expect(overRed.r < 40 && overRed.g > 200 && overRed.b > 200,
                "red below the lens inverts to cyan — got \(overRed)")
        let aboveIt = pixel(output, x: 90, y: 90)
        #expect(aboveIt.g > 240 && aboveIt.r < 16,
                "the layer above the lens is drawn over it untouched — got \(aboveIt)")
    }

    /// A lens with nothing underneath has nothing to show, and must not feed
    /// on itself, loop, or come back as a black box.
    @Test func aLensOverNothingIsNothing() {
        let store = ImageStore()
        var doc = PhotonzDocument(canvasSize: CGSize(width: 100, height: 100), layers: [])
        doc.addLayer(lensLayer(.invert, frame: CGRect(x: 10, y: 10, width: 50, height: 50)))
        doc.addLayer(lensLayer(.blur, amount: 8, frame: CGRect(x: 20, y: 20, width: 50, height: 50)))
        let output = DocumentRenderer().render(doc, store: store)!
        #expect(pixel(output, x: 30, y: 30).a < 16, "still clear canvas")
    }

    /// One lens over another is legal and reads the finished picture below it:
    /// invert then invert again comes back to where it started.
    @Test func aLensCanReadThroughAnotherLens() {
        let store = ImageStore()
        let base = store.register(solidImage(width: 200, height: 200, r: 200, g: 60, b: 20))
        var doc = PhotonzDocument.withBaseImage(base)
        doc.canvasSize = CGSize(width: 200, height: 200)
        doc.addLayer(lensLayer(.invert, frame: CGRect(x: 20, y: 20, width: 80, height: 80)))
        doc.addLayer(lensLayer(.invert, frame: CGRect(x: 20, y: 20, width: 80, height: 80)))
        let inside = pixel(DocumentRenderer().render(doc, store: store)!, x: 60, y: 60)
        #expect(abs(Int(inside.r) - 200) < 8 && abs(Int(inside.g) - 60) < 8,
                "inverted twice is back where it started — got \(inside)")
    }

    /// The rule the zoom callout already follows: inside a group a lens reads
    /// its group's contents over the canvas beneath the group, never the
    /// transparency around the group.
    @Test func aLensInsideAGroupStillReadsTheCanvasBeneathIt() {
        let store = ImageStore()
        let base = store.register(solidImage(width: 200, height: 200, r: 255, g: 0, b: 0))
        var doc = PhotonzDocument.withBaseImage(base)
        doc.canvasSize = CGSize(width: 200, height: 200)
        let lens = lensLayer(.invert, frame: CGRect(x: 10, y: 10, width: 60, height: 60))
        // A group carrying styling of its own buffers its children, which is
        // the case where the underlay matters.
        doc.addLayer(Layer(name: "Group", content: .group(GroupContent(children: [lens])),
                           frame: CGRect(x: 40, y: 40, width: 0, height: 0),
                           style: LayerStyle(opacity: 1, cornerRadius: CornerRadii(4))))
        let output = DocumentRenderer().render(doc, store: store)!
        let inside = pixel(output, x: 80, y: 80)
        #expect(inside.r < 40 && inside.g > 200 && inside.b > 200,
                "the lens inside the group inverts the red canvas under it — got \(inside)")
    }

    @Test func aLensInsideAPlainGroupReadsTheCanvasToo() {
        let store = ImageStore()
        let base = store.register(solidImage(width: 200, height: 200, r: 255, g: 0, b: 0))
        var doc = PhotonzDocument.withBaseImage(base)
        doc.canvasSize = CGSize(width: 200, height: 200)
        let lens = lensLayer(.invert, frame: CGRect(x: 10, y: 10, width: 60, height: 60))
        doc.addLayer(Layer(name: "Group", content: .group(GroupContent(children: [lens])),
                           frame: CGRect(x: 40, y: 40, width: 0, height: 0)))
        let inside = pixel(DocumentRenderer().render(doc, store: store)!, x: 80, y: 80)
        #expect(inside.r < 40 && inside.g > 200 && inside.b > 200,
                "a pass-through group changes nothing about what the lens reads — got \(inside)")
    }

    // MARK: - It is a layer like any other

    @Test func aRoundedLensLeavesItsCornersAlone() {
        let store = ImageStore()
        let base = store.register(solidImage(width: 200, height: 200, r: 255, g: 0, b: 0))
        var doc = PhotonzDocument.withBaseImage(base)
        doc.canvasSize = CGSize(width: 200, height: 200)
        doc.addLayer(lensLayer(.invert, frame: CGRect(x: 50, y: 50, width: 100, height: 100),
                               style: LayerStyle(cornerRadius: CornerRadii(50))))
        let output = DocumentRenderer().render(doc, store: store)!
        let corner = pixel(output, x: 53, y: 53)
        #expect(corner.r > 240 && corner.g < 16,
                "the rounded-off corner shows the untouched picture — got \(corner)")
        let middle = pixel(output, x: 100, y: 100)
        #expect(middle.r < 40 && middle.g > 200, "the middle is inverted — got \(middle)")
    }

    @Test func opacityFadesALensBackTowardsThePictureUnderIt() {
        let store = ImageStore()
        let base = store.register(solidImage(width: 200, height: 200, r: 255, g: 0, b: 0))
        var doc = PhotonzDocument.withBaseImage(base)
        doc.canvasSize = CGSize(width: 200, height: 200)
        doc.addLayer(lensLayer(.invert, frame: CGRect(x: 50, y: 50, width: 100, height: 100),
                               style: LayerStyle(opacity: 0.5)))
        let inside = pixel(DocumentRenderer().render(doc, store: store)!, x: 100, y: 100)
        #expect(inside.r > 60 && inside.r < 220 && inside.g > 60 && inside.g < 220,
                "half an invert is halfway between — got \(inside)")
    }

    @Test func aHiddenLensChangesNothing() {
        let store = ImageStore()
        let base = store.register(solidImage(width: 200, height: 200, r: 255, g: 0, b: 0))
        var doc = PhotonzDocument.withBaseImage(base)
        doc.canvasSize = CGSize(width: 200, height: 200)
        var lens = lensLayer(.invert, frame: CGRect(x: 50, y: 50, width: 100, height: 100))
        lens.isVisible = false
        doc.addLayer(lens)
        let inside = pixel(DocumentRenderer().render(doc, store: store)!, x: 100, y: 100)
        #expect(inside.r > 240 && inside.g < 16, "a hidden lens draws nothing — got \(inside)")
    }

    // MARK: - What leaves the app

    /// The safety claim in one test: what you exported really is pixelated, in
    /// the pixels of the PNG, at the size you asked for.
    @Test func anExportAtTwiceTheSizeCarriesTheSameBlocks() {
        let store = ImageStore()
        let base = store.register(stripeImage(size: 200))
        var doc = PhotonzDocument.withBaseImage(base)
        doc.canvasSize = CGSize(width: 200, height: 200)
        doc.addLayer(lensLayer(.pixelate, amount: 20, frame: CGRect(x: 40, y: 40, width: 80, height: 80)))

        let exported = DocumentRenderer().render(doc, store: store, scale: 2)!
        #expect(exported.width == 400 && exported.height == 400)
        // Document point (62, 62) is export pixel (124, 124); its neighbour one
        // document point over is still inside the same 20pt block.
        let a = pixel(exported, x: 124, y: 124)
        let b = pixel(exported, x: 126, y: 124)
        #expect(a.r == b.r && a.g == b.g && a.b == b.b,
                "a 20pt block is still 20 document points wide at 2x — got \(a) and \(b)")
        #expect(a.r > 40 && a.r < 220, "and it is still an average, not a stripe — got \(a)")
        let outside = pixel(exported, x: 320, y: 124)
        let outsideNext = pixel(exported, x: 322, y: 124)
        #expect(outside.r != outsideNext.r, "outside the lens the stripes survive the export")
    }

    /// A blur exported at 2x has to be twice as many pixels wide or the export
    /// quietly sharpens what somebody hid.
    @Test func anExportAtTwiceTheSizeBlursJustAsHard() {
        let store = ImageStore()
        var doc = halvesDocument(store)
        doc.addLayer(lensLayer(.blur, amount: 12, frame: CGRect(x: 60, y: 60, width: 80, height: 80)))
        let once = DocumentRenderer().render(doc, store: store)!
        let twice = DocumentRenderer().render(doc, store: store, scale: 2)!
        // 12 document points left of the seam: softened by the same amount in
        // both renders.
        let a = pixel(once, x: 88, y: 100)
        let b = pixel(twice, x: 176, y: 200)
        #expect(abs(Int(a.b) - Int(b.b)) < 24,
                "the same document point is blurred the same at 1x and 2x — got \(a) and \(b)")
        #expect(a.b > 8, "and it really is blurred — got \(a)")
    }

    // MARK: - The layers panel

    /// A lens has no picture of its own, so rendering it alone gives an empty
    /// tile. Its row in the layers list shows the part of the real composite
    /// it covers instead.
    @Test func aLensThumbnailShowsThePictureItCovers() {
        let store = ImageStore()
        let base = store.register(solidImage(width: 200, height: 200, r: 255, g: 0, b: 0))
        var doc = PhotonzDocument.withBaseImage(base)
        doc.canvasSize = CGSize(width: 200, height: 200)
        let lens = lensLayer(.invert, frame: CGRect(x: 50, y: 50, width: 100, height: 100))
        doc.addLayer(lens)
        let tile = DocumentRenderer().thumbnail(for: lens.id, in: doc, store: store, maxDimension: 40)
        #expect(tile != nil)
        if let tile {
            let inside = pixel(tile, x: tile.width / 2, y: tile.height / 2)
            #expect(inside.r < 40 && inside.g > 200,
                    "the tile shows the inverted picture — got \(inside)")
        }
    }
}
