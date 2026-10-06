import CoreGraphics
import Foundation
import PhotonzCore
import Testing
@testable import PhotonzRender

/// A border's keyed width and colour reach the pixels and move between their
/// keys, round a box and round a title's letters alike
/// (task `a-border-s-width-and-colour-key-like-any-other-v`).
@Suite("A keyed border moves in the picture")
struct KeyedBorderRenderTests {

    static let canvas = CGSize(width: 200, height: 100)

    static func pixels(_ image: CGImage) -> (data: [UInt8], width: Int, height: Int) {
        let width = image.width, height = image.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        let context = CGContext(data: &data, width: width, height: height,
                                bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return (data, width, height)
    }

    static func ink(_ image: CGImage, at point: CGPoint) -> (r: Int, g: Int, b: Int) {
        let (data, width, height) = pixels(image)
        let row = height - 1 - Int(point.y)
        let index = (row * width + Int(point.x)) * 4
        return (Int(data[index]), Int(data[index + 1]), Int(data[index + 2]))
    }

    /// How many pixels read as plainly red.
    static func redCount(_ image: CGImage) -> Int {
        let (data, width, height) = pixels(image)
        var count = 0
        for index in stride(from: 0, to: width * height * 4, by: 4)
        where data[index] > 180 && data[index + 1] < 90 && data[index + 2] < 90 {
            count += 1
        }
        return count
    }

    static func box(_ name: String, _ rect: CGRect, hex: String) -> Layer {
        Layer(name: name,
              content: .annotation(AnnotationContent(shape: .rectangle, strokeWidth: 0, colorHex: hex,
                                                     start: .zero,
                                                     end: CGPoint(x: rect.width, y: rect.height),
                                                     fillColorHex: hex)),
              frame: rect)
    }

    /// A blue square at the left of a white ground, wearing a red border
    /// outside its edge, in a four second document.
    static func bordered(width: CGFloat) -> (PhotonzDocument, UUID) {
        let ground = box("Ground", CGRect(origin: .zero, size: canvas), hex: "#FFFFFF")
        var square = box("Square", CGRect(x: 40, y: 30, width: 40, height: 40), hex: "#0000FF")
        square.time = LayerTime(inMS: 0, outMS: 4000)
        square.style.effects = [.border(BorderEffect(width: width, colorHex: "#FF0000", position: .outside))]
        var document = PhotonzDocument(canvasSize: canvas, layers: [ground, square])
        document.durationMS = 4000
        return (document, square.id)
    }

    static func render(_ document: PhotonzDocument, atMS ms: Int) -> CGImage? {
        DocumentRenderer().render(document.drawn(atTimeMS: ms), store: ImageStore(), scale: 1)
    }

    @Test func aBorderKeyedWiderGrowsInThePicture() throws {
        var (document, id) = Self.bordered(width: 0)
        document.startKeying(layerID: id, .motion(.borderWidth), atDocumentTimeMS: 1000, ease: .linear)
        document.setKeyedValue(.number(20), layerID: id, .motion(.borderWidth),
                               atDocumentTimeMS: 3000, ease: .linear)
        let early = try #require(Self.render(document, atMS: 500))
        let middle = try #require(Self.render(document, atMS: 2000))
        let late = try #require(Self.render(document, atMS: 3500))
        // The square's right edge is at 80. At the first key there is no ring:
        // just right of the edge is white.
        #expect(Self.ink(early, at: CGPoint(x: 83, y: 50)).g > 200)
        // Half way it is about 10 wide: 85 is red, 95 not yet.
        let halfIn = Self.ink(middle, at: CGPoint(x: 85, y: 50))
        #expect(halfIn.r > 200 && halfIn.g < 60, "\(halfIn)")
        #expect(Self.ink(middle, at: CGPoint(x: 95, y: 50)).g > 200)
        // At the last key it is the whole 20.
        let wide = Self.ink(late, at: CGPoint(x: 95, y: 50))
        #expect(wide.r > 200 && wide.g < 60, "\(wide)")
        // Nothing baked in.
        #expect(document.layer(id: id)?.style.borderEffects.first?.width == 0)
    }

    @Test func aBordersKeyedColourChangesInThePicture() throws {
        var (document, id) = Self.bordered(width: 10)
        document.startKeying(layerID: id, .motion(.borderColor), atDocumentTimeMS: 1000, ease: .linear)
        document.setKeyedValue(.color("#00FF00"), layerID: id, .motion(.borderColor),
                               atDocumentTimeMS: 3000, ease: .linear)
        let spot = CGPoint(x: 85, y: 50)
        let early = Self.ink(try #require(Self.render(document, atMS: 500)), at: spot)
        let middle = Self.ink(try #require(Self.render(document, atMS: 2000)), at: spot)
        let late = Self.ink(try #require(Self.render(document, atMS: 3500)), at: spot)
        #expect(early.r > 200 && early.g < 60, "\(early)")
        #expect(late.g > 200 && late.r < 60, "\(late)")
        #expect(middle.r > 60 && middle.r < 200 && middle.g > 60 && middle.g < 200, "\(middle)")
        #expect(document.layer(id: id)?.style.borderEffects.first?.colorHex == "#FF0000")
    }

    @Test func aBorderRoundATitlesLettersGrowsWithItsKeys() throws {
        // A border that follows a title's letters is drawn round each glyph,
        // not round a box, and keys move it the same way.
        let ground = Self.box("Ground", CGRect(origin: .zero, size: Self.canvas), hex: "#FFFFFF")
        var title = Layer(name: "Title",
                          content: .text(TextContent(string: "HI", fontSize: 60, colorHex: "#FFFFFF")),
                          frame: CGRect(x: 40, y: 10, width: 120, height: 80))
        title.time = LayerTime(inMS: 0, outMS: 4000)
        title.style.effects = [.border(BorderEffect(width: 1, colorHex: "#FF0000", follows: .letters))]
        var document = PhotonzDocument(canvasSize: Self.canvas, layers: [ground, title])
        document.durationMS = 4000
        document.startKeying(layerID: title.id, .motion(.borderWidth), atDocumentTimeMS: 1000, ease: .linear)
        document.setKeyedValue(.number(8), layerID: title.id, .motion(.borderWidth),
                               atDocumentTimeMS: 3000, ease: .linear)
        let thin = Self.redCount(try #require(Self.render(document, atMS: 500)))
        let middle = Self.redCount(try #require(Self.render(document, atMS: 2000)))
        let thick = Self.redCount(try #require(Self.render(document, atMS: 3500)))
        #expect(thin > 0, "a 1pt ring round the letters paints something")
        #expect(middle > thin, "half way it is thicker: \(thin) -> \(middle)")
        #expect(thick > middle, "and thicker again at the last key: \(middle) -> \(thick)")
    }
}
