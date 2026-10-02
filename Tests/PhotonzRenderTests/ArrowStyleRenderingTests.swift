import CoreGraphics
import Foundation
import Testing
import PhotonzCore
@testable import PhotonzRender

/// The hand-made arrow styles measured off real pixels: they draw, they draw
/// the same every time, they stay inside their frame, they keep their colours,
/// and a sharper copy for a zoomed canvas or a 2x/3x export is the same
/// drawing, only finer.
@Suite("Arrow styles on screen")
struct ArrowStyleRenderingTests {

    private struct Pixels {
        let data: [UInt8]
        let width: Int
        let height: Int

        func alpha(_ x: Int, _ y: Int) -> UInt8 {
            guard x >= 0, y >= 0, x < width, y < height else { return 0 }
            return data[(y * width + x) * 4 + 3]
        }
        func rgba(_ x: Int, _ y: Int) -> (UInt8, UInt8, UInt8, UInt8) {
            let i = (y * width + x) * 4
            return (data[i], data[i + 1], data[i + 2], data[i + 3])
        }
        var inkCount: Int {
            stride(from: 3, to: data.count, by: 4).reduce(0) { $0 + (data[$1] > 40 ? 1 : 0) }
        }
    }

    private func layer(_ style: ArrowStyle, seed: UInt32 = 11, width: CGFloat = 4,
                       from start: CGPoint = CGPoint(x: 30, y: 140),
                       to end: CGPoint = CGPoint(x: 330, y: 60)) -> Layer {
        var content = AnnotationContent(shape: .arrow, strokeWidth: width, colorHex: "#FF3B30")
        content.arrowStyle = style
        content.styleSeed = seed
        return AnnotationBuilder.layer(content: content, from: start, to: end)
    }

