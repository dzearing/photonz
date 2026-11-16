import CoreGraphics
import CoreImage
import CoreText
import Foundation
import PhotonzCore
@testable import PhotonzRender
import Testing

/// Soft gradients in a recording come out smooth (task
/// `soft-gradients-in-a-recording-come-out-smooth-ev`).
///
/// The Mac draws a dark translucent window in 8-bit steps, so a recording of
/// it is a staircase of flat bands however deep it is captured. The pass
/// blends those steps into a ramp when a recording is shown or written out,
/// and leaves anything with a real edge exactly as it was. The staircase here
/// is the user's own: ten shades over 1300 pixels, measured down the sidebar
/// of a terminal window on 2026-11-16 (11 levels, flat runs of up to 164 px).
@Suite("Soft gradients in a recording come out smooth", .serialized)
struct RecordingSmoothingTests {

    static let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
    static let p3 = CGColorSpace(name: CGColorSpace.displayP3)!

    /// Grey bytes, row 0 at the top, as an opaque 8-bit picture.
    static func picture(width: Int, height: Int, space: CGColorSpace = srgb,
                        _ grey: (Int, Int) -> UInt8) -> CGImage {
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let v = grey(x, y)
                let i = (y * width + x) * 4
                bytes[i] = v; bytes[i + 1] = v; bytes[i + 2] = v
            }
        }
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: width * 4, space: space,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    }

    /// The user's staircase: shades 51 to 62 down 1560 rows, 130 rows each,
    /// of which the middle 1300 (`measured`) are the strip the user's was
    /// measured on, ten shades over 1300 px, with the gradient going on past
    /// both ends as it does in the window.
    static func staircase(width: Int = 96, space: CGColorSpace = srgb) -> CGImage {
        picture(width: width, height: 1560, space: space) { _, y in UInt8(51 + y / 130) }
    }

    static let measured = 130..<1430

    /// Every channel of every pixel as a fraction of full scale, read back in
    /// the picture's own colours at 16 bits, so nothing is rounded on the way.
    static func fractions(_ image: CGImage) -> (width: Int, height: Int, values: [Double]) {
        let w = image.width, h = image.height
        var raw = [UInt16](repeating: 0, count: w * h * 4)
        let space = image.colorSpace ?? srgb
        let ctx = CGContext(data: &raw, width: w, height: h, bitsPerComponent: 16, bytesPerRow: w * 8,
                            space: space,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                                | CGBitmapInfo.byteOrder16Little.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return (w, h, raw.map { Double($0) / 65535 })
    }

    /// The green channel down column `x`.
    static func column(_ image: CGImage, x: Int) -> [Double] {
        let f = fractions(image)
        return (0..<f.height).map { f.values[($0 * f.width + x) * 4 + 1] }
    }

    /// The green channel down the picture, averaged across each row: what the
    /// eye sees of a dithered ramp, which is the mean of its grain.
    static func rowMeans(_ image: CGImage) -> [Double] {
        let f = fractions(image)
        return (0..<f.height).map { y in
            (0..<f.width).reduce(0.0) { $0 + f.values[(y * f.width + $1) * 4 + 1] } / Double(f.width)
        }
    }

    static func tenBit(_ values: [Double]) -> BandingReading {
        BandingReading(levels: BandingReading.codes(values, bits: 10))
    }

    @Test("The kernels compile on this Mac")
    func compiles() {
        #expect(RecordingSmoothing.isAvailable)
    }

    @Test("The staircase itself fails the bar, as today's recording does")
    func staircaseFails() {
        let reading = Self.tenBit(Array(Self.column(Self.staircase(), x: 48)[Self.measured]))
        #expect(reading.longestFlatRun >= 130)
        #expect(!reading.isSmooth(longestRunUnder: 40, levelsAtLeast: 35))
    }

    @Test("Smoothed deep, the staircase becomes a ramp: under 40 px flat, 35 levels or more",
          arguments: [Self.srgb, Self.p3])
    func deepRamp(space: CGColorSpace) throws {
        let out = try #require(RecordingSmoothing.deepPicture(Self.staircase(space: space)))
        let reading = Self.tenBit(Array(Self.column(out, x: 48)[Self.measured]))
        #expect(reading.isSmooth(longestRunUnder: 40, levelsAtLeast: 35),
                "flat \(reading.longestFlatRun) px, \(reading.distinctLevels) levels")
        // Still the same gradient: nothing darker or lighter than it was.
        #expect(reading.lowest >= 51 * 4 && reading.highest <= 62 * 4 + 4)
    }

    @Test("Smoothed into 8 bits, the grain carries the ramp: its row means pass the same bar")
    func ditheredRamp() throws {
        let out = try #require(RecordingSmoothing.smoothedPicture(Self.staircase(width: 128)))
        #expect(out.bitsPerComponent == 8)
        let reading = Self.tenBit(Array(Self.rowMeans(out)[Self.measured]))
        #expect(reading.isSmooth(longestRunUnder: 40, levelsAtLeast: 35),
                "flat \(reading.longestFlatRun) px, \(reading.distinctLevels) levels")
        // The grain is at most a shade either way, on top of the ramp.
        let f = Self.fractions(out)
        let original = Self.fractions(Self.staircase(width: 128))
        let worst = zip(f.values, original.values).map { abs($0 - $1) * 255 }.max() ?? 0
        #expect(worst <= 2.01)
    }

    @Test("A flat area is left exactly as it was")
    func flatUntouched() throws {
        let flat = Self.picture(width: 200, height: 200) { _, _ in 57 }
        let out = try #require(RecordingSmoothing.smoothedPicture(flat))
        #expect(Self.fractions(out).values == Self.fractions(flat).values)
    }

    /// Words, a window edge and two hairlines over the staircase.
    static func busy() -> CGImage {
        let w = 400, h = 1560
        let base = staircase(width: w)
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: srgb, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        ctx.draw(base, in: CGRect(x: 0, y: 0, width: w, height: h))
        // A window edge: a lighter panel on the right.
        ctx.setFillColor(CGColor(srgbRed: 90 / 255, green: 90 / 255, blue: 90 / 255, alpha: 1))
        ctx.fill(CGRect(x: 300, y: 0, width: 100, height: h))
        // A one-pixel line a shade off what is under it, and a stronger one.
        ctx.setShouldAntialias(false)
        ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.0055))
        ctx.fill(CGRect(x: 0, y: 1000, width: 300, height: 1))
        ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.2))
        ctx.fill(CGRect(x: 0, y: 900, width: 300, height: 1))
        ctx.setShouldAntialias(true)
        // Words.
        let font = CTFontCreateWithName("Helvetica" as CFString, 13, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String):
                CGColor(srgbRed: 0.85, green: 0.85, blue: 0.85, alpha: 1),
        ]
        for row in 0..<12 {
            let line = CTLineCreateWithAttributedString(
                NSAttributedString(string: "swift build && Scripts/test.sh  \(row)", attributes: attributes))
            ctx.textPosition = CGPoint(x: 12, y: 1510 - row * 18)
            CTLineDraw(line, ctx)
        }
        return ctx.makeImage()!
    }

    @Test("Words, edges and one-pixel lines are not softened")
    func sharpThingsStaySharp() throws {
        let input = Self.busy()
        let out = try #require(RecordingSmoothing.smoothedPicture(input))
        let a = Self.fractions(input), b = Self.fractions(out)
        let w = a.width
        func g(_ f: (width: Int, height: Int, values: [Double]), _ x: Int, _ y: Int) -> Double {
            f.values[(y * w + x) * 4 + 1]
        }
        // Every pixel with a neighbour more than one and a half shades off it
        // is an edge, and an edge is left exactly as it was.
        var edges = 0
        for y in 1..<(a.height - 1) {
            for x in 1..<(w - 1) {
                let c = g(a, x, y)
                let near = [g(a, x - 1, y), g(a, x + 1, y), g(a, x, y - 1), g(a, x, y + 1)]
                guard near.contains(where: { abs($0 - c) * 255 > 1.5 }) else { continue }
                edges += 1
                #expect(g(b, x, y) == c, "edge pixel \(x),\(y) moved: \((-1...1).map { dy in (-1...1).map { dx in Int((g(a, x + dx, y + dy) * 255).rounded()) } }) -> \((-1...1).map { dy in (-1...1).map { dx in Int((g(b, x + dx, y + dy) * 255).rounded()) } })")
                if g(b, x, y) != c { return }
            }
        }
        #expect(edges > 500)
        // Around the words, the window edge and the lines (every pixel within
        // two of an edge), at the 99th percentile no pixel moves by more than
        // one 10-bit code.
        var near = Set<Int>()
        for y in 1..<(a.height - 1) {
            for x in 1..<(w - 1) {
                let c = g(a, x, y)
                let around = [g(a, x - 1, y), g(a, x + 1, y), g(a, x, y - 1), g(a, x, y + 1)]
                guard around.contains(where: { abs($0 - c) * 255 > 1.5 }) else { continue }
                for dy in -2...2 { for dx in -2...2 {
                    let nx = x + dx, ny = y + dy
                    if nx >= 0, nx < w, ny >= 0, ny < a.height { near.insert(ny * w + nx) }
                } }
            }
        }
        var moved = near.map { abs(b.values[$0 * 4 + 1] - a.values[$0 * 4 + 1]) * 1023 }
        moved.sort()
        #expect(moved[Int(Double(moved.count) * 0.99)] <= 1.0)
        // The faint hairline (drawn at 1000 up from the bottom, so row 559
        // from the top) is still a shade off the rows beside it.
        let line = (20..<280).map { g(b, $0, 559) }
        let beside = (20..<280).map { g(b, $0, 562) }
        let lift = zip(line, beside).map { ($0 - $1) * 255 }.reduce(0, +) / Double(line.count)
        #expect(lift > 0.5, "hairline lifted \(lift) shades")
    }

    /// Drawn the way a frame being played is: in Core Image's own working
    /// space (linear light), in a context that rounds through half floats.
    static func drawnInLinearLight(_ picture: CGImage, smoothed: Bool) -> CGImage? {
        let context = CIContext(options: [.cacheIntermediates: false])
        var image = CIImage(cgImage: picture)
        let extent = image.extent
        if smoothed {
            image = RecordingSmoothing.smoothed(image, reach: RecordingSmoothing.reachInRecordingPixels, grain: true)
        }
        return context.createCGImage(image, from: extent, format: .RGBA8, colorSpace: picture.colorSpace ?? srgb)
    }

    @Test("Drawn in linear light, as a frame being played is, the ramp passes and an edge moves a shade at most, one pixel in a hundred at most")
    func linearLight() throws {
        let plain = try #require(Self.drawnInLinearLight(Self.busy(), smoothed: false))
        let out = try #require(Self.drawnInLinearLight(Self.busy(), smoothed: true))
        let a = Self.fractions(plain), b = Self.fractions(out)
        let w = a.width
        var edges = 0, moved = 0, worst = 0.0
        for y in 1..<(a.height - 1) {
            for x in 1..<(w - 1) {
                let i = (y * w + x) * 4 + 1
                let c = a.values[i]
                let around = [a.values[i - 4], a.values[i + 4], a.values[i - w * 4], a.values[i + w * 4]]
                guard around.contains(where: { abs($0 - c) * 255 > 1.5 }) else { continue }
                edges += 1
                if b.values[i] != c { moved += 1 }
                worst = max(worst, abs(b.values[i] - c) * 255)
            }
        }
        #expect(edges > 500)
        // Through the half-float working copy (`RecordingSmoothing.smoothed`).
        #expect(Double(moved) <= Double(edges) * 0.01, "\(moved) of \(edges) edge pixels moved")
        #expect(worst <= 1.01, "an edge moved \(worst) shades")
        // The staircase beside the words, columns 0..<290 below the text.
        let means = (0..<a.height).map { y in
            (0..<290).reduce(0.0) { $0 + b.values[(y * w + $1) * 4 + 1] } / 290
        }
        let reading = Self.tenBit(Array(means[1200..<1430]) + [])
        #expect(reading.longestFlatRun < 40, "flat \(reading.longestFlatRun) px")
    }

    @Test("A frame read at a quarter of the recording's size is smoothed at a quarter of the reach")
    func reachFollowsTheSize() {
        #expect(RecordingSmoothing.reach(readAt: 1) == RecordingSmoothing.reachInRecordingPixels)
        #expect(RecordingSmoothing.reach(readAt: 0.25) == RecordingSmoothing.reachInRecordingPixels / 4)
        #expect(RecordingSmoothing.reach(readAt: 0.001) >= 2)
    }
}
