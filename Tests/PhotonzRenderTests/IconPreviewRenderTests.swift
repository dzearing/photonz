import CoreGraphics
import CoreImage
import Foundation
import Testing
import PhotonzCore
@testable import PhotonzRender

/// The pictures behind the icon previews strip (`next-icon-previews`).
///
/// The whole promise of the strip is that the small sizes are drawn the way the
/// app would really draw them. A big picture shrunk smoothly looks plausible
/// and hides the exact problem the strip exists to show, so these tests compare
/// PIXELS: against the app's own render at that size, which is the path Export
/// takes, and against the smooth shrink, which the preview must not be.
@Suite("An icon previewed at the size it will be used")
struct IconPreviewRenderTests {

    // MARK: - Documents to look at

    /// A 512 icon frame with one dark hairline down the middle of it: a line a
    /// point wide, which is the classic thing that reads beautifully big and is
    /// gone at 16.
    ///
    /// `surface` is the frame's own colour; nil makes a clear frame.
    private func hairlineDocument(lineWidth: CGFloat = 1,
                                  surface: String? = "#FFFFFF") -> PhotonzDocument {
        var document = PhotonzDocument(canvasSize: CGSize(width: 1200, height: 900))
        let frame = document.addFrame(origin: CGPoint(x: 100, y: 100),
                                      size: CGSize(width: 512, height: 512),
                                      backgroundHex: surface)
        // Start and end span the layer's own box: an annotation's shape is
        // drawn between them, not across whatever frame it is given.
        var line = AnnotationContent(shape: .rectangle, strokeWidth: 0,
                                     start: .zero, end: CGPoint(x: lineWidth, y: 384),
                                     fillColorHex: "#101010")
        line.strokePosition = .inside
        document.updateLayer(id: frame.id) {
            $0.children.append(Layer(name: "Hairline", content: .annotation(line),
                                     frame: CGRect(x: 256, y: 64,
                                                   width: lineWidth, height: 384)))
        }
        return document
    }

    private func frameID(_ document: PhotonzDocument) -> UUID {
        document.frames.first!.id
    }

    // MARK: - Reading pixels

