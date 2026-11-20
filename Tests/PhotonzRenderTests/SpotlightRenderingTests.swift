import CoreGraphics
import Foundation
import ImageIO
import Testing
import PhotonzCore
@testable import PhotonzRender

/// A spotlight leaves its own area exactly as it was and dims, blurs or both
/// everything else on the picture.
@Suite("Spotlight rendering")
struct SpotlightRenderingTests {

    static let size = 200
    static let area = CGRect(x: 60, y: 60, width: 80, height: 80)

    // MARK: - Pictures

    /// Alternating black and white columns one point wide: anything that
    /// blurs turns it grey, anything that dims takes the white down.
    static func stripes() -> CGImage {
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

    static func solid(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> CGImage {
        let context = CGContext(data: nil, width: size, height: size,
                                bitsPerComponent: 8, bytesPerRow: size * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(srgbRed: r, green: g, blue: b, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))
        return context.makeImage()!
    }

    /// Straight sRGB bytes, row zero at the TOP, so a document point reads
    /// straight off it.
    static func bytes(_ image: CGImage) -> [UInt8] {
        let width = image.width, height = image.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        let context = CGContext(data: &data, width: width, height: height,
                                bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return data
    }

    struct Pixels {
        let data: [UInt8]
        let width: Int
        init(_ image: CGImage) { data = SpotlightRenderingTests.bytes(image); width = image.width }
        func at(_ x: Int, _ y: Int) -> [Int] {
            let o = (y * width + x) * 4
            return [Int(data[o]), Int(data[o + 1]), Int(data[o + 2]), Int(data[o + 3])]
        }
        func luma(_ x: Int, _ y: Int) -> Double {
            let p = at(x, y)
            return 0.2126 * Double(p[0]) + 0.7152 * Double(p[1]) + 0.0722 * Double(p[2])
        }
        /// Mean luma over every pixel `where` says yes to.
        func meanLuma(where include: (Int, Int) -> Bool) -> Double {
            var total = 0.0, count = 0
            for y in 0..<SpotlightRenderingTests.size {
                for x in 0..<width where include(x, y) {
                    total += luma(x, y)
                    count += 1
                }
            }
            return count > 0 ? total / Double(count) : 0
        }
    }

    static func document(_ picture: CGImage, store: ImageStore,
                         spotlight configure: (inout LensContent) -> Void,
                         frame: CGRect = area, style: (inout LayerStyle) -> Void = { _ in }) -> PhotonzDocument {
        var doc = PhotonzDocument.withBaseImage(store.register(picture))
        doc.canvasSize = CGSize(width: size, height: size)
        var lens = LensContent(adjustment: .spotlight)
        configure(&lens)
        var layerStyle = LayerStyle()
        style(&layerStyle)
        doc.addLayer(Layer(name: "Spotlight", content: .lens(lens), frame: frame, style: layerStyle))
        return doc
    }

    static func isInside(_ x: Int, _ y: Int) -> Bool {
        area.contains(CGPoint(x: CGFloat(x) + 0.5, y: CGFloat(y) + 0.5))
    }

    /// Clear of the area by more than the blur's reach, so a blur that
    /// smears across the edge does not count.
    static func isWellOutside(_ x: Int, _ y: Int) -> Bool {
        !area.insetBy(dx: -30, dy: -30).contains(CGPoint(x: CGFloat(x) + 0.5, y: CGFloat(y) + 0.5))
    }

    // MARK: - The area is untouched

    @Test(arguments: [CompositingSpace.linearLight, .sRGB], [CGFloat(0), 30])
    func theAreaIsPixelIdenticalToThePicture(space: CompositingSpace, feather: CGFloat) throws {
        let store = ImageStore()
        let picture = Self.stripes()
        let plain = PhotonzDocument.withBaseImage(store.register(picture))
        let doc = Self.document(picture, store: store) {
            $0.setSpotlightDim(0.6)
            $0.setSpotlightBlur(10)
            $0.setSpotlightFeather(feather)
        }
        let renderer = DocumentRenderer(compositing: space)
        let before = Pixels(try #require(renderer.render(plain, store: store)))
        let after = Pixels(try #require(renderer.render(doc, store: store)))
        var differing = 0
        for y in 60..<140 { for x in 60..<140 where before.at(x, y) != after.at(x, y) { differing += 1 } }
        #expect(differing == 0, "every pixel inside the area is the picture's own")
        // ...and outside it something did change.
        #expect(before.at(10, 10) != after.at(10, 10))
    }

    // MARK: - Dim

    /// THE BAR: at Dim 50% the picture outside goes half as bright to the eye
    /// and the inside does not change at all. A plain lens cannot do this.
    @Test(arguments: [CompositingSpace.linearLight, .sRGB])
    func dimHalvesTheLightOutsideAndLeavesTheInside(space: CompositingSpace) throws {
        let store = ImageStore()
        let picture = Self.stripes()
        let plain = PhotonzDocument.withBaseImage(store.register(picture))
        let doc = Self.document(picture, store: store) {
            $0.setSpotlightDim(0.5)
            $0.setSpotlightBlur(0)
        }
        let renderer = DocumentRenderer(compositing: space)
        let before = Pixels(try #require(renderer.render(plain, store: store)))
        let after = Pixels(try #require(renderer.render(doc, store: store)))
        let outsideBefore = before.meanLuma { !Self.isInside($0, $1) }
        let outsideAfter = after.meanLuma { !Self.isInside($0, $1) }
        let ratio = outsideAfter / outsideBefore
        #expect(abs(ratio - 0.5) < 0.03, "outside mean luma went \(outsideBefore) to \(outsideAfter)")
        let insideBefore = before.meanLuma(where: Self.isInside)
        let insideAfter = after.meanLuma(where: Self.isInside)
        #expect(insideBefore == insideAfter)
        // Dim only: the stripes are still stripes.
        let a = after.at(10, 10), b = after.at(11, 10)
        #expect(abs(a[0] - b[0]) > 100, "dim alone leaves the stripes sharp, got \(a) and \(b)")
    }

    // MARK: - Blur

    @Test func blurAloneSoftensTheOutsideWithoutDarkeningIt() throws {
        let store = ImageStore()
        let doc = Self.document(Self.stripes(), store: store) {
            $0.setSpotlightDim(0)
            $0.setSpotlightBlur(6)
        }
        let after = Pixels(try #require(DocumentRenderer().render(doc, store: store)))
        let a = after.at(20, 20), b = after.at(21, 20)
        #expect(abs(a[0] - b[0]) < 12, "the stripes run together into grey, got \(a) and \(b)")
        // In light, black and white average to a light grey, not to 128.
        #expect(a[0] > 100, "not darkened, got \(a)")
    }

    /// Blurred against the transparency past the canvas, the picture's edge
    /// would wear a dark rim. It is held at its own edge instead.
    @Test func theBlurLeavesNoDarkRimAtThePicturesEdge() throws {
        let store = ImageStore()
        let doc = Self.document(Self.solid(0.8, 0.7, 0.6), store: store) {
            $0.setSpotlightDim(0)
            $0.setSpotlightBlur(30)
        }
        let after = Pixels(try #require(DocumentRenderer().render(doc, store: store)))
        for (x, y) in [(0, 0), (199, 0), (0, 199), (199, 199), (100, 0), (0, 100)] {
            let p = after.at(x, y)
            #expect(abs(p[0] - 204) <= 2 && abs(p[1] - 179) <= 2 && abs(p[2] - 153) <= 2 && p[3] == 255,
                    "edge pixel (\(x), \(y)) kept its colour, got \(p)")
        }
    }

    @Test func dimAndBlurTogether() throws {
        let store = ImageStore()
        let doc = Self.document(Self.stripes(), store: store) {
            $0.setSpotlightDim(0.5)
            $0.setSpotlightBlur(6)
        }
        let after = Pixels(try #require(DocumentRenderer().render(doc, store: store)))
        let blurOnly = Pixels(try #require(DocumentRenderer().render(
            Self.document(Self.stripes(), store: store) { $0.setSpotlightDim(0); $0.setSpotlightBlur(6) },
            store: store)))
        let a = after.at(20, 20), b = after.at(21, 20)
        #expect(abs(a[0] - b[0]) < 12, "blurred, got \(a) and \(b)")
        let ratio = after.luma(20, 20) / blurOnly.luma(20, 20)
        #expect(abs(ratio - 0.5) < 0.03, "and dimmed by half, ratio \(ratio)")
    }

    // MARK: - Shape and edge

    @Test func anEllipseLightsItsOvalAndDimsTheBoxCorners() throws {
        let store = ImageStore()
        let doc = Self.document(Self.solid(1, 1, 1), store: store) {
            $0.setSpotlightDim(0.5)
            $0.setSpotlightBlur(0)
            $0.spotlightShape = .ellipse
        }
        let after = Pixels(try #require(DocumentRenderer().render(doc, store: store)))
        #expect(after.at(100, 100)[0] == 255, "the middle is lit")
        #expect(after.at(62, 62)[0] < 140, "the box's corner, outside the oval, is dimmed")
        #expect(after.at(10, 10)[0] < 140)
    }

    @Test func roundedCornersRoundTheLitArea() throws {
        let store = ImageStore()
        let doc = Self.document(Self.solid(1, 1, 1), store: store, spotlight: {
            $0.setSpotlightDim(0.5)
            $0.setSpotlightBlur(0)
        }, style: { $0.cornerRadius = 30 })
        let after = Pixels(try #require(DocumentRenderer().render(doc, store: store)))
        #expect(after.at(100, 100)[0] == 255)
        #expect(after.at(61, 61)[0] < 140, "the rounded-off corner is dimmed")
        #expect(after.at(100, 61)[0] == 255, "the straight edge is lit")
    }

    /// A feather's soft band lies wholly outside the area: lit at its edge,
    /// half way down part of the way out, fully dimmed a feather's width out.
    @Test func aFeatherFallsOffOutsideTheArea() throws {
        let store = ImageStore()
        let doc = Self.document(Self.solid(1, 1, 1), store: store) {
            $0.setSpotlightDim(0.5)
            $0.setSpotlightBlur(0)
            $0.setSpotlightFeather(40)
        }
        let after = Pixels(try #require(DocumentRenderer().render(doc, store: store)))
        #expect(after.at(139, 100)[0] == 255, "the area's own edge stays lit")
        let partWay = after.at(160, 100)[0]
        #expect(partWay < 250 && partWay > 140, "twenty points out is part way, got \(partWay)")
        let hard = Pixels(try #require(DocumentRenderer().render(
            Self.document(Self.solid(1, 1, 1), store: store) { $0.setSpotlightDim(0.5); $0.setSpotlightBlur(0) },
            store: store)))
        #expect(abs(after.at(185, 100)[0] - hard.at(185, 100)[0]) <= 2, "a feather's width out is fully dimmed")
        #expect(hard.at(141, 100)[0] < 140, "and with no feather the edge is hard")
    }

    /// An area dragged clear off the picture still leaves the rest dimmed,
    /// feather or no feather.
    @Test func anAreaOffThePictureStillDimsTheRest() throws {
        let store = ImageStore()
        let doc = Self.document(Self.solid(1, 1, 1), store: store, spotlight: {
            $0.setSpotlightDim(0.5)
            $0.setSpotlightBlur(0)
            $0.setSpotlightFeather(20)
        }, frame: CGRect(x: 300, y: 300, width: 40, height: 40))
        let after = Pixels(try #require(DocumentRenderer().render(doc, store: store)))
        #expect(after.at(100, 100)[0] < 140)
    }

    // MARK: - The layer's own opacity

    @Test func noOpacityIsNoSpotlight() throws {
        let store = ImageStore()
        let doc = Self.document(Self.solid(1, 1, 1), store: store, spotlight: {
            $0.setSpotlightDim(1)
            $0.setSpotlightBlur(0)
        }, style: { $0.opacity = 0 })
        let after = Pixels(try #require(DocumentRenderer().render(doc, store: store)))
        #expect(after.at(10, 10)[0] == 255, "a spotlight at no opacity changes nothing")
    }

    // MARK: - Export and redraw

    /// What leaves the app is what the canvas shows.
    @Test func theExportedPNGIsTheCanvas() async throws {
        let store = ImageStore()
        let doc = Self.document(Self.stripes(), store: store) {
            $0.setSpotlightDim(0.5)
            $0.setSpotlightBlur(6)
            $0.setSpotlightFeather(20)
            $0.spotlightShape = .ellipse
        }
        let canvas = Pixels(try #require(DocumentRenderer().render(doc, store: store)))
        let sizer = ExportSizer(renderer: DocumentRenderer(), store: store)
        let data = try #require(await sizer.data(of: doc, frameID: nil, scale: 1, format: .png,
                                                 quality: 1, background: .keep))
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let exported = Pixels(try #require(CGImageSourceCreateImageAtIndex(source, 0, nil)))
        var worst = 0
        for y in stride(from: 0, to: Self.size, by: 3) {
            for x in stride(from: 0, to: Self.size, by: 3) {
                let a = canvas.at(x, y), b = exported.at(x, y)
                worst = max(worst, zip(a, b).map { abs($0 - $1) }.max() ?? 0)
            }
        }
        #expect(worst <= 1, "export matches the canvas, worst channel difference \(worst)")
    }

    /// The canvas redraws a changed part on its own; that part has to come
    /// out the same as it does in the whole picture, blur reach and all.
    @Test func aRedrawnPatchMatchesTheWholePicture() throws {
        let store = ImageStore()
        let doc = Self.document(Self.stripes(), store: store) {
            $0.setSpotlightDim(0.4)
            $0.setSpotlightBlur(8)
        }
        let renderer = DocumentRenderer()
        let whole = Pixels(try #require(renderer.render(doc, store: store)))
        let patch = Pixels(try #require(renderer.rasterize(region: CGRect(x: 40, y: 40, width: 40, height: 40),
                                                            of: doc, store: store)))
        var worst = 0
        for y in 0..<40 {
            for x in 0..<40 {
                let a = whole.at(40 + x, 40 + y), b = patch.at(x, y)
                worst = max(worst, zip(a, b).map { abs($0 - $1) }.max() ?? 0)
            }
        }
        #expect(worst <= 1, "patch matches, worst channel difference \(worst)")
    }
}
