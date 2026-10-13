import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// **A sound's volume line, segment by segment** (task
/// `an-audio-clip-answers-right-click-and-its-volume`): the stretch between two
/// level points is a segment with a curve of its own, picked on the timeline
/// and shaped from its right-click, and a point added on the line keeps the
/// line's shape. What the line draws is what the mix plays.
@Suite("Sound line segments")
struct SoundLineSegmentTests {

    /// A line through three points: loud, quiet, loud again.
    private func dip() -> AudioLevel {
        var level = AudioLevel()
        level.setPoint(atMS: 1000, gain: 1)
        level.setPoint(atMS: 3000, gain: 0.25)
        level.setPoint(atMS: 5000, gain: 1)
        return level
    }

    @Test("A segment nobody has shaped is straight, and a point carries no curve")
    func straightByDefault() {
        let level = dip()
        #expect(level.points.allSatisfy { $0.curve == nil })
        #expect(level.segmentCurve(startingAtMS: 1000) == .linear)
        #expect(level.segmentCurve(startingAtMS: 5000) == nil, "the last point starts no segment")
        #expect(abs(level.gain(atLayerMS: 2000) - 0.625) < 0.0001)
    }

    @Test("A curved segment follows its curve, and only that segment bends")
    func curvedSegment() {
        var level = dip()
        let shaped = level.setSegmentsCurve(.easeOut, startingAt: [1000])
        #expect(shaped)
        #expect(level.segmentCurve(startingAtMS: 1000) == .easeOut)
        for fraction in [0.25, 0.5, 0.75] {
            let ms = 1000 + Int(2000 * fraction)
            let expected = 1 + (0.25 - 1) * EasingCurve.easeOut.value(at: fraction)
            #expect(abs(level.gain(atLayerMS: ms) - expected) < 0.0001)
        }
        // The next segment is still a straight line.
        #expect(abs(level.gain(atLayerMS: 4000) - 0.625) < 0.0001)
    }

    @Test("Hold keeps the level until the next point, then steps")
    func hold() {
        var level = dip()
        level.setSegmentsCurve(.steps(1), startingAt: [1000])
        #expect(level.gain(atLayerMS: 2999) == 1)
        #expect(level.gain(atLayerMS: 3000) == 0.25)
        let moments = level.moments(fromMS: 0, toMS: 6000)
        #expect(moments.contains(2999) && moments.contains(3000), "the step is a corner the mix plays")
    }

    @Test("Several picked segments take a curve in one go, and say it where they agree")
    func severalSegments() {
        var level = dip()
        level.setSegmentsCurve(.smooth, startingAt: [1000, 3000])
        #expect(level.segmentsCurve([1000, 3000]) == .smooth)
        level.setSegmentsCurve(.easeIn, startingAt: [3000])
        #expect(level.segmentsCurve([1000, 3000]) == nil)
        let none = level.setSegmentsCurve(.easeIn, startingAt: [5000])
        #expect(!none, "no segment starts at the last point")
    }

    @Test("A point added on the line holds the level there and keeps the shape")
    func pointOnTheLine() throws {
        var level = dip()
        level.setSegmentsCurve(.easeOut, startingAt: [1000])
        let before = (0...6000).map { level.gain(atLayerMS: $0) }
        let heldAt = level.gain(atLayerMS: 1600)
        let added1600 = level.addPointOnLine(atMS: 1600)
        #expect(added1600)
        let added = try #require(level.points.first { $0.atMS == 1600 })
        #expect(abs(added.gain - heldAt) < 0.0001)
        #expect(level.points.count == 4)
        for ms in stride(from: 0, through: 6000, by: 50) {
            #expect(abs(level.gain(atLayerMS: ms) - before[ms]) < 0.01, "at \(ms)ms")
        }
        let again = level.addPointOnLine(atMS: 3000)
        #expect(!again, "a point is already there")
    }

    @Test("A point added before the first or after the last holds the level that runs there")
    func pointBeyondTheEnds() {
        var level = dip()
        let early = level.addPointOnLine(atMS: 200)
        #expect(early && level.points.first?.gain == 1)
        let late = level.addPointOnLine(atMS: 5800)
        #expect(late && level.points.last?.gain == 1)
        var flat = AudioLevel()
        let onFlat = flat.addPointOnLine(atMS: 700)
        #expect(onFlat)
        #expect(flat.points == [AudioLevelPoint(atMS: 700, gain: 1)])
    }

    @Test("A point moved keeps the curve of the segment it starts")
    func movedPointKeepsItsCurve() {
        var level = dip()
        level.setSegmentsCurve(.easeIn, startingAt: [1000])
        level.movePoint(fromMS: 1000, toMS: 1500, gain: 0.8)
        #expect(level.segmentCurve(startingAtMS: 1500) == .easeIn)
        // Pinned again where it is, it keeps its curve too.
        level.setPoint(atMS: 1500, gain: 0.9)
        #expect(level.segmentCurve(startingAtMS: 1500) == .easeIn)
    }

    @Test("Points picked together go together")
    func removeSeveral() {
        var level = dip()
        level.removePoints([1000, 5000])
        #expect(level.points.map(\.atMS) == [3000])
    }

    @Test("A bend dragged through the middle of a segment lands the middle there")
    func bend() {
        for middle in [0.1, 0.3, 0.5, 0.7, 0.9] {
            let curve = AudioLevel.bentCurve(middle: middle)
            #expect(abs(curve.value(at: 0.5) - middle) < 0.01, "middle \(middle)")
            #expect(curve.value(at: 0) == 0 && abs(curve.value(at: 1) - 1) < 0.0001)
        }
        #expect(AudioLevel.bentCurve(middle: 0.5) == .linear)
    }

    @Test("A curved segment plays as drawn: the mix is within half a decibel of the curve")
    func mixFollowsTheCurve() throws {
        var (doc, id) = AudioMixTests.document(soundLengthMS: 6000)
        var level = dip()
        level.setSegmentsCurve(.easeOut, startingAt: [1000])
        level.setSegmentsCurve(.easeInOut, startingAt: [3000])
        doc.updateLayer(id: id) { $0.setSoundLevel(level) }
        let segment = try #require(doc.audioMix().first)
        for (from, to) in [(1000, 3000), (3000, 5000)] {
            for fraction in [0.25, 0.5, 0.75] {
                let ms = from + Int(Double(to - from) * fraction)
                let heard = segment.gain(atMS: ms), drawn = level.gain(atLayerMS: ms)
                let gap = abs(20 * log10(heard) - 20 * log10(drawn))
                #expect(gap < 0.5, "at \(ms)ms the mix plays \(heard), the line draws \(drawn)")
            }
        }
    }

    @Test("A curve on a segment is kept, and a document from before curves reads back the same")
    func codable() throws {
        var level = dip()
        let plain = try JSONEncoder().encode(level)
        #expect(!String(decoding: plain, as: UTF8.self).contains("curve"))
        level.setSegmentsCurve(.easeOut, startingAt: [3000])
        let back = try JSONDecoder().decode(AudioLevel.self, from: JSONEncoder().encode(level))
        #expect(back == level)
        #expect(back.segmentCurve(startingAtMS: 3000) == .easeOut)
    }
}
