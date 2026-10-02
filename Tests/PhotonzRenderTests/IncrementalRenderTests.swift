import CoreGraphics
import Foundation
import Testing
import PhotonzCore
@testable import PhotonzRender

/// `renderInteractive` patches only the dirty region into the previous frame.
/// Oracle: a cold full render of the same document — the incremental result
/// must be indistinguishable from it everywhere, not just inside the patch.
@Suite("Incremental rendering")
struct IncrementalRenderTests {

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

    private func bytes(_ image: CGImage) -> [UInt8] {
        var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = CGContext(data: &data, width: image.width, height: image.height,
                                bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return data
    }

    /// Worst per-channel delta across every pixel of both images.
    private func maxDelta(_ a: CGImage, _ b: CGImage) -> Int {
        guard a.width == b.width, a.height == b.height else { return .max }
        let da = bytes(a), db = bytes(b)
        var worst = 0
        for i in 0..<da.count {
            worst = max(worst, abs(Int(da[i]) - Int(db[i])))
        }
        return worst
    }

    private func expectMatchesColdRender(_ image: CGImage?, _ doc: PhotonzDocument,
                                         _ store: ImageStore, tolerance: Int = 3,
                                         _ message: String) {
        guard let image else { Issue.record("nil incremental render"); return }
        guard let cold = DocumentRenderer().render(doc, store: store) else {
            Issue.record("nil cold render"); return
        }
        let delta = maxDelta(image, cold)
        #expect(delta <= tolerance, "\(message) (max channel delta \(delta))")
    }

    private func makeStoreAndDocument() -> (ImageStore, PhotonzDocument) {
        let store = ImageStore()
        let base = store.register(solidImage(width: 400, height: 300, r: 220, g: 220, b: 220))
        let patch = store.register(solidImage(width: 80, height: 60, r: 200, g: 40, b: 40))
        var doc = PhotonzDocument.withBaseImage(base)
        doc.addLayer(Layer(name: "Patch", content: .image(patch),
                           frame: CGRect(x: 40, y: 40, width: 80, height: 60)))
        return (store, doc)
    }

    @Test func firstInteractiveRenderMatchesFullRender() {
        let (store, doc) = makeStoreAndDocument()
        let renderer = DocumentRenderer()
        let image = renderer.renderInteractive(doc, store: store)
        expectMatchesColdRender(image, doc, store, "first interactive render diverged")
    }

    @Test func unchangedDocumentReturnsThePreviousFrame() throws {
        let (store, doc) = makeStoreAndDocument()
        let renderer = DocumentRenderer()
        let first = try #require(renderer.renderInteractive(doc, store: store))
        let second = try #require(renderer.renderInteractive(doc, store: store))
        #expect(first === second, "unchanged document should reuse the frame object")
    }

    @Test func movedLayerMatchesColdRender() {
        let (store, doc) = makeStoreAndDocument()
        let renderer = DocumentRenderer()
        _ = renderer.renderInteractive(doc, store: store)

        var moved = doc
        moved.updateLayer(id: doc.layers[1].id) {
            $0.frame = CGRect(x: 240, y: 180, width: 80, height: 60)
        }
        let image = renderer.renderInteractive(moved, store: store)
        expectMatchesColdRender(image, moved, store,
                                "moved layer left stale pixels (old or new spot)")
    }

    @Test func shadowedLayerMoveMatchesColdRender() {
        let (store, doc) = makeStoreAndDocument()
        var shadowed = doc
        shadowed.updateLayer(id: doc.layers[1].id) {
            $0.style = LayerStyle(shadow: ShadowStyle(radius: 16, offset: CGSize(width: 6, height: 8)))
        }
        let renderer = DocumentRenderer()
        _ = renderer.renderInteractive(shadowed, store: store)

        var moved = shadowed
        moved.updateLayer(id: shadowed.layers[1].id) {
            $0.frame = CGRect(x: 200, y: 100, width: 80, height: 60)
        }
        let image = renderer.renderInteractive(moved, store: store)
        expectMatchesColdRender(image, moved, store,
                                "shadow region not fully repainted")
    }

    @Test func styleTweakMatchesColdRender() {
        let (store, doc) = makeStoreAndDocument()
        let renderer = DocumentRenderer()
        _ = renderer.renderInteractive(doc, store: store)

        var tweaked = doc
        tweaked.updateLayer(id: doc.layers[1].id) { $0.style.opacity = 0.4 }
        let image = renderer.renderInteractive(tweaked, store: store)
        expectMatchesColdRender(image, tweaked, store, "opacity tweak diverged")
    }

    @Test func deletedLayerMatchesColdRender() {
        let (store, doc) = makeStoreAndDocument()
        let renderer = DocumentRenderer()
        _ = renderer.renderInteractive(doc, store: store)

        var removed = doc
        removed.removeLayer(id: doc.layers[1].id)
        let image = renderer.renderInteractive(removed, store: store)
        expectMatchesColdRender(image, removed, store, "deleted layer left ghost pixels")
    }

    @Test func canvasResizeMatchesColdRender() {
        let (store, doc) = makeStoreAndDocument()
        let renderer = DocumentRenderer()
        _ = renderer.renderInteractive(doc, store: store)

        var resized = doc
        resized.canvasSize = CGSize(width: 300, height: 200)
        let image = renderer.renderInteractive(resized, store: store)
        #expect(image?.width == 300)
        expectMatchesColdRender(image, resized, store, "canvas resize diverged")
    }

    @Test func editUnderCalloutSourceUpdatesTheBox() {
        let (store, doc) = makeStoreAndDocument()
        var withCallout = doc
        withCallout.addLayer(Layer(
            name: "Zoom",
            content: .zoomCallout(ZoomCalloutContent(
                sourceRect: CGRect(x: 30, y: 30, width: 100, height: 80), magnification: 2)),
            frame: CGRect(x: 180, y: 120, width: 200, height: 160),
            style: LayerStyle(borderWidth: 3, borderColorHex: "#FF3B30")))
        let renderer = DocumentRenderer()
        _ = renderer.renderInteractive(withCallout, store: store)

        // Move the red patch inside the magnified source region.
        var moved = withCallout
        moved.updateLayer(id: doc.layers[1].id) {
            $0.frame = CGRect(x: 50, y: 50, width: 80, height: 60)
        }
        let image = renderer.renderInteractive(moved, store: store)
        expectMatchesColdRender(image, moved, store,
                                "callout box did not track the edit beneath its source")
    }

    @Test func interleavedFullRendersDoNotCorruptIncrementalState() {
        let (store, doc) = makeStoreAndDocument()
        let renderer = DocumentRenderer()
        _ = renderer.renderInteractive(doc, store: store)
        // An export-style full render in between must not confuse the patcher.
        _ = renderer.render(doc, store: store, scale: 2)

        var moved = doc
        moved.updateLayer(id: doc.layers[1].id) {
            $0.frame = CGRect(x: 300, y: 220, width: 80, height: 60)
        }
        let image = renderer.renderInteractive(moved, store: store)
        expectMatchesColdRender(image, moved, store, "interleaved render corrupted state")
    }

    @Test func sequenceOfEditsStaysFaithful() {
        let (store, doc) = makeStoreAndDocument()
        let renderer = DocumentRenderer()
        var current = doc
        _ = renderer.renderInteractive(current, store: store)

        // Drag-like burst: many small moves, each patched incrementally.
        for step in 1...12 {
            current.updateLayer(id: doc.layers[1].id) {
                $0.frame = CGRect(x: 40 + step * 20, y: 40 + step * 15, width: 80, height: 60)
            }
            let image = renderer.renderInteractive(current, store: store)
            if step % 4 == 0 || step == 12 {
                expectMatchesColdRender(image, current, store,
                                        "divergence accumulated by step \(step)")
            }
        }
    }

    // MARK: screens that get resized

    /// A screen painted a colour, holding one layer, sitting on the base.
    private func makeStoreAndScreenDocument() -> (ImageStore, PhotonzDocument) {
        let store = ImageStore()
        let base = store.register(solidImage(width: 400, height: 300, r: 220, g: 220, b: 220))
        let patch = store.register(solidImage(width: 40, height: 30, r: 200, g: 40, b: 40))
        var doc = PhotonzDocument.withBaseImage(base)
        let child = Layer(name: "Patch", content: .image(patch),
                          frame: CGRect(x: 10, y: 10, width: 40, height: 30))
        doc.addLayer(Layer(name: "Screen",
                           content: .group(GroupContent(children: [child], isFrame: true,
                                                        clipsContents: true,
                                                        backgroundHex: "#3B78E7")),
                           frame: CGRect(x: 40, y: 40, width: 140, height: 100)))
        return (store, doc)
    }

    @Test func widenedScreenMatchesColdRender() {
        let (store, doc) = makeStoreAndScreenDocument()
        let renderer = DocumentRenderer()
        _ = renderer.renderInteractive(doc, store: store)

        // Dragged by the bottom-right corner, the way a person resizes a screen:
        // the origin holds still and the box grows.
        var wider = doc
        wider.updateLayer(id: doc.layers[1].id) { layer in
            layer.frame = CGRect(x: 40, y: 40, width: 260, height: 190)
            layer.children[0].frame = CGRect(x: 14, y: 12, width: 44, height: 32)
        }
        let image = renderer.renderInteractive(wider, store: store)
        expectMatchesColdRender(image, wider, store,
                                "widened screen left an unpainted band inside its outline")
    }

    @Test func shrunkScreenMatchesColdRender() {
        let (store, doc) = makeStoreAndScreenDocument()
        let renderer = DocumentRenderer()
        _ = renderer.renderInteractive(doc, store: store)

        var smaller = doc
        smaller.updateLayer(id: doc.layers[1].id) { layer in
            layer.frame = CGRect(x: 40, y: 40, width: 70, height: 55)
            layer.children[0].frame = CGRect(x: 5, y: 6, width: 20, height: 16)
        }
        let image = renderer.renderInteractive(smaller, store: store)
        expectMatchesColdRender(image, smaller, store,
                                "shrunk screen left its old surface painted on the canvas")
    }

    @Test func repaintedScreenSurfaceMatchesColdRender() {
        let (store, doc) = makeStoreAndScreenDocument()
        let renderer = DocumentRenderer()
        _ = renderer.renderInteractive(doc, store: store)

        var repainted = doc
        repainted.updateLayer(id: doc.layers[1].id) { layer in
            guard case .group(var group) = layer.content else { return }
            group.backgroundHex = "#E7783B"
            layer.content = .group(group)
        }
        let image = renderer.renderInteractive(repainted, store: store)
        expectMatchesColdRender(image, repainted, store,
                                "repainting a screen's surface left the old colour behind")
    }

    // MARK: Drawn in the screen's colours

    /// The raw bytes of `image` as stored, without any colour matching.
    private func storedBytes(_ image: CGImage, x: Int, y: Int) -> [UInt8] {
        guard let data = image.dataProvider?.data, let base = CFDataGetBytePtr(data) else { return [] }
        let offset = y * image.bytesPerRow + x * 4
        return (0..<4).map { base[offset + $0] }
    }

    /// A frame handed to a window in any colour space but the window's own is
    /// matched to the screen on the main thread as it goes up, about 8ms for a
    /// recording-sized frame (`first-long-jump-when-zoomed-in-walk`). Drawn
    /// straight into the window's space, it goes up as it is.
    @Test func aFrameIsDrawnInTheColourSpaceItIsAskedFor() throws {
        let (store, doc) = makeStoreAndDocument()
        let p3 = try #require(CGColorSpace(name: CGColorSpace.displayP3))
        let image = try #require(DocumentRenderer().renderInteractive(doc, store: store, colorSpace: p3))
        #expect(image.colorSpace?.name == CGColorSpace.displayP3)
        // The same colours, only written in the other space: matched back to
        // sRGB it is the sRGB render.
        expectMatchesColdRender(image, doc, store, tolerance: 4, "a frame drawn in Display P3 changed colour")
        // ...and really written in it: the patch's red is not stored as the
        // sRGB numbers.
        let srgb = try #require(DocumentRenderer().renderInteractive(doc, store: store))
        #expect(storedBytes(image, x: 60, y: 60) != storedBytes(srgb, x: 60, y: 60),
                "the Display P3 frame stored the sRGB numbers")
    }

