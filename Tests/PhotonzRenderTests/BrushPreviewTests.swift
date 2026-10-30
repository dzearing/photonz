import CoreGraphics
import Foundation
import Testing
import PhotonzCore
@testable import PhotonzRender

/// **A brush tile is that brush's real stroke.** Each tile in the brush library
/// is painted by the same engine that paints the canvas, at the brush's own
/// settings and in the current colour, never a stored picture, and it is the
/// same picture every time it is drawn (`brush-library.html`).
///
/// Written before the code.
@Suite("Brush tiles paint the brush's real stroke")
struct BrushPreviewTests {

    private let tile = CGSize(width: 150, height: 46)

    private func pixels(_ image: CGImage) -> [UInt8] {
        let width = image.width, height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let context = CGContext(data: &bytes, width: width, height: height, bitsPerComponent: 8,
                                bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return bytes
    }

    /// The share of the tile the stroke covers at all.
    private func coverage(_ image: CGImage) -> Double {
        let bytes = pixels(image)
        var inked = 0
        for i in stride(from: 3, to: bytes.count, by: 4) where bytes[i] > 8 { inked += 1 }
        return Double(inked) / Double(bytes.count / 4)
    }

    /// The mean colour of the inked pixels, un-premultiplied.
    private func meanInk(_ image: CGImage) -> (r: Double, g: Double, b: Double) {
        let bytes = pixels(image)
        var r = 0.0, g = 0.0, b = 0.0, n = 0.0
        for i in stride(from: 0, to: bytes.count, by: 4) where bytes[i + 3] > 64 {
            let a = Double(bytes[i + 3])
            r += Double(bytes[i]) / a; g += Double(bytes[i + 1]) / a; b += Double(bytes[i + 2]) / a
            n += 1
        }
        return n == 0 ? (0, 0, 0) : (r / n, g / n, b / n)
    }

    @Test func everyBrushPaintsAVisibleStrokeInItsTile() throws {
        for medium in BrushMedium.allCases {
            let image = try #require(BrushPreview.image(settings: BrushSettings(medium: medium),
                                                        colorHex: "#ff5d8f", size: tile, scale: 2))
            #expect(image.width == 300 && image.height == 92)
            let covered = coverage(image)
            #expect(covered > 0.04, "\(medium.title) covers only \(covered)")
            #expect(covered < 0.95, "\(medium.title) floods the tile: \(covered)")
        }
    }

    @Test func aTileIsTheSamePictureEveryTime() throws {
        for medium in BrushMedium.allCases {
            let settings = BrushSettings(medium: medium)
            let a = try #require(BrushPreview.image(settings: settings, colorHex: "#3ecf8e", size: tile, scale: 2))
            let b = try #require(BrushPreview.image(settings: settings, colorHex: "#3ecf8e", size: tile, scale: 2))
            #expect(pixels(a) == pixels(b), "\(medium.title) shimmers between renders")
        }
    }

    @Test func aTileIsPaintedInTheCurrentColour() throws {
        for medium in BrushMedium.allCases {
            let settings = BrushSettings(medium: medium)
            let red = try #require(BrushPreview.image(settings: settings, colorHex: "#e02020", size: tile, scale: 2))
            let blue = try #require(BrushPreview.image(settings: settings, colorHex: "#2040e0", size: tile, scale: 2))
            let r = meanInk(red), b = meanInk(blue)
            #expect(r.r > r.b, "\(medium.title) in red is not red")
            #expect(b.b > b.r, "\(medium.title) in blue is not blue")
        }
    }

    @Test func noTwoBrushesPaintTheSameTile() throws {
        let images = try BrushMedium.allCases.map {
            try #require(BrushPreview.image(settings: BrushSettings(medium: $0), colorHex: "#000000",
                                            size: tile, scale: 1))
        }
        for i in images.indices {
            for j in images.indices where j > i {
                #expect(pixels(images[i]) != pixels(images[j]),
                        "\(BrushMedium.allCases[i].title) and \(BrushMedium.allCases[j].title) look the same")
            }
        }
    }

    @Test func aTileFollowsTheBrushsOwnSettings() throws {
        var soft = BrushSettings(medium: .marker)
        soft.set("opacity", to: 20)
        let faint = try #require(BrushPreview.image(settings: soft, colorHex: "#000000", size: tile, scale: 1))
        let full = try #require(BrushPreview.image(settings: BrushSettings(medium: .marker), colorHex: "#000000",
                                                   size: tile, scale: 1))
        #expect(pixels(faint) != pixels(full))
    }

    // MARK: - The cache

    @Test func theCacheHandsBackTheSamePictureAndKeepsToItsLimit() throws {
        let cache = BrushPreviewCache(limit: 3)
        let settings = BrushSettings(medium: .chalk)
        let a = try #require(cache.image(settings: settings, colorHex: "#000000", size: tile, scale: 1))
        let b = try #require(cache.image(settings: settings, colorHex: "#000000", size: tile, scale: 1))
        #expect(a === b)
        #expect(cache.count == 1)
        for medium in [BrushMedium.pencil, .oil, .marker, .crayon] {
            _ = cache.image(settings: BrushSettings(medium: medium), colorHex: "#000000", size: tile, scale: 1)
        }
        #expect(cache.count <= 3)
        // A new colour is a new picture.
        let red = try #require(cache.image(settings: settings, colorHex: "#ff0000", size: tile, scale: 1))
        #expect(red !== a)
        cache.removeAll()
        #expect(cache.count == 0)
    }
}

