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
    ///
    /// The document AS IT IS BEING SHOWN, which is the same thing except
    /// while a trim is running: then the clip is laid out at full length, so
    /// the transport and the ruler say how much there is to choose from rather
    /// than how much is currently kept (`EditorState+Trim`).
    var documentLengthMS: Int { shownDocument?.documentDurationMS ?? 0 }

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

    // MARK: Where you were

    /// Note where the playhead is, so opening this recording again comes back
    /// to it instead of starting over (`RecordingPlaces`). Called when playback
    /// stops and when the window goes, never while a drag is running: what is
    /// worth keeping is where somebody LEFT it.
    func noteRecordingPlace() {
        guard Experiments.shared.openingARecording, documentHasTime,
              let url = recordingURL, documentLengthMS > 0 else { return }
        RecordingPlaceStore.shared.remember(url: url, momentMS: documentTimeMS,
                                            durationMS: documentLengthMS)
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
        if isDocumentPlaying {
            restartDocumentClock()
            // The sound is scheduled against one engine start, so a scrub
            // mid-play has to schedule it again from where the hand put the
            // playhead. Nothing is faded: a scrub is somebody looking for a
            // moment, and what they want to hear is that moment.
            startAudio()
        }
        // ...and where the playhead is being DRAGGED, the sliver of sound
        // under it, so somebody hunting for a word can hear it go by
        // (`ScrubAudition.swift`). Does nothing unless a drag is in hand.
        auditionScrub()
        documentMomentChanged()
    }

    // MARK: Dragging the playhead

    // The three calls a hand on the playhead makes, in one place rather than
    // inside a gesture, so the timeline's own drag and a scripted walk drive
    // the same thing. Taking hold is where the listening starts; letting go is
    // where it stops (`ScrubAudition.swift`).

    /// A hand took hold of the playhead.
    func beginPlayheadDrag() { beginScrubAudition() }

    /// ...and moved it. The same landing as any other scrub, so the canvas,
    /// the ruler and the sound all follow one call.
    func dragPlayhead(toMS ms: Int) { scrubDocument(toMS: ms) }

    /// ...and let go.
    func endPlayheadDrag() { endScrubAudition() }

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
        // Anything left listening to a hand stands down: the whole mix is
        // about to play, and a scrub over the top of it is the same sound
        // twice (`ScrubAudition.swift`).
        endScrubAudition()
        restartDocumentClock()
        startAudio()
    }

    func pauseDocument() {
        guard isDocumentPlaying else { return }
        noteRecordingPlace()
        isDocumentPlaying = false
        stopAudio()
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
        guard let document = shownDocument else { return }
        // A timeline opened out carries its window along with the playhead, a
        // screenful at a time (`EditorState+TimelineZoom`). Free where the
        // playhead is already on screen, which is nearly every call.
        followTimelineWindow()
        // Every layer's level put where the plan says it is at this moment,
        // which is what turns a pair of points into a duck you can hear
        // (`EditorState+Audio.swift`).
        followAudio()
        let wanted = document.movieFrames(atTimeMS: documentTimeMS)
        if !wanted.isEmpty {
            let size = movieDecodeSize(in: document)
            movieFrames.fetch(wanted, size: size)
            // ...and the stretch just ahead, so playing forward is decoding
            // ahead of the playhead rather than behind it.
            if isDocumentPlaying {
                for step in 1...MovieFrameFetcher.playAheadFrames {
                    let ahead = documentTimeMS + step * MovieRef.frameStepMS
                    guard ahead <= lastDocumentTimeMS else { break }
                    movieFrames.fetch(document.movieFrames(atTimeMS: ahead), size: size)
                }
            }
        }
        submit(document)
    }

    /// The canvas zoomed: read the frames on screen again if the new zoom
    /// shows them bigger than they were read. Nothing is redrawn here; the
    /// sharper frame redraws the canvas when it lands, and until then the one
    /// in hand keeps showing.
    func refetchMovieFramesForZoom() {
        guard documentHasTime, let document = shownDocument else { return }
        let wanted = document.movieFrames(atTimeMS: documentTimeMS)
        guard !wanted.isEmpty else { return }
        movieFrames.fetch(wanted, size: movieDecodeSize(in: document))
    }

    /// How big each frame is worth reading: as many pixels as the canvas
    /// shows it with, which for a full-screen Retina recording in a window is
    /// usually well under its own size (`MovieRef.decodePixelSize`).
    private func movieDecodeSize(in document: PhotonzDocument) -> (MovieFrameRequest) -> CGSize {
        let screen = zoom * (hostWindow?.backingScaleFactor ?? 2)
        return { request in
            // A clip punched in on is drawn bigger than the recording, so its
            // frames are worth that much more. The second picture of a
            // dissolve has no layer of its own and reads like the first.
            let movieWidth = max(1, request.movie.pixelSize.width)
            let drawnWidth = document.layer(id: request.layerID)?.frame.width ?? movieWidth
            return request.movie.decodePixelSize(shownScale: screen * drawnWidth / movieWidth)
        }
    }

    /// A frame arrived that the canvas did not have when it last drew.
    func movieFrameLanded() {
        guard let document = shownDocument, documentHasTime else { return }
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
