import CoreGraphics
import CoreImage
import Foundation
import PhotonzCore
@testable import PhotonzRender
import Testing

/// Words set tighter than their own letters stay hidden behind their mask
/// until their beat (task `keynote-clean-soft-gradient-glass-kinetic-bold-t`).
///
/// A mask reveal slides each word up out from behind its own line box. Set at
/// a leading under the face's own height (condensed capitals stacked at 0.78,
/// as a poster stacks them) the letters stand taller than that box, and a word
/// slid down by only the box's height left the tops of its capitals inside
/// the mask: thin dashes on the title's first frame, before anything should
/// show. Seen on Condensed Poster's first frame on 2026-11-21.
@Suite("A mask reveal hides words set tighter than their letters")
struct MaskRevealTightLeadingTests {

    static let context = CIContext(options: [.useSoftwareRenderer: true, .workingColorSpace: NSNull(),
                                             .outputColorSpace: NSNull(),
                                             .workingFormat: NSNumber(value: CIFormat.RGBAf.rawValue)])

    static func ink(_ image: CIImage) -> Double {
        let extent = image.extent
        guard extent.width >= 1, extent.height >= 1, extent.width.isFinite, extent.height.isFinite else { return 0 }
        let average = image.applyingFilter("CIAreaAverage", parameters: [kCIInputExtentKey: CIVector(cgRect: extent)])
        var pixel = [Float](repeating: 0, count: 4)
        context.render(average, toBitmap: &pixel, rowBytes: 16, bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                       format: .RGBAf, colorSpace: nil)
        return Double(pixel[3]) * Double(extent.width * extent.height)
    }

    @Test("Before a word's beat nothing of it shows, at any leading",
          arguments: [0.78, 0.9, 1.1])
    func hiddenUntilItsBeat(_ leading: Double) throws {
        var text = TextContent(string: "YOUR\nTITLE", fontName: "DIN Condensed", fontSize: 200,
                               colorHex: "#FFFFFF", weight: .bold)
        text.lineHeight = leading
        let size = TextRasterizer.naturalSize(text, maxWidth: .greatestFiniteMagnitude)
        let pieces = try #require(TextRasterizer.revealPieces(text, size: size, unit: .word))
        let reveal = TextReveal(style: .maskReveal, unit: .word, staggerMS: 300, lengthMS: 900, startMS: 100,
                                curve: .easeOutExpo)
        let reach = TextRevealCompositor.reach(of: pieces, reveal: reveal)
        let before = TextRevealCompositor.image(pieces, reveal: reveal, elapsedMS: 0, reach: reach)
        let landed = TextRevealCompositor.image(pieces, reveal: reveal, elapsedMS: 5000, reach: reach)
        let whole = Self.ink(landed)
        #expect(whole > 100)
        #expect(Self.ink(before) / whole < 0.001,
                "\(String(format: "%.1f", Self.ink(before) / whole * 100))% of the words show at 0 ms at leading \(leading)")
        // The second word is still behind its mask while the first slides.
        let midFirst = TextRevealCompositor.image(pieces, reveal: reveal, elapsedMS: 300, reach: reach)
        let firstAlone = TextRevealCompositor.image(pieces, reveal: reveal, elapsedMS: 399, reach: reach)
        #expect(Self.ink(midFirst) < Self.ink(firstAlone) + whole * 0.001)
    }

    /// A word almost landed is almost whole: its mask holds the whole of its
    /// letters, not only its line box (task
    /// `a-main-title-headline-keeps-its-second-line-afte`). Cut to a box
    /// shorter than the capitals, the tops and bottoms of the letters stayed
    /// cut for the whole slow end of the slide and then appeared at once:
    /// Condensed Poster's entrance, seen with its letter bottoms sliced on
    /// 2026-11-26.
    @Test("A word nearly landed shows nearly all of its letters, at any leading",
          arguments: [0.62, 0.78, 1.1])
    func nearlyLandedIsNearlyWhole(_ leading: Double) throws {
        var text = TextContent(string: "MAKE\nNOISE", fontName: "DIN Condensed", fontSize: 200,
                               colorHex: "#FFFFFF", weight: .bold)
        text.lineHeight = leading
        let size = TextRasterizer.naturalSize(text, maxWidth: .greatestFiniteMagnitude)
        let pieces = try #require(TextRasterizer.revealPieces(text, size: size, unit: .word))
        let reveal = TextReveal(style: .maskReveal, unit: .word, staggerMS: 300, lengthMS: 900, startMS: 100,
                                curve: .easeOutExpo)
        let reach = TextRevealCompositor.reach(of: pieces, reveal: reveal)
        let whole = Self.ink(TextRevealCompositor.image(pieces, reveal: reveal, elapsedMS: 5000, reach: reach))
        // The second word 60% through its slide, 1.6% of the way still to
        // go on an expo curve; the first 93% through.
        let nearly = Self.ink(TextRevealCompositor.image(pieces, reveal: reveal, elapsedMS: 940, reach: reach))
        #expect(whole > 100)
        #expect(nearly / whole > 0.95,
                "only \(String(format: "%.1f", nearly / whole * 100))% of the letters show nearly landed at leading \(leading)")
    }
}
