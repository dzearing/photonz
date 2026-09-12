import CoreGraphics
import Foundation
import Testing
import PhotonzCore
@testable import PhotonzRender

@Suite("Blend modes")
struct BlendModeTests {

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

    /// Reads the RGBA value at (x, y) in top-left coordinates.
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

    /// Gray-on-gray 20x20 doc: base value `base`, full-cover layer value `layer`.
    private func renderBlend(_ mode: BlendMode, base: UInt8, layer: UInt8) -> CGImage {
        let store = ImageStore()
        let baseRef = store.register(solidImage(width: 20, height: 20, r: base, g: base, b: base))
        let topRef = store.register(solidImage(width: 20, height: 20, r: layer, g: layer, b: layer))
        var doc = PhotonzDocument.withBaseImage(baseRef)
        doc.addLayer(Layer(name: "Top", content: .image(topRef),
                           frame: CGRect(x: 0, y: 0, width: 20, height: 20),
                           style: LayerStyle(blendMode: mode)))
        return DocumentRenderer().render(doc, store: store)!
    }

    @Test func defaultBlendModeIsNormal() {
        #expect(LayerStyle().blendMode == .normal)
    }

    @Test func blendModeRoundTripsThroughCodable() throws {
        let style = LayerStyle(blendMode: .screen)
        let data = try JSONEncoder().encode(style)
        let back = try JSONDecoder().decode(LayerStyle.self, from: data)
        #expect(back.blendMode == .screen)
    }

    @Test func normalBlendCoversBackdrop() {
        let p = pixel(renderBlend(.normal, base: 64, layer: 128), x: 10, y: 10)
        #expect(p.r > 115 && p.r < 145, "opaque normal blend should read the layer value, got \(p.r)")
    }

    @Test func multiplyBlendDarkens() {
        let p = pixel(renderBlend(.multiply, base: 128, layer: 128), x: 10, y: 10)
        #expect(p.r > 45 && p.r < 85, "mid-gray multiplied by mid-gray should darken, got \(p.r)")
    }

    @Test func screenBlendLightens() {
        let p = pixel(renderBlend(.screen, base: 128, layer: 128), x: 10, y: 10)
        #expect(p.r > 150 && p.r < 215, "mid-gray screened with mid-gray should lighten, got \(p.r)")
        #expect(p.r < 250, "screen of mid-grays is not white")
    }

    @Test func blendOnlyAffectsLayerExtent() {
        // A half-canvas multiply layer leaves the uncovered half untouched.
        let store = ImageStore()
        let baseRef = store.register(solidImage(width: 40, height: 20, r: 128, g: 128, b: 128))
        let topRef = store.register(solidImage(width: 20, height: 20, r: 128, g: 128, b: 128))
        var doc = PhotonzDocument.withBaseImage(baseRef)
        doc.addLayer(Layer(name: "Half", content: .image(topRef),
                           frame: CGRect(x: 0, y: 0, width: 20, height: 20),
                           style: LayerStyle(blendMode: .multiply)))
        let output = DocumentRenderer().render(doc, store: store)!
        let covered = pixel(output, x: 10, y: 10)
        let uncovered = pixel(output, x: 30, y: 10)
        #expect(covered.r < 90, "covered half darkens")
        #expect(uncovered.r > 115 && uncovered.r < 145, "uncovered half keeps the base value")
    }

    // MARK: - The three modes added on 2026-09-12

