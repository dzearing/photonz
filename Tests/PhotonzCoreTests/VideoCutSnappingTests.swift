import Testing
import Foundation
import CoreGraphics
@testable import PhotonzCore

@Suite("Trim handles catch on cuts")
struct VideoCutSnappingTests {

    /// An eighteen second recording cut in three, drawn on a track where one
    /// second is ten points, so a point of travel is a tenth of a second and
    /// every distance in these tests reads straight off the screen.
    private let pointsPerSecond: CGFloat = 10

    private func threePieces() -> VideoCutList {
        var cuts = VideoCutList(duration: 18)
        _ = cuts.split(atTimeline: 6)
        _ = cuts.split(atTimeline: 12)
        return cuts
    }

    // MARK: - What a handle may catch on

    @Test("Every cut is a candidate, and so are the two ends of the recording")
    func candidatesAreCutsAndEnds() {
        #expect(VideoCutSnapping.candidates(in: threePieces()) == [0, 6, 12, 18])
    }

    @Test("An uncut recording still offers its two ends")
    func uncutRecordingOffersItsEnds() {
        #expect(VideoCutSnapping.candidates(in: VideoCutList(duration: 18)) == [0, 18])
    }

    @Test("Candidates the other handle has no room for are not offered")
    func candidatesRespectTheMinimumPiece() {
        // A left handle whose out-point is at 6.05s cannot land on the cut at
        // 6, because the minimum window would push it back off again.
        let allowed = VideoCutSnapping.candidates(in: threePieces(), within: 0...(6.05 - 0.1))
        #expect(allowed == [0])
    }

    // MARK: - Catching

    @Test("A handle within the catch distance lands exactly on the cut")
    func catchesNearbyCut() {
        // 5.4s is six points short of the cut at 6, inside the 8 point reach.
        let snap = VideoCutSnapping.snap(5.4, to: [0, 6, 12, 18],
                                         pointsPerSecond: pointsPerSecond, held: nil)
        #expect(snap.seconds == 6)
        #expect(snap.caught == 6)
    }

    @Test("A handle beyond the catch distance is left exactly where the hand put it")
    func leavesDistantHandleAlone() {
        // 4.9s is eleven points short of the cut: too far to be taken.
        let snap = VideoCutSnapping.snap(4.9, to: [0, 6, 12, 18],
                                         pointsPerSecond: pointsPerSecond, held: nil)
        #expect(snap.seconds == 4.9)
        #expect(snap.caught == nil)
    }

    @Test("The nearest cut wins when two are in reach")
    func nearestCutWins() {
        var cuts = VideoCutList(duration: 18)
        _ = cuts.split(atTimeline: 6)
        _ = cuts.split(atTimeline: 6.5)
        let snap = VideoCutSnapping.snap(6.4, to: VideoCutSnapping.candidates(in: cuts),
                                         pointsPerSecond: pointsPerSecond, held: nil)
        #expect(snap.caught == 6.5)
    }

    @Test("The catch is a distance on screen, so it does not widen with the recording")
    func catchDistanceIsInPoints() {
        // Six seconds short of the cut at a minute. On a track where a second
        // is one point that is six points away, well inside the reach.
        let loose = VideoCutSnapping.snap(54, to: [0, 60, 120, 180],
                                          pointsPerSecond: 1, held: nil)
        #expect(loose.seconds == 60)
        // The same six seconds on a track ten times as tight is sixty points,
        // nowhere near it. What the magnet measures is the screen, not the clock.
        let tight = VideoCutSnapping.snap(54, to: [0, 60, 120, 180],
                                          pointsPerSecond: 10, held: nil)
        #expect(tight.seconds == 54)
        #expect(tight.caught == nil)
    }

    @Test("Both ends of the recording catch the same way as a cut in the middle")
    func endsCatchToo() {
        let ends = VideoCutSnapping.candidates(in: threePieces())
        #expect(VideoCutSnapping.snap(0.5, to: ends,
                                      pointsPerSecond: pointsPerSecond, held: nil).caught == 0)
        #expect(VideoCutSnapping.snap(17.5, to: ends,
                                      pointsPerSecond: pointsPerSecond, held: nil).caught == 18)
    }

    // MARK: - Keeping, and getting away

    @Test("A cut that caught keeps the handle past the distance that caught it")
    func caughtCutKeepsTheHandle() {
        // Twelve points past the cut: outside the 8 point reach, inside the 16
        // point hold, so the handle is still standing on the cut. This is the
        // wobble that would otherwise flicker the snap on and off.
        let snap = VideoCutSnapping.snap(4.8, to: [0, 6, 12, 18],
                                         pointsPerSecond: pointsPerSecond, held: 6)
        #expect(snap.seconds == 6)
        #expect(snap.caught == 6)
    }

    @Test("A deliberate drag past the cut gets past it")
    func deliberateDragEscapes() {
        // Eighteen points past: beyond the hold, so the handle lets go and
        // follows the hand exactly.
        let snap = VideoCutSnapping.snap(4.2, to: [0, 6, 12, 18],
                                         pointsPerSecond: pointsPerSecond, held: 6)
        #expect(snap.seconds == 4.2)
        #expect(snap.caught == nil)
    }

    @Test("Letting go of one cut can catch the next one straight away")
    func escapingOneCutCanCatchAnother() {
        var cuts = VideoCutList(duration: 18)
        _ = cuts.split(atTimeline: 6)
        _ = cuts.split(atTimeline: 8)
        let snap = VideoCutSnapping.snap(7.6, to: VideoCutSnapping.candidates(in: cuts),
                                         pointsPerSecond: pointsPerSecond, held: 6)
        #expect(snap.caught == 8)
        #expect(snap.seconds == 8)
    }

    @Test("A held cut that is no longer on offer does not hold anything")
    func staleHoldIsIgnored() {
        let snap = VideoCutSnapping.snap(5.9, to: [0, 12, 18],
                                         pointsPerSecond: pointsPerSecond, held: 6)
        #expect(snap.seconds == 5.9)
        #expect(snap.caught == nil)
    }

    // MARK: - Degenerate tracks

    @Test("A track with no width on screen cannot catch anything")
    func noTrackNoMagnet() {
        let snap = VideoCutSnapping.snap(5.99, to: [0, 6, 12, 18],
                                         pointsPerSecond: 0, held: nil)
        #expect(snap.seconds == 5.99)
        #expect(snap.caught == nil)
    }

    @Test("Nothing to catch on leaves the handle alone")
    func noCandidates() {
        let snap = VideoCutSnapping.snap(5.4, to: [],
                                         pointsPerSecond: pointsPerSecond, held: nil)
        #expect(snap.seconds == 5.4)
        #expect(snap.caught == nil)
    }

    // MARK: - The number you see is the number you get

    @Test("What the window keeps after a catch is measured from the cut itself")
    func caughtWindowMatchesTheCut() {
        let cuts = threePieces()
        let snap = VideoCutSnapping.snap(5.4, to: VideoCutSnapping.candidates(in: cuts),
                                         pointsPerSecond: pointsPerSecond, held: nil)
        var trim = VideoTrim(duration: cuts.timelineDuration)
        trim.setIn(snap.seconds, duration: cuts.timelineDuration)
        // The handle is on the cut to the last decimal, so the piece before it
        // is wholly dropped and no sliver of it survives.
        #expect(trim.inPoint == 6)
        #expect(trim.effectiveDuration == 12)
        let reading = cuts.piecesUnderTrim(fromTimeline: trim.inPoint, toTimeline: trim.outPoint)
        #expect(reading[0].isDropped)
        #expect(reading[1].isWhollyKept)
    }
}
