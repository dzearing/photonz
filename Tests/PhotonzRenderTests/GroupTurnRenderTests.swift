import CoreGraphics
import Foundation
import Testing
import PhotonzCore
@testable import PhotonzRender

/// Turning a group turns the whole card and everything in it, about the middle
/// of the box its contents make. A plain group used to draw straight onto the
/// canvas one child at a time; once it is turned it has to become one picture
/// first, or each piece would turn about its own middle and the card would
/// come apart.
@Suite("A group turns as one picture")
struct GroupTurnRenderTests {

    private func solid(_ width: Int, _ height: Int, r: CGFloat, g: CGFloat, b: CGFloat) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height,
                                bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(srgbRed: r, green: g, blue: b, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    private func pixel(_ image: CGImage, x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8) {
        var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = CGContext(data: &data, width: image.width, height: image.height,
                                bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let offset = (y * image.width + x) * 4
        return (data[offset], data[offset + 1], data[offset + 2])
    }

    /// A 100x100 red canvas holding one group anchored at (0, 0) with a blue
    /// 60x20 bar at (20, 40): the same bar `TransformRenderingTests` turns on
    /// its own, so a turned group and a turned layer can be compared.
    private func renderGroup(rotation: CGFloat, styled: Bool = false) -> CGImage {
        let store = ImageStore()
        let base = store.register(solid(100, 100, r: 1, g: 0, b: 0))
        let bar = store.register(solid(60, 20, r: 0, g: 0, b: 1))
        var doc = PhotonzDocument.withBaseImage(base)
        let child = Layer(name: "Bar", content: .image(bar),
                          frame: CGRect(x: 20, y: 40, width: 60, height: 20))
        var group = Layer(name: "Card", content: .group(GroupContent(children: [child])),
                          frame: CGRect(x: 0, y: 0, width: 0, height: 0),
                          transform: LayerTransform(rotation: rotation))
        if styled { group.style.opacity = 1 }
        doc.addLayer(group)
        return DocumentRenderer().render(doc, store: store)!
    }

    @Test("A quarter turn stands the group's contents on end")
    func aQuarterTurnStandsTheBarUp() {
        let output = renderGroup(rotation: .pi / 2)
        // 60x20 about (50, 50) becomes 20x60: it now reaches above and below.
        #expect(pixel(output, x: 50, y: 30).b > 240)
        #expect(pixel(output, x: 50, y: 70).b > 240)
        // ...and the arms it used to have are canvas again.
        let left = pixel(output, x: 30, y: 50)
        #expect(left.r > 240 && left.b < 16)
    }

    @Test("An unturned group still draws exactly where it always did")
    func anUprightGroupIsUnchanged() {
        let output = renderGroup(rotation: 0)
        #expect(pixel(output, x: 30, y: 50).b > 240)
        #expect(pixel(output, x: 50, y: 30).r > 240)
    }

    @Test("The group turns about the middle of the box its contents make")
    func thePivotIsTheContentsBoxNotTheAnchor() {
        // The group is anchored at (0, 0) while its contents sit round
        // (50, 50). Turning about the anchor would swing the bar clean off the
        // canvas and leave nothing but red behind.
        let output = renderGroup(rotation: .pi / 2)
        var blue = 0
        for y in 0..<100 where pixel(output, x: 50, y: y).b > 240 { blue += 1 }
        #expect(blue > 50, "the turned bar should still be on the canvas, down the middle")
    }

    @Test("A group that already drew as one object turns too")
    func aStyledGroupTurns() {
        // A group carrying styling of its own has always composited into a
        // buffer first; the turn has to take that picture as well, not only
        // the plain group that now buffers because it was turned.
        let store = ImageStore()
        let base = store.register(solid(100, 100, r: 1, g: 0, b: 0))
        let bar = store.register(solid(60, 20, r: 0, g: 0, b: 1))
        var doc = PhotonzDocument.withBaseImage(base)
        let child = Layer(name: "Bar", content: .image(bar),
                          frame: CGRect(x: 20, y: 40, width: 60, height: 20))
        var group = Layer(name: "Card", content: .group(GroupContent(children: [child])),
                          frame: CGRect(x: 0, y: 0, width: 0, height: 0),
                          transform: LayerTransform(rotation: .pi / 2))
        group.style.cornerRadius = 6
        let output = DocumentRenderer().render({ doc.addLayer(group); return doc }(), store: store)!
        #expect(pixel(output, x: 50, y: 30).b > 240)
        #expect(pixel(output, x: 50, y: 70).b > 240)
        let left = pixel(output, x: 30, y: 50)
        #expect(left.r > 240 && left.b < 16)
    }

    @Test("A turned group inside another group still lands where the turn puts it")
    func aTurnedGroupNestedInsideAnother() {
        let store = ImageStore()
        let base = store.register(solid(100, 100, r: 1, g: 0, b: 0))
        let bar = store.register(solid(60, 20, r: 0, g: 0, b: 1))
        var doc = PhotonzDocument.withBaseImage(base)
        let child = Layer(name: "Bar", content: .image(bar),
                          frame: CGRect(x: 20, y: 40, width: 60, height: 20))
        let inner = Layer(name: "Card", content: .group(GroupContent(children: [child])),
                          frame: CGRect(x: 0, y: 0, width: 0, height: 0),
                          transform: LayerTransform(rotation: .pi / 2))
        doc.addLayer(Layer(name: "Outer", content: .group(GroupContent(children: [inner])),
                           frame: CGRect(x: 0, y: 0, width: 0, height: 0)))
        let output = DocumentRenderer().render(doc, store: store)!
        #expect(pixel(output, x: 50, y: 30).b > 240)
        #expect(pixel(output, x: 50, y: 70).b > 240)
        #expect(pixel(output, x: 30, y: 50).r > 240)
    }

    @Test("A turned group inside a group that draws as one object is not cut off by it")
    func aTurnedGroupInsideAStyledParent() {
        // The parent composites into a buffer of its own, sized by how far its
        // contents reach BEFORE any of them turned. A turn that swings the
        // card past that edge must still be in the picture.
        let store = ImageStore()
        let base = store.register(solid(100, 100, r: 1, g: 0, b: 0))
        let bar = store.register(solid(60, 20, r: 0, g: 0, b: 1))
        var doc = PhotonzDocument.withBaseImage(base)
        let child = Layer(name: "Bar", content: .image(bar),
                          frame: CGRect(x: 20, y: 40, width: 60, height: 20))
        let inner = Layer(name: "Card", content: .group(GroupContent(children: [child])),
                          frame: CGRect(x: 0, y: 0, width: 0, height: 0),
                          transform: LayerTransform(rotation: .pi / 2))
        var outer = Layer(name: "Outer", content: .group(GroupContent(children: [inner])),
                          frame: CGRect(x: 0, y: 0, width: 0, height: 0))
        // Faded, not rounded: a rounded container is TOLD to cut what leaves
        // it, and this is about the buffer being big enough, not about the cut.
        outer.style.opacity = 0.5
        doc.addLayer(outer)
        let output = DocumentRenderer().render(doc, store: store)!
        #expect(pixel(output, x: 50, y: 30).b > 100, "the top of the turned bar is in the picture")
        #expect(pixel(output, x: 50, y: 70).b > 100, "and so is the bottom")
    }

    @Test("Half a turn round brings the group back where it started")
    func aFullTurnLandsWhereItBegan() {
        let full = renderGroup(rotation: .pi * 2)
        #expect(pixel(full, x: 30, y: 50).b > 240)
        #expect(pixel(full, x: 50, y: 30).r > 240)
    }
}
