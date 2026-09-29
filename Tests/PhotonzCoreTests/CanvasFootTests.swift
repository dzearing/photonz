import CoreGraphics
import PhotonzCore
import Testing

// The bottom of the canvas (`EditorChromeLayout.canvasFoot`).
//
// Three things want the band just above the floating tool bar: the capsule a
// modal tool puts up (Trim's In · Out · Cancel · Trim, Crop's Cancel · Crop),
// the notice pill (Captions written, Clip added, a refusal), and on a captioned
// recording the caption line itself. Until 2026-09-28 the capsule and the pill
// were both padded to exactly `aboveToolBar`, so the pill lay under the capsule
// and could not be read at all, and on a small picture both sat on the caption.
// One layout now: the capsule, then the pill on top of it, and both lifted
// clear of the captions when they would cover them.
@Suite("Canvas foot")
struct CanvasFootTests {

    private let canvas = CGSize(width: 1000, height: 700)
    private let base = EditorChromeLayout.aboveToolBar
    private let gap = EditorChromeLayout.toolBarStackGap
    private let capsule = CGSize(width: 480, height: 50)
    private let notice = CGSize(width: 420, height: 34)

    private func frame(bottom: CGFloat, size: CGSize) -> CGRect {
        CGRect(x: (canvas.width - size.width) / 2, y: canvas.height - bottom - size.height,
               width: size.width, height: size.height)
    }

    // MARK: - Nothing to keep clear

    @Test func withNoCapsuleTheNoticeKeepsItsOldPlace() {
        let foot = EditorChromeLayout.canvasFoot(canvasSize: canvas, base: base,
                                                 capsuleSize: nil, noticeSize: notice, keepClear: [])
        #expect(foot.noticeBottom == base)
        #expect(foot.capsuleBottom == base)
    }

    @Test func theNoticeStacksOnTopOfTheCapsuleRatherThanUnderIt() {
        let foot = EditorChromeLayout.canvasFoot(canvasSize: canvas, base: base,
                                                 capsuleSize: capsule, noticeSize: notice, keepClear: [])
        #expect(foot.capsuleBottom == base, "the capsule stays where Crop and Trim always put it")
        #expect(foot.noticeBottom == base + capsule.height + gap)
        let a = frame(bottom: foot.capsuleBottom, size: capsule)
        let b = frame(bottom: foot.noticeBottom, size: notice)
        #expect(!a.intersects(b))
    }

    // MARK: - Captions

    @Test func captionsWellAboveTheFootMoveNothing() {
        let caption = CGRect(x: 250, y: 400, width: 500, height: 60)
        let foot = EditorChromeLayout.canvasFoot(canvasSize: canvas, base: base,
                                                 capsuleSize: capsule, noticeSize: notice,
                                                 keepClear: [caption])
        #expect(foot.capsuleBottom == base)
        #expect(foot.noticeBottom == base + capsule.height + gap)
    }

    @Test func aCapsuleThatWouldCoverTheCaptionsRisesClearOfThem() {
        // A small picture: its caption box sits where the capsule would be.
        let caption = CGRect(x: 300, y: 560, width: 400, height: 50)
        let foot = EditorChromeLayout.canvasFoot(canvasSize: canvas, base: base,
                                                 capsuleSize: capsule, noticeSize: notice,
                                                 keepClear: [caption])
        let a = frame(bottom: foot.capsuleBottom, size: capsule)
        let b = frame(bottom: foot.noticeBottom, size: notice)
        #expect(!a.intersects(caption))
        #expect(!b.intersects(caption))
        #expect(!a.intersects(b))
        #expect(a.maxY == caption.minY - gap, "just clear of them, not flung up the picture")
    }

    @Test func withNoCapsuleTheNoticeAloneRisesOverTheCaptions() {
        // Clip added on a captioned recording used to land on the caption line.
        let caption = CGRect(x: 300, y: 590, width: 400, height: 40)
        let foot = EditorChromeLayout.canvasFoot(canvasSize: canvas, base: base,
                                                 capsuleSize: nil, noticeSize: notice,
                                                 keepClear: [caption])
        #expect(!frame(bottom: foot.noticeBottom, size: notice).intersects(caption))
    }

    @Test func captionsOffToOneSideLeaveTheCentredCapsuleAlone() {
        let caption = CGRect(x: 10, y: 560, width: 150, height: 50)
        let foot = EditorChromeLayout.canvasFoot(canvasSize: canvas, base: base,
                                                 capsuleSize: capsule, noticeSize: notice,
                                                 keepClear: [caption])
        #expect(foot.capsuleBottom == base)
    }

    @Test func aLiftThatWouldLeaveTheCanvasIsNotMade() {
        // A caption box as tall as the canvas: rising over it would put the
        // capsule off the top, which is worse than sitting where it always does.
        let caption = CGRect(x: 0, y: 20, width: 1000, height: 660)
        let foot = EditorChromeLayout.canvasFoot(canvasSize: canvas, base: base,
                                                 capsuleSize: capsule, noticeSize: notice,
                                                 keepClear: [caption])
        #expect(foot.capsuleBottom == base)
    }
}
