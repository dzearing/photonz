import CoreGraphics
import Foundation
import Testing
import PhotonzCore
@testable import PhotonzRender

/// A mouse stroke's end is drawn thinned as it goes, so every move with a new
/// dab used to take the old end back, lay the dab that had just gone down for
/// good, and lay the new end: three dabs' work on the move, with the cores
/// idle for the moves between (one dab every 50 points at 500 points). At 500
/// points on a screenshot that was 9 to 12.6 ms a move for oil, charcoal and
/// chalk, over one 120 Hz frame (every-brush-follows-the-pointer-with-no-lag,
/// 2026-10-31). Now the dab every next move will settle is laid in the gap
/// before it, and the move lays only the new end. The pixels are the same
/// whichever way it goes, including when the guess is wrong (a release just
/// short of a whole spacing).
@Suite("The dab that goes down for good is laid between moves")
struct LaidAheadTests {
    private let size = CGSize(width: 420, height: 240)
    private let scale: CGFloat = 1.5

    static let media: [BrushMedium] = [.pencil, .charcoal, .chalk, .crayon, .oil]

    private func mouseStroke(_ medium: BrushMedium, diameter: Double = 160) -> BrushStroke {
        let settings = BrushSettings(medium: medium, values: ["size": diameter])
        let samples = (0...30).map { (i: Int) -> StrokeSample in
            let f = CGFloat(i)
            let point = CGPoint(x: 40 + f * 11.3, y: 90 + f * 1.7 + sin(f) * 2)
            return StrokeSample(point: point, ms: Double(i) * 8)
        }
        return BrushStroke(samples: samples, settings: settings, colorHex: "#D03030", seed: 21, startedAt: 300)
    }

    private func base() throws -> PaintLayerBase {
        let settings = BrushSettings(medium: .oil, values: ["size": 50])
        let samples = (0...20).map { i in
            StrokeSample(point: CGPoint(x: 30 + CGFloat(i) * 18, y: 120 - CGFloat(i) * 2), ms: Double(i) * 8)
        }
        let under = BrushStroke(samples: samples, settings: settings, colorHex: "#2060E0", seed: 3, startedAt: 200)
        let cache = PaintRasterCache(budgetBytes: 64 << 20)
        return try #require(cache.base(PaintContent(strokes: [under]), size: size, scale: scale))
    }

    private func bytes(_ live: PaintLayerStroke) throws -> [UInt8] {
        let image = try #require(live.picture(of: CGRect(x: 0, y: 0, width: live.width, height: live.height)))
        var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = try #require(CGContext(data: &data, width: image.width, height: image.height,
                                             bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                             space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setBlendMode(.copy)
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return data
    }

    /// How many bytes differ: compared as arrays, a failure is reported with
    /// a diff of millions of bytes that does not finish.
    private func differ(_ a: [UInt8], _ b: [UInt8]) -> Int {
        guard a.count == b.count else { return max(a.count, b.count) }
        return zip(a, b).reduce(0) { $0 + ($1.0 == $1.1 ? 0 : 1) }
    }

    private func begun(_ stroke: BrushStroke) -> BrushStroke {
        BrushStroke(samples: [], settings: stroke.settings, colorHex: stroke.colorHex, seed: stroke.seed,
                    startedAt: stroke.startedAt)
    }