    private func bytes(_ image: CGImage) -> [UInt8] {
        var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = CGContext(data: &data, width: image.width, height: image.height,
                                bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return data
    }

    /// How dark the darkest pixel in the picture is on a white ground, 0
    /// (white) to 255 (black). The hairline's whole story is told by this one
    /// number. Read premultiplied, coverage less red is exactly how far the
    /// pixel darkens the white it sits on, so a picture whose white is the
    /// chip's rather than its own reads the same as one that carries it.
    private func darkestInk(_ image: CGImage) -> Int {
        let data = bytes(image)
        var darkest = 0
        for offset in stride(from: 0, to: data.count, by: 4) {
            darkest = max(darkest, Int(data[offset + 3]) - Int(data[offset]))
        }
        return darkest
    }

    /// The picture shrunk the plausible-looking way: drawn big, then resampled
    /// down with the best interpolation CoreGraphics has. This is what the
    /// preview must NOT be.
    private func smoothlyShrunk(_ image: CGImage, to side: Int) -> CGImage {
        let context = CGContext(data: nil, width: side, height: side,
                                bitsPerComponent: 8, bytesPerRow: side * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        return context.makeImage()!
    }

    // MARK: - The tests

    @Test("A preview is exactly the picture the app would export at that size")
    func matchesTheExportPath() {
        let renderer = DocumentRenderer()
        let store = ImageStore()
        let document = hairlineDocument()
        let id = frameID(document)

        for side in IconPreviews.interfaceSides {
            let preview = renderer.iconPreview(for: id, in: document, store: store, side: side)
            #expect(preview != nil)
            #expect(preview?.width == Int(side))
            #expect(preview?.height == Int(side))

            // The path Export takes for one frame at a scale
            // (`EditorState.exportComposite`), built here independently so the
            // claim is a comparison rather than a restatement.
            let scoped = document.frameDocument(id: id)!
            let exported = renderer.render(scoped, store: store, scale: side / 512)
            #expect(exported != nil)
            #expect(bytes(preview!) == bytes(exported!),
                    "the \(Int(side)) preview is not what exporting at \(Int(side)) gives")
        }
    }

    @Test("The preview is drawn small, not shrunk from the big one")
    func isNotASmoothShrink() {
        let renderer = DocumentRenderer()
        let store = ImageStore()
        let document = hairlineDocument(surface: nil)
        let id = frameID(document)
        let scoped = document.frameDocument(id: id)!

        let big = renderer.render(scoped, store: store)!
        #expect(big.width == 512)

        let preview = renderer.iconPreview(for: id, in: document, store: store, side: 16)!
        let shrunk = smoothlyShrunk(big, to: 16)
        #expect(bytes(preview) != bytes(shrunk))
    }

    @Test("A hairline that survives big is gone small, and a solid shape is not")
    func theHairlineFallsApart() {
        let renderer = DocumentRenderer()
        let store = ImageStore()
        let hairline = hairlineDocument(lineWidth: 1)
        let thick = hairlineDocument(lineWidth: 32)

        // Drawn on the 512 canvas both lines are plain to see.
        #expect(darkestInk(renderer.render(hairline.frameDocument(id: frameID(hairline))!,
                                           store: store)!) > 200)

        // This is the feature in one assertion. The same drawing at 16: the
        // line a point wide has nothing left to draw with and is simply not
        // there, while the one that was drawn thick enough is still ink.
        // Somebody watching the strip finds that out while they can still
        // thicken the line, instead of after exporting.
        let smallHairline = renderer.iconPreview(for: frameID(hairline), in: hairline,
                                                 store: store, side: 16)!
        let smallThick = renderer.iconPreview(for: frameID(thick), in: thick,
                                              store: store, side: 16)!
        #expect(darkestInk(smallHairline) == 0)
        #expect(darkestInk(smallThick) > 200)
    }

    @Test("A frame previewed at its own size is the frame itself")
    func atItsOwnSize() {
        let renderer = DocumentRenderer()
        let store = ImageStore()
        var document = PhotonzDocument(canvasSize: CGSize(width: 400, height: 400))
        let frame = document.addFrame(origin: CGPoint(x: 20, y: 20),
                                      size: CGSize(width: 32, height: 32), backgroundHex: nil)
        let preview = renderer.iconPreview(for: frame.id, in: document, store: store, side: 32)
        let scoped = document.frameDocument(id: frame.id)!
        #expect(preview != nil)
        #expect(bytes(preview!) == bytes(renderer.render(scoped, store: store)!))
    }

    @Test("Anything that is not a frame has no preview")
    func onlyFrames() {
        let renderer = DocumentRenderer()
        let store = ImageStore()
        var document = PhotonzDocument(canvasSize: CGSize(width: 400, height: 400))
        let loose = Layer(name: "Box", content: .annotation(
                            AnnotationContent(shape: .rectangle, start: .zero,
                                              end: CGPoint(x: 40, y: 40))),
                          frame: CGRect(x: 10, y: 10, width: 40, height: 40))
        document.addLayer(loose)
        #expect(renderer.iconPreview(for: loose.id, in: document, store: store, side: 16) == nil)
        #expect(renderer.iconPreview(for: UUID(), in: document, store: store, side: 16) == nil)
        // A side nobody could draw is refused rather than guessed at.
        let frame = document.addFrame(origin: .zero, size: CGSize(width: 64, height: 64))
        #expect(renderer.iconPreview(for: frame.id, in: document, store: store, side: 0) == nil)
    }
}

/// The one chip on a dark ground (icon-draw-wt.html, step 11).
///
/// The mock draws the same glyph light on that chip, because a glyph drawn in
/// one dark grey is a template: the Mac draws it in the label colour, which is
/// light on a dark ground. So a picture in one dark grey is redrawn in the
/// light ink there, edges and all. Anything else (a blue glyph, an app icon of
/// many colours) is shown exactly as drawn, since that is how it will be seen.
@Suite("An icon previewed on the dark chip")
struct IconPreviewDarkGroundTests {

