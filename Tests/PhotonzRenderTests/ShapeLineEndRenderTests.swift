import CoreGraphics
import Foundation
import Testing
import PhotonzCore
@testable import PhotonzRender

/// The end a line or an arrow is set to is the end it is DRAWN with.
///
/// A path has been drawn with its own ends since 2026-09-15; a line and an
/// arrow ended in a half circle whatever anybody chose, so the two halves of
/// the app could not be made to match (`PhotonzCore/PathLineStyle.swift`).
@Suite("How a line and an arrow are drawn at their ends")
struct ShapeLineEndRenderTests {

    private func pixel(_ image: CGImage, x: Int, y: Int) -> UInt8 {
        let width = image.width, height = image.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        let context = CGContext(data: &data, width: width, height: height,
                                bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return data[(y * width + x) * 4 + 3]
    }

    /// A level line 100 long and 10 thick, drawn 20 points down a box with
    /// room round it, so each end has empty space to reach into.
    private func level(_ end: PathLineEnd, shape: AnnotationShape = .line) -> AnnotationContent {
        var content = AnnotationContent(shape: shape, strokeWidth: 10,
                                        start: CGPoint(x: 20, y: 20),
                                        end: CGPoint(x: 120, y: 20))
        content.colorHex = "#000000"
        content.lineEnd = end
        return content
    }

    private func drawn(_ content: AnnotationContent) -> (CGImage, Int) {
        let pad = Int(content.strokeOutset)
        let image = AnnotationRasterizer.rasterize(content,
                                                   size: CGSize(width: 160, height: 60))!
        return (image, pad)
    }

    @Test("A flat end stops dead on its last point; a round and a square one carry on past it")
    func endsDiffer() {
        // Three points past where the line stops, level with it.
        func ink(_ end: PathLineEnd) -> UInt8 {
            let (image, pad) = drawn(level(end))
            return pixel(image, x: 123 + pad, y: 20 + pad)
        }
        #expect(ink(.flat) == 0)
        #expect(ink(.round) == 255)
        #expect(ink(.square) == 255)
    }

    @Test("A square end keeps its corners where a round one is cut away")
    func squareKeepsItsCorners() {
        // The very corner of the cap: 4 past the end AND 4 above the middle.
        func corner(_ end: PathLineEnd) -> UInt8 {
            let (image, pad) = drawn(level(end))
            return pixel(image, x: 124 + pad, y: 24 + pad)
        }
        #expect(corner(.round) == 0)
        #expect(corner(.square) == 255)
    }

    @Test("A square end is drawn in full rather than sliced off by the shape's own bitmap")
    func aSquareEndHasRoomToBeDrawn() {
        // A DIAGONAL line, because that is where a square end costs anything:
        // level with the page its corner is half a width past the last point,
        // the same as a round one, and at forty five degrees it is width/√2.
        // The box is the one a drag would have left a ROUND line — half a
        // width of slack all round — so an end switched afterwards has to be
        // given its room by the bitmap.
        var content = AnnotationContent(shape: .line, strokeWidth: 10,
                                        start: CGPoint(x: 5, y: 5),
                                        end: CGPoint(x: 85, y: 85))
        content.colorHex = "#000000"
        content.lineEnd = .square
        let pad = Int(content.strokeOutset)
        #expect(pad >= 3, "room for the extra width/√2 − width/2")
        let image = AnnotationRasterizer.rasterize(content,
                                                    size: CGSize(width: 90, height: 90))!
        // Two points short of the corner, which lands at 85 + 10/√2 = 92.07
        // in x: past the box the line was given, and inside the bitmap only
        // because the bitmap grew.
        #expect(pixel(image, x: 90 + pad, y: 85 + pad) == 255)
    }

    @Test("An arrow's tail takes the end it was given")
    func theArrowsTailIsShaped() {
        func ink(_ end: PathLineEnd) -> UInt8 {
            var content = level(end, shape: .arrow)
            content.arrowheadStyle = .standard
            let (image, pad) = drawn(content)
            // Three points BEHIND the tail, which only a round or square end
            // reaches. The head is at the other end and cannot confuse this.
            return pixel(image, x: 17 + pad, y: 20 + pad)
        }
        #expect(ink(.flat) == 0)
        #expect(ink(.round) == 255)
        #expect(ink(.square) == 255)
    }

    @Test("A box is drawn exactly as it always was, whatever is stored on it")
    func closedShapesAreUnchanged() {
        var box = AnnotationContent(shape: .rectangle, strokeWidth: 10,
                                    start: CGPoint(x: 10, y: 10),
                                    end: CGPoint(x: 120, y: 50))
        box.colorHex = "#000000"
        let before = AnnotationRasterizer.rasterize(box, size: CGSize(width: 160, height: 60))!
        box.lineEnd = .square
        let after = AnnotationRasterizer.rasterize(box, size: CGSize(width: 160, height: 60))!
        #expect(before.width == after.width && before.height == after.height)
        for x in stride(from: 2, to: before.width - 2, by: 11) {
            #expect(pixel(before, x: x, y: 12) == pixel(after, x: x, y: 12))
        }
    }
}
