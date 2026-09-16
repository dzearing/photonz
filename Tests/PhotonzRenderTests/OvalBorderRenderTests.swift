import CoreGraphics
import Foundation
import Testing
import PhotonzCore
@testable import PhotonzRender

/// A border round an OVAL follows the oval.
///
/// Two complaints, one geometry. The background showed through along the
/// inside of an outside border, round the diagonals of a stretched oval; and
/// the line itself drifted, sitting closer to the curve on the flanks than on
/// the ends. Both come from the ring being built out of ovals inset from each
/// other, or from a stroke ridden round a middle oval, neither of which is the
/// curve a person means by "eight points outside this shape".
///
/// The curve they mean is the OFFSET curve: every point exactly the border's
/// width away from the shape's own edge. That is already what a border round a
/// PATH follows, which is why the last test here — turn the oval into a path
/// and the picture must not move — is the one that pins the rest down.
@Suite("Oval borders")
struct OvalBorderRenderTests {

    private let canvas = CGSize(width: 320, height: 220)
    /// A 2:1 oval: stretched enough that an oval inset inside it and the real
    /// offset curve are visibly different things.
    private let box = CGRect(x: 40, y: 50, width: 240, height: 120)
    /// A pixel carrying less than this of a channel is rounding, not a leak.
    private let noise = 6

    // MARK: - Building the picture

    private func background() -> Layer {
        let frame = CGRect(origin: .zero, size: canvas)
        let fill = AnnotationContent(shape: .rectangle, strokeWidth: 0, colorHex: "#00FF00",
                                     start: .zero,
                                     end: CGPoint(x: frame.width, y: frame.height),
                                     fillColorHex: "#00FF00")
        return Layer(name: "Sheet", content: .annotation(fill), frame: frame, style: LayerStyle())
    }

    private func oval(_ box: CGRect, _ border: BorderEffect) -> Layer {
        var style = LayerStyle()
        style.effects = [.border(border)]
        let fill = AnnotationContent(shape: .ellipse, strokeWidth: 0, colorHex: "#FF0000",
                                     start: .zero,
                                     end: CGPoint(x: box.width, y: box.height),
                                     fillColorHex: "#FF0000")
        return Layer(name: "Oval", content: .annotation(fill), frame: box, style: style)
    }

    private func render(_ layer: Layer, scale: CGFloat = 1) -> CGImage {
        var document = PhotonzDocument(canvasSize: canvas)
        document.addLayer(background())
        document.addLayer(layer)
        let renderer = DocumentRenderer()
        return renderer.render(document, store: ImageStore(), scale: scale)!
    }

    private func render(_ box: CGRect, _ border: BorderEffect, scale: CGFloat = 1) -> CGImage {
        render(oval(box, border), scale: scale)
    }

    // MARK: - Reading it back

    private func pixels(_ image: CGImage) -> [UInt8] {
        var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = CGContext(data: &data, width: image.width, height: image.height,
                                bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return data
    }

    /// Every pixel carrying some fill AND some background at once: the border
    /// failed to separate them there.
    private func mixed(_ image: CGImage) -> [(x: Int, y: Int, r: Int, g: Int)] {
        let data = pixels(image)
        var found: [(x: Int, y: Int, r: Int, g: Int)] = []
        for y in 0..<image.height {
            for x in 0..<image.width {
                let i = (y * image.width + x) * 4
                let r = Int(data[i]), g = Int(data[i + 1])
                if r > noise && g > noise { found.append((x, y, r, g)) }
            }
        }
        return found.sorted { min($0.r, $0.g) > min($1.r, $1.g) }
    }

    private func describe(_ leaks: [(x: Int, y: Int, r: Int, g: Int)]) -> String {
        let worst = leaks.prefix(5).map { "(\($0.x),\($0.y)) r=\($0.r) g=\($0.g)" }
        return "\(leaks.count) mixed pixels, worst: \(worst.joined(separator: ", "))"
    }

    /// How far the border reaches out from the fill, measured all the way
    /// round: for every pixel that is still pure background, the distance to
    /// the nearest pixel that is still pure fill.
    ///
    /// The SMALLEST of those, over the whole picture, is how thin the border
    /// gets at its thinnest. On a ring that follows the offset curve it is the
    /// border's width wherever you stand; on a ring built from an oval inset
    /// inside another it dips round the diagonals.
    private func thinnestReach(_ image: CGImage, scale: CGFloat = 1) -> CGFloat {
        let data = pixels(image)
        let w = image.width, h = image.height
        var fill: [CGPoint] = []
        var backEdge: [CGPoint] = []
        func at(_ x: Int, _ y: Int) -> (Int, Int) {
            let i = (y * w + x) * 4
            return (Int(data[i]), Int(data[i + 1]))
        }
        for y in 0..<h {
            for x in 0..<w {
                let (r, g) = at(x, y)
                if r > 250 && g < noise { fill.append(CGPoint(x: x, y: y)) }
                if r < noise && g > 250 {
                    // Only background right up against the ring is interesting;
                    // the open field far away says nothing.
                    var touchesRing = false
                    for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                        let nx = x + dx, ny = y + dy
                        guard nx >= 0, nx < w, ny >= 0, ny < h else { continue }
                        let (nr, ng) = at(nx, ny)
                        if nr < 250 && ng < 250 { touchesRing = true }
                    }
                    if touchesRing { backEdge.append(CGPoint(x: x, y: y)) }
                }
            }
        }
        guard !fill.isEmpty, !backEdge.isEmpty else { return 0 }
        var thinnest = CGFloat.greatestFiniteMagnitude
        for b in backEdge {
            var best = CGFloat.greatestFiniteMagnitude
            for f in fill {
                let dx = b.x - f.x, dy = b.y - f.y
                let d = dx * dx + dy * dy
                if d < best { best = d }
            }
            thinnest = min(thinnest, best.squareRoot())
        }
        return thinnest / scale
    }

