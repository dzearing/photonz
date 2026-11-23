import CoreGraphics
import Foundation
import PhotonzCore
import Testing
@testable import PhotonzRender

/// A colour grade on a track of its own grades every picture under it and
/// nothing over it, mixes with them by its Blending, shows only where the
/// layer under it lets it when it is masked, and a keyed matte moves the
/// reveal (task `a-colour-grade-can-be-its-own-track-over-the-cli`).
@Suite("A colour grade track changes the picture under it")
struct ColorGradeLayerRenderTests {

    static let canvas = CGSize(width: 160, height: 90)

    static func pixels(_ image: CGImage) -> [UInt8] {
        let width = image.width, height = image.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        let context = CGContext(data: &data, width: width, height: height,
                                bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return data
    }

    /// One pixel, top-left origin.
    static func pixel(_ image: CGImage, _ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int) {
        let data = pixels(image)
        let index = (y * image.width + x) * 4
        return (Int(data[index]), Int(data[index + 1]), Int(data[index + 2]))
    }

    /// Mean red over blue, and mean brightness, over the whole picture.
    static func mean(_ image: CGImage) -> (warmth: Double, luma: Double) {
        let data = pixels(image)
        var r = 0.0, g = 0.0, b = 0.0
        let count = Double(data.count / 4)
        for index in stride(from: 0, to: data.count, by: 4) {
            r += Double(data[index]); g += Double(data[index + 1]); b += Double(data[index + 2])
        }
        r /= count; g /= count; b /= count
        return (r - b, 0.2126 * r + 0.7152 * g + 0.0722 * b)
    }

    /// A clip stand-in, four colour bands filling the frame, on V1 of an
    /// eight second video.
    static func video() -> (PhotonzDocument, ImageStore) {
        let store = ImageStore()
        let width = Int(canvas.width), height = Int(canvas.height)
        var data = [UInt8](repeating: 255, count: width * height * 4)
        let bands: [(UInt8, UInt8, UInt8)] = [(150, 90, 70), (70, 130, 90), (60, 90, 150), (120, 120, 120)]
        for y in 0..<height {
            for x in 0..<width {
                let band = bands[min(x * bands.count / width, bands.count - 1)]
                let index = (y * width + x) * 4
                data[index] = band.0; data[index + 1] = band.1; data[index + 2] = band.2
            }
        }
        let context = CGContext(data: &data, width: width, height: height, bitsPerComponent: 8,
                                bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let ref = store.register(context.makeImage()!)
        var clip = Layer(name: "beach.mov", content: .image(ref), frame: CGRect(origin: .zero, size: canvas))
        clip.time = LayerTime(inMS: 0, outMS: 8000)
        var document = PhotonzDocument(canvasSize: canvas, layers: [clip])
        document.durationMS = 8000
        return (document, store)
    }

    /// A white box, the matte shape, on a track of its own over the clip.
    @discardableResult
    static func addMatte(_ document: inout PhotonzDocument, box: CGRect) -> UUID {
        var shape = Layer(name: "Matte shape",
                          content: .annotation(AnnotationContent(shape: .rectangle, strokeWidth: 0,
                                                                 colorHex: "#FFFFFF", start: .zero,
                                                                 end: CGPoint(x: box.width, y: box.height),
                                                                 fillColorHex: "#FFFFFF")),
                          frame: box)
        shape.time = LayerTime(inMS: 0, outMS: 8000)
        let landing = document.titleLanding(lengthMS: 8000, atMS: 0, over: nil, newTrackNamed: "Matte")
        return document.land(shape, at: landing) ?? shape.id
    }

    static func render(_ document: PhotonzDocument, store: ImageStore, atMS ms: Int = 1000) throws -> CGImage {
        try #require(DocumentRenderer().render(document.drawn(atTimeMS: ms), store: store, scale: 1))
    }

    @Test func theGradeWarmsEveryPictureUnderIt() throws {
        var (document, store) = Self.video()
        let plain = try Self.render(document, store: store)
        let idAdded = document.addColorGrade(atMS: 0)
        let id = try #require(idAdded)
        document.updateLayer(id: id) { $0.style.effects = [.colorGrade(ColorGradeEffect(temperature: 80))] }
        let graded = try Self.render(document, store: store)
        #expect(Self.mean(graded).warmth - Self.mean(plain).warmth > 20)
    }

    @Test func aGradeAtItsMiddleOrSwitchedOffLeavesThePictureAsItWas() throws {
        var (document, store) = Self.video()
        let plain = try Self.render(document, store: store)
        let idAdded = document.addColorGrade(atMS: 0)
        let id = try #require(idAdded)
        document.updateLayer(id: id) { $0.style.effects = [.colorGrade(.neutral)] }
        #expect(Self.pixels(try Self.render(document, store: store)) == Self.pixels(plain))
        document.updateLayer(id: id) {
            $0.style.effects = [.colorGrade(ColorGradeEffect(temperature: 80, isOn: false))]
        }
        #expect(Self.pixels(try Self.render(document, store: store)) == Self.pixels(plain))
    }

    @Test func outsideItsTimeTheGradeIsNotThere() throws {
        var (document, store) = Self.video()
        let plain = try Self.render(document, store: store, atMS: 1000)
        let idAdded = document.addColorGrade(atMS: 4000)
        let id = try #require(idAdded)
        document.updateLayer(id: id) { $0.style.effects = [.colorGrade(ColorGradeEffect(temperature: 80))] }
        #expect(Self.pixels(try Self.render(document, store: store, atMS: 1000)) == Self.pixels(plain))
        #expect(Self.mean(try Self.render(document, store: store, atMS: 5000)).warmth
            > Self.mean(plain).warmth + 20)
    }

    @Test func whatIsOverTheGradeIsNotGraded() throws {
        var (document, store) = Self.video()
        let idAdded = document.addColorGrade(atMS: 0)
        let id = try #require(idAdded)
        document.updateLayer(id: id) { $0.style.effects = [.colorGrade(ColorGradeEffect(temperature: 80))] }
        // A grey box on a track above the grade keeps its grey.
        Self.addMatte(&document, box: CGRect(x: 0, y: 0, width: 30, height: 30))
        let top = try Self.render(document, store: store)
        let corner = Self.pixel(top, 10, 10)
        #expect(corner.r == 255 && corner.g == 255 && corner.b == 255)
        // ...while the clip beside it, under the grade, is warmed.
        let plain = try Self.render(Self.video().0, store: store)
        #expect(Self.pixel(top, 10, 60).r - Self.pixel(top, 10, 60).b
            > Self.pixel(plain, 10, 60).r - Self.pixel(plain, 10, 60).b + 20)
    }

