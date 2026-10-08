import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// **A sound lane as tall as the mock's, its waveform one shape**
/// (`SoundLaneShape.swift`).
///
/// video-audio.html draws a sound lane 84 points tall (72 in a narrow window)
/// and its waveform as one filled path, the top edge along and the bottom edge
/// back, mirrored about the middle. The timeline drew 34 points of thin bars.
///
/// Written before the change, which is the rule for `PhotonzCore`.
@Suite("A sound lane as tall as the mock's, its waveform one shape")
struct SoundLaneShapeTests {

    // MARK: - How tall

    @Test func aSoundLaneIsTheMocksEightyFourPoints() {
        #expect(SoundLaneShape.height == 84)
        #expect(SoundLaneShape.height(windowWidth: 1400) == 84)
        #expect(SoundLaneShape.height(windowWidth: 881) == 84)
    }

    @Test func aNarrowWindowDrawsItSeventyTwo() {
        // `@container shell (max-width:880px){ .lane.alane{height:72px} }`
        #expect(SoundLaneShape.narrowHeight == 72)
        #expect(SoundLaneShape.height(windowWidth: 880) == 72)
        #expect(SoundLaneShape.height(windowWidth: 600) == 72)
    }

    @Test func aWindowNotYetMeasuredIsNotNarrow() {
        #expect(SoundLaneShape.height(windowWidth: 0) == 84)
        #expect(SoundLaneShape.height(windowWidth: -1) == 84)
        #expect(SoundLaneShape.height(windowWidth: .nan) == 84)
    }

    // MARK: - The waveform's outline

    @Test func noHeightsNoShape() {
        #expect(SoundLaneShape.outline(heights: [], width: 100, height: 84).isEmpty)
        #expect(SoundLaneShape.outline(heights: [1, 1], width: 0, height: 84).isEmpty)
        #expect(SoundLaneShape.outline(heights: [1, 1], width: 100, height: 0).isEmpty)
    }

    @Test func theTopEdgeRunsAlongAndTheBottomEdgeComesBack() {
        let heights: [Float] = [0.2, 0.6, 1.0, 0.4]
        let outline = SoundLaneShape.outline(heights: heights, width: 40, height: 84)
        #expect(outline.count == heights.count * 2)
        let top = Array(outline.prefix(heights.count))
        let bottom = Array(outline.suffix(heights.count))
        // Left to right along the top, right to left along the bottom.
        #expect(top.map(\.x) == top.map(\.x).sorted())
        #expect(bottom.map(\.x) == bottom.map(\.x).sorted(by: >))
        // Each column at its own middle, so the shape spans the whole width.
        #expect(top.first?.x == 5)
        #expect(top.last?.x == 35)
    }

    @Test func itIsMirroredAboutTheMiddle() {
        let heights: [Float] = [0.1, 0.5, 0.9, 0.3, 0.7]
        let outline = SoundLaneShape.outline(heights: heights, width: 50, height: 84)
        let top = Array(outline.prefix(heights.count))
        let bottom = Array(outline.suffix(heights.count).reversed())
        for (up, down) in zip(top, bottom) {
            #expect(up.x == down.x)
            #expect(abs((up.y + down.y) / 2 - 42) < 0.0001)
        }
    }

    @Test func aTallerSoundDrawsTaller() {
        let outline = SoundLaneShape.outline(heights: [0.25, 1.0], width: 20, height: 84)
        let quiet = 42 - outline[0].y
        let loud = 42 - outline[1].y
        #expect(loud > quiet)
        // Full height reaches as far as the mock's does: 42 of its 50.
        #expect(SoundLaneShape.reach == 0.84)
        #expect(abs(loud - 42 * 0.84) < 0.0001)
        #expect(abs(quiet - 42 * 0.84 * 0.25) < 0.0001)
    }

    @Test func silenceIsAHairlineNotAGap() {
        let outline = SoundLaneShape.outline(heights: [0, 0, 0], width: 30, height: 84)
        for point in outline.prefix(3) {
            #expect(abs(42 - point.y - SoundLaneShape.hairline) < 0.0001)
        }
    }

    @Test func oneColumnStillMakesAShapeAcrossIt() {
        let outline = SoundLaneShape.outline(heights: [0.5], width: 10, height: 84)
        #expect(outline.count == 2)
        #expect(outline[0].x == 5)
        #expect(outline[0].y < outline[1].y)
    }
}
