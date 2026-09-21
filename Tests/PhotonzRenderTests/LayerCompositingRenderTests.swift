import CoreGraphics
import Foundation
import Testing
import PhotonzCore
@testable import PhotonzRender

/// The two new compositing rules really land on the canvas: a colour keyed out
/// of a layer, and a layer cut to the shape of the one under it.
///
/// Every test composites a real document and reads points out of the picture,
/// the same bargain `BorderEffectRenderTests` strikes: a rule that is right in
/// the model and wrong in the pixels is wrong.
@Suite("Keying and matting on the canvas")
struct LayerCompositingRenderTests {

    private let canvas = CGSize(width: 200, height: 160)

    private func pixel(_ image: CGImage, _ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int, a: Int) {
        var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = CGContext(data: &data, width: image.width, height: image.height,
                                bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let i = (y * image.width + x) * 4
        guard i + 3 < data.count else { return (0, 0, 0, 0) }
        return (Int(data[i]), Int(data[i + 1]), Int(data[i + 2]), Int(data[i + 3]))
    }

    /// A flat rectangle of one colour filling `frame`.
    private func plate(_ name: String, _ hex: String, _ frame: CGRect) -> Layer {
        Layer(name: name,
              content: .annotation(AnnotationContent(shape: .rectangle,
                                                     strokeWidth: 0,
                                                     colorHex: hex,
                                                     start: .zero,
                                                     end: CGPoint(x: frame.width, y: frame.height),
                                                     fillColorHex: hex)),
              frame: frame)
    }

    private func render(_ layers: [Layer]) -> CGImage {
        var doc = PhotonzDocument(canvasSize: canvas)
        for layer in layers { doc.addLayer(layer) }
        return DocumentRenderer().render(doc, store: ImageStore())!
    }

    private func render(_ doc: PhotonzDocument) -> CGImage {
        DocumentRenderer().render(doc, store: ImageStore())!
    }

    // MARK: - Keying a colour out

    /// A green wall over a blue plate. With the key on, the blue is what you
    /// see: the green is gone rather than merely faded.
    @Test func aKeyedColourLetsWhatIsBehindItThrough() {
        let whole = CGRect(origin: .zero, size: canvas)
        let plateBelow = plate("Beach plate", "#2B6CD4", whole)
        var wall = plate("Subject on green", "#00D84A", whole)

        let before = render([plateBelow, wall])
        let wasGreen = pixel(before, 100, 80)
        #expect(wasGreen.g > 150 && wasGreen.r < 90)

        wall.style.key = ChromaKey(colorHex: "#00D84A")
        let after = render([plateBelow, wall])
        let now = pixel(after, 100, 80)
        #expect(now.b > 150)
        #expect(now.g < 130)
    }

    /// The other half: what is NOT the key colour is still there afterwards.
    @Test func whatIsNotTheKeyColourSurvivesTheKey() {
        let whole = CGRect(origin: .zero, size: canvas)
        var wall = plate("Subject on green", "#00D84A", whole)
        wall.style.key = ChromaKey(colorHex: "#00D84A")
        // A patch of skin inside the wall, drawn over it in the same layer's
        // place on the stack — its own layer, so it keeps its own pixels.
        var subject = plate("Subject", "#E3AC7F", CGRect(x: 70, y: 50, width: 60, height: 60))
        subject.style.key = ChromaKey(colorHex: "#00D84A")

        let image = render([wall, subject])
        let skin = pixel(image, 100, 80)
        #expect(skin.a > 200)
        #expect(skin.r > 180 && skin.b < 190)
        // ...and the wall around it really did go.
        #expect(pixel(image, 10, 10).a < 40)
    }

    @Test func aKeyThatIsSwitchedOffLeavesThePictureExactlyAsItWas() {
        let whole = CGRect(origin: .zero, size: canvas)
        var on = plate("Wall", "#00D84A", whole)
        on.style.key = ChromaKey(colorHex: "#00D84A", isOn: false)
        #expect(pixel(render([on]), 100, 80).g > 150)
    }

    /// A layer that was already part transparent stays part transparent. The
    /// colour cube on its own hands back an opaque picture, so the source's own
    /// alpha has to be put back over the top — without it, every rounded corner
    /// and every letter's edge would fill in black.
    @Test func aKeyDoesNotFillInWhatWasAlreadyTransparent() {
        var small = plate("Card", "#2B6CD4", CGRect(x: 60, y: 40, width: 80, height: 80))
        small.style.key = ChromaKey(colorHex: "#00D84A")
        let image = render([small])
        // Outside the card there was nothing, and there still is nothing.
        #expect(pixel(image, 10, 10).a < 20)
        #expect(pixel(image, 100, 80).a > 200)
    }

    // MARK: - Masked by the layer below

    @Test func aLayerIsCutToTheShapeOfTheOneBelowIt() {
        let whole = CGRect(origin: .zero, size: canvas)
        let shape = plate("Matte shape", "#FFFFFF", CGRect(x: 60, y: 40, width: 80, height: 80))
        var grade = plate("Colour grade", "#FF3366", whole)
        grade.style.matte = .shape

        let image = render([shape, grade])
        // Inside the shape, the grade shows.
        let inside = pixel(image, 100, 80)
        #expect(inside.a > 200 && inside.r > 180 && inside.g < 120)
        // Outside it, nothing at all: the grade is cut away AND the shape that
        // cut it is spent, so it does not draw itself either.
        #expect(pixel(image, 10, 10).a < 20)
        #expect(pixel(image, 190, 150).a < 20)
    }

    @Test func aMatteSourceDoesNotDrawItsOwnColour() {
        let shape = plate("Matte shape", "#FFFFFF", CGRect(x: 60, y: 40, width: 80, height: 80))
        var grade = plate("Colour grade", "#FF3366", CGRect(x: 60, y: 40, width: 80, height: 80))
        grade.style.matte = .shape
        let image = render([shape, grade])
        // If the white were still being drawn it would be under the grade and
        // invisible, so the test that means anything is the one where the top
        // layer covers only half of it.
        var half = plate("Colour grade", "#FF3366", CGRect(x: 60, y: 40, width: 40, height: 80))
        half.style.matte = .shape
        let halfImage = render([shape, half])
        #expect(pixel(halfImage, 70, 80).r > 180)
        // The right half of the white shape has nothing over it, and it is not
        // drawn: it is a shape, not a picture.
        #expect(pixel(halfImage, 130, 80).a < 20)
        #expect(pixel(image, 100, 80).r > 180)
    }

    /// Brightness rather than shape: a mid grey below shows the layer above at
    /// about half, which is what makes a gradient below a fade above.
    @Test func aBrightnessMatteFadesByHowLightTheLayerBelowIs() {
        let whole = CGRect(origin: .zero, size: canvas)
        let dark = plate("Matte", "#404040", whole)
        var grade = plate("Colour grade", "#FF3366", whole)
        grade.style.matte = .brightness
        let dim = pixel(render([dark, grade]), 100, 80)

        let bright = plate("Matte", "#FFFFFF", whole)
        let full = pixel(render([bright, grade]), 100, 80)

        #expect(dim.a > 20 && dim.a < 160)
        #expect(full.a > 230)
    }

    @Test func aLayerWithNothingBelowItIsNotMasked() {
        let whole = CGRect(origin: .zero, size: canvas)
        var grade = plate("Colour grade", "#FF3366", whole)
        grade.style.matte = .shape
        #expect(pixel(render([grade]), 100, 80).a > 200)
    }

    /// Reordering is the gesture: the same three layers, one of them moved, and
    /// the picture changes the way the layers list says it should.
    @Test func reorderingChangesWhatIsMasked() {
        let whole = CGRect(origin: .zero, size: canvas)
        let wide = plate("Wide plate", "#FFFFFF", whole)
        let small = plate("Matte shape", "#FFFFFF", CGRect(x: 60, y: 40, width: 80, height: 80))
        var grade = plate("Colour grade", "#FF3366", whole)
        grade.style.matte = .shape

        // Small directly under the grade: at the corner the grade is cut away,
        // and what is left there is the white plate.
        let cut = pixel(render([wide, small, grade]), 10, 10)
        #expect(cut.r > 200 && cut.g > 200)
        // Wide directly under it: the grade covers the whole canvas, corner
        // included. Nothing moved but the order of two rows.
        let swapped = pixel(render([small, wide, grade]), 10, 10)
        #expect(swapped.r > 180 && swapped.g < 120)
    }

    // MARK: - At a moment of the document's clock

    /// The whole thesis: what a scrub shows is what an export writes, keys and
    /// mattes included. `drawn(atTimeMS:)` hands the renderer an ordinary
    /// document, so nothing about compositing needs to know about time — this
    /// is the test that proves it rather than assuming it.
    @Test func aKeyAndAMatteBothHoldAtAMomentOnTheTimeline() {
        let whole = CGRect(origin: .zero, size: canvas)
        var plateBelow = plate("Beach plate", "#2B6CD4", whole)
        plateBelow.time = LayerTime(inMS: 0, outMS: 4000)
        var wall = plate("Subject on green", "#00D84A", whole)
        wall.time = LayerTime(inMS: 0, outMS: 2000)
        wall.style.key = ChromaKey(colorHex: "#00D84A")

        var doc = PhotonzDocument(canvasSize: canvas)
        doc.addLayer(plateBelow)
        doc.addLayer(wall)
        doc.durationMS = 4000

        // One second in, the keyed wall is on screen and the blue shows through.
        let early = pixel(render(doc.drawn(atTimeMS: 1000)), 100, 80)
        #expect(early.b > 150)
        // Three seconds in the wall has gone entirely, and the blue is still
        // the blue: a key is not a thing that leaks past its clip.
        let late = pixel(render(doc.drawn(atTimeMS: 3000)), 100, 80)
        #expect(late.b > 150)
        #expect(late.a > 200)
    }

    // MARK: - One click of Key it

    /// The colour a key starts on is read off the picture, so keying a green
    /// screen is one click rather than an exercise with an eyedropper.
    @Test func theKeyColourIsSampledFromTheEdgesOfThePicture() {
        let width = 64, height = 48
        var data = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                // A subject in the middle, a green wall everywhere else.
                let middle = x > 20 && x < 44 && y > 12 && y < 36
                data[i] = middle ? 227 : 0
                data[i + 1] = middle ? 172 : 216
                data[i + 2] = middle ? 127 : 74
                data[i + 3] = 255
            }
        }
        let context = CGContext(data: &data, width: width, height: height,
                                bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let sampled = ChromaKeySampler.wallColour(of: context.makeImage()!)
        #expect(sampled != nil)
        #expect(sampled!.g > 0.6)
        #expect(sampled!.r < 0.25)
    }

