import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// **Saving an edited recording puts the finished video in history**
/// (`saving-an-edited-recording-puts-the-finished-vid`).
///
/// A recording in history is a file somebody pastes into a chat. Command S on
/// an edit of it keeps the edit as a project beside the file, writes the
/// finished video over the file, and keeps the recording as it was made in the
/// hidden originals folder, so the tile is the edited video and nothing is lost.
@Suite("Saving an edited recording into history")
struct HistoryVideoSaveTests {

    private func situation(inHistory: Bool = true, fileThere: Bool = true, untouched: Bool = false,
                           originalKept: Bool = false, playsTheHistoryFile: Bool = true)
        -> HistoryVideoSave.Situation {
        HistoryVideoSave.Situation(inHistory: inHistory, fileThere: fileThere, untouched: untouched,
                                   originalKept: originalKept, playsTheHistoryFile: playsTheHistoryFile)
    }

    @Test("The first save of an edit keeps the recording as it was made and writes the edit over the tile's file")
    func firstSaveKeepsTheOriginal() {
        #expect(HistoryVideoSave.plan(situation()) == .writeTheEdit(keepOriginal: true))
    }

    @Test("Saving again writes the edit in place: the original is already kept and the edit plays it")
    func secondSaveReplacesInPlace() {
        #expect(HistoryVideoSave.plan(situation(originalKept: true, playsTheHistoryFile: false))
                == .writeTheEdit(keepOriginal: false))
    }

    @Test("A recording nobody has changed saves nothing new")
    func untouchedSavesNothing() {
        #expect(HistoryVideoSave.plan(situation(untouched: true)) == .nothingToDo)
    }

    @Test("An edit taken all the way back to the recording puts the recording back on the tile")
    func untouchedAfterAnEditPutsTheRecordingBack() {
        #expect(HistoryVideoSave.plan(situation(untouched: true, originalKept: true, playsTheHistoryFile: false))
                == .putTheRecordingBack)
    }

    @Test("A recording that is not in history, or whose file has not landed, asks where to save as before")
    func outsideHistoryAsksWhere() {
        #expect(HistoryVideoSave.plan(situation(inHistory: false)) == .askWhere)
        #expect(HistoryVideoSave.plan(situation(fileThere: false)) == .askWhere)
        #expect(HistoryVideoSave.plan(situation(inHistory: false, untouched: true)) == .askWhere)
    }

    @Test("A file that is already an edit of a kept original, opened on its own, is never written over")
    func anEditOfAnEditAsksWhere() {
        // The original is kept but this window plays the tile's file itself:
        // writing over it would lose the only copy of what it plays.
        #expect(HistoryVideoSave.plan(situation(originalKept: true, playsTheHistoryFile: true)) == .askWhere)
    }

    @Test("The finished video is the Export sheet's MP4 at High, the recording's own size, all of it, captions in the picture")
    func theChoiceMatchesTheExportSheetsBest() {
        let choice = HistoryVideoSave.choice
        #expect(choice.quality == .high)
        #expect(choice.size == .full)
        #expect(choice.range == .whole)
        #expect(choice.captions == .burnedIn)
    }

    @Test("The project beside the tile is the edit while it is as new as the video, and not once the video has been replaced by something else")
    func theProjectIsCurrentOnlyWhileTheVideoIsItsOwn() {
        let saved = Date(timeIntervalSince1970: 1_000_000)
        #expect(HistoryVideoSave.projectIsCurrent(projectModified: saved, videoModified: saved))
        // Saved, and the video still being written: the project is newer.
        #expect(HistoryVideoSave.projectIsCurrent(projectModified: saved, videoModified: saved.addingTimeInterval(-60)))
        // Within the slack a file system's dates allow.
        #expect(HistoryVideoSave.projectIsCurrent(projectModified: saved, videoModified: saved.addingTimeInterval(1.5)))
        // Something else wrote the video a minute later: the video is the truth.
        #expect(!HistoryVideoSave.projectIsCurrent(projectModified: saved, videoModified: saved.addingTimeInterval(60)))
        #expect(!HistoryVideoSave.projectIsCurrent(projectModified: nil, videoModified: saved))
        #expect(!HistoryVideoSave.projectIsCurrent(projectModified: saved, videoModified: nil))
    }

    @Test("The video is written in the hidden originals folder first, so history never lists half a file")
    func writtenOutOfSight() {
        let tile = URL(fileURLWithPath: "/Users/me/Pictures/Screenshots/Recording 1.mp4")
        let writing = HistoryVideoSave.writingURL(for: tile)
        #expect(writing.deletingLastPathComponent() == VideoOriginals.url(for: tile).deletingLastPathComponent())
        #expect(writing.pathExtension == "mp4")
        #expect(writing.lastPathComponent != tile.lastPathComponent)
        #expect(HistoryVideoSave.projectURL(for: tile).lastPathComponent == "Recording 1.photonz")
    }

    @Test("Saves still to finish are remembered by path, once each, and forgotten when they land")
    func pendingSavesAreRemembered() {
        var pending = HistoryVideoSave.Pending()
        pending.add("/a.mp4")
        pending.add("/b.mp4")
        pending.add("/a.mp4")
        #expect(pending.paths == ["/a.mp4", "/b.mp4"])
        pending.remove("/a.mp4")
        #expect(pending.paths == ["/b.mp4"])
        let back = HistoryVideoSave.Pending(paths: pending.paths)
        #expect(back == pending)
    }
}
