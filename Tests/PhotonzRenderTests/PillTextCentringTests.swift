import CoreGraphics
import Foundation
import PhotonzCore
@testable import PhotonzRender
import Testing

/// Where the WORDS sit inside a pill, measured off real pixels.
///
/// The text used to sit about two points left of centre in every badge in the
/// app: the box a string is measured into carries slack on its right (rounding
/// plus the frame inset), left-aligned glyphs are drawn flush to its left edge,
/// and the pill centred that box rather than the ink inside it. Nobody names a
/// two point error, but every badge carrying one is what makes a screenshot
/// read as hand-drawn.
@Suite("Pill text centring")
struct PillTextCentringTests {

    /// A rendered field of pixels, plus the ink bounds of whatever color a
    /// caller asks about.
    private struct Raster {
        let data: [UInt8]
        let width: Int
        let height: Int

        func bounds(_ matches: (_ r: Int, _ g: Int, _ b: Int, _ a: Int) -> Bool) -> CGRect? {
            var minX = width, minY = height, maxX = -1, maxY = -1
            for y in 0..<height {
                for x in 0..<width {
                    let o = (y * width + x) * 4
                    guard matches(Int(data[o]), Int(data[o + 1]), Int(data[o + 2]), Int(data[o + 3]))
                    else { continue }
                    minX = min(minX, x); maxX = max(maxX, x)
                    minY = min(minY, y); maxY = max(maxY, y)
                }
            }
            guard maxX >= minX, maxY >= minY else { return nil }
            return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
        }
    }

    private func read(_ image: CGImage) -> Raster? {
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return Raster(data: data, width: w, height: h)
    }

    /// Green pill, blue text, so each can be found by its own color.
    private static let pillFill = CGColor(srgbRed: 0, green: 1, blue: 0, alpha: 1)
    private static let textHex = "#0000FF"

    private func isPill(_ r: Int, _ g: Int, _ b: Int, _ a: Int) -> Bool {
        a > 200 && g > r + 40 && g > b + 40
    }

    private func isText(_ r: Int, _ g: Int, _ b: Int, _ a: Int) -> Bool {
        a > 200 && b > r + 40 && b > g + 40
    }

    /// How far the glyphs' ink centre sits from the pill's, in POINTS.
    /// Positive is to the right. Nil when either was not drawn.
    ///
    /// `deviceScale` is how many pixels the pill is baked with per point — the
    /// same lever a zoomed-in canvas pulls. Small type is measured at 3, not
    /// because the app is wrong at 1 but because a ten point "i" is three
    /// pixels of grey: thresholding it back into a bounding box cannot resolve
    /// a point either way, so the picture is drawn bigger to read it.
    private func glyphOffCentre(_ string: String, fontSize: CGFloat,
                                deviceScale: CGFloat = 1) -> CGFloat? {
        let padding = fontSize * MeasureContent.labelPadding / MeasureContent.labelFontSize
        let pill = PillRasterizer.footprint(for: string, fontSize: fontSize, padding: padding,
                                            minWidth: fontSize * 3)
        let points = CGSize(width: (pill.width + 40).rounded(.up),
                            height: (pill.height + 40).rounded(.up))
        let width = Int(points.width * deviceScale), height = Int(points.height * deviceScale)
        guard let context = CGContext(data: nil, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        // The rasterizers draw in flipped (top-left) space, in document points.
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: deviceScale, y: -deviceScale)
        PillRasterizer.draw(string, at: CGPoint(x: points.width / 2, y: points.height / 2),
                            chipSize: pill, fontSize: fontSize, borderWidth: 2,
                            fill: Self.pillFill, border: Self.pillFill,
                            textColorHex: Self.textHex, in: context)
        guard let image = context.makeImage(), let px = read(image),
              let pillInk = px.bounds(isPill), let textInk = px.bounds(isText) else { return nil }
        return (textInk.midX - pillInk.midX) / deviceScale
    }

    // MARK: - The caption pill

    /// One character, two characters and a whole sentence: the ink of the word
    /// lands on the middle of its pill, at every caption size the app offers.
    @Test func aWordSitsInTheMiddleOfItsPill() {
        for string in ["H", "1", "Hi", "12", "A much longer caption"] {
            for fontSize in [CGFloat(10), 20, 48] {
                guard let off = glyphOffCentre(string, fontSize: fontSize, deviceScale: 3) else {
                    Issue.record("\(string.debugDescription) at \(fontSize) drew no glyphs")
                    continue
                }
                #expect(abs(off) <= 1,
                        "\(string.debugDescription) at \(fontSize) sits \(off) off centre")
            }
        }
    }

    /// The same words, baked at the resolution a document raster uses. Sliding
    /// the glyphs is rounded to a whole pixel there, so this is the one that
    /// would catch a half point of rounding turning into a visible one.
    @Test func aWordStaysCentredAtDocumentResolution() {
        for string in ["H", "1", "Hi", "12", "A much longer caption"] {
            for fontSize in [CGFloat(20), 48] {
                guard let off = glyphOffCentre(string, fontSize: fontSize) else {
                    Issue.record("\(string.debugDescription) at \(fontSize) drew no glyphs")
                    continue
                }
                #expect(abs(off) <= 1,
                        "\(string.debugDescription) at \(fontSize) sits \(off) off centre")
            }
        }
    }

    /// The centring moves the words, never the pill: the footprint a caption
    /// reserves is the footprint it draws.
    @Test func thePillsOwnSizeDoesNotChange() {
        // The numbers the pill sized itself with before the words moved. Any
        // change here is a re-layout of every caption and chip in a document.
        let expected: [String: CGFloat] = ["H": 35, "Hi": 39, "A much longer caption": 217]
        for (string, width) in expected {
            let pill = PillRasterizer.footprint(for: string, fontSize: 20, padding: 8)
            #expect(pill.width == width, "\(string.debugDescription) footprint is \(pill)")
        }
    }

    // MARK: - The measurement chip

    private func caliper(distance: CGFloat) -> MeasureContent {
        var m = MeasureContent(start: CGPoint(x: 100, y: 100),
                               end: CGPoint(x: 100 + distance, y: 100),
                               mode: .horizontal, strokeWidth: 2)
        m.strokeColorHex = "#FF0000"
        m.chipColorHex = "#00FF00"
        m.chipOpacity = 1
        m.textColorHex = Self.textHex
        return m
    }

    /// A measurement reads out of the same badge, so its digits are centred
    /// the same way — one digit, two digits and three.
    @Test(arguments: [CGFloat(4), 12, 999])
    func aMeasurementSitsInTheMiddleOfItsChip(distance: CGFloat) {
        guard let image = MeasureRasterizer.rasterize(caliper(distance: distance),
                                                      size: CGSize(width: 1200, height: 1200),
                                                      pixelScale: 1),
              let px = read(image), let pill = px.bounds(isPill), let text = px.bounds(isText) else {
            Issue.record("\(distance): no chip drawn")
            return
        }
        #expect(abs(text.midX - pill.midX) <= 1,
                "\(distance)px reads \(text.midX - pill.midX) off centre")
    }
}
