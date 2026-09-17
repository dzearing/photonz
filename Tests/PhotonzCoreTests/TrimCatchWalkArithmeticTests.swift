import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// The numbers `Scripts/playtest/trim-catches-on-a-cut-walk.json` claims,
/// replayed against the model.
///
/// Same reason as `TrimPickWalkArithmeticTests`: the walk was written on a Mac
/// whose screen was locked, so it could not be RUN before it was committed, and
/// a walk whose claims were arrived at by hand is a walk that fails the next
/// sweep for arithmetic rather than for a bug.
///
/// Every step of it is a pure model operation plus the magnet, so the sequence
/// is replayed here exactly as `PlaytestHarness.dragTrimHandle` performs it:
/// the drag targets are a number of POINTS away from a cut, turned into seconds
/// through the live track width, which is the one thing a run would supply and
/// a test has to stand in for. This does not prove the app wires it up — only a
/// run can do that — but it does prove the walk is asking for the right
/// numbers, at any track width a real window could have.
@Suite("Trim catch walk arithmetic")
struct TrimCatchWalkArithmeticTests {
    /// The sample recording the walk opens: eight seconds.
    private static let clip: TimeInterval = 8

    /// Track widths a recording window could plausibly come up at: the video
    /// controller is not resizable to anything narrower than a few hundred
    /// points, and the walk's claims have to hold across the lot.
    private static let trackWidths: [CGFloat] = [200, 320, 500, 900, 1600]

    /// What the editor does with a handle drag, carrying only what the walk
    /// claims about it.
    private struct Editor {
        var cuts: VideoCutList
        var trim: VideoTrim
        var playhead: TimeInterval = 0
        var caught: TimeInterval?
        let trackWidth: CGFloat

        init(duration: TimeInterval, trackWidth: CGFloat) {
            cuts = VideoCutList(duration: duration)
            trim = VideoTrim(duration: duration)
            self.trackWidth = trackWidth
        }

        var keeps: Int {
            cuts.piecesUnderTrim(fromTimeline: trim.inPoint, toTimeline: trim.outPoint)
                .count { !$0.isDropped }
        }
        var seconds: TimeInterval { trim.effectiveDuration }
        var perSecond: CGFloat { trackWidth / CGFloat(cuts.timelineDuration) }
        /// The interior cuts, which is what a handle is dragged towards.
        var joins: [TimeInterval] {
            VideoCutSnapping.candidates(in: cuts)
                .filter { $0 > 1e-6 && $0 < cuts.timelineDuration - 1e-6 }
        }

        mutating func seek(toFraction f: Double) {
            playhead = min(max(trim.inPoint, cuts.timelineDuration * f), trim.outPoint)
        }
        mutating func cut() { cuts.split(atTimeline: playhead) }

        /// `VideoEditorState.dragTrimIn`, driven the way the harness drives it.
        mutating func dragStart(pointsShortOfFirstJoin points: CGFloat) {
            guard let join = joins.first else { return }
            let ceiling = max(0, trim.outPoint - VideoCutList.minPieceDuration)
            let snap = VideoCutSnapping.snap(
                join - TimeInterval(points / perSecond),
                to: VideoCutSnapping.candidates(in: cuts, within: 0...ceiling),
                pointsPerSecond: perSecond, held: caught)
            caught = snap.caught
            trim.setIn(snap.seconds, duration: cuts.timelineDuration)
            playhead = trim.inPoint
        }

        /// `VideoEditorState.dragTrimOut`, the same way.
        mutating func dragEnd(pointsPastLastJoin points: CGFloat) {
            guard let join = joins.last else { return }
            let floor = min(cuts.timelineDuration,
                            trim.inPoint + VideoCutList.minPieceDuration)
            let snap = VideoCutSnapping.snap(
                join + TimeInterval(points / perSecond),
                to: VideoCutSnapping.candidates(in: cuts,
                                                within: floor...max(floor, cuts.timelineDuration)),
                pointsPerSecond: perSecond, held: caught)
            caught = snap.caught
            trim.setOut(snap.seconds, duration: cuts.timelineDuration)
            playhead = trim.outPoint
        }

        mutating func release() { caught = nil }

        mutating func done() {
            caught = nil
            guard trim.isTrimmed else { return }
            cuts.keep(fromTimeline: trim.inPoint, toTimeline: trim.outPoint)
            trim = VideoTrim(duration: cuts.timelineDuration)
            playhead = 0
        }
    }

    private func check(_ editor: Editor, stage: String, width: CGFloat,
                       pieces: Int? = nil, keeps: Int? = nil,
                       seconds: TimeInterval? = nil, starts: TimeInterval? = nil,
                       caught: Bool? = nil) {
        let at = "\(stage) at \(Int(width))pt"
        if let pieces { #expect(editor.cuts.pieceCount == pieces, "\(at): pieces") }
        if let keeps { #expect(editor.keeps == keeps, "\(at): keeps") }
        if let seconds {
            #expect(abs(editor.seconds - seconds) <= 0.05, "\(at): seconds is \(editor.seconds)")
        }
        if let starts {
            // The same tolerance the walk's claim is checked with, which is
            // tight on purpose: a handle that caught is ON the cut.
            #expect(abs(editor.trim.inPoint - starts) <= 0.005,
                    "\(at): starts at \(editor.trim.inPoint)")
        }
        if let caught {
            #expect((editor.caught != nil) == caught, "\(at): caught is \(String(describing: editor.caught))")
        }
    }

    @Test("trim-catches-on-a-cut-walk", arguments: TrimCatchWalkArithmeticTests.trackWidths)
    func catchesOnACut(width: CGFloat) {
        var editor = Editor(duration: Self.clip, trackWidth: width)
        editor.seek(toFraction: 0.25)
        editor.cut()
        editor.seek(toFraction: 0.75)
        editor.cut()
        check(editor, stage: "1-handles-open", width: width,
              pieces: 3, keeps: 3, seconds: 8, starts: 0, caught: false)

        // Five points short of the cut at two seconds: inside the reach.
        editor.dragStart(pointsShortOfFirstJoin: 5)
        check(editor, stage: "2-caught-on-the-cut", width: width,
              keeps: 2, seconds: 6, starts: 2, caught: true)

        // Twelve points short: past the reach, inside the hold, still caught.
        editor.dragStart(pointsShortOfFirstJoin: 12)
        check(editor, stage: "3-a-wobble-does-not-lose-it", width: width,
              keeps: 2, starts: 2, caught: true)

        // Twenty four points short: a deliberate move, so it lets go.
        editor.dragStart(pointsShortOfFirstJoin: 24)
        check(editor, stage: "4-slid-past-it", width: width, keeps: 3, caught: false)
        #expect(editor.trim.inPoint < 2 - 1e-6, "4-slid-past-it at \(Int(width))pt: still on the cut")

        editor.release()
        editor.dragStart(pointsShortOfFirstJoin: 5)
        check(editor, stage: "5-caught-again", width: width, starts: 2, caught: true)

        editor.dragEnd(pointsPastLastJoin: 5)
        check(editor, stage: "5-both-ends-catch", width: width,
              keeps: 1, seconds: 4, starts: 2, caught: true)

        editor.done()
        check(editor, stage: "6-done-keeps-exactly-that", width: width,
              pieces: 1, seconds: 4, caught: false)
    }
}
