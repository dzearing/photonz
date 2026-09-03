import CoreGraphics
import Foundation
import Testing
import PhotonzCore
@testable import PhotonzRender

/// A group paints as one object: the pieces inside composite together first,
/// then the group's own opacity, blur, shadow and rounded corners apply to the
/// result. A group that carries no styling of its own is invisible to the
/// renderer — its children draw exactly as if they sat loose on the canvas, so
/// grouping never changes a picture on its own.
@Suite("Group rendering")
struct GroupRenderingTests {

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

    private func rgba(_ image: CGImage) -> [UInt8] {
        var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = CGContext(data: &data, width: image.width, height: image.height,
                                bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return data
    }

    private func pixel(_ image: CGImage, x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        let data = rgba(image)
        let offset = (y * image.width + x) * 4
        return (data[offset], data[offset + 1], data[offset + 2], data[offset + 3])
    }

    private let canvas = CGSize(width: 200, height: 200)

    /// A white 200×200 base plus whatever else is handed in.
    private func document(_ store: ImageStore, _ layers: [Layer]) -> PhotonzDocument {
        let base = store.register(solidImage(width: 200, height: 200, r: 255, g: 255, b: 255))
        var doc = PhotonzDocument(canvasSize: canvas, layers: [
            Layer(name: "Base", content: .image(base),
                  frame: CGRect(origin: .zero, size: canvas), isLocked: true)
        ])
        for layer in layers { doc.addLayer(layer) }
        return doc
    }

    private func patch(_ store: ImageStore, _ name: String, _ frame: CGRect,
                       r: UInt8, g: UInt8, b: UInt8, style: LayerStyle = LayerStyle()) -> Layer {
        let ref = store.register(solidImage(width: Int(frame.width), height: Int(frame.height), r: r, g: g, b: b))
        return Layer(name: name, content: .image(ref), frame: frame, style: style)
    }

    private func group(_ name: String, at origin: CGPoint, style: LayerStyle = LayerStyle(),
                       _ children: [Layer]) -> Layer {
        Layer(name: name, content: .group(GroupContent(children: children)),
              frame: CGRect(origin: origin, size: .zero), style: style)
    }

    // MARK: - A plain group changes nothing

    @Test func aPlainGroupDrawsExactlyWhatTheSameLayersDrawLoose() {
        let store = ImageStore()
        let loose = document(store, [
            patch(store, "A", CGRect(x: 40, y: 40, width: 40, height: 40), r: 255, g: 0, b: 0),
            patch(store, "B", CGRect(x: 60, y: 60, width: 40, height: 40), r: 0, g: 0, b: 255)
        ])
        let grouped = document(store, [
            group("Card", at: CGPoint(x: 40, y: 40), [
                patch(store, "A", CGRect(x: 0, y: 0, width: 40, height: 40), r: 255, g: 0, b: 0),
                patch(store, "B", CGRect(x: 20, y: 20, width: 40, height: 40), r: 0, g: 0, b: 255)
            ])
        ])
        let a = DocumentRenderer().render(loose, store: store)!
        let b = DocumentRenderer().render(grouped, store: store)!
        #expect(rgba(a) == rgba(b), "grouping alone must not change a single pixel")
    }

    /// A highlight blends by multiplying with what is under it. Grouping it
    /// must not cut it off from the canvas underneath — the group passes
    /// through, so the highlight still multiplies against the photo.
    @Test func aPlainGroupDoesNotChangeHowAHighlightBlends() {
        let store = ImageStore()
        let highlight = Layer(name: "Highlight",
                              content: .annotation(AnnotationContent(shape: .highlight, strokeWidth: 0,
                                                                     colorHex: "#FFF200",
                                                                     start: CGPoint(x: 20, y: 80),
                                                                     end: CGPoint(x: 180, y: 120))),
                              frame: CGRect(origin: .zero, size: canvas))
        let photo = store.register(solidImage(width: 200, height: 200, r: 120, g: 160, b: 220))
        var loose = document(store, [])
        loose.addLayer(Layer(name: "Photo", content: .image(photo), frame: CGRect(origin: .zero, size: canvas)))
        var grouped = loose
        loose.addLayer(highlight)
        grouped.addLayer(group("Marks", at: .zero, [highlight]))

        let a = DocumentRenderer().render(loose, store: store)!
        let b = DocumentRenderer().render(grouped, store: store)!
        #expect(rgba(a) == rgba(b), "a grouped highlight must still multiply with the canvas below")
    }

    // MARK: - Styling applies once, to the whole group

    @Test func groupOpacityFadesTheCompositeNotEachChild() {
        let store = ImageStore()
        let doc = document(store, [
            group("Card", at: CGPoint(x: 40, y: 40), style: LayerStyle(opacity: 0.5), [
                patch(store, "A", CGRect(x: 0, y: 0, width: 40, height: 40), r: 255, g: 0, b: 0),
                patch(store, "B", CGRect(x: 20, y: 20, width: 40, height: 40), r: 0, g: 0, b: 255)
            ])
        ])
        let output = DocumentRenderer().render(doc, store: store)!
        // (70, 70) is where the blue child covers the red one: the group fades
        // once, so it is simply half-strength blue on white (188 in the green
        // channel, blending in linear light). Fading each child on its own
        // would leave half-faded red showing through underneath and drop that
        // channel to about 137.
        let overlap = pixel(output, x: 70, y: 70)
        #expect(overlap.g > 170,
                "the overlap must be blue over white at half strength, got \(overlap)")
        #expect(overlap.b > 240, "and still fully blue in the blue channel, got \(overlap)")
        // Where only the red child draws, one fade is one fade either way — and
        // it fades exactly as much as the overlap does.
        let single = pixel(output, x: 45, y: 45)
        #expect(single.r > 240 && single.g > 170, "got \(single)")
        #expect(abs(Int(single.g) - Int(overlap.g)) < 8,
                "one fade for the whole group: \(single) vs \(overlap)")
    }

    @Test func aGroupCastsOneShadowForTheWholeGroup() {
        let store = ImageStore()
        let shadow = LayerStyle(shadow: ShadowStyle(radius: 2, offset: CGSize(width: -20, height: -20),
                                                    spread: 0, colorHex: "#000000", opacity: 1))
        let doc = document(store, [
            group("Card", at: CGPoint(x: 40, y: 40), style: shadow, [
                patch(store, "A", CGRect(x: 0, y: 0, width: 40, height: 40), r: 0, g: 0, b: 255),
                patch(store, "B", CGRect(x: 30, y: 30, width: 40, height: 40), r: 0, g: 0, b: 255)
            ])
        ])
        let output = DocumentRenderer().render(doc, store: store)!
        // The children span (40,40)–(110,110). Inside that box nothing casts a
        // shadow on anything: one silhouette, one shadow, and it is hidden
        // under the group. Shadowing each child separately would drop the lower
        // child's shadow across the upper one right here.
        let inside = pixel(output, x: 55, y: 55)
        #expect(inside.b > 200 && inside.r < 60, "no shadow inside the group, got \(inside)")
        // Up and left of the whole group the one shadow does show.
        let outside = pixel(output, x: 30, y: 30)
        #expect(outside.r < 120, "the group's own shadow should darken here, got \(outside)")
    }

    @Test func groupCornerRadiusRoundsTheWholeGroupsBox() {
        let store = ImageStore()
        func render(radius: CGFloat) -> CGImage {
            let doc = document(store, [
                group("Card", at: CGPoint(x: 40, y: 40), style: LayerStyle(cornerRadius: radius), [
                    patch(store, "A", CGRect(x: 0, y: 0, width: 40, height: 40), r: 0, g: 0, b: 255),
                    patch(store, "B", CGRect(x: 20, y: 20, width: 40, height: 40), r: 0, g: 0, b: 255)
                ])
            ])
            return DocumentRenderer().render(doc, store: store)!
        }
        // The group's box is (40,40)–(100,100). A 20pt radius cuts its corners,
        // even though the child sitting in that corner is a square.
        let square = pixel(render(radius: 0), x: 42, y: 42)
        let rounded = pixel(render(radius: 20), x: 42, y: 42)
        #expect(square.b > 240 && square.r < 60,
                "with no radius the child fills the corner, got \(square)")
        #expect(rounded.r > 240 && rounded.g > 240,
                "the group's rounded corner should clip the child back to the white base, got \(rounded)")
        #expect(pixel(render(radius: 20), x: 70, y: 70).b > 240, "the middle stays covered")
    }

    @Test func groupBlurSoftensTheGroupsOutlineNotEveryChildsEdges() {
        let store = ImageStore()
        let doc = document(store, [
            group("Card", at: CGPoint(x: 40, y: 60), style: LayerStyle(blurRadius: 4), [
                patch(store, "Left", CGRect(x: 0, y: 0, width: 40, height: 40), r: 255, g: 0, b: 0),
                patch(store, "Right", CGRect(x: 40, y: 0, width: 40, height: 40), r: 255, g: 0, b: 0)
            ])
        ])
        let output = DocumentRenderer().render(doc, store: store)!
        // The two halves touch at x = 80. Blurring the group blurs one solid
        // 80×40 shape, so the seam is invisible; blurring each child would fade
        // both edges there and let the white base show through as a pale stripe.
        let seam = pixel(output, x: 80, y: 80)
        #expect(seam.r > 240 && seam.g < 40, "the seam inside the group must stay solid, got \(seam)")
        // The group's own outline still softens.
        let edge = pixel(output, x: 40, y: 80)
        #expect(edge.g > 60, "the outer edge should be soft, got \(edge)")
    }

    // MARK: - Groups inside groups

    @Test func aGroupInsideAGroupPositionsAndFadesTogether() {
        let store = ImageStore()
        let inner = group("Inner", at: CGPoint(x: 10, y: 10), style: LayerStyle(opacity: 0.5), [
            patch(store, "Dot", CGRect(x: 0, y: 0, width: 20, height: 20), r: 0, g: 0, b: 255)
        ])
        let doc = document(store, [
            group("Outer", at: CGPoint(x: 60, y: 60), style: LayerStyle(opacity: 0.5), [inner])
        ])
        let output = DocumentRenderer().render(doc, store: store)!
        // Origins add up: the dot lands at (70, 70). Both fades apply, so it is
        // a quarter-strength blue over white (225 in the red channel, blending
        // in linear light) rather than the half-strength 188.
        let dot = pixel(output, x: 80, y: 80)
        #expect(dot.r > 210 && dot.r < 240 && dot.b > 240, "got \(dot)")
        #expect(pixel(output, x: 65, y: 65).r > 250, "nothing draws before the two origins add up")
    }

    @Test func aStyledGroupInsideAPlainGroupStillDrawsAsOneThing() {
        let store = ImageStore()
        let card = group("Card", at: CGPoint(x: 40, y: 40), style: LayerStyle(opacity: 0.5), [
            patch(store, "A", CGRect(x: 0, y: 0, width: 40, height: 40), r: 255, g: 0, b: 0),
            patch(store, "B", CGRect(x: 20, y: 20, width: 40, height: 40), r: 0, g: 0, b: 255)
        ])
        let nested = document(store, [group("Wrapper", at: .zero, [card])])
        let flat = document(store, [card])
        let a = DocumentRenderer().render(nested, store: store)!
        let b = DocumentRenderer().render(flat, store: store)!
        #expect(rgba(a) == rgba(b), "wrapping a styled group in a plain one changes nothing")
    }

    // MARK: - Previews

    @Test func aGroupHasADragSpriteCoveringEverythingInIt() {
        let store = ImageStore()
        let doc = document(store, [
            group("Card", at: CGPoint(x: 40, y: 40), [
                patch(store, "A", CGRect(x: 0, y: 0, width: 40, height: 40), r: 255, g: 0, b: 0),
                patch(store, "B", CGRect(x: 20, y: 20, width: 40, height: 40), r: 0, g: 0, b: 255)
            ])
        ])
        let groupID = doc.layers.last!.id
        let sprite = DocumentRenderer().renderSprite(for: groupID, in: doc, store: store, padding: 8)
        #expect(sprite != nil, "a group must have a drag preview like any other layer")
        guard let sprite else { return }
        // The group's box is 60×60; the sprite adds 8pt of clear on every side.
        #expect(sprite.width == 76 && sprite.height == 76, "got \(sprite.width)×\(sprite.height)")
        #expect(pixel(sprite, x: 18, y: 18).r > 240, "the first child is in the sprite")
        #expect(pixel(sprite, x: 60, y: 60).b > 240, "and so is the second")
    }
}