    // MARK: - No background against the fill

    @Test("A stretched oval's outside border leaves no background against the fill")
    func outsideBorderOnAStretchedOvalIsClean() {
        let image = render(box, BorderEffect(width: 8, colorHex: "#000000", position: .outside))
        let leaks = mixed(image)
        #expect(leaks.isEmpty, "\(describe(leaks))")
    }

    @Test("It stays clean at every zoom", arguments: [CGFloat(1.5), 2, 2.75, 4])
    func outsideBorderCleanAtZoom(_ scale: CGFloat) {
        let image = render(box, BorderEffect(width: 8, colorHex: "#000000", position: .outside),
                           scale: scale)
        let leaks = mixed(image)
        #expect(leaks.isEmpty, "at \(scale)x: \(describe(leaks))")
    }

    @Test("A thin outside border on a stretched oval is clean too")
    func thinOutsideBorderIsClean() {
        let image = render(box, BorderEffect(width: 3, colorHex: "#000000", position: .outside),
                           scale: 3)
        let leaks = mixed(image)
        #expect(leaks.isEmpty, "\(describe(leaks))")
    }

    // MARK: - The same distance from the curve all the way round

    @Test("A border on a 2:1 oval stands its full width from the curve all the way round")
    func borderKeepsItsWidthAllTheWayRound() {
        let width: CGFloat = 8
        let image = render(box, BorderEffect(width: width, colorHex: "#000000",
                                             position: .outside), scale: 2)
        // A pixel of slack for the grid itself: the nearest whole pixel of
        // fill is up to a pixel inside the fill's real edge.
        let reach = thinnestReach(image, scale: 2)
        #expect(reach >= width - 1.0, "thinnest reach \(reach) of \(width)")
    }

    @Test("A circle's border keeps its width all the way round, as it always did")
    func circleBorderKeepsItsWidth() {
        let circle = CGRect(x: 60, y: 40, width: 140, height: 140)
        let width: CGFloat = 8
        let image = render(circle, BorderEffect(width: width, colorHex: "#000000",
                                                position: .outside), scale: 2)
        let reach = thinnestReach(image, scale: 2)
        #expect(reach >= width - 1.0, "thinnest reach \(reach) of \(width)")
        #expect(mixed(image).isEmpty, "\(describe(mixed(image)))")
    }

    // MARK: - An oval and the same oval as a path draw the same picture

    @Test("Turning an oval into a path leaves the picture where it was",
          arguments: [BorderPosition.inside, .center, .outside])
    func ovalAndItsPathAgree(_ position: BorderPosition) {
        let border = BorderEffect(width: 8, colorHex: "#000000", position: position)
        let shape = oval(box, border)
        guard let asPath = shape.turnedIntoPath() else {
            Issue.record("an oval must be able to turn into a path")
            return
        }
        let before = pixels(render(shape))
        let after = pixels(render(asPath))
        #expect(before.count == after.count)
        var worst = 0
        var offBy2 = 0
        for i in 0..<min(before.count, after.count) {
            let d = abs(Int(before[i]) - Int(after[i]))
            worst = max(worst, d)
            if d > 2 { offBy2 += 1 }
        }
        // Not byte for byte: the two are rasterized by different code paths and
        // an antialiased curve rounds differently by a step or two. What must
        // not survive is a SEAM — a line of pixels tens of levels apart.
        #expect(worst <= 24, "worst channel difference \(worst), \(offBy2) samples off by more than 2")
    }

    // MARK: - The other two things a border on an oval can be

