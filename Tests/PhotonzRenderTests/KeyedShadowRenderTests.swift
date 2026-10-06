import CoreGraphics
import Foundation
import PhotonzCore
import Testing
@testable import PhotonzRender

/// A shadow's keyed distance and colour, and a glow's keyed colour, reach the
/// pixels and move between their keys
/// (task `a-shadow-s-offset-colour-and-softness-and-a-glow`).
@Suite("A keyed shadow and glow move in the picture")
struct KeyedShadowRenderTests {

    static let canvas = CGSize(width: 200, height: 100)

    static func ink(_ image: CGImage, at point: CGPoint) -> (r: Int, g: Int, b: Int) {
        let width = image.width, height = image.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        let context = CGContext(data: &data, width: width, height: height,
                                bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let row = height - 1 - Int(point.y)
        let index = (row * width + Int(point.x)) * 4
        return (Int(data[index]), Int(data[index + 1]), Int(data[index + 2]))
    }

    static func box(_ name: String, _ rect: CGRect, hex: String) -> Layer {
        Layer(name: name,
              content: .annotation(AnnotationContent(shape: .rectangle, strokeWidth: 0, colorHex: hex,
                                                     start: .zero,
                                                     end: CGPoint(x: rect.width, y: rect.height),
                                                     fillColorHex: hex)),
              frame: rect)
    }

    /// A blue square at the left of a white ground, throwing a hard red
    /// shadow straight to the right, in a four second document.
    static func shadowed(distance: CGFloat) -> (PhotonzDocument, UUID) {
        let ground = box("Ground", CGRect(origin: .zero, size: canvas), hex: "#FFFFFF")
        var square = box("Square", CGRect(x: 20, y: 30, width: 40, height: 40), hex: "#0000FF")
        square.time = LayerTime(inMS: 0, outMS: 4000)
        square.style.shadows = [ShadowStyle(radius: 0, offset: CGSize(width: distance, height: 0),
                                            colorHex: "#FF0000", opacity: 1)]
        var document = PhotonzDocument(canvasSize: canvas, layers: [ground, square])
        document.durationMS = 4000
        return (document, square.id)
    }

    static func render(_ document: PhotonzDocument, atMS ms: Int) -> CGImage? {
        DocumentRenderer().render(document.drawn(atTimeMS: ms), store: ImageStore(), scale: 1)
    }

    @Test func aShadowKeyedFurtherAwayIsThrownFurtherInThePicture() throws {
        var (document, id) = Self.shadowed(distance: 1)
        document.startKeying(layerID: id, .motion(.shadowDistance), atDocumentTimeMS: 1000, ease: .linear)
        document.setKeyedValue(.number(40), layerID: id, .motion(.shadowDistance),
                               atDocumentTimeMS: 3000, ease: .linear)
        let early = try #require(Self.render(document, atMS: 500))
        let middle = try #require(Self.render(document, atMS: 2000))
        let late = try #require(Self.render(document, atMS: 3500))
        // At the first key the shadow is tucked under the square: the ground
        // to its right is white.
        #expect(Self.ink(early, at: CGPoint(x: 75, y: 50)).g > 200)
        // Half way it reaches about 20 out: past 75 is red, past 85 not yet.
        let halfIn = Self.ink(middle, at: CGPoint(x: 75, y: 50))
        #expect(halfIn.r > 200 && halfIn.g < 60, "\(halfIn)")
        #expect(Self.ink(middle, at: CGPoint(x: 92, y: 50)).g > 200)
        // At the last key it is thrown the whole 40.
        let far = Self.ink(late, at: CGPoint(x: 92, y: 50))
        #expect(far.r > 200 && far.g < 60, "\(far)")
    }

    @Test func aShadowsKeyedColourChangesInThePicture() throws {
        var (document, id) = Self.shadowed(distance: 40)
        document.startKeying(layerID: id, .motion(.shadowColor), atDocumentTimeMS: 1000, ease: .linear)
        document.setKeyedValue(.color("#00FF00"), layerID: id, .motion(.shadowColor),
                               atDocumentTimeMS: 3000, ease: .linear)
        let spot = CGPoint(x: 80, y: 50)
        let early = Self.ink(try #require(Self.render(document, atMS: 500)), at: spot)
        let middle = Self.ink(try #require(Self.render(document, atMS: 2000)), at: spot)
        let late = Self.ink(try #require(Self.render(document, atMS: 3500)), at: spot)
        #expect(early.r > 200 && early.g < 60, "\(early)")
        #expect(late.g > 200 && late.r < 60, "\(late)")
        // Between the keys, some of each.
        #expect(middle.r > 60 && middle.r < 200 && middle.g > 60 && middle.g < 200, "\(middle)")
        // Nothing baked in.
        #expect(document.layer(id: id)?.style.shadows.first?.colorHex == "#FF0000")
    }

    @Test func aGlowsKeyedColourChangesInThePicture() throws {
        var (document, id) = Self.shadowed(distance: 0)
        document.updateLayer(id: id) {
            $0.style.shadows = []
            $0.style.effects.append(.glow(GlowEffect(colorHex: "#FF0000", radius: 0, size: 10, opacity: 1)))
        }
        document.startKeying(layerID: id, .motion(.glowColor), atDocumentTimeMS: 1000, ease: .linear)
        document.setKeyedValue(.color("#00FF00"), layerID: id, .motion(.glowColor),
                               atDocumentTimeMS: 3000, ease: .linear)
        // Just outside the square's right edge, inside the glow's reach.
        let spot = CGPoint(x: 64, y: 50)
        let early = Self.ink(try #require(Self.render(document, atMS: 500)), at: spot)
        let late = Self.ink(try #require(Self.render(document, atMS: 3500)), at: spot)
        #expect(early.r > early.g + 80, "\(early)")
        #expect(late.g > late.r + 80, "\(late)")
    }
}