    /// The picture every move shows, then held before the release and after
    /// it, painted with dabs laid ahead or not.
    private func drawn(_ stroke: BrushStroke, ahead: Bool, pause: Bool) throws
        -> (moves: [[UInt8]], held: [UInt8], released: [UInt8], laidAhead: Int) {
        let live = try #require(PaintLayerStroke(stroke: begun(stroke), base: try base(), size: size, scale: scale,
                                                 laysAhead: ahead))
        var walker = BrushPlacement.Walker(settings: stroke.settings, seed: stroke.seed,
                                           jitter: PaintRasterizer.jitter(for: stroke.settings.medium))
        var moves: [[UInt8]] = []
        for (i, sample) in stroke.samples.enumerated() {
            live.mark(walker.add(sample))
            live.layAhead()
            // The hand's gap between moves, on some of them.
            if pause, i % 3 == 0 { Thread.sleep(forTimeInterval: 0.004) }
            if i % 5 == 4 { moves.append(try bytes(live)) }
        }
        live.mark(walker.finish())
        let held = try bytes(live)
        live.finish()
        return (moves, held, try bytes(live), live.dabsLaidAhead)
    }

    @Test(arguments: media)
    func everyMoveShowsTheSamePixelsAsBefore(_ medium: BrushMedium) throws {
        let stroke = mouseStroke(medium)
        let before = try drawn(stroke, ahead: false, pause: false)
        for pause in [false, true] {
            let now = try drawn(stroke, ahead: true, pause: pause)
            #expect(now.laidAhead > 0, "\(medium): no dab was laid between moves")
            #expect(zip(now.moves, before.moves).map { differ($0, $1) } == before.moves.map { _ in 0 }, "\(medium): a move showed different pixels (pause \(pause))")
            #expect(differ(now.held, before.held) == 0, "\(medium): the held stroke differs (pause \(pause))")
            #expect(differ(now.released, before.released) == 0, "\(medium): the released stroke differs (pause \(pause))")
        }
        #expect(before.laidAhead == 0)
    }

    /// Dabs placed by hand at a 500 point brush's spacing (50 points) and a
    /// taper of 60: after the third, the second is due to settle on the next
    /// whole spacing, but the release lays a last dab only 5 points on, so it
    /// does not, and what was laid ahead is taken back.
    @Test(arguments: media)
    func aGuessTheReleaseProvesWrongIsTakenBack(_ medium: BrushMedium) throws {
        let settings = BrushSettings(medium: medium, values: ["size": 500])
        let stroke = BrushStroke(samples: [], settings: settings, colorHex: "#30A040", seed: 5, startedAt: 400)
        func dab(_ along: Double) -> BrushDab {
            BrushDab(center: CGPoint(x: 20 + along * 0.8, y: 120), diameter: 140, opacity: 1, pressure: 0.5,
                     along: along)
        }
        func run(_ ahead: Bool) throws -> (held: [UInt8], released: [UInt8], laidAhead: Int, takenBack: Int) {
            let live = try #require(PaintLayerStroke(stroke: stroke, base: try base(), size: size, scale: scale,
                                                     laysAhead: ahead))
            for along in [0.0, 50, 100] {
                live.mark([dab(along)])
                live.layAhead()
            }
            Thread.sleep(forTimeInterval: 0.01)
            live.mark([dab(105)])
            let held = try bytes(live)
            live.finish()
            return (held, try bytes(live), live.dabsLaidAhead, live.dabsTakenBackAhead)
        }
        let before = try run(false)
        let now = try run(true)
        #expect(now.laidAhead > 0)
        #expect(now.takenBack > 0, "\(medium): the wrong guess was not taken back")
        #expect(differ(now.held, before.held) == 0, "\(medium): held")
        #expect(differ(now.released, before.released) == 0, "\(medium): released")
    }

    /// A release with no dab of its own still lands the end the hand saw,
    /// though the stroke had already moved on past it in the gap.
    @Test(arguments: media)
    func aReleaseWithNoNewDabKeepsTheEndOnScreen(_ medium: BrushMedium) throws {
        let stroke = mouseStroke(medium, diameter: 300)
        func run(_ ahead: Bool) throws -> (held: [UInt8], released: [UInt8]) {
            let live = try #require(PaintLayerStroke(stroke: begun(stroke), base: try base(), size: size,
                                                     scale: scale, laysAhead: ahead))
            var walker = BrushPlacement.Walker(settings: stroke.settings, seed: stroke.seed)
            for sample in stroke.samples {
                live.mark(walker.add(sample))
                live.layAhead()
            }
            Thread.sleep(forTimeInterval: 0.01)
            let held = try bytes(live)
            live.finish()
            return (held, try bytes(live))
        }
        let before = try run(false)
        let now = try run(true)
        #expect(differ(now.held, before.held) == 0, "\(medium): held")
        #expect(differ(now.released, before.released) == 0, "\(medium): released")
        #expect(differ(now.held, now.released) == 0, "\(medium): nothing changes as the button comes up")
    }
}

