import Foundation
import Testing
@testable import PhotonzCore

/// The numbers the two trim-pick walks claim, replayed against the model.
///
/// `Scripts/playtest/trim-keeps-the-piece-you-picked-walk.json` and
/// `trim-cancel-after-a-delete-walk.json` assert exact piece counts, picks and
/// window lengths at each stage. They were written on a Mac whose screen was
/// locked, so neither could be RUN before it was committed, and a walk whose
/// claims were arrived at by hand is a walk that fails the next sweep for
/// arithmetic rather than for a bug.
///
/// Every step of those walks is a pure model operation, so the sequence is
/// replayed here. This does not prove the app wires it up — only a run can do
/// that — but it does prove the walks are asking for the right numbers.
@Suite("Trim pick walk arithmetic")
struct TrimPickWalkArithmeticTests {
    /// The sample recording the walks open: eight seconds.
    private static let clip: TimeInterval = 8

    /// A stand-in for the editor's state, carrying only what the walks claim.
    private struct Editor {
        var cuts: VideoCutList
        var trim: VideoTrim
        var playhead: TimeInterval = 0
        var baseline: VideoTrim?

        init(duration: TimeInterval) {
            cuts = VideoCutList(duration: duration)
            trim = VideoTrim(duration: duration)
        }

        /// 1-based, 0 for none, exactly as `expectRecording` counts.
        var picked: Int {
            guard cuts.isCut else { return 0 }
            return (cuts.pieceIndex(atTimeline: playhead) ?? -1) + 1
        }
        var keeps: Int {
            cuts.piecesUnderTrim(fromTimeline: trim.inPoint, toTimeline: trim.outPoint)
                .count { !$0.isDropped }
        }
        var seconds: TimeInterval { trim.effectiveDuration }

        /// `scrub`: clamped into the live window.
        mutating func seek(toFraction f: Double) {
            playhead = min(max(trim.inPoint, cuts.timelineDuration * f), trim.outPoint)
        }
        mutating func cut() { cuts.split(atTimeline: playhead) }
        mutating func beginTrim() { baseline = trim }
        /// `setTrimIn` / `setTrimOut`: move the handle, then seek to it.
        mutating func trimStart() {
            trim.setIn(cuts.timelineDuration * 0.25, duration: cuts.timelineDuration)
            playhead = trim.inPoint
        }
        mutating func trimEnd() {
            trim.setOut(cuts.timelineDuration * 0.75, duration: cuts.timelineDuration)
            playhead = trim.outPoint
        }
        /// `deleteSelectedPiece`, trimming.
        mutating func deletePicked() {
            let index = picked - 1
            let landing = cuts.timelineStart(ofPiece: index)
            let moved = cuts.trimAfterRemovingPiece(at: index, from: trim)
            baseline = baseline.map { cuts.trimAfterRemovingPiece(at: index, from: $0) }
            cuts.removePiece(at: index)
            trim = moved
            playhead = min(landing, cuts.timelineDuration)
        }
        mutating func done() {
            guard trim.isTrimmed else { baseline = nil; return }
            cuts.keep(fromTimeline: trim.inPoint, toTimeline: trim.outPoint)
            trim = VideoTrim(duration: cuts.timelineDuration)
            playhead = 0
            baseline = nil
        }
        mutating func cancel() {
            if let baseline { trim = baseline }
            baseline = nil
        }
    }

    private func check(_ editor: Editor, stage: String,
                       pieces: Int? = nil, picked: Int? = nil,
                       keeps: Int? = nil, seconds: TimeInterval? = nil) {
        if let pieces { #expect(editor.cuts.pieceCount == pieces, "\(stage): pieces") }
        if let picked { #expect(editor.picked == picked, "\(stage): picked") }
        if let keeps { #expect(editor.keeps == keeps, "\(stage): keeps") }
        if let seconds {
            #expect(abs(editor.seconds - seconds) <= 0.05, "\(stage): seconds is \(editor.seconds)")
        }
    }

    /// Three pieces out of the eight second sample: cuts at two and six seconds.
    private func threePieces() -> Editor {
        var editor = Editor(duration: Self.clip)
        editor.seek(toFraction: 0.25)
        editor.cut()
        editor.seek(toFraction: 0.75)
        editor.cut()
        return editor
    }

    @Test("trim-keeps-the-piece-you-picked-walk")
    func keepsThePiecePicked() {
        var editor = threePieces()
        editor.seek(toFraction: 0.5)
        check(editor, stage: "1-middle-piece-picked", pieces: 3, picked: 2)

        editor.beginTrim()
        check(editor, stage: "2-trim-keeps-the-pick",
              pieces: 3, picked: 2, keeps: 3, seconds: 8)

        editor.trimStart()
        check(editor, stage: "3-handle-in-pick-held",
              pieces: 3, picked: 2, keeps: 2, seconds: 6)

        let before = editor
        editor.deletePicked()
        check(editor, stage: "4-delete-took-the-picked-piece",
              pieces: 2, picked: 2, keeps: 1, seconds: 2)

        editor = before  // undo restores the snapshot the edit was made against
        check(editor, stage: "5-undo-brings-it-back",
              pieces: 3, picked: 2, keeps: 2, seconds: 6)

        editor.done()
        check(editor, stage: "6-done-lands-on-the-first-piece",
              pieces: 2, picked: 1, keeps: 2, seconds: 6)
    }

    @Test("trim-cancel-after-a-delete-walk")
    func cancelAfterADelete() {
        var editor = threePieces()
        editor.seek(toFraction: 0.5)
        check(editor, stage: "opening", pieces: 3, picked: 2)

        editor.beginTrim()
        check(editor, stage: "1-handles-open", picked: 2, keeps: 3, seconds: 8)

        editor.trimEnd()
        check(editor, stage: "2-end-handle-on-the-last-join",
              picked: 3, keeps: 2, seconds: 6)

        editor.deletePicked()
        check(editor, stage: "3-piece-dropped-window-whole-again",
              pieces: 2, picked: 2, keeps: 2, seconds: 6)

        editor.trimStart()
        check(editor, stage: "4-start-handle-moved",
              pieces: 2, picked: 1, keeps: 2, seconds: 4.5)

        editor.cancel()
        check(editor, stage: "5-cancel-gives-back-what-is-left",
              pieces: 2, picked: 1, keeps: 2, seconds: 6)
    }
}
