import CoreGraphics
import Foundation
import PhotonzCore
@testable import PhotonzRender

/// How steadily the letters of a word travel while the word scales, moves or
/// turns: each letter's centre is found on every frame, and what is measured
/// is how far it sits from where the rest of the word says it should be.
///
/// Letters are told apart by the space between them, so the words measured
/// are set loose (tracking).
enum GlyphSteadiness {

    typealias Letter = LetterSteadiness.Mark

    struct Report {
        /// The furthest any letter sits from its own smooth motion, in
        /// pixels, on any frame: a straight line in whatever the word is
        /// doing (its scale, its travel), which is what every point of a
        /// solid thing scaling or sliding follows.
        var worstDeviation = 0.0
        /// The furthest any letter sits from where the rest of the word says
        /// its outline belongs.
        var worstOutOfPlace = 0.0
        /// The furthest any letter jumps against the word between two frames.
        var worstJump = 0.0
        /// The furthest the word as a whole sits from where the motion puts it.
        var worstWordOffset = 0.0
        /// The word's fitted scale on each frame.
        var scales: [Double] = []
        /// The word's fitted middle on each frame.
        var xs: [Double] = []
        var ys: [Double] = []
        /// Frames whose letters could not be told apart.
        var unread = 0
        /// Per frame, each letter's deviation across.
        var deviations: [[Double]] = []
    }

    /// The ink of `image` (light on black), one value a pixel, cut to the rows
    /// and columns that hold any, and where that stretch starts.
    static func ink(_ image: CGImage) -> (values: [UInt8], width: Int, height: Int, x: Int, y: Int) {
        let width = image.width, height = image.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        let context = CGContext(data: &data, width: width, height: height, bitsPerComponent: 8,
                                bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.interpolationQuality = .none
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        // A row of nothing, compared whole: a picture is mostly those, and a
        // test is built without optimisation.
        var black = [UInt8](repeating: 0, count: width * 4)
        for x in 0..<width { black[x * 4 + 3] = 255 }
        return data.withUnsafeBufferPointer { p -> ([UInt8], Int, Int, Int, Int) in
            let rows = (0..<height).filter { memcmp(p.baseAddress! + $0 * width * 4, black, width * 4) != 0 }
            guard let top = rows.first, let bottom = rows.last else { return ([], 0, 0, 0, 0) }
            var left = width, right = -1
            for y in rows {
                let row = p.baseAddress! + y * width * 4
                var x = 0
                while x < left, row[x * 4] == 0 { x += 1 }
                left = min(left, x)
                x = width - 1
                while x > right, row[x * 4] == 0 { x -= 1 }
                right = max(right, x)
            }
            guard right >= left else { return ([], 0, 0, 0, 0) }
            let w = right - left + 1, h = bottom - top + 1
            var out = [UInt8](repeating: 0, count: w * h)
            for y in 0..<h { for x in 0..<w { out[y * w + x] = p[((y + top) * width + x + left) * 4] } }
            return (out, w, h, left, top)
        }
    }

    /// The marks in a picture of light words on black, left to right.
    static func letters(_ image: CGImage) -> [LetterSteadiness.Mark] {
        let found = ink(image)
        return LetterSteadiness.marks(in: found.values, width: found.width, height: found.height, least: 2).map {
            .init(x: $0.x + Double(found.x), y: $0.y + Double(found.y), ink: $0.ink)
        }
    }

    /// Reads `frames` (each a picture of the word and the scale it should be
    /// at) against the letters' places in `reference`, a big clean picture of
    /// the same word. `middle` is the still point of the scale, in pixels.
    static func read(_ frames: [(image: CGImage, scale: Double)], reference: [Letter],
                     middle: CGPoint? = nil, referenceMiddle: CGPoint? = nil,
                     referenceScale: Double = 1) -> Report {
        var report = Report()
        var last: [Double]?
        var tracks: [(at: Double, letters: [Letter])] = []
        for frame in frames {
            let found = letters(frame.image)
            guard found.count == reference.count, found.count > 2 else { report.unread += 1; continue }
            tracks.append((frame.scale, found))
            // The word's own motion: one scale and one shift that best fit the
            // letters' centres.
            let n = Double(found.count)
            let mrx = reference.map(\.x).reduce(0, +) / n, mry = reference.map(\.y).reduce(0, +) / n
            let mfx = found.map(\.x).reduce(0, +) / n, mfy = found.map(\.y).reduce(0, +) / n
            var top = 0.0, bottom = 0.0
            for (r, f) in zip(reference, found) {
                top += (r.x - mrx) * (f.x - mfx) + (r.y - mry) * (f.y - mfy)
                bottom += (r.x - mrx) * (r.x - mrx) + (r.y - mry) * (r.y - mry)
            }
            let s = bottom > 0 ? top / bottom : 1
            var across: [Double] = []
            for (r, f) in zip(reference, found) {
                let dx = f.x - (mfx + s * (r.x - mrx)), dy = f.y - (mfy + s * (r.y - mry))
                report.worstOutOfPlace = max(report.worstOutOfPlace, max(abs(dx), abs(dy)))
                across.append(dx); across.append(dy)
            }
            if let last {
                for (a, b) in zip(across, last) { report.worstJump = max(report.worstJump, abs(a - b)) }
            }
            last = across
            report.deviations.append(across)
            report.scales.append(s)
            report.xs.append(mfx); report.ys.append(mfy)
            if let middle, let referenceMiddle {
                let wantX = Double(middle.x) + frame.scale / referenceScale * (mrx - Double(referenceMiddle.x))
                let wantY = Double(middle.y) + frame.scale / referenceScale * (mry - Double(referenceMiddle.y))
                report.worstWordOffset = max(report.worstWordOffset,
                                             max(abs(mfx - wantX), abs(mfy - wantY)))
            }
        }
        for letter in reference.indices where tracks.count > 3 {
            for track in [tracks.map(\.letters[letter].x), tracks.map(\.letters[letter].y)] {
                report.worstDeviation = max(report.worstDeviation, offLine(track, against: tracks.map(\.at)))
            }
        }
        return report
    }

    static func offLine(_ track: [Double], against at: [Double]) -> Double {
        LetterSteadiness.offLine(track, against: at)
    }
}
