import CoreGraphics
import Foundation
import Testing
import PhotonzCore
@testable import PhotonzRender

/// The line style a path is set to is the line style it is DRAWN with: the
/// ends, the corners and the dashes all reach the pixels
/// (`docs/design/vector-paths.md`, "What kind of line it is").
@Suite("A path's line style, drawn")
struct PathLineStyleRenderingTests {

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

    /// How much ink is in the whole picture, so a dashed line can be told from
    /// a solid one without guessing where a gap landed.
    private func inkedPixels(_ image: CGImage) -> Int {
        let width = image.width, height = image.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        let context = CGContext(data: &data, width: width, height: height,
                                bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return stride(from: 3, to: data.count, by: 4).reduce(0) { $0 + (data[$1] > 128 ? 1 : 0) }
    }

    /// A level line 100 long, 10 thick, in black, with room round it.
    private func level(width: CGFloat = 10) -> PathContent {
        var path = PathContent(anchors: [PathAnchor(point: CGPoint(x: 0, y: 20)),
                                         PathAnchor(point: CGPoint(x: 100, y: 20))],
                               isClosed: false, fill: nil)
        path.colorHex = "#000000"
        path.strokeWidth = width
        return path
    }

    private func drawn(_ path: PathContent) -> CGImage {
        PathRasterizer.rasterize(path, size: CGSize(width: 100, height: 40))!
    }

    // MARK: Ends

    @Test("A flat end stops dead on the last point; a square one carries on past it")
    func endsDiffer() {
        var flat = level()
        flat.lineEnd = .flat
        var square = level()
        square.lineEnd = .square
        // The pad round the drawing differs with the end, so each picture is
        // asked about the same DOCUMENT point: three points past the line's
        // own last point, level with it.
        let past = CGPoint(x: 103, y: 20)
        func ink(_ path: PathContent) -> UInt8 {
            let image = drawn(path)
            let pad = path.strokeOutset
            return pixel(image, x: Int(past.x + pad), y: Int(past.y + pad)).a
        }
        #expect(ink(flat) == 0)
        #expect(ink(square) == 255)
    }

    @Test("A round end reaches as far as a square one along the line, and less at its corner")
    func roundVersusSquare() {
        var round = level()
        round.lineEnd = .round
        var square = level()
        square.lineEnd = .square
        // The very corner of the cap: 4 points past the end AND 4 above the
        // middle of the line. A square end paints it, a round one does not.
        func corner(_ path: PathContent) -> UInt8 {
            let image = drawn(path)
            let pad = path.strokeOutset
            return pixel(image, x: Int(104 + pad), y: Int(24 + pad)).a
        }
        #expect(corner(round) == 0)
        #expect(corner(square) == 255)
    }

    // MARK: Corners

    /// A V with a tail, so the sharp corner at the bottom of the V points into
    /// the middle of the shape's own box rather than off the edge of it.
    private func vee() -> PathContent {
        var path = PathContent(anchors: [PathAnchor(point: CGPoint(x: 10, y: 10)),
                                         PathAnchor(point: CGPoint(x: 50, y: 60)),
                                         PathAnchor(point: CGPoint(x: 90, y: 10)),
                                         PathAnchor(point: CGPoint(x: 90, y: 110))],
                               isClosed: false, fill: nil)
        path.colorHex = "#000000"
        path.strokeWidth = 12
        path.lineEnd = .flat
        return path
    }

    /// Just past where a sliced-off corner stops, straight below the point of
    /// the V: only a corner carried out to a point reaches here.
    private func pointOfTheV(_ corner: PathLineCorner) -> UInt8 {
        var path = vee()
        path.lineCorner = corner
        let image = PathRasterizer.rasterize(path, size: CGSize(width: 80, height: 100))!
        let pad = Int(path.strokeOutset)
        return pixel(image, x: 50 + pad, y: 67 + pad).a
    }

    @Test("A sharp corner is carried out to a point")
    func sharpCornerReachesFurthest() {
        #expect(pointOfTheV(.sharp) == 255)
    }

    @Test("A flat corner is sliced straight off, and a round one is turned through an arc")
    func otherCornersStopShort() {
        #expect(pointOfTheV(.flat) == 0)
        #expect(pointOfTheV(.round) == 0)
    }

    @Test("How far a sharp corner may be carried is stated, so the canvas and the SVG agree")
    func theLimitIsStated() {
        // SVG's own default is 4 and Core Graphics' is 10, so a file that did
        // not say would come back a different shape in a browser.
        #expect(pathMiterLimit == 10)
    }

    // MARK: Dashes

    @Test("A dashed line paints less than a solid one, and a dotted one less again")
    func dashesBreakTheLine() {
        var solid = level(width: 6)
        solid.lineEnd = .flat
        var dashed = solid
        dashed.linePattern = .dashed
        var dotted = solid
        dotted.linePattern = .dotted
        let solidInk = inkedPixels(drawn(solid))
        let dashedInk = inkedPixels(drawn(dashed))
        let dottedInk = inkedPixels(drawn(dotted))
        #expect(dashedInk < solidInk)
        #expect(dottedInk < dashedInk)
        #expect(dashedInk > 0)
        #expect(dottedInk > 0)
    }

    @Test("Dashes scale with the weight, so a thicker dashed line has fewer, bigger dashes")
    func dashesScale() {
        // Same line, two weights. The pattern is measured in line widths, so
        // the thick one is broken into a quarter as many marks.
        func marks(_ width: CGFloat) -> Int {
            var path = level(width: width)
            path.lineEnd = .flat
            path.linePattern = .dashed
            let image = drawn(path)
            let pad = Int(path.strokeOutset)
            var runs = 0, wasInk = false
            for x in 0..<image.width {
                let ink = pixel(image, x: x, y: 20 + pad).a > 128
                if ink, !wasInk { runs += 1 }
                wasInk = ink
            }
            return runs
        }
        #expect(marks(2) > marks(8))
    }

    @Test("A solid line is drawn exactly as it always was, dash pattern or no")
    func solidIsUnchanged() {
        let path = level()
        let image = drawn(path)
        let pad = Int(path.strokeOutset)
        // Every point along the middle of the line is inked.
        for x in stride(from: 2, to: 98, by: 7) {
            #expect(pixel(image, x: x + pad, y: 20 + pad).a == 255)
        }
    }
}

// MARK: - Room for a sharp corner

extension PathLineStyleRenderingTests {

