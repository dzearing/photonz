import AppKit
import PhotonzCore

// A recording opened the moment it was stopped (`ClosingRecording`).
//
// macOS takes most of a second to close a long recording's file. The frame the
// recording ended on is in memory from the moment Stop is pressed, so a window
// asked for in that time opens at once on that frame, in View, with the
// playhead on the moment it really is and the transport there. Play pressed
// meanwhile is remembered. When the file lands its real length and size are
// taken on under the same identity the stand-in had, outside the undo history
// and without marking anything edited, so the frame on screen keeps drawing,
// the window does not change, and nothing done while it landed is lost.

extension EditorState {

    /// Open a recording whose file is still being closed on the frame it
    /// ended on. False when there is no such frame held for it, and the
    /// caller opens it the ordinary way.
    func openClosingRecording(at url: URL, from store: CaptureStore) -> Bool {
        guard let reserved = store.closingRecordingURL(matching: url) else { return false }
        Task { @MainActor [weak self] in
            guard let picture = await store.closingPicture(for: reserved) else {
                // The frame could not be read: wait for the file instead, the
                // way every recording was opened before.
                store.whenLanded(reserved) { [weak self] landed in
                    guard let self else { return }
                    guard let landed else { onRecordingWouldNotOpen?(reserved); return }
                    openRecordingAsDocument(at: landed.url)
                }
                return
            }
            self?.installClosingRecording(picture, url: reserved, store: store)
        }
        return true
    }

    private func installClosingRecording(_ picture: CaptureStore.ClosingPicture, url: URL,
                                         store: CaptureStore) {
        let standIn = picture.recording.standIn(id: picture.movieID)
        let name = url.deletingPathExtension().lastPathComponent
        var opened = PhotonzDocument.recording(standIn, name: name)
        opened.rememberMedia(.recording(standIn), named: url.lastPathComponent)
        installDocument(opened, url: nil)
        recordingAsOpened = opened
        recordingURL = url
        openedFileURL = url
        markSaved()
        // The frame is filed where the playhead waits before anything draws,
        // so the window's first picture is the recording's last.
        let waiting = picture.recording.waitingMS
        for request in opened.movieFrames(atTimeMS: waiting) {
            movieFrames.hold(picture.image, for: request)
        }
        recordingStillLanding = true
        closingRecordingWaitingMS = waiting
        documentTimeMS = waiting
        documentMomentChanged()
        restoreTimelineView()
        openInItsMode(opened)
        #if PHOTONZ_PLAYTEST
        PlaytestHarness.register(self)
        #endif
        store.whenLanded(url) { [weak self] landed in
            Task { @MainActor [weak self] in
                await self?.closingRecordingLanded(landed, standIn: standIn, reserved: url)
            }
        }
    }

    private func closingRecordingLanded(_ landed: CaptureEntry?, standIn: MovieRef, reserved: URL) async {
        guard let landed,
              let real = await MovieLibrary.shared.movie(at: landed.url, as: standIn.id) else {
            recordingStillLanding = false
            playWhenLanded = false
            onRecordingWouldNotOpen?(reserved)
            return
        }
        applyWithoutMarkingEdited { $0.adoptLandedRecording(real) }
        recordingAsOpened?.adoptLandedRecording(real)
        recordingURL = landed.url
        openedFileURL = landed.url
        recordingStillLanding = false
        // Still where it waited: it stays on the last frame, which is now the
        // file's own last moment, so Play starts from the top.
        if documentTimeMS == closingRecordingWaitingMS {
            documentTimeMS = lastDocumentTimeMS
        }
        closingRecordingWaitingMS = nil
        let play = playWhenLanded
        playWhenLanded = false
        if play { playDocument() } else { documentMomentChanged() }
    }
}
