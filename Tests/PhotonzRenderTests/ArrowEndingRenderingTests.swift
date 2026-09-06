import CoreGraphics
import Foundation
import Testing
import PhotonzCore
@testable import PhotonzRender

/// What each ending actually PUTS ON SCREEN, measured off real pixels rather
/// than reasoned about from the path. A filled head and an open one describe
/// the same three points; only the ink tells them apart.
@Suite("Arrow endings on screen")
struct ArrowEndingRenderingTests {

    private let size = CGSize(width: 220, height: 130)
    /// A long horizontal arrow, so the head is at its full size and every
    /// sample point below can be worked out by hand.
    private let tail = CGPoint(x: 40, y: 60)
    private let tip = CGPoint(x: 160, y: 60)

    private func render(_ style: ArrowheadStyle, strokeWidth: CGFloat = 4)
        -> (data: [UInt8], width: Int, height: Int)? {
        var content = AnnotationContent(shape: .arrow, strokeWidth: strokeWidth,
                                        colorHex: "#FF3B30", start: tail, end: tip)
        content.arrowheadStyle = style
        guard let image = AnnotationRasterizer.rasterize(content, size: size) else { return nil }
        let width = image.width, height = image.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        guard let read = CGContext(data: &data, width: width, height: height,
                                   bitsPerComponent: 8, bytesPerRow: width * 4,
                                   space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                   bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        read.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return (data, width, height)
    }

    /// Whether there is ink at a point in the annotation's own (top-left)
    /// coordinates — the same numbers `start` and `end` are stated in.
    private func inked(_ px: (data: [UInt8], width: Int, height: Int), _ point: CGPoint) -> Bool {
        let x = Int(point.x.rounded()), y = Int(point.y.rounded())
        guard x >= 0, y >= 0, x < px.width, y < px.height else { return false }
        return px.data[(y * px.width + x) * 4 + 3] > 40
    }

    /// Inside the head's body, well off the shaft: filled for a solid head,
    /// empty for an open one.
    private let insideTheHead = CGPoint(x: 140, y: 64)
    /// A hair inside the head's lower edge, halfway from tip to wing: under
    /// the open head's stroke, and inside the solid one's body.
    private let onTheHeadsEdge = CGPoint(x: 145, y: 66)
    /// Past the point the arrow marks: only a dot reaches here.
    private let pastThePoint = CGPoint(x: 168, y: 60)

    @Test func aSolidHeadIsFilledIn() throws {
        let px = try #require(render(.triangle))
        #expect(inked(px, insideTheHead))
        #expect(inked(px, onTheHeadsEdge))
        #expect(!inked(px, pastThePoint), "a triangle's tip is the furthest it goes")
    }

    @Test func anOpenHeadIsAnOutlineWithNothingInIt() throws {
        let px = try #require(render(.open))
        #expect(inked(px, onTheHeadsEdge), "the two fine strokes are there")
        #expect(!inked(px, insideTheHead), "and nothing is filled in behind them")
    }

    @Test func aPlainEndingDrawsNoHeadAtAll() throws {
        let px = try #require(render(.plain))
        #expect(!inked(px, insideTheHead))
        #expect(!inked(px, onTheHeadsEdge))
        #expect(!inked(px, pastThePoint))
        #expect(inked(px, CGPoint(x: 158, y: 60)), "but the line still reaches the point")
    }

    @Test func aSolidDotSitsOnThePointAndIsFilled() throws {
        let px = try #require(render(.dot))
        #expect(inked(px, tip))
        #expect(inked(px, pastThePoint), "the dot is centred on the point, so it reaches past it")
        #expect(inked(px, CGPoint(x: 160, y: 68)), "and above and below it too")
    }

    /// The point of a hollow dot is that what it marks shows through, so the
    /// shaft must stop on its near edge instead of skewering it.
    @Test func aHollowDotStaysHollow() throws {
        let px = try #require(render(.hollowDot))
        #expect(!inked(px, tip), "the middle is clear")
        let circle = try #require(Geometry.arrowheadCircle(at: tip, strokeWidth: 4, scale: 1,
                                                           style: .hollowDot))
        #expect(inked(px, CGPoint(x: tip.x + circle.radius, y: tip.y)), "and the ring is drawn")
        #expect(inked(px, CGPoint(x: tip.x, y: tip.y - circle.radius)))
    }

    /// The layer the arrow is drawn into has to make room for whatever it ends
    /// in, or the ending is sliced off at the edge.
    @Test func aDotIsNotClippedByItsOwnLayer() throws {
        var content = AnnotationContent(shape: .arrow, strokeWidth: 4,
                                        start: .zero, end: CGPoint(x: 120, y: 0))
        content.arrowheadStyle = .dot
        let pad = content.renderPadding
        let circle = try #require(Geometry.arrowheadCircle(at: content.end, strokeWidth: 4,
                                                           scale: 1, style: .dot))
        #expect(pad >= circle.radius)
    }
}

/// The caption pill's corner, from square through badge to full pill.
@Suite("Caption pill corner")
struct CaptionCornerRenderingTests {

    /// Renders one arrow's caption pill on its own and reports where the pill
    /// sits in the bitmap, so a corner can be probed.
    private func render(roundness: CGFloat)
        -> (data: [UInt8], width: Int, height: Int, pill: CGRect)? {
        var content = AnnotationContent(shape: .arrow, strokeWidth: 4, colorHex: "#FF3B30")
        content.caption = "Login button"
        content.captionRoundness = roundness
        guard let (image, size) = AnnotationRasterizer.captionPill(content) else { return nil }
        let chip = CaptionMetrics.pillSize(for: "Login button", in: content)
        let pill = CGRect(x: (size.width - chip.width) / 2, y: (size.height - chip.height) / 2,
                          width: chip.width, height: chip.height)
        let width = image.width, height = image.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        guard let read = CGContext(data: &data, width: width, height: height,
                                   bitsPerComponent: 8, bytesPerRow: width * 4,
                                   space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                   bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        read.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return (data, width, height, pill)
    }

    private func alpha(_ px: (data: [UInt8], width: Int, height: Int, pill: CGRect),
                       _ point: CGPoint) -> UInt8 {
        let x = Int(point.x.rounded()), y = Int(point.y.rounded())
        guard x >= 0, y >= 0, x < px.width, y < px.height else { return 0 }
        return px.data[(y * px.width + x) * 4 + 3]
    }

    /// A point just inside the pill's top-left corner: covered when the corner
    /// is square, cut away when it is a full capsule.
    private func corner(_ pill: CGRect) -> CGPoint {
        CGPoint(x: pill.minX + 2, y: pill.minY + 2)
    }

    @Test func aSquareCornerFillsItsCorner() throws {
        let px = try #require(render(roundness: 0))
        #expect(alpha(px, corner(px.pill)) > 40)
    }

    @Test func aFullPillCutsThatCornerAway() throws {
        let px = try #require(render(roundness: 1))
        #expect(alpha(px, corner(px.pill)) < 20,
                "a capsule's cap curves well inside the box's corner")
    }

    /// The shape a label wears has to be the shape the app remembers, not a
    /// coincidence of the drawing order: fully round is what an unchanged
    /// caption still draws.
    @Test func fullyRoundIsWhatAnUntouchedCaptionDraws() throws {
        let untouched = try #require(render(roundness: AnnotationContent.captionRoundnessDefault))
        let full = try #require(render(roundness: 1))
        #expect(untouched.data == full.data)
    }
}