    @Test func darkenKeepsWhicheverIsDarker() {
        let overLighter = pixel(renderBlend(.darken, base: 200, layer: 100), x: 10, y: 10)
        let overDarker = pixel(renderBlend(.darken, base: 60, layer: 100), x: 10, y: 10)
        #expect(overLighter.r > 85 && overLighter.r < 115,
                "the layer is darker, so the layer wins, got \(overLighter.r)")
        #expect(overDarker.r > 45 && overDarker.r < 75,
                "what is underneath is darker, so it stays, got \(overDarker.r)")
    }

    @Test func lightenKeepsWhicheverIsLighter() {
        let overLighter = pixel(renderBlend(.lighten, base: 200, layer: 100), x: 10, y: 10)
        let overDarker = pixel(renderBlend(.lighten, base: 60, layer: 100), x: 10, y: 10)
        #expect(overLighter.r > 185 && overLighter.r < 215,
                "what is underneath is lighter, so it stays, got \(overLighter.r)")
        #expect(overDarker.r > 85 && overDarker.r < 115,
                "the layer is lighter, so the layer wins, got \(overDarker.r)")
    }

    /// Each mode over the SAME backdrop, so the five can be read as one list:
    /// darker, lighter, or the same, exactly as each one's sentence promises.
    @Test func everyModeDoesWhatItsSentenceSays() {
        let base: UInt8 = 128
        func value(_ mode: BlendMode, layer: UInt8) -> Int {
            Int(pixel(renderBlend(mode, base: base, layer: layer), x: 10, y: 10).r)
        }
        // Over a lighter layer.
        #expect(value(.normal, layer: 200) > 180)
        #expect(value(.multiply, layer: 200) < Int(base), "multiply never lightens")
        #expect(value(.screen, layer: 200) > Int(base), "screen never darkens")
        #expect(value(.darken, layer: 200) > 115 && value(.darken, layer: 200) < 145,
                "the backdrop is darker, so darken leaves it alone")
        #expect(value(.lighten, layer: 200) > 185, "the layer is lighter, so lighten takes it")
        // ...and over a darker one.
        #expect(value(.multiply, layer: 60) < Int(base))
        #expect(value(.screen, layer: 60) > Int(base))
        #expect(value(.darken, layer: 60) < 75, "the layer is darker, so darken takes it")
        #expect(value(.lighten, layer: 60) > 115 && value(.lighten, layer: 60) < 145,
                "the backdrop is lighter, so lighten leaves it alone")
    }

    @Test func transparencyOutsideTheLayerNeverMixes() {
        // Every mode must leave alone what the layer does not cover. Core
        // Image's blend filters grow their frame to the union of both inputs,
        // so a mode that forgot to cut back would tint the whole canvas.
        for mode in BlendMode.allCases {
            let store = ImageStore()
            let baseRef = store.register(solidImage(width: 40, height: 20, r: 200, g: 200, b: 200))
            let topRef = store.register(solidImage(width: 20, height: 20, r: 40, g: 40, b: 40))
            var doc = PhotonzDocument.withBaseImage(baseRef)
            doc.addLayer(Layer(name: "Half", content: .image(topRef),
                               frame: CGRect(x: 0, y: 0, width: 20, height: 20),
                               style: LayerStyle(blendMode: mode)))
            let output = DocumentRenderer().render(doc, store: store)!
            let uncovered = pixel(output, x: 30, y: 10)
            #expect(uncovered.r > 185 && uncovered.a > 250,
                    "\(mode) reached past the layer it belongs to, got \(uncovered)")
        }
    }

    // MARK: - Inside a group

    /// 40x20 doc, a DARK base (40). A group covers the left half and holds a
    /// light strip (220) over the left quarter with the mixing layer above it,
    /// so the group has two halves of its own: one where the mixer meets a
    /// sibling, and one where it meets nothing at all.
    ///
    /// That second half is what tells the two group rules apart. Inside a
    /// buffer the mixer has nothing under it there, so it comes out as itself;
    /// passing through, it has the dark canvas under it and burns down into it.
    private func renderInGroup(_ mode: BlendMode, groupStyle: LayerStyle) -> CGImage {
        let store = ImageStore()
        let baseRef = store.register(solidImage(width: 40, height: 20, r: 40, g: 40, b: 40))
        let stripRef = store.register(solidImage(width: 10, height: 20, r: 220, g: 220, b: 220))
        let topRef = store.register(solidImage(width: 20, height: 20, r: 128, g: 128, b: 128))
        var doc = PhotonzDocument.withBaseImage(baseRef)
        let strip = Layer(name: "Strip", content: .image(stripRef),
                          frame: CGRect(x: 0, y: 0, width: 10, height: 20))
        let top = Layer(name: "Mixer", content: .image(topRef),
                        frame: CGRect(x: 0, y: 0, width: 20, height: 20),
                        style: LayerStyle(blendMode: mode))
        var group = Layer(name: "Group",
                          content: .group(GroupContent(children: [strip, top])),
                          frame: CGRect(x: 0, y: 0, width: 20, height: 20))
        group.style = groupStyle
        doc.addLayer(group)
        return DocumentRenderer().render(doc, store: store)!
    }

    @Test func aPlainGroupChangesNoPixels() {
        // Grouping must not change what anything looks like. A group with no
        // styling of its own passes its children straight through, so a layer
        // that multiplies inside one mixes with everything below it on the
        // canvas — exactly as it did the moment before Cmd-G. Photoshop calls
        // this Pass Through and makes it the default for the same reason, and
        // it is why the task's own wording ("mixes with the group's contents,
        // not with the whole canvas") is not what shipped.
        let grouped = renderInGroup(.multiply, groupStyle: LayerStyle())
        // The same two layers loose on the canvas, for comparison.
        let store = ImageStore()
        let baseRef = store.register(solidImage(width: 40, height: 20, r: 40, g: 40, b: 40))
        let stripRef = store.register(solidImage(width: 10, height: 20, r: 220, g: 220, b: 220))
        let topRef = store.register(solidImage(width: 20, height: 20, r: 128, g: 128, b: 128))
        var doc = PhotonzDocument.withBaseImage(baseRef)
        doc.addLayer(Layer(name: "Strip", content: .image(stripRef),
                           frame: CGRect(x: 0, y: 0, width: 10, height: 20)))
        doc.addLayer(Layer(name: "Mixer", content: .image(topRef),
                           frame: CGRect(x: 0, y: 0, width: 20, height: 20),
                           style: LayerStyle(blendMode: .multiply)))
        let loose = DocumentRenderer().render(doc, store: store)!
        for x in [5, 15, 30] {
            let a = pixel(grouped, x: x, y: 10)
            let b = pixel(loose, x: x, y: 10)
            #expect(abs(Int(a.r) - Int(b.r)) <= 2,
                    "grouping changed the picture at x=\(x): \(a.r) grouped vs \(b.r) loose")
        }
        // ...and what it reads is the canvas burnt into, not nothing.
        #expect(pixel(grouped, x: 15, y: 10).r < 40,
                "over the dark canvas the mixer burns down, got \(pixel(grouped, x: 15, y: 10).r)")
    }

    @Test func aGroupThatIsAnObjectMixesInsideItself() {
        // A group carrying styling of its own is one object: its children draw
        // into a buffer of its own first, so a child that multiplies inside one
        // meets its siblings and nothing else. That is the price of being one
        // object, and it is the switch a person actually has for isolating
        // blending — the same switch Photoshop offers by taking a group's own
        // mode off Pass Through.
        //
        // Corner radius rather than a fade, so the numbers here are the mixing
        // and nothing else.
        let output = renderInGroup(.multiply, groupStyle: LayerStyle(cornerRadius: 4))
        let overSibling = pixel(output, x: 5, y: 10)
        let overNothing = pixel(output, x: 15, y: 10)
        let outside = pixel(output, x: 30, y: 10)
        #expect(outside.r > 30 && outside.r < 55,
                "the canvas beside the group is untouched, got \(outside.r)")
        #expect(overNothing.r > 115 && overNothing.r < 145,
                "inside the buffer nothing is under the mixer, so it is itself, got \(overNothing.r)")
        #expect(overSibling.r > 95 && overSibling.r < 130,
                "over its own sibling it burns into 220, got \(overSibling.r)")
    }

    @Test func everyModeSurvivesInsideAGroupThatIsAnObject() {
        for mode in BlendMode.allCases {
            let output = renderInGroup(mode, groupStyle: LayerStyle(cornerRadius: 4))
            let outside = pixel(output, x: 30, y: 10)
            #expect(outside.r > 30 && outside.r < 55,
                    "\(mode) inside a group reached the canvas beside it, got \(outside.r)")
        }
    }

    // MARK: - What leaves the app

    @Test func anExportAtTwiceTheSizeCarriesTheMix() {
        // Export and copy both go down this path, so a tint burnt into a
        // screenshot is burnt into the file somebody is handed.
        let store = ImageStore()
        let baseRef = store.register(solidImage(width: 20, height: 20, r: 200, g: 200, b: 200))
        let topRef = store.register(solidImage(width: 20, height: 20, r: 100, g: 100, b: 100))
        var doc = PhotonzDocument.withBaseImage(baseRef)
        doc.addLayer(Layer(name: "Tint", content: .image(topRef),
                           frame: CGRect(x: 0, y: 0, width: 20, height: 20),
                           style: LayerStyle(blendMode: .multiply)))
        let exported = DocumentRenderer().render(doc, store: store, scale: 2)!
        #expect(exported.width == 40 && exported.height == 40)
        let p = pixel(exported, x: 20, y: 20)
        // 200 x 100 in sRGB is about 78, nowhere near either input.
        #expect(p.r > 60 && p.r < 95, "the export multiplied, got \(p.r)")
    }

    @Test func everyModeReachesAnExport() {
        for mode in BlendMode.allCases {
            let store = ImageStore()
            let baseRef = store.register(solidImage(width: 20, height: 20, r: 200, g: 200, b: 200))
            let topRef = store.register(solidImage(width: 20, height: 20, r: 100, g: 100, b: 100))
            var doc = PhotonzDocument.withBaseImage(baseRef)
            doc.addLayer(Layer(name: "Tint", content: .image(topRef),
                               frame: CGRect(x: 0, y: 0, width: 20, height: 20),
                               style: LayerStyle(blendMode: mode)))
            let onscreen = pixel(DocumentRenderer().render(doc, store: store)!, x: 10, y: 10)
            let exported = pixel(DocumentRenderer().render(doc, store: store, scale: 2)!, x: 20, y: 20)
            #expect(abs(Int(onscreen.r) - Int(exported.r)) <= 3,
                    "\(mode) exported as \(exported.r) but shows as \(onscreen.r)")
        }
    }
}
