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
        for style in ArrowStyle.allCases where style.drawsOwnInk {
            let px = try #require(render(layer(style)))
            #expect(px.data != clean.data, "\(style)")
        }
    }

    /// Two renders of the same arrow are the same pixels: nothing wobbles.
    @Test func theSameArrowRendersTheSamePixels() throws {
        for style in ArrowStyle.allCases where style.drawsOwnInk {
            let a = try #require(render(layer(style)))
            let b = try #require(render(layer(style)))
            #expect(a.data == b.data, "\(style)")
        }
    }

    /// The bitmap's outermost row and column are empty: the frame holds the
    /// whole drawing, so nothing is clipped at its edge.
    @Test func nothingIsClippedAtTheFrame() throws {
        for style in ArrowStyle.allCases where style.drawsOwnInk {
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
        for style in ArrowStyle.allCases where style.drawsOwnInk {
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
        for style in ArrowStyle.allCases where style.drawsOwnInk {
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
        // Neon's glow and core go on top of its line by design
        // (`neonGlowsAndHasABrightCore`).
        for style in ArrowStyle.allCases where style.drawsOwnInk && !style.glows {
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
        // Elbow is a right-angle connector: a bend picks its corner instead.
        for style in ArrowStyle.allCases where style != .elbow {
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

    // MARK: - The five exact styles

    /// Neon glows: soft ink well clear of the line on both sides, fading
    /// out, and a centre lighter than its edge.
    @Test func neonGlowsAndHasABrightCore() throws {
        let built = layer(.neon, width: 4, from: CGPoint(x: 30, y: 100), to: CGPoint(x: 330, y: 100))
        let neon = try #require(render(built))
        let clean = try #require(render(layer(.clean, width: 4, from: CGPoint(x: 30, y: 100),
                                              to: CGPoint(x: 330, y: 100))))
        guard let content = built.annotation else { return }
        let x = Int(content.start.x + 120)
        let y = Int(content.start.y.rounded())
        // Halo: half a line beyond the line's edge (1.6 widths across) and
        // further, there is still some ink, less the further out.
        let near = neon.alpha(x, y + 6), far = neon.alpha(x, y + 12)
        #expect(near > 40, "near \(near)")
        #expect(far > 5 && far < near, "far \(far), near \(near)")
        #expect(neon.inkCount > clean.inkCount * 2)
        // Core: lighter (more white) in the middle than at the line's edge.
        let (r0, g0, b0, _) = neon.rgba(x, y)
        let (r1, g1, b1, _) = neon.rgba(x, y + 3)
        #expect(Int(g0) + Int(b0) > Int(g1) + Int(b1) + 60, "centre \(r0),\(g0),\(b0) edge \(r1),\(g1),\(b1)")
    }

    /// Dashed leaves real gaps along the line; Dotted leaves more.
    @Test func dashedAndDottedLeaveGaps() throws {
        func emptyRun(_ style: ArrowStyle) throws -> Double {
            let built = layer(style, width: 4, from: CGPoint(x: 30, y: 100), to: CGPoint(x: 330, y: 100))
            let px = try #require(render(built))
            guard let content = built.annotation else { return 0 }
            let y = Int(content.start.y.rounded())
            let xs = Int(content.start.x + 20)..<Int(content.start.x + 220)
            return Double(xs.filter { px.alpha($0, y) < 20 }.count) / Double(xs.count)
        }
        #expect(try emptyRun(.clean) == 0)
        let dashed = try emptyRun(.dashed)
        let dotted = try emptyRun(.dotted)
        #expect(dashed > 0.25 && dashed < 0.55, "dashed \(dashed)")
        #expect(dotted > dashed, "dotted \(dotted)")
    }

    /// Block is far heavier than Clean at the same thickness.
    @Test func blockIsBold() throws {
        let block = try #require(render(layer(.block)))
        let clean = try #require(render(layer(.clean)))
        #expect(Double(block.inkCount) > Double(clean.inkCount) * 1.8)
    }

    /// An elbow paints its corner and leaves the straight line between its
    /// ends empty.
    @Test func anElbowPaintsItsCornerNotTheDiagonal() throws {
        let built = layer(.elbow, from: CGPoint(x: 30, y: 40), to: CGPoint(x: 330, y: 240))
        let px = try #require(render(built))
        let corner = (x: Int(330 - built.frame.minX), y: Int(40 - built.frame.minY))
        var atCorner: UInt8 = 0
        for dx in -12...0 { for dy in 0...12 { atCorner = max(atCorner, px.alpha(corner.x + dx, corner.y + dy)) } }
        #expect(atCorner > 100)
        let middle = (x: Int(180 - built.frame.minX), y: Int(140 - built.frame.minY))
        #expect(px.alpha(middle.x, middle.y) == 0)
    }
}
