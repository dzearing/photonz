import CoreGraphics
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
    private func hairlineDocument(lineWidth: CGFloat = 1) -> PhotonzDocument {
        var document = PhotonzDocument(canvasSize: CGSize(width: 1200, height: 900))
        let frame = document.addFrame(origin: CGPoint(x: 100, y: 100),
                                      size: CGSize(width: 512, height: 512))
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

    /// How dark the darkest pixel in the picture is, 0 (white) to 255 (black).
    /// The hairline's whole story is told by this one number.
    private func darkestInk(_ image: CGImage) -> Int {
        let data = bytes(image)
        var darkest = 0
        for offset in stride(from: 0, to: data.count, by: 4) {
            darkest = max(darkest, 255 - Int(data[offset]))
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
        let document = hairlineDocument()
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
                                      size: CGSize(width: 32, height: 32))
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
