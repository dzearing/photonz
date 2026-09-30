import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// Pills and toasts say what happened, never how to do something
/// (`pills-and-toasts-say-what-happened-never-how-to`, 2026-09-30).
///
/// The placement contract (`shared/UX-PATTERNS.md`, the table at the top):
/// "Toasts: what just happened. Results, with Undo when it applies. Never
/// instructions", and the canvas carries "never persistent status pills".
/// With Next's `next-notices-say-what-happened` on, a notice is built
/// `resultsOnly`, the standing how-to pills are gone, and what they taught
/// moves to the tool's hover tip and the tutorials, in the same words.
@Suite("Notices say what happened")
struct NoticesSayWhatHappenedTests {

    private let t0 = Date(timeIntervalSinceReferenceDate: 3_000)

    // MARK: - Telling an instruction from a result

    static let instructions: [String] = [
        PathEditHint.opening, PathEditHint.penOpening, PathEditHint.cornerPicked,
        PathEditHint.bendPicked, PathEditHint.halfPicked, PathEditHint.severalPicked,
        PathEditHint.justTurned(paths: 1), PathEditHint.justJoined(paths: 2),
        PathEditHint.justClosed(paths: 1), PathEditHint.nothingJoined(), PathEditHint.nothingClosed(),
        PenSession.hint(for: PenSession()),
        "Click the next point, or press and drag for a curve. Esc starts over.",
        "Keep clicking points. Return finishes the line, Esc discards it.",
        "Only a picture can have a piece cut out. Turn it into a picture from the Layer menu, then try again.",
        "Only a picture can have a piece cut out. Command J copies the whole layer instead.",
        "This picture is cropped or turned. Clear the marquee to cut the whole layer.",
        "More than one run of text here. Separate into Layers first, then turn one run into words",
        "2 runs of text. 4 left in the picture, run it again for more",
        "Pick a shape to put it on", "Pick two shapes that have an inside",
        "Label comes from Button. Detach this copy to edit it.",
        "It was still being written after 30 seconds. Try again once it has landed.",
    ] + MeasureToolMode.allCases.map(\.hint)

    static let results: [String] = [
        "Copied", "2 runs of text and 1 box", "Turned into text", "Label, set in SF Pro",
        "The look of Title", "3 shapes are now one path", "1 of 3 shapes shows. Copies pick it with Size",
        "There is no cut at the playhead", "\u{2318}T now puts Dissolve on a cut",
        "Clip.mov is on the timeline at the playhead", "Turned into a path", "Joined into one path",
        "Closed", "No two ends are within 2 pt of each other", "The points are in a line",
        "Only a picture can have a piece taken out.", "The original arrived beside it. Editing that changes every copy",
    ]

    @Test(arguments: instructions)
    func aLineOfAdviceIsCaught(line: String) {
        #expect(!NoticeCopy.instructions(in: line).isEmpty, "\"\(line)\" tells somebody what to do")
    }

