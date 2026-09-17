import CoreGraphics
import Foundation
import PhotonzCore
@testable import PhotonzRender
import Testing

/// How far off a size read off a screenshot is, measured against type of a
/// KNOWN size rather than against another reading.
///
/// Every other test of the reader asks whether the labels of one capture agree
/// with each other. None of them can say whether the number they agree on is
/// the number the type really was, because nothing in a captured PNG says what
/// size it was set at. So these tests set the type themselves, photograph it,
/// and read it back.
///
/// ## What they found
///
/// Read at the scale it was set at, the reading is right: every size, every
/// face, 1x and 2x, lands within a point of the type that made it.
///
/// Read into a document measured in the CAPTURE'S OWN PIXELS — which is what
/// opening a Retina screenshot gives you, a 2x picture laid out one document
/// point per pixel — a 13 point label comes back as a 28 point layer where 26
/// is the size the type really was. About 9 per cent high, every label by the
/// same amount.
///
/// ## Why
///
/// Not antialiasing, not the coverage floor, not rounding. It is the system
/// font: **SF Pro at 13 points is a different drawing from SF Pro at 26**. The
/// small one is wider and set further apart, because the typeface carries an
/// optical size and the operating system applies it. Measured here, "Launch at
/// login" is 181 pixels of ink wide set at 13 points and photographed at 2x,
/// and 168 pixels wide set at 26 points and photographed at 1x — the same em in
/// the same number of pixels, 7.7 per cent apart. Helvetica Neue and SF Mono,
/// which carry no optical size, come out pixel for pixel identical.
///
/// So on a Retina capture the two things a size could mean stop being one
/// number. The size the type really was is 13 points, which is 26 of the
/// document's own points. The size that makes the retyped words cover the ink
/// they replace is 28.4, because SF Pro at 28 is narrower than SF Pro at 13
/// magnified. The reader reports the second and the Size menu calls it the
/// size, which is the gap this suite pins.
///
/// Serialized, like every suite that leans on the recogniser.
@Suite("A size read off a capture against type of a known size", .serialized)
struct ReadSizeGroundTruthTests {

    // MARK: - Photographing type of a known size

    /// The words set at `size` and drawn at `scale` onto an opaque background
    /// with a margin round them: a screenshot of one label, with nothing in it
    /// the app has not been told.
    static func capture(_ string: String, face: TextReading.Face, size: CGFloat,
                        scale: CGFloat, ink: String = "#3c3c43",
                        back: (UInt8, UInt8, UInt8) = (255, 255, 255)) -> CGImage? {
        var text = TextContent(string: string, fontName: face.fontName, fontSize: size,
                               colorHex: ink, weight: face.weight)
        text.staysOnOneLine = true
        let box = TextRasterizer.naturalSize(text)
        guard let image = TextRasterizer.rasterize(text, size: box, scale: scale),
              let bytes = LayerSeparator.read(image) else { return nil }
        return flatten(bytes, width: image.width, height: image.height,
                       into: (back, pad: 8))
    }

    /// A whole pane of rows, so the page vote and the cohort sizes are the ones
    /// a real capture gets rather than a single label deciding alone.
    static func pane(_ rows: [(words: String, size: CGFloat, weight: TextWeight, ink: String)],
                     face family: String, scale: CGFloat) -> CGImage? {
        let rowHeight: CGFloat = 34, left: CGFloat = 16, top: CGFloat = 12
        let w = Int((360 * scale).rounded())
        let h = Int(((top * 2 + rowHeight * CGFloat(rows.count)) * scale).rounded())
        guard w > 0, h > 0 else { return nil }
        var out = [UInt8](repeating: 0, count: w * h * 4)
        for p in 0..<(w * h) {
            out[p * 4] = 242; out[p * 4 + 1] = 242; out[p * 4 + 2] = 247; out[p * 4 + 3] = 255
        }
        for (index, row) in rows.enumerated() {
            var text = TextContent(string: row.words, fontName: family, fontSize: row.size,
                                   colorHex: row.ink, weight: row.weight)
            text.staysOnOneLine = true
            let box = TextRasterizer.naturalSize(text)
            guard let image = TextRasterizer.rasterize(text, size: box, scale: scale),
                  let bytes = LayerSeparator.read(image) else { continue }
            let ox = Int((left * scale).rounded())
            let oy = Int(((top + CGFloat(index) * rowHeight) * scale).rounded())
            draw(bytes, width: image.width, height: image.height,
                 onto: &out, canvas: (w, h), at: (ox, oy))
        }
        return LayerSeparator.makeImage(out, width: w, height: h)
    }

    private static func flatten(_ bytes: [UInt8], width: Int, height: Int,
                                into background: (colour: (UInt8, UInt8, UInt8), pad: Int))
        -> CGImage? {
        let pad = background.pad
        let ow = width + pad * 2, oh = height + pad * 2
        var out = [UInt8](repeating: 0, count: ow * oh * 4)
        for p in 0..<(ow * oh) {
            out[p * 4] = background.colour.0
            out[p * 4 + 1] = background.colour.1
            out[p * 4 + 2] = background.colour.2
            out[p * 4 + 3] = 255
        }
        draw(bytes, width: width, height: height, onto: &out, canvas: (ow, oh), at: (pad, pad))
        return LayerSeparator.makeImage(out, width: ow, height: oh)
    }

