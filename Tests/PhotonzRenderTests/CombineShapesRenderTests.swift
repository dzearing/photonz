import CoreGraphics
import Foundation
import Testing
import PhotonzCore
@testable import PhotonzRender

/// A shape with a hole in it really draws with the hole
/// (`PathCombining.swift`).
///
/// The model tests prove the geometry. This proves the only thing they cannot:
/// that the picture on the canvas has a transparent middle, drawn through the
/// app's own composite rather than through a path built for the test. A ring
/// whose model is right and whose render is a filled disc is the exact bug this
/// exists to catch.
@Suite("A combined shape draws")
struct CombineShapesRenderTests {

    // MARK: Building the pair

    private static let canvas = CGSize(width: 320, height: 320)

    private func circleLayer(_ name: String, box: CGRect, fill: String) -> Layer {
        var shape = AnnotationContent(shape: .ellipse, strokeWidth: 0, colorHex: fill,
                                      start: .zero,
                                      end: CGPoint(x: box.width, y: box.height))
        shape.fill = Paint(hex: fill)
        return Layer(name: name, content: .annotation(shape), frame: box)
    }

    /// A big circle with a smaller one overlapping it, the pair every one of
    /// the four commands is shown on.
    private func pair(overlapping: Bool = true) -> PhotonzDocument {
        var document = PhotonzDocument(canvasSize: Self.canvas)
        document.layers = [
            circleLayer("Circle A", box: CGRect(x: 40, y: 80, width: 160, height: 160),
                        fill: "#3478F6"),
            circleLayer("Circle B",
                        box: overlapping ? CGRect(x: 120, y: 80, width: 160, height: 160)
                                         : CGRect(x: 240, y: 80, width: 60, height: 60),
                        fill: "#FF9F0A")
        ]
        return document
    }

    /// The same pair, but with the second circle wholly inside the first, which
    /// is what makes Cut Out a ring.
    private func nested() -> PhotonzDocument {
        var document = PhotonzDocument(canvasSize: Self.canvas)
        document.layers = [
            circleLayer("Circle A", box: CGRect(x: 60, y: 60, width: 200, height: 200),
                        fill: "#3478F6"),
            circleLayer("Circle B", box: CGRect(x: 120, y: 120, width: 80, height: 80),
                        fill: "#FF9F0A")
        ]
        return document
    }

    private func render(_ document: PhotonzDocument) -> CGImage? {
        DocumentRenderer().render(document, store: ImageStore())
    }

    private func pixel(_ image: CGImage, x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        let width = image.width, height = image.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        let context = CGContext(data: &data, width: width, height: height,
                                bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let offset = (y * width + x) * 4
        return (data[offset], data[offset + 1], data[offset + 2], data[offset + 3])
    }

    // MARK: The hole is really a hole

    @Test("A ring draws with its middle clear and its rim painted")
    func theHoleIsTransparent() throws {
        var document = nested()
        let plan = document.combineLayers(ids: Set(document.layers.map(\.id)), .cutOut)
        #expect(plan.rings == 2)
        let image = try #require(render(document))
        let scale = CGFloat(image.width) / Self.canvas.width
        func at(_ x: CGFloat, _ y: CGFloat) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
            pixel(image, x: Int(x * scale), y: Int(y * scale))
        }
        // Both circles are centred on (160, 160): the rim reaches 100 points
        // out and the hole 40, so the middle of the canvas is the middle of the
        // hole and a point 80 above it is on the rim.
        #expect(at(160, 160).a < 20, "the hole lets the canvas through")
        let rim = at(160, 80)
        #expect(rim.a > 200, "the rim is painted")
        #expect(rim.b > rim.r, "and it is the BOTTOM shape's blue, not the top one's orange")
        #expect(at(160, 300).a < 20, "and outside the rim there is nothing")
    }

    @Test("A result in two pieces draws both of them and nothing between")
    func bothPiecesDraw() throws {
        var document = pair(overlapping: false)
        let plan = document.combineLayers(ids: Set(document.layers.map(\.id)), .join)
        #expect(plan.rings == 2)
        let image = try #require(render(document))
        let scale = CGFloat(image.width) / Self.canvas.width
        func at(_ x: CGFloat, _ y: CGFloat) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
            pixel(image, x: Int(x * scale), y: Int(y * scale))
        }
        #expect(at(120, 160).a > 200, "the big circle")
        #expect(at(270, 110).a > 200, "the little one, away on its own")
        #expect(at(220, 160).a < 20, "and clear canvas between them")
    }

    @Test("Keeping the overlap paints only where the two circles met")
    func onlyTheOverlapDraws() throws {
        var document = pair()
        document.combineLayers(ids: Set(document.layers.map(\.id)), .keepOverlap)
        let image = try #require(render(document))
        let scale = CGFloat(image.width) / Self.canvas.width
        func at(_ x: CGFloat, _ y: CGFloat) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
            pixel(image, x: Int(x * scale), y: Int(y * scale))
        }
        #expect(at(160, 160).a > 200, "the lens where they met")
        #expect(at(60, 160).a < 20, "the left of the big circle has gone")
        #expect(at(260, 160).a < 20, "and so has the right of the small one")
    }

    /// A contact sheet of the two sources and all four results, for looking at
    /// rather than asserting on. Off unless asked for, so the suite writes
    /// nothing in the normal run.
    ///
    /// `PHOTONZ_COMBINE_SHEET=/some/dir Scripts/test.sh --filter CombineShapesRender`
    @Test func writesAContactSheetWhenAsked() throws {
        guard let directory = ProcessInfo.processInfo.environment["PHOTONZ_COMBINE_SHEET"]
        else { return }
        let out = URL(fileURLWithPath: directory)
        func write(_ document: PhotonzDocument, _ name: String) throws {
            guard let image = render(document) else { return }
            try ImageCodec.encode(image, format: .png)?
                .write(to: out.appendingPathComponent("combine-\(name).png"))
        }
        try write(nested(), "0-two-circles")
        for operation in PathCombine.Operation.allCases {
            var document = nested()
            document.combineLayers(ids: Set(document.layers.map(\.id)), operation)
            try write(document, "\(operation.rawValue)-nested")
            var side = pair()
            side.combineLayers(ids: Set(side.layers.map(\.id)), operation)
            try write(side, "\(operation.rawValue)-overlapping")
        }
        try write(pair(), "0-two-circles-overlapping")
    }
}