    @Test(arguments: results)
    func aResultIsLeftAlone(line: String) {
        #expect(NoticeCopy.instructions(in: line).isEmpty,
                "\"\(line)\" only says what happened: \(NoticeCopy.instructions(in: line))")
    }

    // MARK: - Every notice, built results only

    private func notice(_ subject: CopyConfirmation.Subject,
                        action: CanvasNoticeAction? = nil) -> CopyConfirmation {
        CopyConfirmation(subject: subject, shownAt: t0, action: action, resultsOnly: true)
    }

    private var piece: ComponentPiece {
        ComponentPiece(layer: UUID(), instance: UUID(), componentID: UUID(), source: UUID(), isNested: false)
    }

    private var everyNoticeThatUsedToAdvise: [CopyConfirmation] {
        var all: [CopyConfirmation] = []
        for action in [RegionSliceRefusal.Action.cut, .erase, .fill, .cutToLayer] {
            for reason in [RegionSliceRefusal.Reason.notPixels, .canBecomeAPicture, .adjustedPicture] {
                all.append(notice(.regionSliceRefused(RegionSliceRefusal(action: action, reason: reason))))
            }
        }
        all.append(notice(.turnedIntoText(.refused(.moreThanOneRun))))
        all.append(notice(.separatedIntoLayers(runs: 2, boxes: 0, skipped: 1, crowded: 3)))
        all.append(notice(.lookPasted(LookPaste(layerCount: 0))))
        all.append(notice(.shapesCombined(PathCombinePlan(operation: .join, takes: 1))))
        for remedy in [ComponentPieceRemedy.unlock, .exposeWording, .detach] {
            all.append(notice(.componentPieceRefused(
                ComponentPieceRefusal(piece: piece, component: "Button", pieceName: "Label", remedy: remedy))))
        }
        all += [notice(.pathTurned(paths: 1), action: .undo), notice(.pathTurned(paths: 3), action: .undo),
                notice(.pathJoined(paths: 1), action: .undo), notice(.pathClosed(paths: 2), action: .undo),
                notice(.nothingJoined(gap: PathJoin.tolerance)), notice(.nothingClosed)]
        return all
    }

    @Test func noNoticeEndsWithAdvice() {
        for notice in everyNoticeThatUsedToAdvise {
            let said = "\(notice.title). \(notice.detail)"
            #expect(NoticeCopy.instructions(in: said).isEmpty,
                    "\(notice.subject) still says how: \(NoticeCopy.instructions(in: said))")
        }
    }

    @Test func currentKeepsEveryLineItHad() {
        // Built without `resultsOnly`, which is how Current (and Next with the
        // switch off) builds them: word for word what they said before.
        let refusal = RegionSliceRefusal(action: .cut, reason: .canBecomeAPicture)
        #expect(CopyConfirmation(subject: .regionSliceRefused(refusal), shownAt: t0).detail
                == refusal.detail)
        #expect(CopyConfirmation(subject: .separatedIntoLayers(runs: 2, boxes: 0, skipped: 1, crowded: 3),
                                 shownAt: t0).detail
                == "2 runs of text. 4 left in the picture, run it again for more")
        #expect(CopyConfirmation(subject: .turnedIntoText(.refused(.moreThanOneRun)), shownAt: t0).detail
                == TextReading.Refusal.moreThanOneRun.sentence)
    }

    @Test func aResultStillSaysWhatItFound() {
        let separated = notice(.separatedIntoLayers(runs: 2, boxes: 0, skipped: 1, crowded: 3))
        #expect(separated.detail == "2 runs of text. 4 left in the picture")
        #expect(notice(.turnedIntoText(.refused(.moreThanOneRun))).detail == "More than one run of text here")
        let slice = notice(.regionSliceRefused(RegionSliceRefusal(action: .cut, reason: .notPixels)))
        #expect(slice.detail == "Only a picture can have a piece taken out")
    }

    @Test func reshowingKeepsTheWording() {
        let first = notice(.nothingClosed)
        #expect(first.reshown(as: .nothingJoined(gap: 2), at: t0).resultsOnly)
    }

    // MARK: - A path's results are notices, with Undo

    @Test func aPathResultSaysWhatHappenedAndOffersUndo() {
        #expect(notice(.pathTurned(paths: 1)).title == "Turned into a path")
        #expect(notice(.pathTurned(paths: 3)).title == "Turned into 3 paths")
        #expect(notice(.pathJoined(paths: 1)).title == "Joined into one path")
        #expect(notice(.pathClosed(paths: 1)).title == "Closed")
        #expect(notice(.pathClosed(paths: 2)).title == "Closed 2 paths")
        #expect(notice(.nothingJoined(gap: 2)).title == "Nothing joined")
        #expect(notice(.nothingJoined(gap: 2)).detail == "No two ends are within 2 pt of each other")
        #expect(notice(.nothingClosed).title == "Nothing closed")
        #expect(notice(.nothingClosed).detail == "The points are in a line")
        #expect(CanvasNoticeAction.undo.label == "Undo")
        #expect(CanvasNoticeAction.undo.shortcutHint == "\u{2318}Z")
        #expect(CanvasNoticeAction.undo.presentation == .button)
        #expect(CanvasNoticeAction.undo.layerIDs.isEmpty)
        // Long enough to reach for the button.
        #expect(notice(.pathTurned(paths: 1), action: .undo).lifetime == CopyConfirmation.actionLifetime)
        #expect(notice(.nothingClosed).lifetime == CopyConfirmation.breakLifetime)
    }

    // MARK: - The teaching moves to the tip, in the same words

    @Test func thePenTipCarriesTheWordsThePillSaid() {
        let tip = PenSession.toolTipDetail
        #expect(tip.contains("Click to place a corner, or press and drag for a curve"))
        #expect(tip.contains("Click the first point to close the shape"))
        #expect(tip.contains("Return finishes it open, Esc discards it"))
    }

    @Test func eachMeasureModeTipCarriesItsPillLine() {
        for mode in MeasureToolMode.allCases {
            #expect(mode.toolTipDetail == mode.hint)
        }
    }

    @Test func theReshapeTutorialTeachesEveryGestureThePathPillDid() throws {
        let guide = try #require(TutorialCatalog.guide(id: "reshape-what-you-drew"))
        let words = guide.steps.map { "\($0.title) \($0.body)" }.joined(separator: " ")
        for gesture in ["Drag a point to reshape", "a box to pick several", "the outline to add one",
                        "Option drag frees the two sides", "Arrow keys nudge, Delete takes them out"] {
            #expect(words.contains(gesture), "the reshape guide never says \"\(gesture)\"")
        }
    }

    @Test func thePenTutorialNoLongerPointsAtALineUnderTheCanvas() throws {
        let guide = try #require(TutorialCatalog.guide(id: "draw-it-with-the-pen"))
        #expect(!guide.steps.contains { $0.id == "the-line-underneath" })
        let words = guide.steps.map(\.body).joined(separator: " ")
        #expect(!words.contains("under the canvas"))
        #expect(words.contains("Return finishes it open, Esc discards it"))
    }

    // MARK: - The global toast

    @Test func aRecordingThatNeverLandedSaysSoWithoutAdvice() {
        let said = RecordingDoor.gaveUpMessage(name: "Take 1.mov", resultsOnly: true)
        #expect(NoticeCopy.instructions(in: said.detail).isEmpty, "\(said.detail)")
        #expect(RecordingDoor.gaveUpMessage(name: "Take 1.mov").detail.contains("Try again"))
    }

    // MARK: - The switch

    @Test func theSwitchIsNextOnlyAndOnByDefault() throws {
        let name = FeatureCatalog.noticesSayWhatHappenedFlag
        let next = try #require(FeatureCatalog.flags(for: .next).first { $0.name == name })
        #expect(next.isEnabled)
        #expect(!FeatureCatalog.flags(for: .current).contains { $0.name == name })
    }
}
