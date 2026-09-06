import CoreGraphics
import Foundation
import PhotonzCore
@testable import PhotonzRender
import Testing

/// The drawn readout is a badge at every length.
///
/// "4 px" used to come out 55 wide by 42 tall: with the corner radius at half
/// the short side, the two caps left barely a dozen points of straight run, so
/// a short measurement drew a circle while "120 px" beside it drew a capsule.
/// The pill now has a floor width of 1.7x its height — the proportion a three
/// digit readout already has — so every chip reads as the same object.
@Suite("Measure chip is a badge")
struct MeasureChipBadgeTests {

    /// Below the slider's floor, the default, and the slider's ceiling.
    private static let labelPixels: [CGFloat] = [8, 18, 90]

    private func caliper(_ mode: MeasureMode, distance: CGFloat,
                         labelPixels: CGFloat = MeasureContent.labelFontSize) -> MeasureContent {
        MeasureContent(start: CGPoint(x: 100, y: 100),
                       end: mode == .vertical ? CGPoint(x: 100, y: 100 + distance)
                                              : CGPoint(x: 100 + distance, y: 100),
                       mode: mode, strokeWidth: 2,
                       labelScale: labelPixels / MeasureContent.labelFontSize)
    }

    private func footprint(_ m: MeasureContent) -> CGSize {
        PillRasterizer.footprint(for: m.chipText(pixelScale: 1), fontSize: m.labelPointSize,
                                 padding: m.labelPadding, minWidth: m.labelMinPillWidth)
    }

    // MARK: - The footprint the rasterizer draws

    /// One digit and two digit readouts, at every label size: the pill it
    /// draws is a badge.
    @Test func aShortReadoutDrawsAsABadge() {
        for distance in [CGFloat(0), 4, 12] {
            for px in Self.labelPixels {
                let m = caliper(.horizontal, distance: distance, labelPixels: px)
                let size = footprint(m)
                #expect(size.width >= size.height * MeasureContent.labelBadgeAspect,
                        "\(m.chipText(pixelScale: 1)) at \(px)px draws \(size)")
            }
        }
    }

    /// A long readout is exactly the size it was: text plus padding, untouched.
    @Test func aLongReadoutKeepsItsMeasuredWidth() {
        for distance in [CGFloat(120), 4321] {
            for px in Self.labelPixels {
                let m = caliper(.horizontal, distance: distance, labelPixels: px)
                let text = PillRasterizer.footprint(for: m.chipText(pixelScale: 1),
                                                    fontSize: m.labelPointSize,
                                                    padding: m.labelPadding)
                #expect(footprint(m) == text,
                        "\(m.chipText(pixelScale: 1)) at \(px)px: \(footprint(m)) vs \(text)")
            }
        }
    }

    /// The reservation the builder makes still holds the pill the rasterizer
    /// draws, now that both have a floor.
    @Test func theReservationStillHoldsTheDrawnPill() {
        for mode in [MeasureMode.horizontal, .vertical] {
            for distance in [CGFloat(0), 4, 12, 120, 4321] {
                for px in Self.labelPixels {
                    let m = caliper(mode, distance: distance, labelPixels: px)
                    let real = footprint(m), estimate = m.estimatedLabelSize
                    #expect(real.width <= estimate.width && real.height <= estimate.height,
                            "\(m.chipText(pixelScale: 1)) at \(px)px: \(real) vs \(estimate)")
                }
            }
        }
    }

    // MARK: - The pixels

    /// The chip fill's bounding box, found by its own color: the caliper is
    /// drawn in red with a solid green chip, so the pill is the only green
    /// thing in the picture.
    private func chipInk(_ m: MeasureContent, size: CGSize) -> CGRect? {
        var c = m
        c.strokeColorHex = "#FF0000"
        c.chipColorHex = "#00FF00"
        c.chipOpacity = 1
        c.textColorHex = "#0000FF"
        guard let image = MeasureRasterizer.rasterize(c, size: size, pixelScale: 1) else { return nil }
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        var minX = w, minY = h, maxX = -1, maxY = -1
        for y in 0..<h {
            for x in 0..<w {
                let o = (y * w + x) * 4
                let (r, g, b, a) = (Int(data[o]), Int(data[o + 1]), Int(data[o + 2]), Int(data[o + 3]))
                guard a > 200, g > r + 40, g > b + 40 else { continue }
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= 0 else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    /// One digit, two digits, and a long readout, in pixels: the short ones
    /// are floored to the badge proportion and the long one is left alone.
    @Test(arguments: [CGFloat(4), 12, 999])
    func theDrawnChipIsABadge(distance: CGFloat) {
        for mode in [MeasureMode.horizontal, .vertical] {
            let m = caliper(mode, distance: distance, labelPixels: 18)
            guard let ink = chipInk(m, size: CGSize(width: 1200, height: 1200)) else {
                Issue.record("\(mode) \(distance): no chip drawn")
                continue
            }
            let expected = footprint(m)
            // The fill stops on the pill's outline; the border straddles it, so
            // the green runs a hairline shy of the full footprint.
            #expect(abs(ink.width - expected.width) <= 3 && abs(ink.height - expected.height) <= 3,
                    "\(mode) \(m.chipText(pixelScale: 1)): drew \(ink.size), planned \(expected)")
            #expect(ink.width >= ink.height * MeasureContent.labelBadgeAspect,
                    "\(mode) \(m.chipText(pixelScale: 1)): drew \(ink.size), a circle not a badge")
        }
    }
}