    /// A side by side picture with the given colours painted as blocks on a
    /// clear ground, plus a soft edge on the first so anti-aliasing is there.
    private func picture(_ colours: [CGColor], side: Int = 24) -> CGImage {
        let context = CGContext(data: nil, width: side, height: side,
                                bitsPerComponent: 8, bytesPerRow: side * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        for (index, colour) in colours.enumerated() {
            context.setFillColor(colour)
            context.fillEllipse(in: CGRect(x: CGFloat(2 + index * 10), y: 4, width: 9.5, height: 15.3))
        }
        return context.makeImage()!
    }

    private func srgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> CGColor {
        CGColor(srgbRed: r, green: g, blue: b, alpha: 1)
    }

    /// Every pixel as (r, g, b, a), un-premultiplied for the opaque-ish ones.
    private func pixels(_ image: CGImage) -> [(r: Int, g: Int, b: Int, a: Int)] {
        var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = CGContext(data: &data, width: image.width, height: image.height,
                                bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return stride(from: 0, to: data.count, by: 4).map { offset in
            let a = Int(data[offset + 3])
            func straight(_ v: UInt8) -> Int { a == 0 ? 0 : min(255, Int(v) * 255 / a) }
            return (straight(data[offset]), straight(data[offset + 1]),
                    straight(data[offset + 2]), a)
        }
    }

    @Test("A glyph in one dark grey is drawn light on the dark chip, edges kept")
    func templateGlyphGoesLight() {
        let glyph = picture([srgb(0.06, 0.06, 0.06)])
        let onDark = IconPreviewInk.onDarkGround(glyph)
        #expect(onDark.width == glyph.width && onDark.height == glyph.height)
        let before = pixels(glyph), after = pixels(onDark)
        // Same coverage, pixel for pixel: only the colour changed.
        #expect(before.map(\.a) == after.map(\.a))
        let inked = after.filter { $0.a > 128 }
        #expect(!inked.isEmpty)
        #expect(inked.allSatisfy { $0.r > 220 && $0.g > 220 && $0.b > 220 })
    }

    @Test("Pure black reads as a template too")
    func blackGoesLight() {
        let after = pixels(IconPreviewInk.onDarkGround(picture([srgb(0, 0, 0)])))
        #expect(after.filter { $0.a > 128 }.allSatisfy { $0.r > 220 })
    }

    @Test("A coloured glyph is shown as drawn")
    func colouredGlyphIsKept() {
        let blue = picture([srgb(0.13, 0.31, 0.75)])
        #expect(pixels(IconPreviewInk.onDarkGround(blue)).map(\.b)
                == pixels(blue).map(\.b))
        #expect(IconPreviewInk.onDarkGround(blue) === blue)
    }

    @Test("A drawing of more than one colour is shown as drawn")
    func manyColoursAreKept() {
        let two = picture([srgb(0.06, 0.06, 0.06), srgb(0.9, 0.2, 0.1)])
        #expect(IconPreviewInk.onDarkGround(two) === two)
        // Two greys are two colours as well: the drawing chose its shading.
        let greys = picture([srgb(0.06, 0.06, 0.06), srgb(0.45, 0.45, 0.45)])
        #expect(IconPreviewInk.onDarkGround(greys) === greys)
    }

    @Test("A light glyph and an empty frame are shown as drawn")
    func lightAndEmptyAreKept() {
        let white = picture([srgb(1, 1, 1)])
        #expect(IconPreviewInk.onDarkGround(white) === white)
        let empty = picture([])
        #expect(IconPreviewInk.onDarkGround(empty) === empty)
    }

    @Test("The hairline icon, previewed for the dark chip, comes back light")
    func throughTheRenderer() {
        let renderer = DocumentRenderer()
        var document = PhotonzDocument(canvasSize: CGSize(width: 400, height: 400))
        let frame = document.addFrame(origin: CGPoint(x: 20, y: 20),
                                      size: CGSize(width: 24, height: 24))
        var bar = AnnotationContent(shape: .rectangle, strokeWidth: 0, start: .zero,
                                    end: CGPoint(x: 4, y: 16), fillColorHex: "#101010")
        bar.strokePosition = .inside
        document.updateLayer(id: frame.id) {
            $0.children.append(Layer(name: "Bar", content: .annotation(bar),
                                     frame: CGRect(x: 10, y: 4, width: 4, height: 16)))
        }
        let preview = renderer.iconPreview(for: frame.id, in: document, store: ImageStore(),
                                           side: 32, onDarkGround: true)
        #expect(preview?.width == 32)
        let inked = preview.map { pixels($0).filter { $0.a > 200 } } ?? []
        #expect(!inked.isEmpty)
        #expect(inked.allSatisfy { $0.r > 220 })
    }
}

/// What one frame of the looping previews costs (`next-motion`).
///
/// The strip stops being a still life when the preview runs: every one of its
/// chips is redrawn thirty times a second, from the frame as it looks at that
/// moment of the loop. That is a real cost on a real canvas, so it gets a
/// budget like any other repeating render.
///
/// The number to beat is 33ms, which is one frame at the rate the preview loop
/// runs at. A whole strip of four comes in around 5ms of that on the machine
/// these baselines were recorded on, and it is spent off the main actor, so the
/// canvas composite still has its own frame to itself. What the main actor pays
/// is the second test here: working out where the frame's contents are, which
/// is three hundredths of a millisecond.
@Suite("Previewing a moving icon, frame after frame")
struct IconPreviewMotionPerfTests {

