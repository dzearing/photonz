import CoreGraphics
import Foundation
import Testing
import PhotonzCore
@testable import PhotonzRender

/// The join between a caliper and the number it produced.
///
/// A measurement chip has to look JOINED to the line that made it, and three
/// different pictures used to come out of the same code:
///
/// - a long measurement whose head bar curved toward the chip and then stopped
///   five points short of it, leaving a visible space;
/// - a tighter one where the whole head bar fell inside that clearance, so two
///   bare lines ended either side of the pill with no curve at all and the
///   number looked like it was floating between two unrelated lines;
/// - a short one whose chip is wider than the span it describes, where the legs
///   ran on UNDERNEATH the pill and showed through its fill.
///
/// All three are the same question — where does the caliper's ink stop? — and
/// the answer is: exactly on the pill's outline, so its round cap tucks under
/// the pill's own border and the two read as one line. These tests pin both
/// halves of that: the ink REACHES the pill (nothing separates them) and it
/// stops there (nothing shows through the pill).
@Suite("Caliper chip join")
struct MeasureChipJoinTests {

    // MARK: - Pixels

    private struct Raster {
        let image: CGImage
        let scale: CGFloat
        private let data: [UInt8]

        init(_ image: CGImage, scale: CGFloat) {
            self.image = image
            self.scale = scale
            var buffer = [UInt8](repeating: 0, count: image.width * image.height * 4)
            let context = CGContext(data: &buffer, width: image.width, height: image.height,
                                    bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            data = buffer
        }

        func pixel(_ x: Int, _ y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
            guard x >= 0, y >= 0, x < image.width, y < image.height else { return (0, 0, 0, 0) }
            let o = (y * image.width + x) * 4
            return (data[o], data[o + 1], data[o + 2], data[o + 3])
        }

        /// Caliper ink at any coverage. Premultiplied components stay
        /// red-dominant wherever a stroke only partly covers a pixel, and the
        /// readout is drawn in blue in these tests so glyphs never count.
        func isInk(_ x: Int, _ y: Int, minAlpha: UInt8 = 40) -> Bool {
            let p = pixel(x, y)
            return p.a >= minAlpha && Int(p.r) > Int(p.g) + 20 && Int(p.r) > Int(p.b) + 20
        }

        /// Document point → pixel.
        func px(_ p: CGPoint) -> (x: Int, y: Int) {
            (Int((p.x * scale).rounded()), Int((p.y * scale).rounded()))
        }
    }

    // MARK: - The caliper under test

    /// Red ink, a BLUE readout (so glyphs are never mistaken for the line) and
    /// a fully transparent chip fill (so anything drawn behind the pill shows).
    private func caliper(mode: MeasureMode, span: CGFloat, stroke: CGFloat) -> MeasureContent {
        let start = mode == .horizontal ? CGPoint(x: 60, y: 100) : CGPoint(x: 100, y: 60)
        let end = mode == .horizontal ? CGPoint(x: 60 + span, y: 100) : CGPoint(x: 100, y: 60 + span)
        var c = MeasureContent(start: start, end: end, mode: mode, strokeWidth: stroke,
                               strokeColorHex: "#FF0000", chipColorHex: "#FFFFFF",
                               chipOpacity: 0, textColorHex: "#0000FF")
        // The standoff the app itself picks, so the chip sits where a real
        // measurement puts it.
        c.headOffset = MeasureBuilder.clearingHeadOffset(content: c, from: start, to: end)
        return c
    }

    private let canvas = CGSize(width: 340, height: 340)

    private func raster(_ c: MeasureContent, scale: CGFloat = 1) -> Raster {
        Raster(MeasureRasterizer.rasterize(c, size: canvas, pixelScale: 1, scale: scale)!, scale: scale)
    }

    private func chipRect(_ c: MeasureContent) -> CGRect {
        let size = PillRasterizer.footprint(for: c.chipText(pixelScale: 1),
                                            fontSize: c.labelPointSize, padding: c.labelPadding,
                                            minWidth: c.labelMinPillWidth)
        return c.labelRect(chipSize: size)
    }

    /// Signed distance from the pill's outline: negative inside, positive out.
    private func outlineDistance(_ p: CGPoint, chip: CGRect) -> CGFloat {
        let r = min(chip.height, chip.width) / 2
        let core = chip.insetBy(dx: r, dy: r)
        let dx = max(core.minX - p.x, 0, p.x - core.maxX)
        let dy = max(core.minY - p.y, 0, p.y - core.maxY)
        return hypot(dx, dy) - r
    }

    // MARK: - Does the line reach the chip?

    /// Ink connected to `seed`, 8-connected, as a set of pixels.
    private func inkReachable(from seed: (x: Int, y: Int), in r: Raster) -> Set<Int> {
        var seen = Set<Int>()
        var stack = [seed]
        let w = r.image.width, h = r.image.height
        seen.insert(seed.y * w + seed.x)
        while let (x, y) = stack.popLast() {
            for dy in -1...1 {
                for dx in -1...1 where dx != 0 || dy != 0 {
                    let nx = x + dx, ny = y + dy
                    guard nx >= 0, ny >= 0, nx < w, ny < h else { continue }
                    let key = ny * w + nx
                    guard !seen.contains(key), r.isInk(nx, ny) else { continue }
                    seen.insert(key)
                    stack.append((nx, ny))
                }
            }
        }
        return seen
    }

