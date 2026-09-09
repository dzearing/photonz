import CoreGraphics
import Foundation
import Testing
import PhotonzCore
@testable import PhotonzRender

/// A shape with one corner rounded and another square, all the way through the
/// composite.
///
/// The fill was never the hard part: the ring round a box, the mask cut out of
/// a picture and the corner a group clips its children with are three different
/// pieces of the renderer, and each of them used to take ONE radius. Every test
/// here composites a real document and reads the pixel diagonally in from a
/// corner, which is the one place a rounded corner and a square one differ.
@Suite("Per corner rendering")
struct PerCornerRenderTests {

    private let canvas = CGSize(width: 240, height: 200)
    private let box = CGRect(x: 40, y: 30, width: 160, height: 140)
    /// A card with a rounded top and a square foot.
    private let roundedTop = CornerRadii(topLeft: 40, topRight: 40, bottomRight: 0, bottomLeft: 0)

    private func pixel(_ image: CGImage, _ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int, a: Int) {
        var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = CGContext(data: &data, width: image.width, height: image.height,
                                bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let i = (y * image.width + x) * 4
        guard i + 3 < data.count else { return (0, 0, 0, 0) }
        return (Int(data[i]), Int(data[i + 1]), Int(data[i + 2]), Int(data[i + 3]))
    }

    private func isClear(_ p: (r: Int, g: Int, b: Int, a: Int)) -> Bool { p.a < 40 }
    private func isPainted(_ p: (r: Int, g: Int, b: Int, a: Int)) -> Bool { p.a > 200 }
    private func isGreen(_ p: (r: Int, g: Int, b: Int, a: Int)) -> Bool {
        p.a > 180 && p.g > 150 && p.r < 100 && p.b < 100
    }

    private func render(_ layers: [Layer], store: ImageStore = ImageStore()) -> CGImage {
        var doc = PhotonzDocument(canvasSize: canvas)
        for layer in layers { doc.addLayer(layer) }
        return DocumentRenderer().render(doc, store: store)!
    }

    /// The four points a short way in from each corner of the box, in the
    /// order the corners are named.
    private func corners(_ image: CGImage, inset: Int = 8)
    -> [CornerRadii.Corner: (r: Int, g: Int, b: Int, a: Int)] {
        let x0 = Int(box.minX) + inset, x1 = Int(box.maxX) - inset
        let y0 = Int(box.minY) + inset, y1 = Int(box.maxY) - inset
        var seen: [CornerRadii.Corner: (r: Int, g: Int, b: Int, a: Int)] = [:]
        seen[CornerRadii.Corner.topLeft] = pixel(image, x0, y0)
        seen[CornerRadii.Corner.topRight] = pixel(image, x1, y0)
        seen[CornerRadii.Corner.bottomRight] = pixel(image, x1, y1)
        seen[CornerRadii.Corner.bottomLeft] = pixel(image, x0, y1)
        return seen
    }

    // MARK: - The shape a person draws

    @Test("A filled rectangle's top corners round and its bottom corners stay square")
    func shapeFillFollowsFourCorners() {
        var annotation = AnnotationContent(shape: .rectangle, strokeWidth: 0, colorHex: "#FF0000",
                                           start: .zero,
                                           end: CGPoint(x: box.width, y: box.height),
                                           cornerRadii: roundedTop, fillColorHex: "#FF0000")
        annotation.strokePosition = .inside
        let seen = corners(render([Layer(name: "Card", content: .annotation(annotation),
                                         frame: box)]))
        #expect(isClear(seen[.topLeft]!))
        #expect(isClear(seen[.topRight]!))
        #expect(isPainted(seen[.bottomRight]!))
        #expect(isPainted(seen[.bottomLeft]!))
    }

    @Test("The line round the shape follows the same four corners")
    func shapeStrokeFollowsFourCorners() {
        var annotation = AnnotationContent(shape: .rectangle, strokeWidth: 10, colorHex: "#00FF00",
                                           start: .zero,
                                           end: CGPoint(x: box.width, y: box.height),
                                           cornerRadii: roundedTop)
        annotation.strokePosition = .inside
        let image = render([Layer(name: "Card", content: .annotation(annotation), frame: box)])
        // Right on the box's own corner: empty where it is rounded away, and
        // wearing the line where the corner is still square.
        #expect(isClear(pixel(image, Int(box.minX) + 3, Int(box.minY) + 3)))
        #expect(isGreen(pixel(image, Int(box.minX) + 3, Int(box.maxY) - 3)))
    }

    // MARK: - A ring somebody ADDED

    @Test("An added border follows the four corners rather than framing them square")
    func addedBorderFollowsFourCorners() {
        var annotation = AnnotationContent(shape: .rectangle, strokeWidth: 0, colorHex: "#FF0000",
                                           start: .zero,
                                           end: CGPoint(x: box.width, y: box.height),
                                           cornerRadii: roundedTop, fillColorHex: "#FF0000")
        annotation.strokePosition = .inside
        var style = LayerStyle()
        style.effects = [.border(BorderEffect(width: 8, colorHex: "#00FF00", position: .outside))]
        let image = render([Layer(name: "Card", content: .annotation(annotation),
                                  frame: box, style: style)])
        // Diagonally OUT from each corner: a ring that follows a 40pt curve
        // leaves the top corners empty, and one that does not paints a frame.
        #expect(isClear(pixel(image, Int(box.minX) - 4, Int(box.minY) - 4)))
        #expect(isGreen(pixel(image, Int(box.minX) - 4, Int(box.maxY) + 4)))
    }

    // MARK: - The mask cut out of a picture

    @Test("A picture's mask cuts the rounded corners and leaves the square ones")
    func pictureMaskFollowsFourCorners() {
        let store = ImageStore()
        let size = CGSize(width: box.width, height: box.height)
        let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height),
                                bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1))
        context.fill(CGRect(origin: .zero, size: size))
        let ref = store.register(context.makeImage()!)
        var style = LayerStyle()
        style.cornerRadii = roundedTop
        let seen = corners(render([Layer(name: "Shot", content: .image(ref),
                                         frame: box, style: style)], store: store))
        #expect(isClear(seen[.topLeft]!))
        #expect(isClear(seen[.topRight]!))
        #expect(isPainted(seen[.bottomRight]!))
        #expect(isPainted(seen[.bottomLeft]!))
    }

    // MARK: - What a group clips

    @Test("A group clips its children to the four corners, not to one")
    func groupClipFollowsFourCorners() {
        var fill = AnnotationContent(shape: .rectangle, strokeWidth: 0, colorHex: "#FF0000",
                                     start: .zero,
                                     end: CGPoint(x: box.width, y: box.height),
                                     fillColorHex: "#FF0000")
        fill.strokePosition = .inside
        let child = Layer(name: "Fill", content: .annotation(fill),
                          frame: CGRect(origin: .zero, size: box.size))
        var style = LayerStyle()
        style.cornerRadii = roundedTop
        let group = Layer(name: "Card", content: .group(GroupContent(children: [child], clipsContents: true)),
                          frame: box, style: style)
        let seen = corners(render([group]))
        #expect(isClear(seen[.topLeft]!))
        #expect(isClear(seen[.topRight]!))
        #expect(isPainted(seen[.bottomRight]!))
        #expect(isPainted(seen[.bottomLeft]!))
    }

    // MARK: - The common case is unchanged

    @Test("Four corners that agree render exactly as one radius always did")
    func uniformIsUnchanged() {
        func card(_ radii: CornerRadii) -> CGImage {
            var style = LayerStyle()
            style.cornerRadii = radii
            var fill = AnnotationContent(shape: .rectangle, strokeWidth: 0, colorHex: "#FF0000",
                                         start: .zero,
                                         end: CGPoint(x: box.width, y: box.height),
                                         fillColorHex: "#FF0000")
            fill.strokePosition = .inside
            let child = Layer(name: "Fill", content: .annotation(fill),
                              frame: CGRect(origin: .zero, size: box.size))
            let group = Layer(name: "Card", content: .group(GroupContent(children: [child], clipsContents: true)),
                              frame: box, style: style)
            return render([group])
        }
        let one = card(CornerRadii(24)), four = card(CornerRadii(24))
        for corner in CornerRadii.Corner.allCases {
            #expect(corners(one)[corner]!.a == corners(four)[corner]!.a, "\(corner)")
        }
        // ...and it really is rounded, so the test is not passing on two squares.
        #expect(isClear(corners(one, inset: 4)[.topLeft]!))
    }
}