    /// A border can stand OFF the shape, which pushes both silhouettes the
    /// same way and must leave plain fill in the gap rather than swallowing it.
    @Test("An oval's border standing off the edge leaves the fill in the gap")
    func offsetOvalBorderKeepsTheGap() {
        let image = render(box, BorderEffect(width: 6, colorHex: "#000000",
                                             position: .inside, offset: 12))
        let data = pixels(image)
        let w = image.width
        func at(_ x: Int, _ y: Int) -> (Int, Int, Int) {
            let i = (y * w + x) * 4
            return (Int(data[i]), Int(data[i + 1]), Int(data[i + 3]))
        }
        // Across the middle, left to right: fill outside the ring, then the
        // ring, then fill again inside it.
        let y = Int(box.midY)
        let outside = at(Int(box.minX) + 3, y)
        #expect(outside.0 > 200 && outside.1 < 40, "gap should still be fill, got \(outside)")
        let ring = at(Int(box.minX) + 15, y)
        #expect(ring.0 < 40 && ring.1 < 40 && ring.2 > 200, "ring should be black, got \(ring)")
        let inside = at(Int(box.minX) + 25, y)
        #expect(inside.0 > 200 && inside.1 < 40, "inside should be fill, got \(inside)")
    }

    /// A ramp poured through the band, which is a different branch from a flat
    /// colour and the one that would quietly go missing.
    @Test("A gradient border on an oval is a ramp, not a flat line")
    func gradientOvalBorderPoursARamp() {
        var border = BorderEffect(width: 10, colorHex: "#0000FF", position: .outside)
        border.paint = Paint(hex: "#0000FF", kind: .linear,
                             stops: [GradientStop(hex: "#0000FF", position: 0),
                                     GradientStop(hex: "#FFFFFF", position: 1)],
                             angle: 90)
        let image = render(box, border)
        let data = pixels(image)
        let w = image.width
        func blue(_ x: Int, _ y: Int) -> (Int, Int, Int) {
            let i = (y * w + x) * 4
            return (Int(data[i]), Int(data[i + 1]), Int(data[i + 2]))
        }
        // Left end of the ring against the right end of it: same band, two
        // ends of the ramp, so they must not be the same colour.
        let left = blue(Int(box.minX) - 5, Int(box.midY))
        let right = blue(Int(box.maxX) + 4, Int(box.midY))
        #expect(left.2 > 100, "left end of the ring should carry paint, got \(left)")
        #expect(right.2 > 100, "right end of the ring should carry paint, got \(right)")
        #expect(abs(left.0 - right.0) > 60,
                "a ramp should run across the ring: left \(left) right \(right)")
    }

    // MARK: - ...and the path route it now shares has to survive a zoom

    /// The border round a PATH reached twice as far as it was asked to on any
    /// render above 100%, ran off the edge of the bitmap it was drawn into,
    /// and came back with the overflow squared off: a circle with an 8pt
    /// border at 2x had an octagon round it, bulging out to the corners. It
    /// went unnoticed because the ring still measured right along the axes,
    /// which is where the clipping happened to land.
    @Test("A border round a path keeps its curve at every zoom",
          arguments: [CGFloat(1), 2, 3])
    func pathBorderKeepsItsCurveAtZoom(_ scale: CGFloat) {
        let circle = CGRect(x: 60, y: 40, width: 140, height: 140)
        let width: CGFloat = 8
        var path = PathContent.ellipse(in: CGRect(origin: .zero, size: circle.size))
        path.fill = Paint(hex: "#FF0000")
        path.strokeWidth = 0
        var style = LayerStyle()
        style.effects = [.border(BorderEffect(width: width, colorHex: "#000000",
                                              position: .outside))]
        let image = render(Layer(name: "P", content: .path(path), frame: circle, style: style),
                           scale: scale)
        let data = pixels(image)
        let center = CGPoint(x: circle.midX * scale, y: circle.midY * scale)
        let reach = (circle.width / 2 + width) * scale
        // Straight out along the diagonal, which is where the squared-off
        // corner was: the ring must stop where a circle of that radius stops.
        var last: CGFloat = 0
        var step: CGFloat = 0
        while step < reach * 2 {
            let x = Int((center.x + step * 0.70710678).rounded())
            let y = Int((center.y + step * 0.70710678).rounded())
            guard x >= 0, x < image.width, y >= 0, y < image.height else { break }
            let i = (y * image.width + x) * 4
            if Int(data[i]) < 40 && Int(data[i + 1]) < 40 && Int(data[i + 3]) > 200 { last = step }
            step += 0.25
        }
        #expect(abs(last - reach) <= 2,
                "at \(scale)x the ring reaches \(last) on the diagonal, asked for \(reach)")
    }
}
