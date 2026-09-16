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

/// What a turn turns AROUND, in the pixels.
///
/// The model tests next door settle where a pivot IS. This settles that the
/// composite actually swings about it, which is the whole claim: with the
/// pivot in the middle a bell rocks like a bobblehead, and one drag to the
/// mount turns it into a bell.
@Suite("A turn swings about the pivot it was given")
struct MotionPivotRenderTests {

    /// Where the ink is, as the box that holds every pixel that is not clear.
    private func inkBox(_ image: CGImage) -> CGRect? {
        let width = image.width, height = image.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        let context = CGContext(data: &data, width: width, height: height,
                                bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            for x in 0..<width where data[(y * width + x) * 4 + 3] > 40 {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= 0 else { return nil }
        // Row nought of a bitmap context IS the top row of the picture drawn
        // into it, and the renderer hands back a CGImage that already shares
        // the model's top-left origin, so this is document space already.
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    /// A 40x40 black square at (80, 80) on a 200x200 canvas, turned a quarter
    /// turn, about whatever it is told to turn about.
    private func turned(_ pivot: MotionPivot) -> PhotonzDocument {
        var layer = Layer(name: "Box",
                          content: .annotation(AnnotationContent(shape: .rectangle,
                                                                 strokeWidth: 0,
                                                                 colorHex: "#000000",
                                                                 start: .zero,
                                                                 end: CGPoint(x: 40, y: 40),
                                                                 fillColorHex: "#000000")),
                          frame: CGRect(x: 80, y: 80, width: 40, height: 40))
        layer.transform.rotation = .pi / 2
        layer.motions = [LayerMotion(property: .rotation,
                                     from: .number(90), to: .number(90),
                                     timing: MotionTiming(startMS: 0, durationMS: 900),
                                     pivot: pivot)]
        return PhotonzDocument(canvasSize: CGSize(width: 200, height: 200), layers: [layer])
    }

    private func render(_ document: PhotonzDocument) -> CGImage? {
        DocumentRenderer().render(document, store: ImageStore(), scale: 1)
    }

    /// The ruler these tests are read with, checked against a layer that is
    /// not turned at all: a 40x40 box stored at (80, 80) has its ink at
    /// (80, 80). Without this every number below could be upside down and
    /// still agree with itself.
    @Test func theInkOfAnUnturnedLayerIsWhereItsFrameSays() throws {
        var still = turned(.centre)
        still.layers[0].transform.rotation = 0
        still.layers[0].motions = nil
        let image = try #require(render(still))
        let box = try #require(inkBox(image))
        #expect(abs(box.minX - 80) < 1.5, "got \(box)")
        #expect(abs(box.minY - 80) < 1.5, "got \(box)")
    }

    /// A square turned about its own middle stays exactly where it was: a
    /// square is its own quarter turn.
    @Test func turningAboutTheMiddleLeavesASquareWhereItWas() throws {
        let image = try #require(render(turned(.centre)))
        let box = try #require(inkBox(image))
        #expect(abs(box.midX - 100) < 1.5)
        #expect(abs(box.midY - 100) < 1.5)
    }

    /// ...and the same square turned about its TOP edge swings out from under
    /// itself. A quarter turn clockwise about (100, 80) takes the box's middle
    /// from twenty below the pivot to twenty to its left.
    @Test func turningAboutTheTopEdgeSwingsTheSquareOutFromUnderIt() throws {
        let image = try #require(render(turned(.topCentre)))
        let box = try #require(inkBox(image))
        #expect(abs(box.midX - 80) < 1.5, "expected the middle 20 left of the pivot, got \(box)")
        #expect(abs(box.midY - 80) < 1.5, "expected the middle level with the pivot, got \(box)")
    }

    /// A pivot ABOVE the shape altogether, which is what a bell hanging from
    /// its mount is: the swing is wider the further the mount is.
    @Test func aPivotAboveTheShapeSwingsItFurther() throws {
        let mount = MotionPivot(unit: CGPoint(x: 0.5, y: -1))
        let image = try #require(render(turned(mount)))
        let box = try #require(inkBox(image))
        // The pivot is at (100, 40); the middle is 60 below it, so a quarter
        // turn clockwise puts it 60 to its left.
        #expect(abs(box.midX - 40) < 1.5, "got \(box)")
        #expect(abs(box.midY - 40) < 1.5, "got \(box)")
    }

    /// The pivot reaches a GROUP the same way. A card turns about its mount
    /// too, and a group's turn is taken by the whole card at once.
    @Test func aGroupTurnsAboutItsPivotAsWell() throws {
        var child = Layer(name: "Box",
                          content: .annotation(AnnotationContent(shape: .rectangle,
                                                                 strokeWidth: 0,
                                                                 colorHex: "#000000",
                                                                 start: .zero,
                                                                 end: CGPoint(x: 40, y: 40),
                                                                 fillColorHex: "#000000")),
                          frame: CGRect(x: 0, y: 0, width: 40, height: 40))
        child.name = "Box"
        var group = Layer(name: "Card", content: .group(GroupContent(children: [child])),
                          frame: CGRect(x: 80, y: 80, width: 0, height: 0))
        group.transform.rotation = .pi / 2
        group.motions = [LayerMotion(property: .rotation,
                                     from: .number(90), to: .number(90),
                                     timing: MotionTiming(startMS: 0, durationMS: 900),
                                     pivot: .topCentre)]
        let document = PhotonzDocument(canvasSize: CGSize(width: 200, height: 200), layers: [group])
        let image = try #require(render(document))
        let box = try #require(inkBox(image))
        // The group's box is the 40x40 its child makes, at (80, 80); its top
        // centre is (100, 80) and its middle is 20 below that.
        #expect(abs(box.midX - 80) < 1.5, "got \(box)")
        #expect(abs(box.midY - 80) < 1.5, "got \(box)")
    }

    /// Nothing that does not turn is touched. This is the guard on every
    /// picture the app has ever drawn: the pivot only ever answers for a layer
    /// that has a rotation motion on it, and only when that motion has been
    /// moved off the middle.
    @Test func aLayerWithNoTurnIsRenderedExactlyAsBefore() throws {
        var plain = turned(.centre)
        plain.layers[0].motions = nil
        let withMotion = try #require(render(turned(.centre)))
        let without = try #require(render(plain))
        #expect(inkBox(withMotion) == inkBox(without))
    }
}

/// A layer told to grow is DRAWN bigger, in pixels.
///
/// Scale used to set the box and nothing else, so a pen path went from 1600
/// drawn pixels to 1600 drawn pixels over a lap that asked it to double: the
/// rasterizer painted a 40pt shape into an 80pt box and scaled that box into
/// the frame at 1:1. Counting ink at the two ends of the lap is the only check
/// that could have caught it, so it lives here rather than in the model tests
/// next door.
@Suite("A layer told to grow is drawn bigger")
struct MotionScaleRenderTests {

    /// How many pixels of this picture have anything in them at all.
    private func ink(_ image: CGImage) -> Int {
        let width = image.width, height = image.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        let context = CGContext(data: &data, width: width, height: height,
                                bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        var lit = 0
        for i in stride(from: 3, to: data.count, by: 4) where data[i] > 20 { lit += 1 }
        return lit
    }

    /// A 40pt square told to go from 100% to 200% over one lap.
    private func doubling(_ layer: Layer) -> PhotonzDocument {
        var moving = layer
        moving.motions = [LayerMotion(property: .scale,
                                      from: .number(100), to: .number(200),
                                      timing: MotionTiming(startMS: 0, durationMS: 1000),
                                      curve: .linear, repeats: .forever)]
        return PhotonzDocument(canvasSize: CGSize(width: 200, height: 200), layers: [moving])
    }

    private func drawnArea(_ document: PhotonzDocument, atMS ms: Int) throws -> Int {
        let image = try #require(DocumentRenderer().render(document.moved(toMotionTimeMS: ms),
                                                           store: ImageStore(), scale: 1))
        return ink(image)
    }

    private func square() -> Layer {
        let content = PathContent(anchors: [PathAnchor(point: .zero),
                                            PathAnchor(point: CGPoint(x: 40, y: 0)),
                                            PathAnchor(point: CGPoint(x: 40, y: 40)),
                                            PathAnchor(point: CGPoint(x: 0, y: 40))],
                                  isClosed: true,
                                  paint: Paint(hex: "#FF0000"),
                                  strokeWidth: 0,
                                  fill: Paint(hex: "#FF0000"))
        return PathBuilder.layer(content, at: CGPoint(x: 30, y: 30))
    }

    private func box() -> Layer {
        Layer(name: "Box",
              content: .annotation(AnnotationContent(shape: .rectangle,
                                                     strokeWidth: 0,
                                                     colorHex: "#FF0000",
                                                     start: .zero,
                                                     end: CGPoint(x: 40, y: 40),
                                                     fillColorHex: "#FF0000")),
              frame: CGRect(x: 30, y: 30, width: 40, height: 40))
    }

    /// THE TEST: twice as wide is four times the ink. Within a couple of
    /// percent, because the last millisecond of the lap is a whisker short of
    /// the full 200% and an edge is antialiased.
    @Test func aPathDoubledDrawsFourTimesTheInk() throws {
        let document = doubling(square())
        let start = try drawnArea(document, atMS: 0)
        let end = try drawnArea(document, atMS: 999)
        #expect(start == 1600)
        #expect(abs(Double(end) / Double(start) - 4) < 0.05,
                "a 40pt square doubled covers four times the pixels, got \(end) from \(start)")
    }

    /// And a rectangle by the same amount, not the one and a quarter times it
    /// used to manage.
    @Test func aBoxDoubledDrawsFourTimesTheInk() throws {
        let document = doubling(box())
        let start = try drawnArea(document, atMS: 0)
        let end = try drawnArea(document, atMS: 999)
        #expect(start == 1600)
        #expect(abs(Double(end) / Double(start) - 4) < 0.05,
                "a 40pt box doubled covers four times the pixels, got \(end) from \(start)")
    }