    /// Source-over, by hand: the run is premultiplied already, so the
    /// background is what is left of it.
    private static func draw(_ bytes: [UInt8], width: Int, height: Int,
                             onto out: inout [UInt8], canvas: (w: Int, h: Int),
                             at origin: (x: Int, y: Int)) {
        for y in 0..<height where y + origin.y < canvas.h {
            for x in 0..<width where x + origin.x < canvas.w {
                let source = (y * width + x) * 4
                let alpha = Double(bytes[source + 3]) / 255
                let target = ((y + origin.y) * canvas.w + (x + origin.x)) * 4
                for channel in 0..<3 {
                    let value = Double(bytes[source + channel])
                        + Double(out[target + channel]) * (1 - alpha)
                    out[target + channel] = UInt8(min(255, max(0, value.rounded())))
                }
            }
        }
    }

    static func readings(of image: CGImage, captureScale: CGFloat,
                         layerScale: CGFloat) -> [TextReading.Reading] {
        guard let separated = LayerSeparator.separateText(
            image, luma: EdgeMapAnalyzer.analyzeFully(image).luma) else { return [] }
        return TextReader.readPage(separated.runs.compactMap { $0.image },
                                   captureScale: captureScale, layerScale: layerScale)
            .compactMap(\.outcome.reading)
    }

    // MARK: - The round trip