    /// The inked pixel nearest `point`. A hairline caliper lands between pixel
    /// centres, so probing the exact coordinate is a coin flip; the ink is
    /// always within a pixel or two of where the geometry says it is.
    private func inkPixel(near point: CGPoint, in r: Raster) -> (x: Int, y: Int)? {
        let seed = r.px(point)
        for radius in 0...3 {
            for dy in -radius...radius {
                for dx in -radius...radius where r.isInk(seed.x + dx, seed.y + dy) {
                    return (seed.x + dx, seed.y + dy)
                }
            }
        }
        return nil
    }

    /// A pixel of the caliper's own leg, as far from the chip as the leg goes:
    /// its foot.
    private func footPixel(_ c: MeasureContent, in r: Raster) -> (x: Int, y: Int)? {
        inkPixel(near: c.caliperGeometry().footA, in: r)
    }

    /// The far side of the pill's border: ink that can only be reached by
    /// travelling through the join, since the chip's fill is transparent and
    /// the readout is a different color.
    private func farPillBorderPixel(_ c: MeasureContent, in r: Raster) -> (x: Int, y: Int)? {
        let chip = chipRect(c)
        // Opposite the feet, so the walk has to cross the join to get here.
        let away: CGPoint = c.mode == .horizontal
            ? CGPoint(x: chip.midX, y: c.headOffset >= 0 ? chip.maxY : chip.minY)
            : CGPoint(x: c.headOffset >= 0 ? chip.maxX : chip.minX, y: chip.midY)
        return inkPixel(near: away, in: r)
    }

    @Test(arguments: [
        (MeasureMode.horizontal, CGFloat(4)), (.horizontal, 12), (.horizontal, 22),
        (.horizontal, 40), (.horizontal, 70), (.horizontal, 100), (.horizontal, 200),
        (.vertical, 4), (.vertical, 12), (.vertical, 22), (.vertical, 70), (.vertical, 200),
    ])
    func theCaliperReachesItsChip(mode: MeasureMode, span: CGFloat) {
        for stroke in [CGFloat(1), 2, 6] {
            let c = caliper(mode: mode, span: span, stroke: stroke)
            let r = raster(c)
            guard let foot = footPixel(c, in: r), let target = farPillBorderPixel(c, in: r) else {
                Issue.record("\(mode) \(span)px at \(stroke)pt: no caliper ink where the geometry says it is")
                continue
            }
            let joined = inkReachable(from: foot, in: r).contains(target.y * r.image.width + target.x)
            #expect(joined,
                    "\(mode) \(span)px at \(stroke)pt: the line and the chip are separate islands of ink")
        }
    }

    @Test func theCaliperReachesItsChipWhenBakedForAZoomedInCanvas() {
        for span in [CGFloat(22), 70, 200] {
            let c = caliper(mode: .horizontal, span: span, stroke: 2)
            let r = raster(c, scale: 2)
            guard let foot = footPixel(c, in: r), let target = farPillBorderPixel(c, in: r) else {
                Issue.record("\(span)px at 2×: no caliper ink where the geometry says it is")
                continue
            }
            let joined = inkReachable(from: foot, in: r).contains(target.y * r.image.width + target.x)
            #expect(joined, "\(span)px at 2×: the line and the chip are separate islands of ink")
        }
    }

    // MARK: - And does it stop there?

    /// Every pixel far enough inside the pill that the pill's own border cannot
    /// account for it. A stroke found here is a stroke showing through the chip.
    private func inkInsideThePill(_ c: MeasureContent, in r: Raster) -> [(x: Int, y: Int)] {
        let chip = chipRect(c)
        // The border straddles the outline by half its width; a pixel of slack
        // on top of that keeps antialiasing out of the answer.
        let clearance = -(max(1, c.strokeWidth) / 2 + 1.5)
        var found: [(x: Int, y: Int)] = []
        for y in Int(chip.minY.rounded(.down))...Int(chip.maxY.rounded(.up)) {
            for x in Int(chip.minX.rounded(.down))...Int(chip.maxX.rounded(.up)) {
                let p = CGPoint(x: CGFloat(x) + 0.5, y: CGFloat(y) + 0.5)
                guard outlineDistance(p, chip: chip) < clearance else { continue }
                if r.isInk(x, y, minAlpha: 24) { found.append((x, y)) }
            }
        }
        return found
    }

    @Test(arguments: [
        (MeasureMode.horizontal, CGFloat(4)), (.horizontal, 12), (.horizontal, 22),
        (.horizontal, 40), (.horizontal, 70), (.horizontal, 100), (.horizontal, 200),
        (.vertical, 4), (.vertical, 12), (.vertical, 22), (.vertical, 70), (.vertical, 200),
    ])
    func nothingShowsThroughTheChip(mode: MeasureMode, span: CGFloat) {
        for stroke in [CGFloat(1), 2, 6] {
            let c = caliper(mode: mode, span: span, stroke: stroke)
            let leaks = inkInsideThePill(c, in: raster(c))
            let leaked = leaks.count
            #expect(leaked == 0,
                    "\(mode) \(span)px at \(stroke)pt: line shows through the chip, first at \(leaks.first ?? (0, 0))")
        }
    }

    // MARK: - Nothing else moved

    @Test func theReadoutKeepsItsValueAndItsPlace() {
        let c = caliper(mode: .horizontal, span: 100, stroke: 2)
        #expect(c.chipText(pixelScale: 1) == "100 px")
        let chip = chipRect(c)
        let g = c.caliperGeometry()
        #expect(abs(chip.midX - g.labelAnchor.x) < 0.001 && abs(chip.midY - g.labelAnchor.y) < 0.001,
                "the chip still centres on the head line's midpoint")
    }
}