    private func render(_ layer: Layer, scale: CGFloat = 1) -> Pixels? {
        guard let content = layer.annotation,
              let image = AnnotationRasterizer.rasterize(content, size: layer.frame.size, scale: scale)
        else { return nil }
        let width = image.width, height = image.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let read = CGContext(data: &data, width: width, height: height,
                                   bitsPerComponent: 8, bytesPerRow: width * 4, space: space,
                                   bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        read.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return Pixels(data: data, width: width, height: height)
    }

    @Test func everyStyleDrawsInk() throws {
        for style in ArrowStyle.allCases {
            let px = try #require(render(layer(style)))
            #expect(px.inkCount > 300, "\(style) drew \(px.inkCount) pixels")
        }
    }

    @Test func aHandMadeArrowIsNotTheCleanOne() throws {
        let clean = try #require(render(layer(.clean)))
        for style in ArrowStyle.allCases where style.isHandMade {
            let px = try #require(render(layer(style)))
            #expect(px.data != clean.data, "\(style)")
        }
    }

    /// Two renders of the same arrow are the same pixels: nothing wobbles.
    @Test func theSameArrowRendersTheSamePixels() throws {
        for style in ArrowStyle.allCases where style.isHandMade {
            let a = try #require(render(layer(style)))
            let b = try #require(render(layer(style)))
            #expect(a.data == b.data, "\(style)")
        }
    }

    /// The bitmap's outermost row and column are empty: the frame holds the
    /// whole drawing, so nothing is clipped at its edge.
    @Test func nothingIsClippedAtTheFrame() throws {
        for style in ArrowStyle.allCases where style.isHandMade {
            for width in [CGFloat(2), 4, 14] {
                for seed in [UInt32(3), 77] {
                    let px = try #require(render(layer(style, seed: seed, width: width)))
                    var edge = 0
                    for x in 0..<px.width { edge = max(edge, Int(px.alpha(x, 0)), Int(px.alpha(x, px.height - 1))) }
                    for y in 0..<px.height { edge = max(edge, Int(px.alpha(0, y)), Int(px.alpha(px.width - 1, y))) }
                    #expect(edge < 40, "\(style) w\(width) seed \(seed) touches its frame (\(edge))")
                }
            }
        }
    }

    /// A sharper copy is the same drawing at more pixels: about scale² as much
    /// ink, in the same place.
    @Test func aSharperCopyIsTheSameDrawing() throws {
        for style in ArrowStyle.allCases where style.isHandMade {
            let one = try #require(render(layer(style)))
            for scale in [CGFloat(2), 3] {
                let sharp = try #require(render(layer(style), scale: scale))
                #expect(sharp.width == Int((CGFloat(one.width) * scale).rounded()))
                let ratio = Double(sharp.inkCount) / Double(one.inkCount) / Double(scale * scale)
                #expect(ratio > 0.8 && ratio < 1.25, "\(style) at \(scale)x: \(ratio)")
            }
        }
    }

    /// The colour of the line and of the head both reach the drawing.
    @Test func theHeadWearsItsOwnColour() throws {
        for style in ArrowStyle.allCases where style.isHandMade {
            var built = layer(style, from: CGPoint(x: 30, y: 100), to: CGPoint(x: 330, y: 100))
            guard var content = built.annotation else { continue }
            content.colorHex = "#0000FF"
            content.headColorHex = "#00FF00"
            built.content = .annotation(content)
            let px = try #require(render(built))
            var blue = 0, green = 0
            for y in 0..<px.height {
                for x in 0..<px.width {
                    let (r, g, b, a) = px.rgba(x, y)
                    guard a > 200 else { continue }
                    if b > 200, g < 60, r < 60 { blue += 1 }
                    if g > 200, b < 60, r < 60 { green += 1 }
                }
            }
            #expect(blue > 100, "\(style) shaft: \(blue)")
            #expect(green > 30, "\(style) head: \(green)")
        }
    }

    /// See-through ink stays one even wash where pieces of the drawing cross:
    /// a sketch's two passes and a brush's wings over its body do not leave
    /// darker knots, and do not punch holes either.
    @Test func translucentInkIsOneEvenWash() throws {
        for style in ArrowStyle.allCases where style.isHandMade {
            var built = layer(style, width: 6, from: CGPoint(x: 30, y: 100), to: CGPoint(x: 330, y: 100))
            guard var content = built.annotation else { continue }
            content.colorHex = "#FF000080"
            content.headColorHex = "#FF000080"
            built.content = .annotation(content)
            let px = try #require(render(built))
            var strongest: UInt8 = 0
            for y in 0..<px.height {
                for x in 0..<px.width { strongest = max(strongest, px.alpha(x, y)) }
            }
            // Shaft and head are separate washes and may overlap once at the
            // join; nowhere else does ink pile up.
            #expect(strongest <= 200, "\(style) piles up to \(strongest)")
        }
    }

    /// A brush stroke starts from a point: there is less ink across the line
    /// near the tail than through the body.
    @Test func theBrushIsThinAtTheTailAndFullInTheBody() throws {
        let built = layer(.brush, width: 6, from: CGPoint(x: 30, y: 100), to: CGPoint(x: 430, y: 100))
        let px = try #require(render(built))
        guard let content = built.annotation else { return }
        func thickness(atX x: CGFloat) -> Int {
            let column = Int((content.start.x + x).rounded())
            return (0..<px.height).reduce(0) { $0 + (px.alpha(column, $1) > 100 ? 1 : 0) }
        }
        #expect(thickness(atX: 12) < thickness(atX: 240))
        #expect(thickness(atX: 240) >= 12)
    }

    // MARK: - A bent arrow

    /// Every style of a bent arrow paints along its curve: ink at the bow,
    /// none where the straight line between its ends used to run, and none
    /// against the edge of the frame that grew to hold it.
    @Test func aBentArrowPaintsAlongItsCurveInEveryStyle() throws {
        for style in ArrowStyle.allCases {
            var bent = layer(style, from: CGPoint(x: 30, y: 200), to: CGPoint(x: 330, y: 200))
            bent = AnnotationBuilder.bending(bent, through: CGPoint(x: 180, y: 80), straightWithin: 2)
            let px = try #require(render(bent))
            let bow = (x: Int(180 - bent.frame.minX), y: Int(80 - bent.frame.minY))
            // Near it rather than on it: the hand-drawn line bows off its spine.
            var inkAtBow: UInt8 = 0
            for dx in -10...10 { for dy in -10...10 { inkAtBow = max(inkAtBow, px.alpha(bow.x + dx, bow.y + dy)) } }
            #expect(inkAtBow > 100, "\(style) left the bow empty")
            let chord = (x: Int(180 - bent.frame.minX), y: Int(200 - bent.frame.minY))
            #expect(px.alpha(chord.x, chord.y) == 0, "\(style) still paints the straight line")
            var edge = 0
            for x in 0..<px.width { edge = max(edge, Int(px.alpha(x, 0)), Int(px.alpha(x, px.height - 1))) }
            for y in 0..<px.height { edge = max(edge, Int(px.alpha(0, y)), Int(px.alpha(px.width - 1, y))) }
            #expect(edge < 40, "\(style) touches its frame's edge")
        }
    }
}
