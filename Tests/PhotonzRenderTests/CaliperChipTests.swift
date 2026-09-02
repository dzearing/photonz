import CoreGraphics
import Foundation
import PhotonzCore
@testable import PhotonzRender
import Testing

/// A caliper's number is set by the rasterizer, but the room the builder
/// reserves for it is an estimate. These pin the estimate against the real
/// pill the rasterizer draws (the way `AlignmentChipTests` does for guides), so
/// a readout parked past the end of its caliper never loses a border pixel in
/// an export.
@Suite("Caliper chip on the canvas")
struct CaliperChipTests {

    /// Label sizes in pixels: below the slider's floor, the default, and the
    /// slider's ceiling (scale 5).
    private static let labelPixels: [CGFloat] = [8, 18, 90]

    private func caliper(_ mode: MeasureMode, distance: CGFloat, labelPixels: CGFloat,
                         strokeWidth: CGFloat = 1) -> MeasureContent {
        MeasureContent(start: .zero,
                       end: mode == .vertical ? CGPoint(x: 0, y: distance) : CGPoint(x: distance, y: 0),
                       mode: mode, strokeWidth: strokeWidth,
                       labelScale: labelPixels / MeasureContent.labelFontSize)
    }

    /// Every digit count the readout can show, at the three label sizes, in
    /// both orientations: the real pill fits inside the reservation.
    @Test func theReservationHoldsTheRealPillAtEveryLabelSize() {
        for mode in [MeasureMode.horizontal, .vertical] {
            for distance in [CGFloat(7), 42, 999, 4321] {
                for px in Self.labelPixels {
                    let m = caliper(mode, distance: distance, labelPixels: px)
                    let text = m.chipText(pixelScale: 1)
                    let real = PillRasterizer.footprint(for: text, fontSize: m.labelPointSize,
                                                        padding: m.labelPadding)
                    let estimate = m.estimatedLabelSize
                    #expect(real.width <= estimate.width, "\(text) at \(px)px: \(real) vs \(estimate)")
                    #expect(real.height <= estimate.height, "\(text) at \(px)px: \(real) vs \(estimate)")
                }
            }
        }
    }

    /// The bounding box of every pixel with any ink, or nil for a blank image.
    private func inkBounds(_ image: CGImage) -> CGRect? {
        let width = image.width, height = image.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(data: &data, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return nil
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            for x in 0..<width where data[(y * width + x) * 4 + 3] > 0 {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= 0 else { return nil }
        // Drawing an image into a fresh context lays its rows out top-down, the
        // same top-left space the layer uses.
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    /// A caliper whose readout rides its head line, past the feet: the pill is
    /// the outermost thing in the layer. Drawn with room to spare on every
    /// side, its ink must still land inside the frame the builder reserved,
    /// so the export (which stops at the frame) shows the whole border.
    @Test func theExportedPillKeepsItsWholeBorderPastTheEnd() {
        for mode in [MeasureMode.horizontal, .vertical] {
            for px in Self.labelPixels {
                for stroke in [CGFloat(1), 3] {
                    let m = caliper(mode, distance: 240, labelPixels: px, strokeWidth: stroke)
                    let start = CGPoint(x: 40, y: 40)
                    let end = mode == .vertical ? CGPoint(x: 40, y: 280) : CGPoint(x: 280, y: 40)
                    let layer = MeasureBuilder.layer(content: m, from: start, to: end)
                    guard var local = layer.measure else {
                        Issue.record("built layer lost its measure")
                        return
                    }
                    let room: CGFloat = 40
                    local.start = CGPoint(x: local.start.x + room, y: local.start.y + room)
                    local.end = CGPoint(x: local.end.x + room, y: local.end.y + room)
                    let roomy = CGSize(width: layer.frame.width + room * 2,
                                       height: layer.frame.height + room * 2)
                    guard let image = MeasureRasterizer.rasterize(local, size: roomy, pixelScale: 1),
                          let ink = inkBounds(image) else {
                        Issue.record("nothing drawn for \(mode) at \(px)px")
                        return
                    }
                    let frame = CGRect(x: room, y: room, width: layer.frame.width, height: layer.frame.height)
                    #expect(frame.contains(ink),
                            "\(mode) at \(px)px, stroke \(stroke): ink \(ink) spills out of \(frame)")
                }
            }
        }
    }
}