/// The brush grid's cost. Serialized and named ...PerfTests, so
/// `Scripts/test.sh` holds it until every other test has finished and nothing
/// else competes for the cores while it is read.
@Suite("The brush grid paints without a stall", .serialized)
struct BrushGridPerfTests {

    /// The whole grid at the size the chooser draws them, twice the points for
    /// a Retina screen, one after another. The app paints its tiles
    /// off the main thread, each on its own, so this is never a stall a person
    /// sees; the bar is a guard against the painting getting dearer, a medium
    /// whose one tile suddenly costs seconds or every tile twice what it did.
    ///
    /// Read against the CPU ruler, taken just before each tile on this
    /// thread's CPU clock, because a stopwatch could not tell a slower brush
    /// from a busier machine: a flat 3000 ms on the slowest tile, which reads
    /// 300 ms alone, failed whole runs at 3.3, 3.5 and 3.7 s on unchanged
    /// code (releases v0.20.0 and v0.21.0) while the chalk tile read 1.5 to
    /// 2.5 s in every full run. A debug build's numbers (this run) are
    /// several times the shipping build's.
    @Test func theWholeGridPaintsWithoutAStall() throws {
        let wide = CGSize(width: 148, height: 76)
        let media = BrushMedium.allCases
        // Each medium once on a tiny tile first, so what is timed is painting
        // a tile and not what a process does once: the first tile painted, a
        // pencil, read 590 to 1030 ms from run to run, and 37 ms warm.
        for medium in media {
            _ = BrushPreview.image(settings: BrushSettings(medium: medium), colorHex: "#000000",
                                   size: CGSize(width: 24, height: 12), scale: 1)
        }
        let reading = PerfClock.calibrated(rounds: media.count, rulerRounds: 20) { round in
            _ = BrushPreview.image(settings: BrushSettings(medium: media[round]), colorHex: "#ff5d8f",
                                   size: wide, scale: 2)
        }
        let each = zip(media, reading.subject).map { "\($0.rawValue) \(Int($1))" }
        print("brush tiles, ms of CPU each: \(each.joined(separator: ", "))")
        print("brush grid of \(media.count) tiles at 148x76@2x: \(Int(reading.subject.reduce(0, +))) ms of CPU")
        // The grid summed, alone on the calibration machine: 942 to 957 ms
        // (2026-10-30). Twice the painting reads about 1900, so 1.6 times
        // fails it.
        PerfClock.check("brush grid of \(media.count) tiles", ms: reading.summedMS, rulerMS: reading.rulerMS,
                        baselineMS: 950, tolerance: 1.6)
    }
}