    @Test func aFrameWithNoColourSpaceAskedForIsSRGB() throws {
        let (store, doc) = makeStoreAndDocument()
        let image = try #require(DocumentRenderer().renderInteractive(doc, store: store))
        #expect(image.colorSpace?.name == CGColorSpace.sRGB)
    }

    /// A window dragged onto another screen asks for that screen's colours,
    /// and the frame already drawn in the old ones is not handed back.
    @Test func aNewColourSpaceDrawsTheFrameAgain() throws {
        let (store, doc) = makeStoreAndDocument()
        let renderer = DocumentRenderer()
        let p3 = try #require(CGColorSpace(name: CGColorSpace.displayP3))
        let first = try #require(renderer.renderInteractive(doc, store: store))
        let second = try #require(renderer.renderInteractive(doc, store: store, colorSpace: p3))
        #expect(first !== second)
        #expect(second.colorSpace?.name == CGColorSpace.displayP3)
        let third = try #require(renderer.renderInteractive(doc, store: store, colorSpace: p3))
        #expect(second === third, "the same space again reuses the frame")
    }

    /// A patch drawn after a move lands in the frame's own space, so the frame
    /// is one picture in one set of colours.
    @Test func aPatchedFrameStaysInItsColourSpace() throws {
        let (store, doc) = makeStoreAndDocument()
        let renderer = DocumentRenderer()
        let p3 = try #require(CGColorSpace(name: CGColorSpace.displayP3))
        _ = renderer.renderInteractive(doc, store: store, colorSpace: p3)
        var moved = doc
        let patchID = try #require(moved.layers.last?.id)
        moved.updateLayer(id: patchID) { $0.frame.origin.x += 10 }
        let image = try #require(renderer.renderInteractive(moved, store: store, colorSpace: p3))
        #expect(image.colorSpace?.name == CGColorSpace.displayP3)
        expectMatchesColdRender(image, moved, store, tolerance: 4, "a patched Display P3 frame diverged")
    }
}