    @Test func maskedByAShapeTheGradeShowsOnlyInsideIt() throws {
        var (document, store) = Self.video()
        let plain = try Self.render(document, store: store)
        Self.addMatte(&document, box: CGRect(x: 40, y: 20, width: 80, height: 50))
        let idAdded = document.addColorGrade(atMS: 0)
        let id = try #require(idAdded)
        document.updateLayer(id: id) {
            $0.style.effects = [.colorGrade(ColorGradeEffect(temperature: 80))]
            $0.style.matte = .shape
        }
        let masked = try Self.render(document, store: store)
        // Outside the box: the clip exactly as it was, and the white box
        // itself is not drawn (it is the grade's shape, not part of the
        // picture).
        for (x, y) in [(5, 5), (150, 85), (20, 45), (140, 10)] {
            let before = Self.pixel(plain, x, y), after = Self.pixel(masked, x, y)
            #expect(before.r == after.r && before.g == after.g && before.b == after.b, "at \(x), \(y)")
        }
        // Inside it: the clip, warmed.
        for (x, y) in [(50, 45), (110, 45)] {
            let before = Self.pixel(plain, x, y), after = Self.pixel(masked, x, y)
            #expect(after.r - after.b > before.r - before.b + 20, "at \(x), \(y)")
        }
    }

    @Test func aKeyedMatteMovesTheReveal() throws {
        var (document, store) = Self.video()
        let plain = try Self.render(document, store: store)
        let matte = Self.addMatte(&document, box: CGRect(x: 0, y: 20, width: 40, height: 50))
        document.startKeying(layerID: matte, .motion(.position), atDocumentTimeMS: 1000)
        document.setKeyedValue(.point(CGPoint(x: 120, y: 20)), layerID: matte,
                               .motion(.position), atDocumentTimeMS: 3000)
        let idAdded = document.addColorGrade(atMS: 0)
        let id = try #require(idAdded)
        document.updateLayer(id: id) {
            $0.style.effects = [.colorGrade(ColorGradeEffect(temperature: 80))]
            $0.style.matte = .shape
        }
        func warmed(_ image: CGImage, _ x: Int) -> Bool {
            let now = Self.pixel(image, x, 45), before = Self.pixel(plain, x, 45)
            return now.r - now.b > before.r - before.b + 20
        }
        let early = try Self.render(document, store: store, atMS: 500)
        let late = try Self.render(document, store: store, atMS: 3500)
        #expect(warmed(early, 20) && !warmed(early, 140))
        #expect(warmed(late, 140) && !warmed(late, 20))
    }

    @Test func blendingPicksHowTheGradeMixesWithThePictureUnderIt() throws {
        var (document, store) = Self.video()
        let idAdded = document.addColorGrade(atMS: 0)
        let id = try #require(idAdded)
        func luma(_ mode: BlendMode) throws -> Double {
            document.updateLayer(id: id) { $0.style.blendMode = mode }
            return Self.mean(try Self.render(document, store: store)).luma
        }
        let normal = try luma(.normal), screen = try luma(.screen)
        let multiply = try luma(.multiply), add = try luma(.add)
        #expect(screen > normal + 20)
        #expect(multiply < normal - 20)
        #expect(add > screen + 5)
    }
}
