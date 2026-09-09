import CoreGraphics
import Foundation
import PhotonzCore
@testable import PhotonzRender
import Testing

/// The pill the canvas shows you while you are still aiming the third click.
///
/// Placing a Distance caliper is three clicks and the last one parks the
/// number, but until now the canvas drew only the thin squared U while you
/// aimed: the number itself appeared after you committed, so where it would
/// land was something you learned by landing it. The preview bakes the SAME
/// pill the composite draws, once per placement, and moves it — so what these
/// tests hold is that the baked pill is the real one, at the real size.
@Suite("Measure readout preview pill")
struct MeasureReadoutPreviewTests {

    private func caliper(distance: CGFloat = 123, labelPixels: CGFloat = MeasureContent.labelFontSize,
                         mode: MeasureMode = .horizontal) -> MeasureContent {
        MeasureContent(start: CGPoint(x: 100, y: 100),
                       end: mode == .vertical ? CGPoint(x: 100, y: 100 + distance)
                                              : CGPoint(x: 100 + distance, y: 100),
                       mode: mode, strokeWidth: 2,
                       labelScale: labelPixels / MeasureContent.labelFontSize)
    }

    @Test("The preview's footprint is the footprint the composite draws")
    func footprintMatchesTheComposite() {
        for pixels in [CGFloat(8), 18, 90] {
            for distance in [CGFloat(4), 123, 1920] {
                let m = caliper(distance: distance, labelPixels: pixels)
                let drawn = PillRasterizer.footprint(for: m.chipText(pixelScale: 1),
                                                     fontSize: m.labelPointSize,
                                                     padding: m.labelPadding,
                                                     minWidth: m.labelMinPillWidth)
                #expect(MeasureRasterizer.chipFootprint(for: m, pixelScale: 1) == drawn)
            }
        }
    }

    /// The frame the builder reserves has to hold the pill the preview shows,
    /// or the number would be clipped the instant it commits.
    @Test("The reservation is never smaller than the pill it reserves for")
    func reservationHoldsTheDrawnPill() {
        for pixels in [CGFloat(8), 18, 90] {
            for distance in [CGFloat(4), 123, 1920] {
                for mode in [MeasureMode.horizontal, .vertical] {
                    let m = caliper(distance: distance, labelPixels: pixels, mode: mode)
                    let drawn = MeasureRasterizer.chipFootprint(for: m, pixelScale: 1)
                    let reserved = m.estimatedLabelSize
                    #expect(drawn.width <= reserved.width)
                    #expect(drawn.height <= reserved.height)
                }
            }
        }
    }

    @Test("A hidden readout has no pill to preview")
    func hiddenReadoutBakesNothing() {
        var m = caliper()
        m.showLabel = false
        #expect(MeasureRasterizer.chipFootprint(for: m, pixelScale: 1) == .zero)
        #expect(MeasureRasterizer.readoutPill(m, pixelScale: 1) == nil)
    }

    /// The bitmap is the pill plus room for the border's overhang on every
    /// side, so the capsule's edge is inside the picture rather than sheared
    /// off at it.
    @Test("The baked bitmap holds the pill and its border")
    func bakedBitmapHoldsTheBorder() throws {
        let m = caliper()
        let baked = try #require(MeasureRasterizer.readoutPill(m, pixelScale: 1, scale: 2))
        let chip = MeasureRasterizer.chipFootprint(for: m, pixelScale: 1)
        #expect(baked.size.width == chip.width + 2 * m.chipRenderPadding)
        #expect(baked.size.height == chip.height + 2 * m.chipRenderPadding)
        #expect(baked.image.width == Int((baked.size.width * 2).rounded()))
        #expect(baked.image.height == Int((baked.size.height * 2).rounded()))
    }

    /// The ink is the caliper's ink: the middle of the baked pill is the chip
    /// colour, not transparent and not the canvas.
    @Test("The baked pill is filled in the caliper's chip colour")
    func bakedPillIsFilled() throws {
        var m = caliper()
        m.chipColorHex = "#0000FF"
        m.chipOpacity = 1
        let baked = try #require(MeasureRasterizer.readoutPill(m, pixelScale: 1, scale: 1))
        let image = baked.image
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let context = try #require(CGContext(data: &pixels, width: width, height: height,
                                             bitsPerComponent: 8, bytesPerRow: width * 4,
                                             space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        // A pixel just inside the left cap, off the text: chip fill, opaque.
        let x = Int(m.chipRenderPadding) + 4, y = height / 2
        let i = (y * width + x) * 4
        #expect(pixels[i + 3] > 200)
        #expect(pixels[i + 2] > pixels[i])
    }
}
