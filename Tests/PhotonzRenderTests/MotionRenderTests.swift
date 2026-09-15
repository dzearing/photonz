import CoreGraphics
import Foundation
import PhotonzCore
import Testing
@testable import PhotonzRender

/// A motion has to reach the PIXELS, and only the pixels.
///
/// The model tests next door settle what a layer's properties are at a given
/// millisecond. This settles the other half of the claim in the task: the
/// picture plays it, and nothing is baked in. It renders the same document at
/// three moments through the same renderer the canvas uses, so it is the real
/// composite path rather than a description of one, and it needs no window:
/// these run with the screen locked, which is when they were written.
@Suite("A motion reaches the pixels and is never baked in")
struct MotionRenderTests {

    private func pixels(_ image: CGImage) -> [UInt8] {
        let width = image.width, height = image.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        let context = CGContext(data: &data, width: width, height: height,
                                bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return data
    }

    /// How different two pictures are, as a share of their bytes. Zero is the
    /// same picture.
    private func difference(_ a: CGImage, _ b: CGImage) -> Double {
        let left = pixels(a), right = pixels(b)
        guard left.count == right.count, !left.isEmpty else { return 1 }
        let changed = zip(left, right).count { abs(Int($0) - Int($1)) > 8 }
        return Double(changed) / Double(left.count)
    }

    /// A black box in the middle of a small canvas, told to swing.
    private func swinging(repeats: MotionRepeat = .foreverThereAndBack) -> PhotonzDocument {
        var layer = Layer(name: "Box",
                          content: .annotation(AnnotationContent(shape: .rectangle,
                                                                 strokeWidth: 0,
                                                                 colorHex: "#000000",
                                                                 start: .zero,
                                                                 end: CGPoint(x: 80, y: 80),
                                                                 fillColorHex: "#000000")),
                          frame: CGRect(x: 60, y: 60, width: 80, height: 80))
        layer.motions = [LayerMotion(property: .rotation,
                                     from: .number(-12), to: .number(12),
                                     timing: MotionTiming(startMS: 0, durationMS: 900),
                                     curve: .easeInOutSine, repeats: repeats)]
        return PhotonzDocument(canvasSize: CGSize(width: 200, height: 200), layers: [layer])
    }

    private func render(_ document: PhotonzDocument) -> CGImage? {
        DocumentRenderer().render(document, store: ImageStore(), scale: 1)
    }

    /// THE TEST: the same document at two moments is two different pictures.
    @Test func thePictureAtTwoMomentsIsTwoDifferentPictures() throws {
        let document = swinging()
        let start = try #require(render(document.moved(toMotionTimeMS: 0)))
        let middle = try #require(render(document.moved(toMotionTimeMS: 450)))
        #expect(difference(start, middle) > 0.01,
                "a swing of 24 degrees has to move more ink than this")
    }

    /// ...and the document itself never moves. What the canvas is handed is a
    /// copy worked out at the moment it is drawn, exactly like a blur or a
    /// shadow, so the layer you can still drag is the layer you drew.
    @Test func theStoredDocumentIsTheOneYouDrew() throws {
        let document = swinging()
        let before = document.layers
        let moved = document.moved(toMotionTimeMS: 450)
        // Asking for a moment does not change anything: the picture the canvas
        // shows while the preview is STOPPED is the stored one, which is what
        // you edit against. A canvas quietly animating under a layer you are
        // trying to drag would be a canvas you cannot work on.
        #expect(document.layers == before)
        #expect(document.layers.first?.transform.rotation == 0)
        let stored = try #require(render(document))
        let playing = try #require(render(moved))
        #expect(difference(stored, playing) > 0.002,
                "and the frame being played is not the stored picture")
    }

    /// There and back comes home, so a loop has no seam in it: the last frame
    /// of one cycle and the first frame of the next are the same picture.
    @Test func aLoopThatComesBackHasNoSeamInIt() throws {
        let document = swinging()
        let topOfTheCycle = try #require(render(document.moved(toMotionTimeMS: 0)))
        let nextCycle = try #require(render(document.moved(toMotionTimeMS: 900)))
        #expect(difference(topOfTheCycle, nextCycle) == 0)
    }

    /// A motion switched off draws nothing at all, whatever the clock says.
    @Test func aSwitchedOffMotionDrawsTheLayerAsItWasDrawn() throws {
        var document = swinging()
        document.layers[0].motions?[0].isOn = false
        let still = try #require(render(document.moved(toMotionTimeMS: 450)))
        let drawn = try #require(render(document))
        #expect(difference(still, drawn) == 0)
    }

    /// Opacity and colour reach the pixels too, not just the transform: the
    /// three go through three different parts of the renderer and only one of
    /// them is the layer's frame.
    @Test func fadingAndRepaintingBothReachThePixels() throws {
        var faded = PhotonzDocument(
            canvasSize: CGSize(width: 120, height: 120),
            layers: [Layer(name: "Box",
                           content: .annotation(AnnotationContent(shape: .rectangle,
                                                                  strokeWidth: 0,
                                                                  colorHex: "#000000",
                                                                  start: .zero,
                                                                  end: CGPoint(x: 80, y: 80),
                                                                  fillColorHex: "#000000")),
                           frame: CGRect(x: 20, y: 20, width: 80, height: 80))])
        faded.layers[0].motions = [LayerMotion(property: .opacity,
                                               from: .number(100), to: .number(0),
                                               timing: MotionTiming(startMS: 0, durationMS: 500),
                                               curve: .linear, repeats: .once)]
        let solid = try #require(render(faded.moved(toMotionTimeMS: 0)))
        let gone = try #require(render(faded.moved(toMotionTimeMS: 500)))
        #expect(difference(solid, gone) > 0.05)

        var repainted = faded
        repainted.layers[0].motions = [LayerMotion(property: .color,
                                                   from: .color("#000000"), to: .color("#FFFFFF"),
                                                   timing: MotionTiming(startMS: 0, durationMS: 500),
                                                   curve: .linear, repeats: .once)]
        let black = try #require(render(repainted.moved(toMotionTimeMS: 0)))
        let white = try #require(render(repainted.moved(toMotionTimeMS: 500)))
        #expect(difference(black, white) > 0.05)
    }
}
