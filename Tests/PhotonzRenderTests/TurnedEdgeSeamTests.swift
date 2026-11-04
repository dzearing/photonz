import CoreGraphics
import Foundation
import ImageIO
import PhotonzCore
import Testing
@testable import PhotonzRender

/// A layer whose edge lands between pixels blends into what is under it the
/// way its own pixels would (`a-turned-or-reshaped-layer-has-no-thin-line-alon`).
///
/// A picture read back from a PNG, which is every marquee copy and every
/// pasted or opened picture, is held with straight alpha. Resampled past its
/// own edge in linear light, the soft edge came out darker than either side,
/// so a white layer on a white picture drew a thin grey outline, up to 64
/// levels off white, wherever the turn, the reshape or a half pixel position
/// put that edge between pixels. A bitmap made in a premultiplied context
/// never showed it, which is why these tests go through a real PNG.
@Suite("A layer's edge has no seam")
struct TurnedEdgeSeamTests {

    static let space = CGColorSpace(name: CGColorSpace.sRGB)!

    /// `paint` in a premultiplied bitmap, the kind a context makes.
    static func drawn(_ width: Int, _ height: Int, _ paint: (CGContext) -> Void) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                bytesPerRow: width * 4, space: space,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        paint(context)
        return context.makeImage()!
    }

    static func solid(_ width: Int, _ height: Int, _ red: CGFloat, _ green: CGFloat,
                      _ blue: CGFloat) -> CGImage {
        drawn(width, height) {
            $0.setFillColor(CGColor(srgbRed: red, green: green, blue: blue, alpha: 1))
            $0.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    /// The same picture the way a paste holds it: through a PNG and back.
    static func throughPNG(_ image: CGImage) -> CGImage {
        let data = ImageCodec.encode(image, format: .png)!
        let source = CGImageSourceCreateWithData(data as CFData, nil)!
        return CGImageSourceCreateImageAtIndex(source, 0, nil)!
    }

    static func bytes(_ image: CGImage) -> [UInt8] {
        var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = CGContext(data: &data, width: image.width, height: image.height,
                                bitsPerComponent: 8, bytesPerRow: image.width * 4, space: space,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return data
    }

    /// How far the furthest pixel is from pure white, two pixels in from the
    /// picture's rim: a scale that does not land on whole pixels leaves the
    /// canvas's own last row part covered, which is not this layer's edge.
    static func levelsOffWhite(_ image: CGImage) -> Int {
        let data = bytes(image)
        var worst = 0
        for y in 2..<(image.height - 2) {
            for x in 2..<(image.width - 2) {
                let index = (y * image.width + x) * 4
                worst = max(worst, 255 - Int(min(data[index], data[index + 1], data[index + 2])))
            }
        }
        return worst
    }

    static let reshape = LayerReshape(offsets: [CGPoint(x: 0.05, y: 0.1), CGPoint(x: 0.1, y: -0.08),
                                                CGPoint(x: -0.06, y: 0.05), CGPoint(x: 0.02, y: -0.04)])
    static let skew = LayerReshape(offsets: [CGPoint(x: 0.1, y: 0), CGPoint(x: 0.1, y: 0), .zero, .zero])
    static let turn = LayerTransform(rotation: .pi / 12)

    static let cases: [(name: String, edit: @Sendable (inout Layer) -> Void)] = [
        ("a turn", { $0.transform = turn }),
        ("a skew", { $0.reshape = skew }),
        ("a distort", { $0.reshape = reshape }),
        ("a 3D tip", { $0.turn3D = LayerTurn3D(rotationY: 30) }),
        ("a turn and a distort", { $0.transform = turn; $0.reshape = reshape }),
        ("all three", {
            $0.transform = turn
            $0.reshape = reshape
            $0.turn3D = LayerTurn3D(rotationY: 30)
        }),
        ("rounded corners and a turn", { $0.style.cornerRadius = 12; $0.transform = turn }),
        ("a shrunk layer turned", {
            $0.frame = CGRect(x: 150, y: 120, width: 105, height: 85)
            $0.transform = turn
        }),
        ("half a pixel off", { $0.frame = CGRect(x: 150.5, y: 120.5, width: 210, height: 170) }),
        ("an uneven size", { $0.frame = CGRect(x: 150.3, y: 120.7, width: 166.3, height: 138.7) })
    ]

    static func document(layer picture: CGImage,
                         _ edit: (inout Layer) -> Void) -> (PhotonzDocument, ImageStore) {
        let store = ImageStore()
        let base = store.register(throughPNG(solid(512, 416, 1, 1, 1)))
        var document = PhotonzDocument.withBaseImage(base)
        var layer = Layer(name: "Copied Selection", content: .image(store.register(picture)),
                          frame: CGRect(x: 150, y: 120, width: 210, height: 170))
        edit(&layer)
        document.addLayer(layer)
        return (document, store)
    }

    @Test("White on white stays white in every space, at every zoom and in exports",
          arguments: [CompositingSpace.linearLight, .sRGB])
    func whiteOnWhite(space: CompositingSpace) throws {
        let renderer = DocumentRenderer(compositing: space)
        let white = Self.throughPNG(Self.solid(210, 170, 1, 1, 1))
        let wholeCanvas = CGRect(x: 0, y: 0, width: 512, height: 416)
        for (name, edit) in Self.cases {
            let (document, store) = Self.document(layer: white, edit)
            // What the canvas shows at or under 1:1 and what an export writes.
            let flat = try #require(renderer.render(document, store: store))
            #expect(Self.levelsOffWhite(flat) <= 1, "\(name) at 1x")
            for scale in [0.25, 0.5, 0.79, 2] as [CGFloat] {
                let scaled = try #require(renderer.render(document, store: store, scale: scale))
                #expect(Self.levelsOffWhite(scaled) <= 1, "\(name) at \(scale)x")
            }
            // The sharp copy a Retina canvas lays over the picture past 50%.
            for zoom in [0.79, 1, 2] as [CGFloat] {
                let tile = try #require(renderer.renderTile(
                    document, store: store, region: wholeCanvas, scale: zoom * 2,
                    magnifyNearest: zoom >= 2, colorSpace: nil))
                #expect(Self.levelsOffWhite(tile.image) <= 1, "\(name) in the tile at \(zoom)")
            }
        }
    }

    @Test("A turned group of a pasted picture has no seam either")
    func turnedGroup() throws {
        let store = ImageStore()
        let base = store.register(Self.throughPNG(Self.solid(512, 416, 1, 1, 1)))
        let picture = store.register(Self.throughPNG(Self.solid(210, 170, 1, 1, 1)))
        var document = PhotonzDocument.withBaseImage(base)
        let child = Layer(name: "Picture", content: .image(picture),
                          frame: CGRect(x: 0, y: 0, width: 210, height: 170))
        var group = Layer(name: "Card", content: .group(GroupContent(children: [child])),
                          frame: CGRect(x: 150, y: 120, width: 210, height: 170))
        group.transform = Self.turn
        document.addLayer(group)
        let output = try #require(DocumentRenderer(compositing: .linearLight).render(document, store: store))
        #expect(Self.levelsOffWhite(output) <= 1)
    }

    /// A coloured layer's edge is the one a premultiplied bitmap of the same
    /// colour draws, which mixes the two sides and nothing else: no lighter
    /// rim, no darker rim, and still soft.
    @Test("A coloured edge stays smooth and grows no rim", arguments: [
        (CGFloat(1), CGFloat(0.2), CGFloat(0.15)), (0, 0, 0), (0.2, 0.4, 0.9)
    ])
    func colouredEdge(colour: (CGFloat, CGFloat, CGFloat)) throws {
        let renderer = DocumentRenderer(compositing: .linearLight)
        let picture = Self.solid(210, 170, colour.0, colour.1, colour.2)
        for (name, edit) in Self.cases {
            let (straightDocument, straightStore) = Self.document(layer: Self.throughPNG(picture), edit)
            let (madeDocument, madeStore) = Self.document(layer: picture, edit)
            let pasted = Self.bytes(try #require(renderer.render(straightDocument, store: straightStore)))
            let made = Self.bytes(try #require(renderer.render(madeDocument, store: madeStore)))
            var worst = 0
            var between = 0
            let floor = Int(min(colour.0, colour.1, colour.2) * 255) - 1
            for index in stride(from: 0, to: pasted.count, by: 4) {
                for channel in 0..<3 {
                    worst = max(worst, abs(Int(pasted[index + channel]) - Int(made[index + channel])))
                }
                let lowest = Int(min(pasted[index], pasted[index + 1], pasted[index + 2]))
                if lowest > floor + 2, lowest < 253 { between += 1 }
            }
            #expect(worst <= 1, "\(name) differs from the same colour made in a context by \(worst)")
            // Half a pixel off lands every edge on a true half, and the rest
            // on a slant: either way there are in-between pixels to find.
            #expect(between > 100, "\(name) lost its soft edge: \(between) in-between pixels")
        }
    }

    /// A layer that sits on whole pixels is copied, not resampled: every byte
    /// of a busy picture arrives as it left.
    @Test("A layer on whole pixels draws byte for byte")
    func unturnedIsUntouched() throws {
        let busy = Self.throughPNG(Self.drawn(200, 120) { context in
            for y in stride(from: 0, to: 120, by: 3) {
                for x in stride(from: 0, to: 200, by: 3) {
                    context.setFillColor(CGColor(srgbRed: CGFloat(x % 97) / 96, green: CGFloat(y % 53) / 52,
                                                 blue: CGFloat((x + y) % 31) / 30, alpha: 1))
                    context.fill(CGRect(x: x, y: y, width: 3, height: 3))
                }
            }
        })
        let (document, store) = Self.document(layer: busy) {
            $0.frame = CGRect(x: 100, y: 60, width: 200, height: 120)
        }
        for space in [CompositingSpace.linearLight, .sRGB] {
            let output = try #require(DocumentRenderer(compositing: space).render(document, store: store))
            let drawn = Self.bytes(output)
            let source = Self.bytes(busy)
            var different = 0
            for y in 0..<120 {
                for x in 0..<200 {
                    let from = (y * 200 + x) * 4
                    let to = ((y + 60) * output.width + x + 100) * 4
                    if drawn[to..<(to + 4)] != source[from..<(from + 4)] { different += 1 }
                }
            }
            #expect(different == 0, "\(space): \(different) pixels changed")
        }
    }
}
