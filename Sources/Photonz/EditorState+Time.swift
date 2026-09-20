import AppKit
import Foundation
import PhotonzCore

// The transport, for a document that has time (`docs/design/video.md` §5).
//
// There is no video window and no video state. A recording is a document, so
// playing one is the same window drawing a different moment, and everything the
// editor already does — picking a layer, naming it, hiding it, styling it,
// undoing — keeps working while it plays.
//
// The whole surface is a playhead in milliseconds. Play moves it, scrubbing
// puts it somewhere, and the canvas draws `document.drawn(atTimeMS:)` for
// wherever it is.
extension EditorState {

    // MARK: Whether there is time at all

    /// True where this document runs for a length of time. False for every
    /// screenshot, which is what keeps the transport, the timeline and the
    /// frame fetching out of the way of everything else.
    var documentHasTime: Bool { document?.hasTime ?? false }

    /// How long it runs for.
    var documentLengthMS: Int { document?.documentDurationMS ?? 0 }

    /// The last moment there is a picture at.
    var lastDocumentTimeMS: Int { max(0, documentLengthMS - 1) }

    /// Where a clip's pixels come from, made the first time one is asked for.
    var movieFrames: MovieFrameFetcher {
        if let already = movieFramesStorage { return already }
        let fetcher = MovieFrameFetcher(store: store)
        fetcher.onFrameLanded = { [weak self] in self?.movieFrameLanded() }
        movieFramesStorage = fetcher
        return fetcher
    }

    // MARK: Moving the playhead

    /// Put the playhead somewhere. Anything outside the document is clamped to
    /// it: there is no frame before the first one and none after the last.
    func scrubDocument(toMS ms: Int) {
        let landing = min(max(0, ms), lastDocumentTimeMS)
        guard landing != documentTimeMS else { return }
        documentTimeMS = landing
        // A scrub while it plays takes over: the clock restarts from where the
        // hand put the playhead rather than snapping back to where it had got
        // to on its own.
        if isDocumentPlaying { restartDocumentClock() }
        documentMomentChanged()
    }

    /// One frame on, or back with a negative count. The step is the grid frames
    /// are fetched on, so stepping always lands on a frame that can be drawn.
    func stepDocument(byFrames frames: Int) {
        pauseDocument()
        scrubDocument(toMS: documentTimeMS + frames * MovieRef.frameStepMS)
    }

    func goToDocumentStart() {
        pauseDocument()
        scrubDocument(toMS: 0)
    }

    func goToDocumentEnd() {
        pauseDocument()
        scrubDocument(toMS: lastDocumentTimeMS)
    }

    // MARK: Playing

    /// Space, and the play button: the same one switch.
    func toggleDocumentPlayback() {
        isDocumentPlaying ? pauseDocument() : playDocument()
    }

    func playDocument() {
        guard documentHasTime, !isDocumentPlaying else { return }
        // Playing from the last frame starts over, which is what pressing play
        // at the end of something obviously means.
        if documentTimeMS >= lastDocumentTimeMS { documentTimeMS = 0 }
        isDocumentPlaying = true
        restartDocumentClock()
    }

    func pauseDocument() {
        guard isDocumentPlaying else { return }
        isDocumentPlaying = false
        documentPlaybackTask?.cancel()
        documentPlaybackTask = nil
        documentPlaybackStartedAt = nil
        documentMomentChanged()
    }

    /// The clock. Real time rather than a frame count, so a frame that takes
    /// too long to decode costs that frame and not the timing of everything
    /// after it: the playhead is always where the wall clock says it should be.
    private func restartDocumentClock() {
        documentPlaybackTask?.cancel()
        documentPlaybackStartedAt = Date()
        documentPlaybackStartedAtMS = documentTimeMS
        let end = lastDocumentTimeMS
        documentPlaybackTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(MovieRef.frameStepMS))
                guard let self, isDocumentPlaying, let started = documentPlaybackStartedAt else { return }
                let elapsed = Int(Date().timeIntervalSince(started) * 1000)
                let landing = documentPlaybackStartedAtMS + elapsed
                if landing >= end {
                    // It finishes rather than looping: a recording has a last
                    // frame, and sitting on it is what having watched it looks
                    // like.
                    documentTimeMS = end
                    pauseDocument()
                    return
                }
                documentTimeMS = landing
                documentMomentChanged()
            }
        }
    }

    // MARK: Drawing the moment

    /// The playhead moved, so the picture has to. Asks for whatever frames this
    /// moment needs and redraws with what is already in hand, which is what
    /// keeps a scrub responsive: the canvas never waits on a decode, it shows
    /// the last frame it has and replaces it the instant the right one lands.
    func documentMomentChanged() {
        guard let document else { return }
        let wanted = document.movieFrames(atTimeMS: documentTimeMS)
        if !wanted.isEmpty {
            movieFrames.fetch(wanted)
            // ...and the handful just ahead, so playing forward is decoding
            // ahead of the playhead rather than behind it.
            if isDocumentPlaying {
                for step in 1...3 {
                    let ahead = documentTimeMS + step * MovieRef.frameStepMS
                    guard ahead <= lastDocumentTimeMS else { break }
                    movieFrames.fetch(document.movieFrames(atTimeMS: ahead))
                }
            }
        }
        submit(document)
    }

    /// A frame arrived that the canvas did not have when it last drew.
    func movieFrameLanded() {
        guard let document, documentHasTime else { return }
        // A clip's row in the layers list is drawn from the frame it points at,
        // and its cache is keyed on the LAYER, which does not change when a
        // frame lands. So a row first drawn before the first frame was decoded
        // would stay blank for the life of the window. Not while playing: a
        // thumbnail redrawn thirty times a second is a thumbnail nobody can
        // read and a core spent on nothing.
        if !isDocumentPlaying {
            for layer in document.allLayers where layer.isClip {
                thumbnailCache[layer.id] = nil
            }
        }
        submit(document)
    }

    // MARK: Reading the clock

    /// `0:04` or `1:02:11`, the way every transport in the world says it.
    static func timecode(ms: Int) -> String {
        let total = max(0, ms) / 1000
        let seconds = total % 60
        let minutes = (total / 60) % 60
        let hours = total / 3600
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, seconds) }
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// Where the playhead is, said the way the transport says it.
    var documentTimecode: String { Self.timecode(ms: documentTimeMS) }
    /// How long the whole thing is.
    var documentLengthTimecode: String { Self.timecode(ms: documentLengthMS) }
}
