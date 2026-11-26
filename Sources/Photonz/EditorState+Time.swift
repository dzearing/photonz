import AppKit
import Foundation
import PhotonzCore
import QuartzCore

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

    // Whether there is time at all is `documentHasTime`, kept beside
    // `hasDocument` in EditorState.swift.

    /// Whether this window's tool bar is a video's: a document with time on
    /// Next's families bar, where the video's own tools lead and the T tool
    /// goes by Title (`ToolName`).
    var hasVideoToolBar: Bool {
        documentHasTime && Experiments.shared.videoToolBarEnabled && Experiments.shared.toolGroupsEnabled
    }

    /// How long it runs for.
    ///
    /// The document AS IT IS BEING SHOWN, which is the same thing except
    /// while a trim is running: then the clip is laid out at full length, so
    /// the transport and the ruler say how much there is to choose from rather
    /// than how much is currently kept (`EditorState+Trim`).
    ///
    /// A keyed picture runs for its lap (`PictureKeys.swift`).
    var documentLengthMS: Int {
        guard let shown = shownDocument else { return 0 }
        return shown.isKeyedPicture ? shown.motionCycleLengthMS : shown.documentDurationMS
    }

    /// The last moment there is a picture at.
    var lastDocumentTimeMS: Int { max(0, documentLengthMS - 1) }

    /// Where a clip's pixels come from, made the first time one is asked for.
    var movieFrames: MovieFrameFetcher {
        if let already = movieFramesStorage { return already }
        let fetcher = MovieFrameFetcher(store: store)
        fetcher.onFrameLanded = { [weak self] in self?.movieFrameLanded() }
        fetcher.onUnreadable = { [weak self] in
            guard let self, !isDocumentPlaying else { return }
            documentMomentChanged()
        }
        movieFramesStorage = fetcher
        // A window that shows recordings is told when one changes on disk.
        MovieFileWatch.shared.add(self)
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
        // A hand on a keyed picture's ruler takes over from the lap.
        if isMotionPlaying, isKeyedPicture { pauseMotionPreview() }
        let landing = min(max(0, ms), lastDocumentTimeMS)
        guard landing != documentTimeMS else { return }
        // While the clock plays it plays on from where it landed, so it goes
        // the clock's way: a click back on the timeline left it going
        // backwards while it played forwards, and the picture swapped between
        // the new place and the old one (`MovieFramesInHand.Travel.afterMove`).
        playheadTravel = .afterMove(from: documentTimeMS, to: landing,
                                    clockRate: isDocumentPlaying ? documentPlaybackRate : nil,
                                    handHolds: playheadInHand)
        playheadStrideMS = max(MovieRef.frameStepMS, abs(landing - documentTimeMS))
        documentTimeMS = landing
        // A scrub while it plays takes over: the clock restarts from where the
        // hand put the playhead rather than snapping back to where it had got
        // to on its own.
        if isDocumentPlaying {
            if !playheadInHand, playsSoundAtRate {
                // A jump while it plays (a click on the timeline, a key to the
                // next cut) waits for its first frames as Space from rest
                // does, and the sound starts again with the clock from there
                // (`preRollWithSound`). Played on at once, a jump back on a
                // full-screen recording held the frame it landed on for three
                // frames while the reading caught up from the key frame
                // (2026-11-24).
                stopAudio()
                restartDocumentClock(fromRest: true)
            } else {
                restartDocumentClock()
                // The sound is scheduled against one engine start, so a scrub
                // mid-play has to schedule it again from where the hand put the
                // playhead. Nothing is faded: a scrub is somebody looking for a
                // moment, and what they want to hear is that moment.
                if playsSoundAtRate { startAudio() }
            }
        }
        // ...and where the playhead is being DRAGGED, the sliver of sound
        // under it, so somebody hunting for a word can hear it go by
        // (`ScrubAudition.swift`). Does nothing unless a drag is in hand.
        auditionScrub()
        if playheadInHand {
            playheadPace.moved(toMS: landing, atMS: CACurrentMediaTime() * 1000)
            // A moving hand is shown frames read in passing, small; holding
            // still is what earns the sharp one (`MovieSweep`).
            playheadSettled = false
            waitForPlayheadToSettle()
            askForMomentByRefresh()
        } else {
            documentMomentChanged()
        }
    }

    /// Start the wait for a hand on the playhead to hold still, over again.
    private func waitForPlayheadToSettle() {
        playheadSettleTask?.cancel()
        playheadSettleTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(MovieSweep.settleMS))
            guard let self, !Task.isCancelled, !playheadSettled else { return }
            playheadSettled = true
            catchUpPanelPlayhead()
            documentMomentChanged()
        }
    }

    // MARK: Dragging the playhead

    // The three calls a hand on the playhead makes, in one place rather than
    // inside a gesture, so the timeline's own drag and a scripted walk drive
    // the same thing. Taking hold is where the listening starts; letting go is
    // where it stops (`ScrubAudition.swift`).

    /// A hand took hold of the playhead.
    func beginPlayheadDrag() {
        playheadInHand = true
        playheadPace.reset()
        playheadPace.moved(toMS: documentTimeMS, atMS: CACurrentMediaTime() * 1000)
        beginScrubAudition()
        if let document = shownDocument {
            var seen = Set<UUID>()
            let movies = document.allLayers.compactMap(\.movie).filter { seen.insert($0.id).inserted }
            movieFrames.learnKeyFrames(of: movies)
        }
    }

    /// ...and moved it. The same landing as any other scrub, so the canvas,
    /// the ruler and the sound all follow one call.
    func dragPlayhead(toMS ms: Int) { scrubDocument(toMS: ms) }

    /// ...and let go. Whatever the last refresh had not yet drawn is drawn now.
    func endPlayheadDrag() {
        playheadInHand = false
        // ...and a clock still playing goes its own way again.
        playheadTravel = .whenHandLetsGo(clockRate: isDocumentPlaying ? documentPlaybackRate : nil,
                                         handWent: playheadTravel)
        // ...and plays on from where it was let go once its first frames are
        // in, the way a jump while playing does.
        if isDocumentPlaying, playsSoundAtRate {
            stopAudio()
            restartDocumentClock(fromRest: true)
        }
        catchUpOnQuietPictures()
        scrubFrames?.stop()
        playheadSettleTask?.cancel()
        // Letting go is holding still for good: whatever the last refresh had
        // not drawn is drawn, and the frame under the playhead is read sharp
        // if the hand was still moving when it let go.
        let unsettled = !playheadSettled
        playheadSettled = true
        catchUpPanelPlayhead()
        if scrubAsks.lettingGo() || unsettled {
            documentMomentChanged()
        }
        endScrubAudition()
    }

    /// While a hand scrubs, the picture is asked for at most once per display
    /// refresh. A trackpad sends moves faster than a screen shows pictures, and
    /// asking for a picture per move queued work the screen could never show.
    /// The first move in a refresh is drawn at once, so pacing never adds a
    /// frame of lag; any more in the same refresh are drawn together at the
    /// next refresh, as one picture of the last of them (`scrubbing-is-smooth-never-goes-black-and-the-pic`).
    ///
    /// A frame landing while the hand is on the playhead only ever waits for
    /// the next refresh (`atOnce: false`): it is never worth making the hand's
    /// own next move wait behind it.
    func askForMomentByRefresh(atOnce: Bool = true) {
        if scrubFrames == nil, let view = hostWindow?.contentView {
            scrubFrames = DisplayFrames(view: view)
        }
        guard let frames = scrubFrames else {
            documentMomentChanged()
            return
        }
        // A landing waits for the refresh, and for any picture still on its
        // way (`ScrubPictureAsks`).
        if !atOnce {
            scrubAsks.frameLanded()
        } else if scrubAsks.handMoved(atRefresh: frames.count) {
            documentMomentChanged()
        }
        frames.run { [weak self] in
            guard let self else { return }
            guard let frames = scrubFrames, scrubAsks.refreshed(atRefresh: frames.count) else {
                // A refresh with nothing new: nothing to draw until the hand
                // moves again.
                if !playheadInHand { scrubFrames?.stop() }
                return
            }
            // What is left over from the refresh just gone. It does not use up
            // the new refresh's own first move, which is still drawn at once.
            documentMomentChanged()
        }
    }

    /// One frame on, or back with a negative count. The step is the grid frames
    /// are fetched on, so stepping always lands on a frame that can be drawn,
    /// and on the next one however far into its own frame the playhead was.
    func stepDocument(byFrames frames: Int) {
        pauseDocument()
        scrubDocument(toMS: MovieRef.gridMS(steppedFrom: documentTimeMS, byFrames: frames))
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
        if recordingStillLanding {
            playWhenLanded.toggle()
            return
        }
        isDocumentPlaying ? pauseDocument() : playDocument()
    }

    /// Premiere's Play In to Out (⌘⇧Space, and the ruler's menu): from the In,
    /// stopping on the Out. Asked again while it plays, it starts over at the
    /// In; nothing marked, nothing to do.
    var canPlayInToOut: Bool {
        documentHasTime && document?.playInToOutMS(lastFrameMS: lastDocumentTimeMS) != nil
    }

    @discardableResult
    func playInToOut() -> Bool {
        guard documentHasTime,
              let stretch = document?.playInToOutMS(lastFrameMS: lastDocumentTimeMS) else { return false }
        pauseDocument()
        scrubDocument(toMS: stretch.lowerBound)
        documentPlaybackStopMS = stretch.upperBound
        playDocument()
        guard isDocumentPlaying else {
            documentPlaybackStopMS = nil
            return false
        }
        return true
    }

    /// Sound plays with the picture forwards up to double speed, its pitch
    /// held off normal speed (`PlaybackSpeed`). Faster, or backwards, it runs
    /// silent rather than garbled.
    var playsSoundAtRate: Bool { PlaybackSpeed.playsSound(atRate: documentPlaybackRate) }

    /// Play, at the window's chosen speed (the transport's speed menu) unless
    /// a shuttle asks for another (`EditorState+TimelineKeys`). Asked again
    /// while it plays, it changes speed where it is rather than starting over.
    func playDocument(rate asked: Double? = nil) {
        let rate = asked ?? chosenPlaybackSpeed
        guard documentHasTime, rate != 0 else { return }
        titlePartReplaying = nil
        // Play is another operation: the transform bar goes (scrubbing keeps
        // it, and its numbers follow the playhead).
        dropTransformBar()
        dropKeyValues()
        // The file is not there yet: play the moment it is.
        if recordingStillLanding {
            playWhenLanded = rate > 0
            return
        }
        if isDocumentPlaying {
            guard rate != documentPlaybackRate else { return }
            // A shuttle takes over from a Play In to Out: J, K and L go where
            // they are told, past the Out if need be.
            documentPlaybackStopMS = nil
            documentPlaybackRate = rate
            playheadTravel = rate < 0 ? .backward : .forward
            timelineShuttle.playing(at: rate)
            restartDocumentClock()
            playsSoundAtRate ? startAudio() : stopAudio()
            return
        }
        // Playing from the last frame starts over, which is what pressing play
        // at the end of something obviously means. Backwards from the first
        // frame there is nowhere to go.
        if rate > 0, documentTimeMS >= lastDocumentTimeMS { documentTimeMS = 0 }
        if rate < 0, documentTimeMS <= 0 { return }
        documentPlaybackRate = rate
        playheadTravel = rate < 0 ? .backward : .forward
        timelineShuttle.playing(at: rate)
        isDocumentPlaying = true
        // Anything left listening to a hand stands down: the whole mix is
        // about to play, and a scrub over the top of it is the same sound
        // twice (`ScrubAudition.swift`).
        endScrubAudition()
        // From rest the clock waits a moment for the frames it shows first,
        // and the sound starts with it (`preRollWithSound`).
        restartDocumentClock(fromRest: true)
    }

    func pauseDocument() {
        if playWhenLanded { playWhenLanded = false }
        titlePartReplaying = nil
        guard isDocumentPlaying else { return }
        noteRecordingPlace()
        isDocumentPlaying = false
        documentPlaybackStopMS = nil
        documentPlaybackRate = 1
        timelineShuttle.stopped()
        stopAudio()
        documentPlaybackTask?.cancel()
        documentPlaybackTask = nil
        documentClockWaiting = false
        documentClockStepping = false
        documentPlaybackStartedAt = nil
        catchUpOnQuietPictures()
        // The panel held the clip it showed while it played past others
        // (`holdsPanelWhilePlaying`): it comes up to the one stopped on.
        catchUpPanelPlayhead()
        documentMomentChanged()
    }

    /// The clock. Real time rather than a frame count, so a frame that takes
    /// too long to decode costs that frame and not the timing of everything
    /// after it: the playhead is always where the wall clock says it should be.
    private func restartDocumentClock(fromRest: Bool = false) {
        documentPlaybackTask?.cancel()
        documentClockWaiting = false
        documentClockStepping = false
        documentPlaybackStartedAt = Date()
        documentPlaybackStartedAtMS = documentTimeMS
        let rate = documentPlaybackRate
        // Forwards it runs to the end, or to the Out on a Play In to Out.
        let end = min(documentPlaybackStopMS ?? lastDocumentTimeMS, lastDocumentTimeMS)
        documentPlaybackTask = Task { @MainActor [weak self] in
            // Backwards, it waits a moment for the frame behind it: the first
            // block decodes from the key frame before it, and a playhead that
            // ran on meanwhile leaves the picture stuck (`MoviePlayBackward`).
            if rate < 0 { await self?.preRollBackward() }
            // ...and forwards faster than double, which is silent, it waits
            // for its first frame the same way (`readyToPlayForward`).
            if rate > PlaybackSpeed.fastestWithSound { await self?.preRollForward() }
            // ...and from rest at a speed with sound, for the frames just
            // ahead too, with the sound starting when the clock does.
            if fromRest, PlaybackSpeed.playsSound(atRate: rate) { await self?.preRollWithSound() }
            // Ticks on its own beat, not a frame after each tick's work
            // (`PlayClockPace`).
            let beat = ContinuousClock.now
            if !Task.isCancelled { self?.documentClockStepping = true }
            while !Task.isCancelled {
                let sinceBeat = beat.duration(to: .now)
                let elapsedMS = Double(sinceBeat.components.seconds) * 1000
                    + Double(sinceBeat.components.attoseconds) / 1e15
                try? await Task.sleep(for: .milliseconds(PlayClockPace.waitMS(elapsedMS: elapsedMS)))
                // A change of speed cancels this clock mid-sleep, and the sleep
                // ends early rather than throwing it out: read against the new
                // clock's start, nothing has elapsed, and from the last frame
                // that read as the end. J J J from a stop at the end stopped
                // dead on the third J (2026-10-08).
                guard !Task.isCancelled, let self, isDocumentPlaying,
                      let started = documentPlaybackStartedAt else { return }
                let elapsed = Int((Date().timeIntervalSince(started) * 1000 * rate).rounded())
                let landing = documentPlaybackStartedAtMS + elapsed
                if rate > 0, landing >= end {
                    // It finishes rather than looping: a recording has a last
                    // frame, and sitting on it is what having watched it looks
                    // like. A part's own Replay settles back on the title
                    // held with every part arrived, so parts that come in
                    // later than it never flash off at the stop.
                    documentTimeMS = end
                    let replayedTitle = titlePartReplaying?.title
                    pauseDocument()
                    if let replayedTitle { holdTitleStill(replayedTitle) }
                    return
                }
                if rate < 0, landing <= 0 {
                    // ...and backwards it stops on the first.
                    documentTimeMS = 0
                    pauseDocument()
                    return
                }
                documentTimeMS = landing
                documentMomentChanged()
                #if PHOTONZ_PLAYTEST
                ViewBuildMeter.shared.playbackTicked()
                #endif
            }
        }
    }

    /// Hold a clock about to play backwards where it is until the frame
    /// behind the playhead is in hand, at most `MoviePlayBackward.preRollMS`,
    /// then start it from there. Silent, since backwards plays no sound.
    private func preRollBackward() async {
        let deadline = Date().addingTimeInterval(Double(MoviePlayBackward.preRollMS) / 1000)
        documentMomentChanged()
        while !Task.isCancelled, isDocumentPlaying, Date() < deadline,
              let document = shownDocument,
              !document.readyToPlayBackward(atTimeMS: documentTimeMS, inHand: movieFrames.inHand,
                                            speed: abs(documentPlaybackRate)) {
            try? await Task.sleep(for: .milliseconds(4))
        }
        // A clock cancelled while it waited leaves the start to the one
        // that replaced it.
        guard !Task.isCancelled else { return }
        documentPlaybackStartedAt = Date()
        documentPlaybackStartedAtMS = documentTimeMS
    }

    /// Hold a clock about to play forwards faster than double where it is
    /// until the first frame it shows is in hand, at most
    /// `MoviePlayBackward.preRollMS`, then start it from there. Silent at those
    /// speeds, so nothing is put out of step with the sound.
    private func preRollForward() async {
        let deadline = Date().addingTimeInterval(Double(MoviePlayBackward.preRollMS) / 1000)
        documentMomentChanged()
        while !Task.isCancelled, isDocumentPlaying, Date() < deadline,
              let document = shownDocument,
              !document.readyToPlayForward(atTimeMS: documentTimeMS, inHand: movieFrames.inHand,
                                           speed: abs(documentPlaybackRate)) {
            try? await Task.sleep(for: .milliseconds(4))
        }
        guard !Task.isCancelled else { return }
        documentPlaybackStartedAt = Date()
        documentPlaybackStartedAtMS = documentTimeMS
    }

    /// Hold a clock about to play forwards from rest at a speed with sound
    /// where it is until the frame under the playhead and the next few are in
    /// hand (`PhotonzDocument.readyToStartPlaying`), at most
    /// `MoviePlayPass.soundStartWaitMS`, then start it, and the sound with it,
    /// from there. Space right after a scrub found the frame under the
    /// playhead read and the pass behind it still decoding from the key frame
    /// a second back; the clock ran on, and a dissolve held a frame up to 10
    /// behind for half a second (2026-11-20). Premiere waits the same way.
    private func preRollWithSound() async {
        let asked = CACurrentMediaTime()
        startGoesWithoutUntil = asked + Double(MoviePlayPass.startGoesWithoutMS) / 1000
        documentClockWaiting = true
        documentMomentChanged()
        while !Task.isCancelled, isDocumentPlaying, let document = shownDocument,
              !MoviePlayPass.starts(document.startReady(atTimeMS: documentTimeMS, inHand: movieFrames.inHand,
                                                        speed: documentPlaybackRate),
                                    waitedMS: (CACurrentMediaTime() - asked) * 1000) {
            try? await Task.sleep(for: .milliseconds(4))
        }
        // A clock cancelled while it waited: whoever cancelled it put the flag
        // down already, and may have raised it again for a clock of its own.
        guard !Task.isCancelled else { return }
        documentClockWaiting = false
        guard isDocumentPlaying else { return }
        documentPlaybackStartedAt = Date()
        documentPlaybackStartedAtMS = documentTimeMS
        if playsSoundAtRate { startAudio() }
    }

    /// Whether the play clock's next step, a refresh away, draws the document
    /// as it is then, so an edit made while it plays has no need to draw its
    /// moment itself: the clock is stepping on its beat, not waiting for its
    /// first frames (`rerender`, `splitClipAtPlayhead`, `setTransition`).
    var clockDrawsTheNextMoment: Bool {
        isDocumentPlaying && documentClockStepping && !documentClockWaiting && documentPlaybackTask != nil
    }

    // MARK: Drawing the moment

    /// The playhead moved, so the picture has to. Asks for whatever frames this
    /// moment needs and redraws with what is already in hand, which is what
    /// keeps a scrub responsive: the canvas never waits on a decode, it shows
    /// the last frame it has and replaces it the instant the right one lands.
    func documentMomentChanged() {
        guard let document = shownDocument else { return }
        // Draws whatever has landed too (`movieFrameLanded`).
        landingWaits = false
        landingDrawnAt = CACurrentMediaTime()
        // A timeline opened out carries its window along with the playhead, a
        // screenful at a time (`EditorState+TimelineZoom`). Free where the
        // playhead is already on screen, which is nearly every call.
        followTimelineWindow()
        // Every layer's level put where the plan says it is at this moment,
        // which is what turns a pair of points into a duck you can hear
        // (`EditorState+Audio.swift`).
        followAudio()
        // Playing forwards, only what is seen is read (`MovieFramesSeen`).
        let playsForward = isDocumentPlaying && playheadTravel != .backward
        var wanted = playsForward ? document.movieFramesSeen(atTimeMS: documentTimeMS)
            : document.movieFrames(atTimeMS: documentTimeMS)
        if !wanted.isEmpty {
            // ...and the stretch just ahead IN THE DIRECTION IT IS GOING, so
            // playing is decoding ahead of the playhead rather than behind it,
            // backwards as much as forwards, and a hand scrubbing finds the
            // frame it is about to reach already read. A hand reads a few
            // moves ahead at the stride it is moving at; a clock reads a
            // quarter second ahead.
            // A hand too fast for a stretch is read one glimpse at a time, of
            // the frame under it alone (`MovieSweep.glimpses`).
            let way = playheadTravel == .backward ? -1 : 1
            let glimpsing = playheadInHand && !playheadSettled
                && MovieSweep.glimpses(pace: playheadPace.editMSPerSecond)
            // ...aimed where the hand will be when it lands, so a clip it is
            // about to cross into is read before it gets there
            // (`MovieSweep.glimpseLeadMS`).
            // The frames under it now come after, read for nothing but kept:
            // they are what is on screen until the key frames land.
            var underHand = wanted.count
            if glimpsing {
                let lead = MovieSweep.glimpseLeadMS(pace: playheadPace.editMSPerSecond)
                let there = document.movieFrames(
                    atTimeMS: min(lastDocumentTimeMS, max(0, documentTimeMS + way * lead)))
                if !there.isEmpty {
                    wanted = there + wanted
                    underHand = there.count
                }
            }
            let (count, stride) = isDocumentPlaying
                ? (MovieFrameFetcher.playAheadFrames, MovieRef.frameStepMS)
                : (playheadInHand && !playheadSettled && !glimpsing ? MovieFrameFetcher.scrubAheadMoves : 0,
                   playheadStrideMS)
            if count > 0 {
                for step in 1...count {
                    let ahead = documentTimeMS + way * step * stride
                    guard ahead >= 0, ahead <= lastDocumentTimeMS else { break }
                    wanted += playsForward ? document.movieFramesSeen(atTimeMS: ahead)
                        : document.movieFrames(atTimeMS: ahead)
                }
            }
            // A hand hunting is also read a quarter second of its own pace
            // ahead, a tenth of a second of the edit at a time, so a clip it
            // is about to cross into is being read when it gets there: three
            // moves ahead is 25ms of a hand, and the first frame of a read
            // takes 50 to 100ms to come (`MovieSweep.cutReachMS`).
            if playheadInHand, !playheadSettled, !glimpsing {
                let reach = MovieSweep.cutReachMS(pace: playheadPace.editMSPerSecond)
                for ahead in Swift.stride(from: MovieSweep.cutStepMS, through: reach, by: MovieSweep.cutStepMS) {
                    let moment = documentTimeMS + way * ahead
                    guard moment >= 0, moment <= lastDocumentTimeMS else { break }
                    wanted += document.movieFrames(atTimeMS: moment)
                }
            }
            // A hand still moving is fed the stretch it is heading into, read
            // in one pass and kept small; anything else reads exact frames.
            let handMoving = playheadInHand && !playheadSettled && !isDocumentPlaying
            // A clock playing forwards also opens the far side of each cut
            // coming up, so the picture does not stick there (`MoviePlayPass`).
            let playing = isDocumentPlaying && playheadTravel != .backward
                ? moviePlayLookahead.points(in: document, atTimeMS: documentTimeMS,
                                            leadMS: MoviePlayPass.comingLead(speed: abs(documentPlaybackRate)))
                : nil
            // At rest, with no hand on it, what Space would show first is read
            // and waits (`MovieFrameFetcher.readAheadOfRest`).
            let starting = !isDocumentPlaying && !playheadInHand ? startingPoints(in: document) : nil
            // ...and the clips that are seen come first, before any under one
            // that fills the frame.
            if let starting {
                wanted = starting.now + wanted
                underHand += starting.now.count
            }
            // ...and a clock playing backwards reads the stretch behind it a
            // block at a time (`MoviePlayBackward`).
            let playingBackward = isDocumentPlaying && playheadTravel == .backward
                ? abs(documentPlaybackRate) : nil
            let backPlaces = playingBackward.map {
                document.moviePlayBackPlaces(atTimeMS: documentTimeMS, speed: $0)
            } ?? []
            movieFrames.fetch(wanted, size: movieDecodeSize(in: document),
                              handMoving: handMoving, handPace: playheadPace.editMSPerSecond,
                              played: playedFrames(in: document),
                              underHand: underHand,
                              backward: playheadTravel == .backward,
                              playing: playing, starting: starting,
                              jumped: MoviePlayPass.restsOnPasses(movedMS: playheadStrideMS, travel: playheadTravel),
                              playingSpeed: isDocumentPlaying ? abs(documentPlaybackRate) : 1,
                              playingBackward: playingBackward, backPlaces: backPlaces)
        }
        guard !holdsPictureForStart(document) else { return }
        submit(document)
    }

    /// Whether a clip still without its own frames is left out of the picture
    /// for now: in the moment after Space, with many clips on screen, until
    /// every one of them has landed (`MoviePlayPass.starts`).
    func startGoesWithout(_ inHand: MovieFramesInHand?, in document: PhotonzDocument) -> Bool {
        guard startGoesWithoutUntil > 0, let inHand else { return false }
        let start = document.startReady(atTimeMS: documentTimeMS, inHand: inHand, speed: documentPlaybackRate)
        guard isDocumentPlaying, CACurrentMediaTime() < startGoesWithoutUntil,
              start.clips > MoviePlayPass.waitsForEveryClipUpTo, start.landed < start.clips else {
            if !documentClockWaiting { startGoesWithoutUntil = 0 }
            return false
        }
        return true
    }

    /// A clock waiting to start keeps the picture that is up until every clip
    /// seen (every big one, with many) has the frame under the playhead: Space in the same breath as a
    /// jump drew the new place with frames of wherever else the same
    /// recordings had been read, or nothing, until each clip's own landed
    /// (2026-11-25). Never past the wait (`MoviePlayPass.soundStartWaitMS`).
    private func holdsPictureForStart(_ document: PhotonzDocument) -> Bool {
        guard documentClockWaiting else { return false }
        return !document.startReady(atTimeMS: documentTimeMS, inHand: movieFrames.inHand,
                                    speed: documentPlaybackRate).isAPicture
    }

    /// The canvas zoomed: read the frames on screen again if the new zoom
    /// shows them bigger than they were read. Nothing is redrawn here; the
    /// sharper frame redraws the canvas when it lands, and until then the one
    /// in hand keeps showing.
    func refetchMovieFramesForZoom() {
        guard documentHasTime, let document = shownDocument else { return }
        let wanted = document.movieFrames(atTimeMS: documentTimeMS)
        guard !wanted.isEmpty else { return }
        movieFrames.fetch(wanted, size: movieDecodeSize(in: document),
                          played: playedFrames(in: document),
                          starting: !isDocumentPlaying && !playheadInHand ? startingPoints(in: document) : nil)
    }

    /// What a clock starting forwards from where the playhead rests shows
    /// first, and what comes on just after.
    private func startingPoints(in document: PhotonzDocument) -> MoviePlayPoints? {
        guard documentTimeMS < lastDocumentTimeMS else { return nil }
        return moviePlayLookahead.points(in: document, atTimeMS: documentTimeMS, leadMS: MoviePlayPass.restLeadMS)
    }

    /// The grid frames of its recording a clip plays.
    private func playedFrames(in document: PhotonzDocument) -> (MovieFrameRequest) -> ClosedRange<Int>? {
        { request in
            document.layer(id: request.layerID)?.playedSourceSpanMS.map {
                request.movie.frameIndex(atSourceMS: $0.lowerBound)
                    ... request.movie.frameIndex(atSourceMS: $0.upperBound)
            }
        }
    }

    /// For each frame the moment under the playhead draws: how wide it is worth
    /// reading at this zoom, and how wide the copy in hand was read (nil when
    /// it has not been read yet). What a walk reads to tell a sharp frame from
    /// a small read stretched up (`expectFrameSharp`).
    func movieFrameReadWidths() -> [(name: String, wanted: CGFloat, read: CGFloat?)] {
        guard let document = shownDocument else { return [] }
        let size = movieDecodeSize(in: document)
        return document.movieFrames(atTimeMS: documentTimeMS).map { request in
            (name: document.layer(id: request.layerID)?.name ?? "a dissolve's second picture",
             wanted: size(request).width,
             read: store.image(for: request.ref).map { CGFloat($0.width) })
        }
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
            let layer = document.layer(id: request.layerID)
            let drawnWidth = layer?.frame.width ?? movieWidth
            // ...and so is a clip inside a zoom, which shows part of its
            // picture across the whole of its box (`ClipZoom.swift`), read at
            // the frame's own moment so frames read ahead are as sharp as the
            // zoom will be when they are shown.
            let zoomed = CGFloat(layer?.zoomFactor(atSourceMS: request.sourceMS) ?? 1)
            return request.movie.decodePixelSize(shownScale: screen * zoomed * drawnWidth / movieWidth)
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
        // read and a core spent on nothing. Nor while a hand is moving the
        // playhead: frames read in passing land dozens a second then, and the
        // sharp one read when it holds still redraws the row.
        if !isDocumentPlaying, !playheadInHand || playheadSettled {
            for layer in document.allLayers where layer.isClip {
                thumbnailCache[layer.id] = nil
            }
        }
        // A hand scrubbing: the landing is drawn with the next refresh's
        // picture rather than as one of its own.
        if playheadInHand {
            askForMomentByRefresh(atOnce: false)
            return
        }
        guard isDocumentPlaying else {
            submit(document)
            return
        }
        // Playing, the frames that land are drawn together, a refresh apart.
        // With ten recordings on screen three hundred land a second, and each
        // drawing the whole canvas on its own held the main thread so that
        // the next ones landed late, and were drawn on their own in turn
        // (2026-11-24). The first one to land is still drawn at once.
        guard !holdsPictureForStart(document) else { return }
        let now = CACurrentMediaTime()
        let due = landingDrawnAt + Self.landingsApart
        if now >= due {
            landingDrawnAt = now
            submit(document)
        } else if !landingWaits {
            landingWaits = true
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(due - now))
                guard let self, landingWaits else { return }
                landingWaits = false
                guard isDocumentPlaying, let document = shownDocument else { return }
                landingDrawnAt = CACurrentMediaTime()
                submit(document)
            }
        }
    }

    /// How far apart landing frames draw the canvas while it plays: a refresh
    /// of a 120 Hz display.
    static let landingsApart = 1.0 / 120

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

    /// Seconds, or timecode once View > Timecode is on: one switch for every
    /// window (`VideoTimeDisplaySetting`).
    var timeDisplay: VideoTimeDisplay { VideoTimeDisplaySetting.shared.display }

    /// Where the playhead is, said the way the transport says it: `0:04`, or
    /// the frame it is on in timecode, `00:00:04:12`.
    var documentTimecode: String { timeDisplay.moment(documentTimeMS) }
    /// How long the whole thing is.
    var documentLengthTimecode: String { timeDisplay.duration(documentLengthMS) }
}