    /// The two kinds agree with each other at every moment of the lap: a shape
    /// and the path it turns into cannot grow at two different rates.
    @Test func aPathAndABoxGrowAtTheSameRate() throws {
        let path = doubling(square()), shape = doubling(box())
        for ms in [0, 250, 500, 750, 999] {
            let a = try drawnArea(path, atMS: ms), b = try drawnArea(shape, atMS: ms)
            #expect(abs(Double(a - b)) / Double(b) < 0.02,
                    "at \(ms)ms the path drew \(a) and the box drew \(b)")
        }
    }
}

/// A piece that moves INSIDE an icon that is itself growing.
///
/// Growing an icon magnifies everything in it, so a piece told to slide 20pt
/// has to travel 40pt when the icon is drawn at twice the size: that is what
/// an exported file does, where the slide is written inside the growth and a
/// browser multiplies the two. The canvas used to slide it 20pt, so the same
/// icon played one way in the app and another way everywhere else.
@Suite("A piece inside an icon that grows slides the grown distance")
struct NestedMotionRenderTests {

    private func render(_ document: PhotonzDocument) -> CGImage? {
        DocumentRenderer().render(document, store: ImageStore(), scale: 1)
    }

    /// The box the ink covers, in pixels, or nil where nothing was drawn.
    private func inkBox(_ image: CGImage) -> CGRect? {
        let width = image.width, height = image.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        let context = CGContext(data: &data, width: width, height: height,
                                bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            for x in 0..<width where data[(y * width + x) * 4 + 3] > 40 {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= 0 else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    /// A 10pt black square at (10, 10) inside a group at (20, 20), where the
    /// group is drawn at 200% for the whole lap and the square slides 20pt
    /// along by the half way mark.
    private func slidingInsideAGrowingIcon() -> PhotonzDocument {
        var dot = Layer(name: "Dot",
                        content: .annotation(AnnotationContent(shape: .rectangle,
                                                               strokeWidth: 0,
                                                               colorHex: "#000000",
                                                               start: .zero,
                                                               end: CGPoint(x: 10, y: 10),
                                                               fillColorHex: "#000000")),
                        frame: CGRect(x: 10, y: 10, width: 10, height: 10))
        dot.motions = [LayerMotion(property: .position,
                                   from: .point(CGPoint(x: 10, y: 10)),
                                   to: .point(CGPoint(x: 30, y: 10)),
                                   timing: MotionTiming(startMS: 0, durationMS: 500),
                                   curve: .linear, repeats: .forever)]
        var icon = Layer(name: "Icon", content: .group(GroupContent(children: [dot])),
                         frame: CGRect(x: 20, y: 20, width: 50, height: 50))
        icon.motions = [LayerMotion(property: .scale,
                                    from: .number(200), to: .number(200),
                                    timing: MotionTiming(startMS: 0, durationMS: 1000),
                                    curve: .linear, repeats: .forever)]
        var document = PhotonzDocument(canvasSize: CGSize(width: 200, height: 200),
                                       layers: [icon])
        document.motionCycleMS = 1000
        return document
    }

    /// THE TEST, in pixels: the ink itself ends up 40pt along, not 20pt. The
    /// model tests next door settle the number; this settles that the picture
    /// the canvas draws carries it.
    @Test func aPieceInsideAGrowingIconSlidesTheGrownDistance() throws {
        let document = slidingInsideAGrowingIcon()
        let top = try #require(render(document.moved(toMotionTimeMS: 0)))
        let end = try #require(render(document.moved(toMotionTimeMS: 900)))
        let atTheTop = try #require(inkBox(top))
        let atTheEnd = try #require(inkBox(end))
        #expect(abs(atTheTop.width - 20) <= 1, "the piece is drawn at twice the size")
        #expect(abs(atTheEnd.width - 20) <= 1)
        let travelled = atTheEnd.midX - atTheTop.midX
        #expect(abs(travelled - 40) <= 1,
                "20pt of slide inside a group at 200% moves the ink 40pt, got \(travelled)")
    }
}
