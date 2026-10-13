import CoreGraphics
import Foundation
import Testing
import PhotonzCore
@testable import PhotonzRender

/// A lens switched to Magnify must draw inside its own reach and nowhere else.
/// On 2026-10-12 a Pixelate lens switched to Magnify drew its magnified picture
/// stretched out past every edge of its box, to the end of the canvas; the
/// canvas patched in only the part near the lens on each frame of a drag, so
/// the stretch piled up as a stair-stepped grey smear behind it.
@Suite("A magnifier draws only inside its own reach")
struct LensDragSmearTests {

    /// Stripes of colour, so a stretched edge reads as a different picture.
    static func stripes(width: Int, height: Int) -> CGImage {
        var data = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                let on = (x / 24 + y / 24) % 2 == 0
                data[i] = on ? 230 : 20; data[i + 1] = on ? 230 : 20; data[i + 2] = on ? 240 : 60
                data[i + 3] = 255
            }
        }
        let ctx = CGContext(data: &data, width: width, height: height, bitsPerComponent: 8,
                            bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return ctx.makeImage()!
    }

    static func bytes(_ image: CGImage) -> [UInt8] {
        var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = CGContext(data: &data, width: image.width, height: image.height,
                                bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return data
    }

    /// Share of pixels OUTSIDE `keep` (top-left canvas space) that differ from
    /// the picture with no lens on it at all.
    static func changedOutside(_ keep: CGRect, _ withLens: CGImage, _ without: CGImage) -> Double {
        let a = bytes(withLens), b = bytes(without)
        let width = withLens.width
        var changed = 0, counted = 0
        for y in 0..<withLens.height {
            for x in 0..<width where !keep.contains(CGPoint(x: x, y: y)) {
                counted += 1
                let i = (y * width + x) * 4
                if (0..<3).contains(where: { abs(Int(a[i + $0]) - Int(b[i + $0])) > 8 }) { changed += 1 }
            }
        }
        return counted == 0 ? 0 : Double(changed) / Double(counted)
    }

    static func scene(_ kind: LensAdjustment) throws -> (ImageStore, PhotonzDocument, Layer) {
        let store = ImageStore()
        let base = store.register(stripes(width: 1200, height: 800))
        var doc = PhotonzDocument.withBaseImage(base)
        let lens = try #require(LensBuilder.layer(from: CGPoint(x: 300, y: 150), to: CGPoint(x: 560, y: 330),
                                                  canvas: doc.canvasSize, adjustment: kind))
        let magnifier = LensConversion.layer(lens, becoming: .magnify, canvas: doc.canvasSize)
        #expect(magnifier.zoomCallout != nil)
        doc.addLayer(magnifier)
        return (store, doc, magnifier)
    }

    @Test(arguments: [LensAdjustment.pixelate, .blur, .greyscale, .invert, .brightness])
    func aLensSwitchedToMagnifyDrawsNothingPastItsReach(kind: LensAdjustment) throws {
        let (store, doc, magnifier) = try Self.scene(kind)
        var bare = doc
        bare.updateLayer(id: magnifier.id) { $0.isVisible = false }
        let withLens = try #require(DocumentRenderer().render(doc, store: store))
        let without = try #require(DocumentRenderer().render(bare, store: store))
        // Its own box and source outline, the leader lines between them, and
        // the ring's reach: everything `RenderDiff` says it can touch.
        let reach = RenderDiff.visualBounds(of: magnifier)
        let leaked = Self.changedOutside(reach, withLens, without)
        #expect(leaked == 0, "\(kind) switched to Magnify changed \(leaked * 100)% of the picture outside its reach")
    }

    /// The cause was never the lens: anything enlarged is held at its own
    /// edge before it is resampled, and a square ring round it let that edge
    /// out. A native magnifier with its corners squared off, and a picture
    /// blown up with a ring round it, are the same case.
    @Test func anEnlargedPictureWithASquareRingStaysInItsBox() throws {
        let store = ImageStore()
        let base = store.register(Self.stripes(width: 1200, height: 800))
        var doc = PhotonzDocument.withBaseImage(base)
        let small = store.register(Self.stripes(width: 130, height: 90))
        var style = LayerStyle()
        style.borderWidth = 3
        style.borderColorHex = "#FF3B30"
        let picture = Layer(name: "Blown up", content: .image(small),
                            frame: CGRect(x: 500, y: 300, width: 520, height: 360), style: style)
        doc.addLayer(picture)
        var square = try #require(ZoomCalloutBuilder.layer(from: CGPoint(x: 60, y: 520), to: CGPoint(x: 260, y: 640),
                                                           canvas: doc.canvasSize))
        square.style.cornerRadius = 0
        doc.addLayer(square)
        var bare = doc
        bare.updateLayer(id: picture.id) { $0.isVisible = false }
        bare.updateLayer(id: square.id) { $0.isVisible = false }
        let withThem = try #require(DocumentRenderer().render(doc, store: store))
        let without = try #require(DocumentRenderer().render(bare, store: store))
        let a = RenderDiff.visualBounds(of: picture), b = RenderDiff.visualBounds(of: square)
        let bytesA = Self.bytes(withThem), bytesB = Self.bytes(without)
        var leaked = 0
        for y in 0..<withThem.height {
            for x in 0..<withThem.width {
                let p = CGPoint(x: x, y: y)
                guard !a.contains(p), !b.contains(p) else { continue }
                let i = (y * withThem.width + x) * 4
                if (0..<3).contains(where: { abs(Int(bytesA[i + $0]) - Int(bytesB[i + $0])) > 8 }) { leaked += 1 }
            }
        }
        #expect(leaked == 0, "\(leaked) pixels changed outside the two boxes")
    }

    @Test(arguments: [LensAdjustment.pixelate, .blur])
    func draggingASwitchedMagnifierMatchesAFreshRender(kind: LensAdjustment) throws {
        let (store, doc, magnifier) = try Self.scene(kind)
        let renderer = DocumentRenderer()
        _ = renderer.renderInteractive(doc, store: store)
        for step in 1...12 {
            var moved = doc
            moved.updateLayer(id: magnifier.id) {
                $0.frame = magnifier.frame.offsetBy(dx: -CGFloat(step) * 19, dy: CGFloat(step) * 13)
            }
            let live = try #require(renderer.renderInteractive(moved, store: store))
            let fresh = try #require(DocumentRenderer().render(moved, store: store))
            let differing = FrameAgreement.differingShare(Self.bytes(live), Self.bytes(fresh))
            #expect(differing < 0.005, "move \(step): \(differing * 100)% of the frame differs from a fresh render")
        }
    }
}