    /// A 48 point icon of ten small shapes, five of them swinging: about as
    /// much as anybody draws on an icon grid, and more than the bell-and-knob
    /// the feature was designed around.
    private func movingIcon() -> PhotonzDocument {
        var document = PhotonzDocument(canvasSize: CGSize(width: 600, height: 600))
        let frame = document.addFrame(origin: CGPoint(x: 100, y: 100),
                                      size: CGSize(width: 48, height: 48))
        document.updateLayer(id: frame.id) { holder in
            for index in 0..<10 {
                let x = CGFloat(4 + (index % 5) * 8)
                let y = CGFloat(6 + (index / 5) * 18)
                var shape = AnnotationContent(shape: .rectangle, strokeWidth: 1,
                                              start: .zero, end: CGPoint(x: 7, y: 12),
                                              fillColorHex: "#2050c0")
                shape.strokePosition = .inside
                var layer = Layer(name: "Part \(index)", content: .annotation(shape),
                                  frame: CGRect(x: x, y: y, width: 7, height: 12))
                if index % 2 == 0 {
                    layer.motions = [LayerMotion(
                        property: .rotation, from: .number(-12), to: .number(12),
                        timing: MotionTiming(startMS: index * 45, durationMS: 900),
                        curve: .easeInOut, repeats: .foreverThereAndBack)]
                }
                holder.children.append(layer)
            }
        }
        return document
    }

    @Test("A whole strip of moving previews fits inside one frame of the loop")
    func aFrameOfTheStripMeetsBudget() {
        // On a context of its own, like the yardstick it is read against.
        // Through the shared one it queued behind whatever the other render
        // suites were drawing at that moment, and read 30ms, 39ms and 97ms in
        // full runs beside a yardstick reading its ordinary 8ms: the ratio
        // cannot cancel a wait only one side of it pays.
        let renderer = DocumentRenderer(privateContext: CIContext(options: [.cacheIntermediates: true]))
        let store = ImageStore()
        let document = movingIcon()
        let id = document.frames.first!.id
        let sides = IconPreviews.sides(forFrameSide: 48)
        #expect(sides == [16, 24, 32, 48, 64])
        #expect(document.motionCycleLengthMS == 1260)

        // One frame of the loop is: work out where this frame's contents are at
        // this moment, then draw the whole row of chips from it. Exactly what
        // `EditorState+IconPreviews` does, and timed together because they only
        // ever happen together.
        func strip(atMS ms: Int) {
            let moved = document.moved(layerID: id, toMotionTimeMS: ms)
            for side in sides {
                _ = renderer.iconPreview(for: id, in: moved, store: store, side: side)
            }
        }
        strip(atMS: 0)

        // Read against the yardstick taken in the same rounds. A flat budget
        // scaled by a factor measured when the process started said 5.3ms alone
        // and 8.9ms inside the full suite for identical work, and went red on
        // 2026-09-15 for no reason but the company it was keeping.
        var frame = 0
        MachineSpeed.checkInterleaved("moving icon previews, whole strip of 5",
                                      baselineMS: 5) {
            strip(atMS: frame * 54)
            frame += 1
        }
    }

    /// Working out where one frame's contents are is the part that happens on
    /// the main actor, in the middle of a view body. The pictures themselves
    /// are made off it, so this number is the one that can stutter the app.
    @Test("Moving one frame costs next to nothing beside drawing it")
    func movingTheFrameIsCheap() {
        let document = movingIcon()
        let id = document.frames.first!.id
        var samples: [Double] = []
        let clock = ContinuousClock()
        for round in 0..<50 {
            let duration = clock.measure {
                _ = document.moved(layerID: id, toMotionTimeMS: round * 27)
            }
            samples.append(Double(duration.components.seconds) * 1000
                           + Double(duration.components.attoseconds) / 1e15)
        }
        samples.sort()
        let median = samples[samples.count / 2]
        print("[perf] one icon frame moved to a moment — "
              + "median \(String(format: "%.3f", median))ms over \(samples.count) frames")
        MachineSpeed.check("one icon frame moved to a moment",
                           medianMS: median, baselineMS: 0.05)
    }
}
