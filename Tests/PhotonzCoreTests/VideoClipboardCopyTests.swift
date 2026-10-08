import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// **An edited video copies to the clipboard as a video or a GIF**
/// (`an-edited-video-copies-to-the-clipboard-as-a-vid`).
///
/// Current's recording window had Copy Video and Copy GIF; Next opens a
/// recording in the editor, where the only way out was a file. Edit ▸ Copy
/// Video and Copy as GIF bring both back, written the way the Export sheet
/// would write them, so what is pasted is what the sheet would have saved.
@Suite("Copying an edited video")
struct VideoClipboardCopyTests {

    private let retina = CGSize(width: 2880, height: 1800)

    @Test("A copy is written at the size and quality the Export sheet last used for that format")
    func usesTheSheetsRememberedChoice() {
        let copy = VideoClipboardCopy.choice(rememberedQuality: .standard,
                                             rememberedSize: .p1080,
                                             canvasSize: retina, format: .mp4)
        #expect(copy.quality == .standard)
        #expect(copy.size == .p1080)
    }

    @Test("A size remembered from a bigger recording falls back to the whole picture, the way the sheet does")
    func aSizeTheDocumentCannotTakeIsFull() {
        let small = CGSize(width: 800, height: 500)
        let copy = VideoClipboardCopy.choice(rememberedQuality: .high, rememberedSize: .p720,
                                             canvasSize: small, format: .mp4)
        #expect(copy.size == .full)
        // GIF offers 480p, which this one can take.
        let gif = VideoClipboardCopy.choice(rememberedQuality: .standard, rememberedSize: .p480,
                                            canvasSize: small, format: .gif)
        #expect(gif.size == .p480)
    }

    @Test("The words burned into the edit go with the copy, and the marks the sheet keeps to")
    func captionsAndRangeMatchTheSheet() {
        let copy = VideoClipboardCopy.choice(rememberedQuality: .high, rememberedSize: .full,
                                             canvasSize: retina, format: .gif)
        #expect(copy.captions == .burnedIn)
        #expect(copy.range == .marked)
    }

    @Test("A copied movie runs as long as the edit when it is within one of its frames")
    func lengthMatchesWithinAFrame() {
        #expect(VideoClipboardCopy.runsAsLong(fileMS: 4_000, asEditMS: 4_000, fps: 30))
        #expect(VideoClipboardCopy.runsAsLong(fileMS: 4_033, asEditMS: 4_000, fps: 30))
        #expect(VideoClipboardCopy.runsAsLong(fileMS: 3_967, asEditMS: 4_000, fps: 30))
        // A GIF's frames are longer, so it may land further off.
        #expect(VideoClipboardCopy.runsAsLong(fileMS: 4_060, asEditMS: 4_000, fps: 15))
        // The raw recording, ten seconds where the edit is four, is not the edit.
        #expect(!VideoClipboardCopy.runsAsLong(fileMS: 10_000, asEditMS: 4_000, fps: 30))
        #expect(!VideoClipboardCopy.runsAsLong(fileMS: 4_200, asEditMS: 4_000, fps: 30))
        #expect(!VideoClipboardCopy.runsAsLong(fileMS: 0, asEditMS: 0, fps: 30))
    }

    @Test("A copied GIF is the edit when it holds the edit's frames, whatever its delays round to")
    func gifFramesMatchTheEdit() {
        // Four seconds at 15 a second is 60 frames, stored at 7 hundredths
        // each because a GIF cannot say 6.67: it plays 4.2 seconds, and it is
        // still exactly the edit's frames.
        #expect(VideoClipboardCopy.holdsTheEdit(frames: 60, editMS: 4_000, fps: 15))
        #expect(VideoClipboardCopy.holdsTheEdit(frames: 61, editMS: 4_000, fps: 15))
        // The eight second recording it was cut from is twice as many.
        #expect(!VideoClipboardCopy.holdsTheEdit(frames: 120, editMS: 4_000, fps: 15))
        #expect(!VideoClipboardCopy.holdsTheEdit(frames: 0, editMS: 4_000, fps: 15))
    }

    @Test("While it writes, the toast names what it is copying")
    func copyingTitles() {
        #expect(RecordingFormat.mp4.copyingTitle == "Copying the video")
        #expect(RecordingFormat.gif.copyingTitle == "Copying the GIF")
        #expect(RecordingFormat.heic.copyingTitle == "Copying the HEIC")
    }

    @Test("When it lands the toast says Copied and names the file; a failure says it was not copied")
    func theResultToast() {
        let landed = CopyConfirmation(subject: .videoCopied(file: "Talk.mp4", format: .mp4),
                                      shownAt: Date(), resultsOnly: true)
        #expect(landed.title == "Copied")
        #expect(landed.detail == "Talk.mp4")
        let gif = CopyConfirmation(subject: .videoCopied(file: nil, format: .gif),
                                   shownAt: Date(), resultsOnly: true)
        #expect(gif.title == "Not copied")
        #expect(gif.detail == "The GIF could not be copied")
        let movie = CopyConfirmation(subject: .videoCopied(file: nil, format: .mp4),
                                     shownAt: Date(), resultsOnly: true)
        #expect(movie.detail == "The video could not be copied")
    }

    @Test("Edit ▸ Copy Video is ⌃⇧⌘C and Copy as GIF is ⌃⇧⌘G, which a walk can press")
    func chordsHaveStandIns() throws {
        let c = try #require(PlaytestKey("c")), g = try #require(PlaytestKey("g"))
        #expect(PlaytestMenuStandIn.action(for: c, modifiers: [.control, .shift, .command]) == .copyVideo)
        #expect(PlaytestMenuStandIn.action(for: g, modifiers: [.command, .shift, .control]) == .copyAsGIF)
        // The neighbours keep their own meanings.
        #expect(PlaytestMenuStandIn.action(for: c, modifiers: [.command, .shift]) == .copyMerged)
        #expect(PlaytestMenuStandIn.action(for: g, modifiers: [.command, .shift]) == nil)
    }

    @Test("A readClipboard step can claim the clipboard holds the edit as a movie")
    func readClipboardCanClaimAMovie() throws {
        let script = try PlaytestScript.decode(Data("""
        { "steps": [ { "do": "readClipboard", "stage": "a", "movie": true },
                     { "do": "readClipboard", "stage": "b" },
                     { "do": "action", "action": "copyVideo" },
                     { "do": "action", "action": "copyAsGIF" },
                     { "do": "action", "action": "awaitCopy" } ] }
        """.utf8))
        guard case .readClipboard(_, _, let claimed, _) = script.steps[0],
              case .readClipboard(_, _, let unclaimed, _) = script.steps[1],
              case .action(let video) = script.steps[2],
              case .action(let gif) = script.steps[3],
              case .action(let wait) = script.steps[4] else {
            Issue.record("readClipboard"); return
        }
        #expect(claimed)
        #expect(!unclaimed)
        #expect(video == .copyVideo)
        #expect(gif == .copyAsGIF)
        #expect(wait == .awaitCopy)
    }
}
