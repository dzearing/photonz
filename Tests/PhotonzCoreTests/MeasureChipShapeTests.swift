import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// A readout with one or two digits used to draw as a circle: the pill's two
/// semicircular caps met in the middle with almost no straight run between
/// them, so "4 px" and "120 px" read as two different kinds of object. The chip
/// now has a floor width in proportion to its height, and these pin the
/// reservation side of it — the room the builder sets aside has to grow with
/// the pill or the drawn border loses pixels at the frame edge.
@Suite("Measure chip shape")
struct MeasureChipShapeTests {

    /// Below the slider's floor, the default, and the slider's ceiling.
    private static let labelPixels: [CGFloat] = [8, 18, 90]

    private func caliper(_ mode: MeasureMode, distance: CGFloat,
                         labelPixels: CGFloat = MeasureContent.labelFontSize) -> MeasureContent {
        MeasureContent(start: .zero,
                       end: mode == .vertical ? CGPoint(x: 0, y: distance) : CGPoint(x: distance, y: 0),
                       mode: mode,
                       labelScale: labelPixels / MeasureContent.labelFontSize)
    }

    @Test func theFloorIsTheProportionALongerReadoutAlreadyHas() {
        let m = caliper(.horizontal, distance: 4)
        #expect(m.labelMinPillWidth == m.labelPillHeight * MeasureContent.labelBadgeAspect)
    }

    /// The floor grows with the label-size slider, so a chip is the same badge
    /// at every size. (Not exactly double at double the size: the pill's line
    /// box carries a fixed five points that does not scale.)
    @Test func theFloorGrowsWithTheLabelSize() {
        var last: CGFloat = 0
        for px in Self.labelPixels {
            let width = caliper(.horizontal, distance: 4, labelPixels: px).labelMinPillWidth
            #expect(width > last, "the floor did not grow by \(px)px")
            last = width
        }
    }

    /// One and two digit readouts: the reserved chip is a badge, not a circle.
    @Test func aShortReadoutReservesABadge() {
        for mode in [MeasureMode.horizontal, .vertical] {
            for distance in [CGFloat(4), 12] {
                for px in Self.labelPixels {
                    let m = caliper(mode, distance: distance, labelPixels: px)
                    let size = m.estimatedLabelSize
                    #expect(size.width >= m.labelMinPillWidth,
                            "\(m.chipText(pixelScale: 1)) at \(px)px reserves \(size), floor \(m.labelMinPillWidth)")
                }
            }
        }
    }

    /// A readout long enough to be a badge on its own keeps exactly the width
    /// its text asks for: the floor is a floor, never a resize.
    @Test func aLongReadoutIsUnchanged() {
        for mode in [MeasureMode.horizontal, .vertical] {
            for distance in [CGFloat(120), 4321] {
                for px in Self.labelPixels {
                    let m = caliper(mode, distance: distance, labelPixels: px)
                    let chars = CGFloat(String(Int(distance)).count + 4)
                    let text = (chars * m.labelPointSize * 0.62 + 2 * m.labelPadding).rounded(.up)
                    #expect(m.estimatedLabelSize.width == text,
                            "\(m.chipText(pixelScale: 1)) at \(px)px: \(m.estimatedLabelSize.width) vs \(text)")
                }
            }
        }
    }

    /// An alignment verdict is a phrase, always far past the floor, so its
    /// reservation is untouched.
    @Test func anAlignmentVerdictIsUnchanged() {
        for px in Self.labelPixels {
            var m = caliper(.horizontal, distance: 120, labelPixels: px)
            m.alignment = AlignmentCheck(items: [])
            let size = m.estimatedLabelSize
            #expect(size.width > m.labelMinPillWidth, "verdict at \(px)px reserves \(size)")
        }
    }
}