    /// The acceptance the whole study rests on: type of a known size, read back
    /// at the scale it was photographed at, comes back that size.
    ///
    /// Several sizes, several faces, 1x and 2x. The tolerance is a fifth of a
    /// point at label size and a point at heading size, and the measured error
    /// is well inside it: the worst of the twenty four combinations tried while
    /// writing this was 1.2 per cent.
    @Test func typeOfAKnownSizeReadsBackAtThatSize() throws {
        let faces = [TextReading.Face(fontName: "SF Pro", weight: .regular),
                     TextReading.Face(fontName: "SF Pro", weight: .semibold),
                     TextReading.Face(fontName: "Helvetica Neue", weight: .regular)]
        var worst = 0.0
        var table: [String] = []
        for face in faces {
            for scale in [CGFloat(1), 2] {
                for size in [CGFloat(11), 13, 17] {
                    let image = try #require(Self.capture("Launch at login", face: face,
                                                          size: size, scale: scale))
                    let read = TextReader.read(image, captureScale: scale, layerScale: scale,
                                               preferring: face.fontName, at: face.weight)
                    let reading = try #require(read.outcome.reading,
                                               "\(face.fontName) \(face.weight) \(size)@\(scale)x")
                    let off = abs(reading.fontSize / size - 1)
                    worst = max(worst, off)
                    table.append(String(format: "%@ %@ %.0f@%.0fx: read %.2f (%+.1f%%)",
                                        face.fontName, "\(face.weight)", size, scale,
                                        reading.fontSize, (reading.fontSize / size - 1) * 100))
                    #expect(abs(reading.fontSize - size) <= max(0.25, size * 0.025),
                            """
                            \(face.fontName) \(face.weight) set at \(size) at \(scale)x \
                            came back \(reading.fontSize)
                            """)
                }
            }
        }
        print("Round trip at the scale the type was set at:\n  "
                + table.joined(separator: "\n  "))
        print(String(format: "  worst %.1f%%", worst * 100))
    }

    /// The same pane read as a PAGE, which is how the app reads it: the family
    /// is voted on and every cohort is held to one size.
    @Test func awholePaneOfKnownTypeComesBackAtItsOwnSizes() throws {
        let rows: [(words: String, size: CGFloat, weight: TextWeight, ink: String)] = [
            ("General", 17, .semibold, "#000000"),
            ("Launch at login", 13, .regular, "#3c3c43"),
            ("Show in menu bar", 13, .regular, "#3c3c43"),
            ("Copy to clipboard", 13, .regular, "#3c3c43"),
            ("Check for updates", 13, .regular, "#3c3c43"),
        ]
        for scale in [CGFloat(1), 2] {
            let image = try #require(Self.pane(rows, face: "SF Pro", scale: scale))
            let readings = Self.readings(of: image, captureScale: scale, layerScale: scale)
            for row in rows {
                let reading = try #require(readings.first { $0.string == row.words },
                                           "\(row.words) at \(scale)x did not come back")
                #expect(abs(reading.fontSize - row.size) <= max(0.5, row.size * 0.04),
                        """
                        \(row.words) was \(row.size) at \(scale)x, came back \
                        \(reading.fontSize)
                        """)
            }
        }
    }

    // MARK: - The gap, and what causes it

    /// The gap the study was opened for, pinned as a number.
    ///
    /// A 2x capture opened as a document measured in its own pixels — which is
    /// every Retina screenshot this app opens — reads its 13 point labels as 28
    /// point layers where 26 is what the type really was. This test does not
    /// say that is acceptable. It says how big it is and that it is the same
    /// for every label, so a change that closes it can be seen to have closed
    /// it.
    @Test func aRetinaCaptureReadIntoAPixelDocumentReadsAboutNinePerCentHigh() throws {
        let rows: [(words: String, size: CGFloat, weight: TextWeight, ink: String)] = [
            ("Launch at login", 13, .regular, "#3c3c43"),
            ("Show in menu bar", 13, .regular, "#3c3c43"),
            ("Copy to clipboard", 13, .regular, "#3c3c43"),
            ("Check for updates", 13, .regular, "#3c3c43"),
        ]
        let image = try #require(Self.pane(rows, face: "SF Pro", scale: 2))
        let readings = Self.readings(of: image, captureScale: 2, layerScale: 1)
        var off: [Double] = []
        for row in rows {
            let reading = try #require(readings.first { $0.string == row.words },
                                       "\(row.words) did not come back")
            // The type was 13 points in a 2x picture, so it is 26 of the
            // document's own points.
            off.append(reading.fontSize / (row.size * 2) - 1)
        }
        let worst = try #require(off.map(abs).max())
        print(String(format: "A 2x capture read into a 1x document: %@",
                     off.map { String(format: "%+.1f%%", $0 * 100) }.joined(separator: " ")))
        // Every label is wrong by the SAME amount, which is what says this is
        // the face rather than noise.
        #expect(Set(off.map { ($0 * 1000).rounded() }).count == 1)
        #expect(worst > 0.04, "the gap has closed to \(worst); update this test and the audit")
        #expect(worst < 0.12, "the gap has grown to \(worst)")
    }

    /// The cause, in one measurement: the same em in the same number of pixels,
    /// drawn two sizes apart, is not the same ink.
    ///
    /// Set at 13 points and photographed at 2x, and set at 26 points and
    /// photographed at 1x, a string occupies exactly the same number of device
    /// pixels per em. A face with no optical size comes out pixel for pixel
    /// identical both ways. SF Pro does not, because the system applies the
    /// typeface's optical size: the 13 point drawing is wider and looser.
    ///
    /// That difference IS the gap above. Nothing about the coverage floor, the
    /// antialiasing or the search changes it.
    @Test func theSystemFontIsADifferentDrawingAtLabelSizeAndAtHeadingSize() throws {
        func ink(_ family: String, _ size: CGFloat, _ scale: CGFloat) throws -> CGRect {
            let face = TextReading.Face(fontName: family, weight: .regular)
            let mask = try #require(TextReader.render("Launch at login", in: face,
                                                      size: size, scale: scale))
            return try #require(mask.inkBounds())
        }
        for steady in ["Helvetica Neue", "SF Mono"] {
            let small = try ink(steady, 13, 2)
            let large = try ink(steady, 26, 1)
            // The SIZE of the ink, not where it sits: the box the words are
            // set in rounds its inset differently at the two scales, which
            // moves the ink a pixel inside it and says nothing about the type.
            #expect(small.size == large.size,
                    """
                    \(steady) carries no optical size, so \(small.size) and \
                    \(large.size) should be the same ink
                    """)
        }
        let label = try ink("SF Pro", 13, 2)
        let heading = try ink("SF Pro", 26, 1)
        let wider = label.width / heading.width
        print(String(format: "SF Pro at 13 doubled is %.0fx%.0f, at 26 it is %.0fx%.0f: "
                        + "%.1f%% wider", label.width, label.height,
                     heading.width, heading.height, (wider - 1) * 100))
        #expect(wider > 1.05, """
                the system font's optical size has stopped mattering; this whole \
                suite needs re-reading
                """)
    }

    // MARK: - On a real capture

    /// The same finding on a picture nobody made for this test: the app's own
    /// settings pane, captured at 2x.
    ///
    /// Read at the scale the type was set at, every row label comes back 13.00
    /// points — a whole number, which nothing in the reading rounds to and
    /// which is what a Mac settings row is actually set at. That is the
    /// strongest evidence in the suite that the MEASUREMENT is sound and the
    /// gap is the conversion into document points.
    @Test func theRealSettingsPaneRowsAreThirteenPointType() throws {
        let url = try #require(Bundle.module.url(forResource: "Fixtures/settings-pane-2x",
                                                 withExtension: "png"))
        let image = try #require(ImageCodec.decode(try Data(contentsOf: url)))
        let readings = Self.readings(of: image, captureScale: 2, layerScale: 2)
        let rows = ["Launch at login", "Show in menu bar", "Copy to clipboard"]
        for words in rows {
            let reading = try #require(readings.first { $0.string == words },
                                       "\(words) did not come back")
            #expect(abs(reading.fontSize - 13) <= 0.25,
                    "\(words) came back \(reading.fontSize), not 13 point type")
        }
    }
}