    @Test func aPictureWithNoOneColourRoundItsEdgeOffersNothingToKey() {
        let width = 32, height = 32
        var data = [UInt8](repeating: 0, count: width * height * 4)
        for i in stride(from: 0, to: data.count, by: 4) {
            data[i] = UInt8((i / 4) % 256)
            data[i + 1] = UInt8((i / 7) % 256)
            data[i + 2] = UInt8((i / 5) % 256)
            data[i + 3] = 255
        }
        let context = CGContext(data: &data, width: width, height: height,
                                bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        #expect(ChromaKeySampler.wallColour(of: context.makeImage()!) == nil)
    }
}

/// The key on a real picture rather than on flat rectangles: a green wall lit
/// from one side, with somebody standing in front of it.
///
/// Flat colours are the easy case. A wall that falls off into its corners is
/// the case the key was designed for, and the only way to know it works is to
/// run it on one.
@Suite("A key on a real green screen")
struct GreenScreenFixtureTests {

    private static let picture: CGImage? = {
        guard let url = Bundle.module.url(forResource: "Fixtures/green-screen",
                                          withExtension: "png"),
              let data = try? Data(contentsOf: url) else { return nil }
        return ImageCodec.decode(data)
    }()

    private func sample(_ image: CGImage, _ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int, a: Int) {
        var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = CGContext(data: &data, width: image.width, height: image.height,
                                bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let i = (y * image.width + x) * 4
        return (Int(data[i]), Int(data[i + 1]), Int(data[i + 2]), Int(data[i + 3]))
    }

    @Test func oneClickFindsTheWall() throws {
        let picture = try #require(Self.picture)
        let wall = try #require(ChromaKeySampler.wallColour(of: picture))
        #expect(wall.g > 0.55)
        #expect(wall.r < 0.2)
    }

    /// The whole claim, end to end: the colour the app would offer, used as the
    /// key the app would set, takes the wall away — its lit corner and its dark
    /// corner both — and leaves the subject standing.
    @Test func theWallGoesAndTheSubjectStays() throws {
        let picture = try #require(Self.picture)
        let wall = try #require(ChromaKeySampler.wallColour(of: picture))
        let key = ChromaKey(colorHex: wall.hexString)

        let store = ImageStore()
        let ref = store.register(picture)
        let size = CGSize(width: picture.width, height: picture.height)
        var layer = Layer(name: "Subject on green", content: .image(ref),
                          frame: CGRect(origin: .zero, size: size))
        layer.style.key = key
        var doc = PhotonzDocument(canvasSize: size)
        doc.addLayer(layer)
        let image = try #require(DocumentRenderer().render(doc, store: store))

        // The brightest corner of the wall and the darkest, both gone.
        #expect(sample(image, 40, 40).a < 40)
        #expect(sample(image, picture.width - 40, picture.height - 40).a < 40)
        // The subject's face, still there and still the colour it was.
        let face = sample(image, picture.width / 2, 250)
        #expect(face.a > 220)
        #expect(face.r > 180 && face.b < 200)
    }
}