    /// A chevron pointing right: its sharp corner sits on the right edge of
    /// the shape's own box, which is where a carried point has furthest to go
    /// and least room to go there.
    private func chevron(width: CGFloat = 12) -> PathContent {
        var path = PathContent(anchors: [PathAnchor(point: CGPoint(x: 0, y: 0)),
                                         PathAnchor(point: CGPoint(x: 40, y: 50)),
                                         PathAnchor(point: CGPoint(x: 0, y: 100))],
                               isClosed: false, fill: nil)
        path.colorHex = "#000000"
        path.strokeWidth = width
        path.lineEnd = .flat
        path.lineCorner = .sharp
        return path
    }

    @Test("A sharp corner is drawn in full rather than sliced off by the shape's own bitmap")
    func sharpCornerHasRoomToBeDrawn() {
        let path = chevron()
        let pad = path.strokeOutset
        let image = PathRasterizer.rasterize(path, size: path.bounds.size)!
        // Where the point of the chevron actually lands: half a line width out
        // along the bisector, divided by the sine of half the angle between
        // the two runs. Two points short of it, so the test is about the point
        // being THERE rather than about the last anti-aliased pixel of it.
        let reach = (path.strokeWidth / 2) / sin(atan2(50.0, 40.0))
        let tipX = 40 + reach - 2
        #expect(pad >= reach, "the bitmap makes room for the whole point")
        #expect(pixel(image, x: Int(tipX + pad), y: Int(50 + pad)).a == 255,
                "the point of the chevron is inked")
    }
}

extension PathLineStyleRenderingTests {

    @Test("A corner too sharp to carry is sliced off, and asks for no more room than a straight run")
    func aBeveledCornerAsksForNoRoom() {
        // A hairpin: the line goes out and comes almost straight back. Past
        // the limit the point is not drawn at all, so reading it as ten line
        // widths would pad this bitmap by 120 points on every side.
        var path = PathContent(anchors: [PathAnchor(point: CGPoint(x: 0, y: 0)),
                                         PathAnchor(point: CGPoint(x: 100, y: 1)),
                                         PathAnchor(point: CGPoint(x: 0, y: 2))],
                               isClosed: false, fill: nil)
        path.colorHex = "#000000"
        path.strokeWidth = 12
        path.lineCorner = .sharp
        #expect(path.strokeOutset == 6, "the same room a straight run of this weight asks for")
    }
}
