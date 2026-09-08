import CoreGraphics
import Foundation
import Testing
import PhotonzCore
@testable import PhotonzRender

/// A label's Border, actually drawn, both ways round: baked into the letters,
/// and laid round the frame the words sit in. White words on a white canvas, so
/// every dark pixel came from the outline round the letters and every blue one
/// from the ring round the box.
@Suite("What a label's border follows, drawn")
struct TextBorderFollowsRenderTests {

    private let canvas = CGSize(width: 200, height: 100)
    private let frame = CGRect(x: 20, y: 20, width: 160, height: 40)

    private func white(_ size: CGSize) -> CGImage {
        let w = Int(size.width), h = Int(size.height)
        let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                bytesPerRow: w * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: size.width, height: size.height))
        return context.makeImage()!
    }

    private func pixels(_ image: CGImage) -> [UInt8] {
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let context = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8,
                                bytesPerRow: w * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return data
    }

    /// A label wearing exactly the borders it is given.
    private func label(_ borders: [BorderEffect]) -> Layer {
        var layer = Layer(name: "Label",
                          content: .text(TextContent(string: "Ship it", fontSize: 28,
                                                     colorHex: "#FFFFFF", weight: .semibold)),
                          frame: frame)
        layer.style.effects = borders.map { .border($0) }
        return layer
    }

    private func border(_ width: CGFloat, _ hex: String, _ follows: BorderFollows) -> BorderEffect {
        var border = BorderEffect(width: width, colorHex: hex, position: .outside)
        border.follows = follows
        return border
    }

    private func rendered(_ layer: Layer) -> [UInt8] {
        let store = ImageStore()
        let base = store.register(white(canvas))
        var doc = PhotonzDocument.withBaseImage(base)
        doc.addLayer(layer)
        return pixels(DocumentRenderer().render(doc, store: store)!)
    }

    /// How many pixels in the four-point band JUST OUTSIDE the label's frame are
    /// blue: the ring that follows the box and nothing else can put one there.
    private func blueOutsideTheFrame(_ data: [UInt8]) -> Int {
        var count = 0
        for y in Int(frame.minY) - 4..<Int(frame.minY) {
            for x in Int(frame.minX)..<Int(frame.maxX) {
                let i = (y * Int(canvas.width) + x) * 4
                if data[i] < 64, data[i + 1] < 64, data[i + 2] > 128 { count += 1 }
            }
        }
        return count
    }

    /// How many pixels INSIDE the frame are dark: the outline round the white
    /// letters.
    private func darkInsideTheFrame(_ data: [UInt8]) -> Int {
        var count = 0
        for y in Int(frame.minY)..<Int(frame.maxY) {
            for x in Int(frame.minX)..<Int(frame.maxX) {
                let i = (y * Int(canvas.width) + x) * 4
                if data[i] < 64, data[i + 1] < 64, data[i + 2] < 64 { count += 1 }
            }
        }
        return count
    }

    /// The thing that went missing: a plain box round the label itself.
    @Test func aBorderThatFollowsTheBoxDrawsARingRoundTheFrame() {
        let drawn = rendered(label([border(4, "#0000FF", .box)]))
        #expect(blueOutsideTheFrame(drawn) > 0)
    }

    /// And the one that was there all along still goes round the letters, with
    /// nothing round the frame.
    @Test func aBorderThatFollowsTheLettersLeavesTheFrameBare() {
        let drawn = rendered(label([border(4, "#0000FF", .letters)]))
        #expect(blueOutsideTheFrame(drawn) == 0)
    }

    /// Both at once, which is the whole point: a fat dark halo on the words and
    /// a thin blue box round the label.
    @Test func aLabelCanWearBothAtOnce() {
        let lettersOnly = rendered(label([border(6, "#000000", .letters)]))
        let both = rendered(label([border(6, "#000000", .letters),
                                   border(4, "#0000FF", .box)]))
        #expect(darkInsideTheFrame(lettersOnly) > 0)
        #expect(blueOutsideTheFrame(lettersOnly) == 0)
        #expect(blueOutsideTheFrame(both) > 0)
        // The box ring is outside the words, so adding it leaves the halo the
        // letters are wearing exactly as it was.
        #expect(darkInsideTheFrame(both) == darkInsideTheFrame(lettersOnly))
    }

    /// A document saved before any of this opens with its letter outline
    /// unchanged: the border it holds says nothing about what it follows, and
    /// the picture is the one it was saved with.
    @Test func aLabelSavedBeforeTheChoiceDrawsExactlyAsItDid() throws {
        let saved = label([border(6, "#000000", .letters)])
        let data = try JSONEncoder().encode(saved)
        let opened = try JSONDecoder().decode(Layer.self, from: data)
        #expect(opened.style.borderEffects.first?.follows == .letters)
        #expect(rendered(opened) == rendered(saved))
    }
}
