import AppKit
import AVFoundation
import CoreGraphics
import Observation
import PhotonzCore
import PhotonzMedia
import SwiftUI

/// Per-window state for the in-app video editor (phase 13.3). The sibling of
/// `EditorState` for recordings: it keeps `EditorState` image-pure by owning the
/// `AVPlayer`/`AVPlayerItem` (both non-Sendable, so this whole type is
/// `@MainActor`) plus the pure, non-destructive `VideoTrim`/`VideoCrop`.
///
/// Saving works exactly like the image editor's (phase 19): ⌘S **commits** the
/// trim/crop into the stored recording, so the file history hands out IS the
/// trimmed media. The pre-edit bytes are preserved as a hidden original, and
/// this editor always edits FROM that original — the same shape as the image
/// editor writing a flattened PNG while keeping the layered `.photonz` sidecar.
@MainActor
@Observable
final class VideoEditorState {
    /// The recording being edited — the file in capture history, and the file
    /// a save commits into; nil until `seed`.
    private(set) var url: URL?
    /// The asset actually loaded into the player and measured against: the
    /// preserved original once a save has made one, else the recording itself.
    /// Editing from the original is what keeps repeated saves from stacking
    /// trims and lets clearing the trim restore the whole clip.
    private(set) var editSourceURL: URL?
    /// Window title (the recording's file name) so video windows are tellable
    /// apart in the ⌘` switcher / Window menu / Dock.
    var windowTitle: String { url?.lastPathComponent ?? "Recording" }
    /// The AVKit player driving the preview. Created on `seed`.
    private(set) var player: AVPlayer?
    /// Full length of the source file in seconds (loaded asynchronously). Export
    /// maps the working window back onto this.
    private(set) var originalDuration: TimeInterval = 0
    /// What the recording has been cut into: the ordered list of kept pieces,
    /// in original-file seconds. One piece covering the whole file is an
    /// untouched recording; applying a trim narrows it; a cut splits a piece in
    /// two; deleting drops one. Everything the UI shows (strip, playhead, live
    /// trim) is expressed in TIMELINE time — the pieces played back to back —
    /// and so is the player, because the player is fed a composition of exactly
    /// these pieces.
    private(set) var cuts = VideoCutList(duration: 0)
    /// The working clip length the UI edits within — what is left to watch.
    var duration: TimeInterval { cuts.timelineDuration }
    /// The piece the playhead is sitting in. There is no separate clip
    /// selection: the piece you are looking at IS the piece you are holding, so
    /// clicking a piece selects it (clicking a time moves the playhead there)
    /// and Delete drops what is on screen.
    var selectedPieceIndex: Int? {
        guard cuts.isCut else { return nil }
        return cuts.pieceIndex(atTimeline: currentTime)
    }
    /// How many pieces the live trim window still keeps, of how many there are.
    /// What the trim handles are drawing, said in words, so a person dragging a
    /// handle past a join can read what they are about to drop as well as see it.
    var trimmedPieceCount: (kept: Int, total: Int) {
        let under = cuts.piecesUnderTrim(fromTimeline: trim.inPoint, toTimeline: trim.outPoint)
        return (under.count { !$0.isDropped }, under.count)
    }

    /// Nominal frame rate (fps), for frame-accurate ←/→ stepping. Defaults to 30
    /// until metadata loads.
    private(set) var frameRate: Double = 30
    /// Natural pixel size of the video, oriented (after `preferredTransform`),
    /// for the crop overlay. `.zero` until loaded.
    private(set) var naturalSize: CGSize = .zero
    /// A poster frame for the empty/loading state.
    private(set) var poster: CGImage?

    /// Non-destructive live trim window, in working seconds. Full working clip
    /// until the user drags a handle; Apply Trim folds it into the applied window.
    private(set) var trim = VideoTrim(duration: 0)
    /// Snapshots for undoing edits applied this session (trim and crop). Observed
    /// so the Undo affordance toggles live; a stack so repeated edits undo one at
    /// a time, newest first. Only edits the user applies here are recorded —
    /// edits recalled from a sidecar are the recording's saved state, not
    /// pending actions, so they never seed this.
    private var editUndo: [EditStep] = []
    /// Non-destructive crop region in natural-video-pixel space, top-left
    /// origin (phase 13.4). Nil = full frame.
    private(set) var crop: VideoCrop?
    /// Whether the crop overlay is active (the user is choosing a region).
    var isCropping = false
    /// Whether trim mode is active (the timeline with in/out handles is shown).
    var isTrimming = false
    /// The live trim as it was when trim mode opened, so Cancel restores it.
    @ObservationIgnored private var trimBeforeSession: VideoTrim?
    /// Aspect lock for the crop UI. Kept outside `VideoCrop` so it applies to
    /// the next drag-defined region when no crop exists yet.
    private(set) var cropAspectSelection: CropAspect = .free
    /// The crop as it was when the overlay opened, so Cancel restores it.
    @ObservationIgnored private var cropBeforeSession: VideoCrop?

    /// The preview's camera (pan/zoom over the video), published by
    /// `VideoPreviewNSView` so the crop overlay maps video pixels ↔ view
    /// points through the same transform the player is drawn with.
    var previewViewport: Viewport?
    /// The window hosting this editor, captured by the preview view: used to
    /// size the window to the recording and for double-click-to-zoom.
    @ObservationIgnored weak var hostWindow: NSWindow?

    /// Live playback head in seconds, updated by the periodic observer so the
    /// scrubber's playhead tracks playback.
    private(set) var currentTime: TimeInterval = 0
    /// Whether the player is currently playing (drives the play/pause button).
    private(set) var isPlaying = false

    /// Playback volume, 0...1, applied straight to the AVPlayer. Muting drops it
    /// to 0 but remembers the prior level so unmuting restores it.
    private(set) var volume: Double = 1
    @ObservationIgnored private var volumeBeforeMute: Double = 1
    /// True when effectively silent, for the speaker-icon glyph.
    var isMuted: Bool { volume <= 0.0001 }

    /// True while a tutorial is running over this window. The floating
    /// controller stays up for the whole of it: every control a video guide
    /// points at lives on that controller, and it otherwise fades two seconds
    /// after the pointer leaves it, which would leave a ring round nothing.
    /// Reveal only, exactly like every other thing a guide is allowed to do.
    var isTutorialRunning = false

    /// True once metadata (duration/size) has loaded, so the timeline can render.
    private(set) var isReady = false
    /// True once the metadata load finished, ready or not — the window stays
    /// hidden until then so it can open already sized to the recording
    /// (instead of appearing small and visibly resizing).
    private(set) var metadataDidLoad = false

    /// What the preview frames when not cropping: the committed crop region,
    /// or the whole video. The window is sized to show this pixel-exact.
    var displayContentSize: CGSize {
        guard let crop, !crop.rect.isEmpty else { return naturalSize }
        return crop.rect.size
    }

    /// The capture history, so a commit can refresh the recording's thumbnail
    /// and duration pill.
    @ObservationIgnored private weak var capture: CaptureCenter?
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var didPlayToEndObserver: NSObjectProtocol?

    /// Cleanup tokens kept outside the actor's isolation so `deinit` (which is
    /// nonisolated) can detach the observers without touching `@MainActor`
    /// state. `nonisolated(unsafe)` is sound because they're only written on the
    /// main actor during setup and only read once in `deinit`.
    @ObservationIgnored private nonisolated(unsafe) var cleanupPlayer: AVPlayer?
    @ObservationIgnored private nonisolated(unsafe) var cleanupTimeObserver: Any?
    @ObservationIgnored private nonisolated(unsafe) var cleanupEndObserver: NSObjectProtocol?

    deinit {
        if let cleanupEndObserver { NotificationCenter.default.removeObserver(cleanupEndObserver) }
        if let cleanupTimeObserver, let cleanupPlayer {
            cleanupPlayer.removeTimeObserver(cleanupTimeObserver)
        }
    }

    /// One-time setup from the window identity (mirrors `EditorState.seed`).
    /// Window reuse keeps the existing state, so this never reloads.
    func seed(url: URL, capture: CaptureCenter) {
        guard self.url == nil else { return }
        self.url = url
        self.capture = capture
        let source = VideoOriginals.editSource(for: url)
        self.editSourceURL = source

        let item = AVPlayerItem(url: source)
        let player = AVPlayer(playerItem: item)
        // Looping is handled within [in, out]; never let AVPlayer overshoot.
        player.actionAtItemEnd = .pause
        self.player = player
        self.cleanupPlayer = player

        installObservers(on: player)
        Task { await loadMetadata(url: source) }
    }

    private func installObservers(on player: AVPlayer) {
        // ~20fps playhead updates keep the scrubber smooth without churn.
        let interval = CMTime(seconds: 0.05, preferredTimescale: 600)
        let observer = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self else { return }
                // The player is fed a composition of the kept pieces, so its
                // clock IS timeline time: no offset bookkeeping.
                let working = time.seconds.isFinite ? time.seconds : 0
                self.currentTime = min(max(0, working), self.duration)
                // Loop back to the in-point when playback runs past the out-point.
                if self.isPlaying, self.currentTime >= self.trim.outPoint - 1e-3 {
                    self.seek(to: self.trim.inPoint)
                }
            }
        }
        timeObserver = observer
        cleanupTimeObserver = observer

        installEndObserver(on: player)
    }

    /// The did-play-to-end observer is bound to the *item*, so it is re-installed
    /// whenever the player is re-pointed at a different asset.
    private func installEndObserver(on player: AVPlayer) {
        if let didPlayToEndObserver { NotificationCenter.default.removeObserver(didPlayToEndObserver) }
        let endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: player.currentItem, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.seek(to: self.trim.inPoint)
                if self.isPlaying { self.player?.play() }
            }
        }
        didPlayToEndObserver = endObserver
        cleanupEndObserver = endObserver
    }

    private func loadMetadata(url: URL) async {
        let asset = AVURLAsset(url: url)
        let seconds = await VideoExporter.duration(of: url)
        let oriented = await VideoExporter.orientedNaturalSize(of: url)
        let poster = await VideoExporter.posterFrame(of: url)
        let fps = await VideoExporter.frameRate(of: url)
        // The asset reference is intentionally unused past metadata; AVPlayerItem
        // holds its own.
        _ = asset
        self.originalDuration = seconds
        self.cuts = VideoCutList(duration: seconds)
        self.naturalSize = oriented
        self.poster = poster
        self.frameRate = fps
        self.trim = VideoTrim(duration: seconds)
        // Recall the recording's edits so reopening it shows what it shows in
        // history. They fold straight into the applied window with NO undo step
        // — this is the recording's state, not a pending action. Trim handles
        // only appear in trim mode, where Reset restores the full length.
        //
        // `committedEdits` is what the stored file already HAS baked in, and it
        // is the clean baseline: matching it means nothing to save. A recording
        // trimmed before phase 19 has a sidecar but no preserved original, so
        // its edits recall as *unsaved* — the user gets a save prompt instead of
        // silently losing a trim that was never applied.
        if let mediaURL = self.url {
            self.committedEdits = VideoSaveState.committedEdits(for: mediaURL)
            if let edits = VideoEditsSidecar.load(for: mediaURL) {
                if let saved = edits.keptPieces, !saved.isWholeClip {
                    self.cuts = saved
                    self.trim = VideoTrim(duration: duration)
                }
                self.crop = edits.crop
            }
        }
        self.isReady = seconds > 0
        self.metadataDidLoad = true
        if isReady {
            // A recalled edit means the player must show the PIECES, not the
            // file; a fresh recording is already exactly its own composition,
            // so it keeps the plain item it was seeded with.
            if !cuts.isWholeClip {
                await rebuildPlayerItem(resumeAt: 0, keepPlaying: false)
            }
            // Autoplay from the top of the working clip, like a normal player.
            seek(to: 0)
            play()
        }
    }

    // MARK: - Playback

    func togglePlayPause() {
        isPlaying ? pause() : play()
    }

    /// Set the playback volume (0...1); a non-zero value also becomes the level
    /// unmute will restore.
    func setVolume(_ value: Double) {
        volume = min(max(0, value), 1)
        player?.volume = Float(volume)
        if volume > 0 { volumeBeforeMute = volume }
    }

    /// Toggle mute, restoring the pre-mute level (or full volume if it was
    /// already near-silent).
    func toggleMute() {
        if isMuted {
            setVolume(volumeBeforeMute > 0.05 ? volumeBeforeMute : 1)
        } else {
            volumeBeforeMute = volume
            setVolume(0)
        }
    }

    func play() {
        guard let player else { return }
        // Restart from the in-point if we're at/after the out-point.
        if currentTime >= trim.outPoint - 1e-3 || currentTime < trim.inPoint {
            seek(to: trim.inPoint)
        }
        player.play()
        isPlaying = true
    }

    func pause() {
        player?.pause()
        isPlaying = false
    }

    /// Seconds an arrow-key skip moves while playing.
    static let skipInterval: TimeInterval = 1

    /// ←/→ behaviour, shared by the transport buttons and the key handler:
    /// while playing, skip ±1s and keep playing; while paused, step a single
    /// frame. Auto-repeat (key held) just calls these again, so paused stepping
    /// scrubs frame-by-frame and playing scrubs in 1s jumps.
    func stepBackward() {
        isPlaying ? skip(by: -Self.skipInterval) : stepFrame(forward: false)
    }

    func stepForward() {
        isPlaying ? skip(by: Self.skipInterval) : stepFrame(forward: true)
    }

    /// Move one frame (paused). Frame-accurate via a zero-tolerance seek; clamped
    /// to the trim window.
    func stepFrame(forward: Bool) {
        pause()
        let delta = (forward ? 1.0 : -1.0) / max(1, frameRate)
        seekWithinTrim(currentTime + delta)
    }

    /// Skip by `seconds` without changing the play state (used for ±5s jumps
    /// during playback). Clamped to the trim window.
    func skip(by seconds: TimeInterval) {
        seekWithinTrim(currentTime + seconds)
    }

    /// Seek, clamped to the active trim window so navigation never leaves the
    /// region playback loops over.
    private func seekWithinTrim(_ seconds: TimeInterval) {
        seek(to: min(max(trim.inPoint, seconds), trim.outPoint))
    }

    /// Seek to `seconds` in **timeline** time (frame-accurate within
    /// tolerance). The player's item is the composition of the kept pieces, so
    /// timeline time and player time are the same number.
    func seek(to seconds: TimeInterval) {
        guard let player else { return }
        let clamped = min(max(0, seconds), max(0, duration))
        let time = CMTime(seconds: clamped, preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = clamped
    }

    /// Scrub from the timeline: pause, then seek within the trimmed window.
    func scrub(to seconds: TimeInterval) {
        pause()
        seek(to: min(max(trim.inPoint, seconds), trim.outPoint))
    }

    // MARK: - Saving (phase 19)

    /// The cumulative edits, measured against `editSourceURL` — the composed
    /// trim plus the crop, with no-op edits dropped. This is what a save
    /// commits, and what Export/Copy apply for edits not yet saved.
    var exportEdits: VideoEdits {
        let pieces = exportCuts
        // An uncut recording keeps travelling as an ordinary trim, so every
        // path that already speaks `VideoTrim` — the sidecar, the save-state
        // comparison, the exporters — is completely untouched by cutting
        // existing. Only a recording with a cut IN it carries a cut list.
        let edits = pieces.isCut
            ? VideoEdits(crop: crop, cuts: pieces)
            : VideoEdits(trim: pieces.singleTrim, crop: crop)
        return edits.normalized(videoSize: naturalSize)
    }

    /// The edits the stored recording already has baked in — the clean
    /// baseline, the video sibling of `EditorState.savedDocument`. Observed, so
    /// the dirty dot and the Save affordance track it live.
    private(set) var committedEdits = VideoEdits()

    /// True while a save's re-encode is in flight.
    private(set) var isSaving = false

    /// Completions waiting on the commit that is already running. A second ⌘S,
    /// or the close sheet's Save pressed while the first one is still
    /// encoding, joins the queue instead of being told "no" — being told no is
    /// what "I click Save and it does nothing" looked like from the outside.
    private var waitingOnSave: [@MainActor (Bool) -> Void] = []

    /// What Save means for this window right now: the ONE answer the File menu
    /// and the close confirmation both read, so they can never contradict each
    /// other (`SaveAffordance`).
    var saveAffordance: SaveAffordance {
        .forDocument(isLoaded: isReady && url != nil,
                     hasChanges: VideoSaveState.needsSave(edits: exportEdits,
                                                          committed: committedEdits),
                     isSaving: isSaving)
    }

    /// Whether closing this window would lose work — the same question
    /// `EditorState.hasUnsavedChanges` answers for an image.
    var hasUnsavedChanges: Bool { saveAffordance.asksBeforeClosing }

    /// True when File ▸ Save is live (drives ⌘S / the Save button).
    var canSave: Bool { saveAffordance.isSaveEnabled }

    /// ⌘S: **commit** the trim/crop into the stored recording, so the file that
    /// history hands out — drag, clipboard, anything reading it — is the
    /// trimmed media. The pre-edit bytes are preserved as a hidden original
    /// first, so the edit stays reversible: reopen, clear the trim, save again.
    ///
    /// Mirrors the image editor's ⌘S writing the flattened composite back into
    /// the capture file. `completion(true)` once the recording is saved (or had
    /// nothing to save); `completion(false)` if the commit failed, so the close
    /// confirmation keeps the window open rather than dropping the edits.
    func save(completion: (@MainActor (Bool) -> Void)? = nil) {
        guard let mediaURL = url, isReady else {
            // Saying "saved" here was a quiet lie: nothing was written, and the
            // close confirmation took it as permission to shut the window.
            // Nothing is loaded, so there is nothing to lose either, but the
            // answer has to be no.
            completion?(false)
            return
        }
        // A commit is already encoding. Wait for it rather than answering no:
        // pressing Save twice, or pressing it in the close sheet while ⌘S is
        // still running, must not read as a dead button.
        guard !isSaving else {
            if let completion { waitingOnSave.append(completion) }
            return
        }
        let edits = exportEdits
        guard let plan = VideoCommitPlanner.plan(mediaURL: mediaURL, edits: edits,
                                                 committed: committedEdits,
                                                 hasOriginal: VideoOriginals.exists(for: mediaURL))
        else {
            committedEdits = edits // already true on disk
            completion?(true)
            return
        }
        isSaving = true
        Task {
            do {
                try await VideoAssetCommit.commit(plan)
                committedEdits = edits
                // The first commit creates the original; from here on the
                // recording itself is the trimmed output, so keep editing (and
                // playing) the original.
                if plan.originalToPreserve != nil {
                    editSourceURL = VideoOriginals.url(for: mediaURL)
                    // Re-point the player at the preserved original, keeping
                    // the playhead and play state.
                    rebuildPlayer(resumeAt: currentTime, keepPlaying: isPlaying)
                }
                isSaving = false
                // The stored media changed: refresh the history thumbnail and
                // duration pill.
                capture?.store.reload()
                completion?(true)
                finishWaitingSaves(saved: true)
            } catch {
                isSaving = false
                presentSaveFailure(error)
                completion?(false)
                finishWaitingSaves(saved: false)
            }
        }
    }

    /// Restore the whole recording: clears the trim and crop so the next save
    /// copies the preserved original back over the stored file. Only offered
    /// once an original exists — before the first save there is nothing to
    /// revert to, and Undo already covers the session.
    var canRevertToOriginal: Bool {
        guard let url else { return false }
        return VideoOriginals.exists(for: url) && (hasEdits || !committedEdits.isEmpty)
    }

    func revertToOriginal() {
        guard canRevertToOriginal else { return }
        editUndo.append(EditStep(kind: .trim, cuts: cuts, trim: trim, crop: crop))
        cuts = VideoCutList(duration: originalDuration)
        trim = VideoTrim(duration: originalDuration)
        crop = nil
        isTrimming = false
        isCropping = false
        pause()
        rebuildPlayer(resumeAt: 0, keepPlaying: false)
    }

    /// Answer everyone who pressed Save while this commit was running.
    private func finishWaitingSaves(saved: Bool) {
        let waiting = waitingOnSave
        waitingOnSave = []
        for completion in waiting { completion(saved) }
    }

    /// A save that failed has to SAY so. Nothing is lost when it does: the trim
    /// is still in the window and the recording on disk is untouched, so the
    /// message leads with that rather than with the machinery, and it names the
    /// way out. Silence here is what "I click Save and it does nothing" felt
    /// like from the outside (reported 2026-09-18).
    private func presentSaveFailure(_ error: Error) {
        NSLog("Couldn't save the recording: \(error)")
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Couldn't save \u{201C}\(windowTitle)\u{201D}"
        alert.informativeText = "Your edits are still here and the recording on disk has not "
            + "changed. Try saving again, or use File \u{25B8} Save As to write a copy somewhere "
            + "else.\n\n\(error.localizedDescription)"
        alert.addButton(withTitle: "OK")
        if let hostWindow {
            alert.beginSheetModal(for: hostWindow, completionHandler: nil)
        } else {
            alert.runModal()
        }
    }

    // MARK: - Trim editing

    /// Drag the in-handle; seeking to the new in-point so the preview shows it.
    func setTrimIn(_ seconds: TimeInterval) {
        pause()
        trim.setIn(seconds, duration: duration)
        seek(to: trim.inPoint)
        TutorialController.shared.note(.trimStartMoved, from: self)
    }

    /// Drag the out-handle; seeking to the out-point so the preview shows it.
    func setTrimOut(_ seconds: TimeInterval) {
        pause()
        trim.setOut(seconds, duration: duration)
        seek(to: trim.outPoint)
        TutorialController.shared.note(.trimEndMoved, from: self)
    }

    // MARK: - A handle catching on a cut

    /// How wide the drawable part of the trim track is on screen, in points.
    /// Published by `TrimTimeline` as it lays out, because the magnet that
    /// catches a handle on a cut reaches a fixed distance on SCREEN and there
    /// is no other way to know how much time that is. Zero until the track has
    /// been laid out, which turns the magnet off rather than making it take
    /// everything.
    var trimTrackWidth: CGFloat = 0

    /// What the handle drag in progress remembers: the cut it is standing on,
    /// and any cut the freeing key has told it to leave alone. Reset whenever
    /// a drag ends, so nothing carries from one to the next.
    private var trimSnapHold = VideoCutSnapHold()

    /// The cut the handle being dragged is standing on, in timeline seconds, or
    /// nil when nothing has it. The track draws its tell from this and the
    /// spoken description says it out loud, so what is on screen and what was
    /// stored are the same fact rather than two that agree by luck.
    var caughtCut: TimeInterval? { trimSnapHold.caught }

    /// How much of the track one second takes up. Nil while there is nothing to
    /// measure against.
    private var trimTrackPointsPerSecond: CGFloat {
        guard duration > 0, trimTrackWidth > 0 else { return 0 }
        return trimTrackWidth / CGFloat(duration)
    }

    /// Drag the in-handle to a timeline position, catching on any cut it passes
    /// close to. The caught position is what gets stored, so the length the
    /// readout shows is the length that is kept.
    ///
    /// `freed` is ⌘ being held right now, which turns the magnet off for as
    /// long as it is down. It is read per event rather than once per drag, so
    /// reaching for the key half way through a drag works: that is the moment
    /// you discover the cut will not let you park where you want.
    func dragTrimIn(toTimeline seconds: TimeInterval, freed: Bool = false) {
        // The out-handle has to be left somewhere legal, so a cut too near it
        // is not offered: `setIn` would shove the window off the cut again and
        // the tell would be describing a place the handle is not.
        let ceiling = max(0, trim.outPoint - VideoCutList.minPieceDuration)
        setTrimIn(snapHandle(to: seconds, within: 0...ceiling, freed: freed))
    }

    /// Drag the out-handle to a timeline position, catching the same way.
    func dragTrimOut(toTimeline seconds: TimeInterval, freed: Bool = false) {
        let floor = min(duration, trim.inPoint + VideoCutList.minPieceDuration)
        setTrimOut(snapHandle(to: seconds, within: floor...max(floor, duration),
                              freed: freed))
    }

    /// Let go of the handle. The cut it was standing on stops being news the
    /// moment the hand comes off it, so the tell goes with it, and so does
    /// every cut this drag had muted.
    func endTrimHandleDrag() {
        trimSnapHold = VideoCutSnapHold()
    }

    private func snapHandle(to seconds: TimeInterval,
                            within range: ClosedRange<TimeInterval>,
                            freed: Bool) -> TimeInterval {
        trimSnapHold.landing(for: seconds,
                             catchingOn: VideoCutSnapping.candidates(in: cuts, within: range),
                             pointsPerSecond: trimTrackPointsPerSecond,
                             freed: freed)
    }

    // MARK: - Cutting a recording into pieces

    /// True when a cut here would actually make two pieces — not at either end
    /// of the recording, and not on a cut that is already there.
    var canCutAtPlayhead: Bool {
        isReady && !isCropping && cuts.canSplit(atTimeline: currentTime)
    }

    /// Put a cut where the playhead is. One piece becomes two that meet there,
    /// and nothing is thrown away: both halves read the same recording with
    /// different in and out points, which is why this costs nothing and undoes
    /// cleanly. Playback carries straight on, because the pieces are still
    /// every frame they were.
    func cutAtPlayhead() {
        guard canCutAtPlayhead else { return }
        let at = currentTime
        var next = cuts
        guard next.split(atTimeline: at) else { return }
        // A split changes no frames, so there is nothing to rebuild and nothing
        // to interrupt: the strip simply grows a join.
        editUndo.append(EditStep(kind: .cut, cuts: cuts, trim: trim, crop: crop,
                                 trimSessionBaseline: trimBeforeSession,
                                 playheadAfterUndo: at))
        cuts = next
    }

    /// True when the piece under the playhead can be thrown away. The last one
    /// cannot: a recording has to still be a recording afterwards.
    var canDeleteSelectedPiece: Bool {
        guard isReady, !isCropping, let index = selectedPieceIndex else { return false }
        return cuts.canRemovePiece(at: index)
    }

    /// Throw away the piece the playhead is in. Everything after it slides up,
    /// so the join closes with nothing in between — there is never a gap to
    /// drag shut. The playhead stays where the join now is, so pressing play
    /// shows you the cut you just made.
    func deleteSelectedPiece() {
        guard canDeleteSelectedPiece, let index = selectedPieceIndex else { return }
        let landing = cuts.timelineStart(ofPiece: index)
        // The trim handles, if they are open, move with the pieces rather than
        // being thrown back to the ends: somebody who has just placed a window
        // and then dropped a piece out of the middle of it has not asked for
        // their handles back. The baseline Cancel restores moves the same way,
        // or Cancel would put the handles somewhere the timeline no longer
        // reaches.
        let movedTrim = isTrimming ? cuts.trimAfterRemovingPiece(at: index, from: trim) : nil
        let movedBaseline = trimBeforeSession
            .map { cuts.trimAfterRemovingPiece(at: index, from: $0) }
        var next = cuts
        guard next.removePiece(at: index) else { return }
        if isTrimming { trimBeforeSession = movedBaseline }
        apply(next, kind: .deletePiece, nextTrim: movedTrim,
              playheadAt: min(landing, next.timelineDuration),
              playheadAfterUndo: landing)
    }

    /// Record an undo step, move to the new pieces, re-point the player at them
    /// and land the playhead. The one path every edit that changes what plays
    /// goes through, so the player is never left showing frames that are no
    /// longer in the recording.
    ///
    /// `nextTrim` is where the live trim window lands afterwards; nil means the
    /// edit has consumed the window, so it re-opens to the whole of what is
    /// left (which is what applying a trim does).
    private func apply(_ next: VideoCutList, kind: EditKind,
                       nextTrim: VideoTrim? = nil,
                       playheadAt landing: TimeInterval,
                       playheadAfterUndo: TimeInterval = 0) {
        editUndo.append(EditStep(kind: kind, cuts: cuts, trim: trim, crop: crop,
                                 trimSessionBaseline: trimBeforeSession,
                                 playheadAfterUndo: playheadAfterUndo))
        cuts = next
        trim = nextTrim ?? VideoTrim(duration: next.timelineDuration)
        // Move the playhead in the same breath as the pieces. Re-pointing the
        // player is asynchronous, and a strip left for a frame showing the
        // playhead inside a piece that is already gone is exactly the kind of
        // flicker that makes an edit feel unsafe.
        currentTime = min(max(0, landing), next.timelineDuration)
        pause()
        rebuildPlayer(resumeAt: currentTime, keepPlaying: false)
    }

    /// Re-point the player at whatever the cut list now says, keeping the
    /// playhead where the caller wants it.
    private func rebuildPlayer(resumeAt seconds: TimeInterval, keepPlaying: Bool) {
        compositionGeneration &+= 1
        let generation = compositionGeneration
        Task { await rebuildPlayerItem(resumeAt: seconds, keepPlaying: keepPlaying,
                                       generation: generation) }
    }

    /// Bumped by every rebuild. Building a composition has to load the source's
    /// tracks, so two rebuilds started close together (delete, then undo) can
    /// finish in either order; without this the slower, older one would land
    /// last and leave the player showing pieces the recording no longer has.
    @ObservationIgnored private var compositionGeneration = 0

    /// Build the item the player shows: the file itself while the recording is
    /// one uncut piece (nothing to compose, so nothing to pay for), and a
    /// composition of the kept pieces once it is not.
    ///
    /// A composition is what makes the join seamless. A player told to skip a
    /// dropped piece would have to notice it had arrived, stop, seek and start
    /// again, and every one of those is a visible hitch at exactly the moment
    /// the person is judging their cut. In a composition the frames either side
    /// of a cut are neighbours in one asset, so playback runs straight through.
    private func rebuildPlayerItem(resumeAt seconds: TimeInterval, keepPlaying: Bool,
                                   generation: Int = 0) async {
        guard let player, let source = editSourceURL else { return }
        let item: AVPlayerItem
        if cuts.isWholeClip {
            item = AVPlayerItem(url: source)
        } else if let composition = await VideoCompositionBuilder.composition(of: source, cuts: cuts) {
            item = AVPlayerItem(asset: composition)
        } else {
            // Nothing readable to compose: leave what is playing alone rather
            // than blanking the window.
            return
        }
        // Something newer started while this one was loading; it wins.
        guard generation == 0 || generation == compositionGeneration else { return }
        player.replaceCurrentItem(with: item)
        installEndObserver(on: player)
        player.volume = Float(volume)
        seek(to: seconds)
        if keepPlaying {
            player.play()
            isPlaying = true
        }
    }

    /// True when at least one applied edit can be undone this session.
    var canUndoEdit: Bool { !editUndo.isEmpty }

    /// The most recent undoable edit's name ("Trim", "Crop"), or nil when there
    /// is nothing to undo. Drives the Undo affordance's visibility and its
    /// action-specific tooltip, so it never reads "Undo Trim" after a crop.
    var lastEditActionName: String? { editUndo.last?.kind.name }

    // MARK: - Trim mode (mirrors crop mode: begin → adjust → cancel/commit)

    /// Begin trimming: show the timeline with in/out handles over the working
    /// clip. Paused, like crop, so the handles scrub the preview.
    func beginTrim() {
        guard isReady else { return }
        trimBeforeSession = trim
        isTrimming = true
        pause()
        TutorialController.shared.note(.trimModeOpened, from: self)
    }

    /// Clear the selection back to the whole working clip (stay in trim mode).
    func resetTrimSelection() {
        trim = VideoTrim(duration: duration)
    }

    /// Finish trimming: fold any selection into the working window (undoable
    /// via `undoLastEdit`, same as the old Apply Trim).
    func commitTrim() {
        isTrimming = false
        trimBeforeSession = nil
        trimSnapHold = VideoCutSnapHold()
        if trim.isTrimmed { applyTrim() }
        // Raised whether or not the handles had been moved, because what the
        // step asks for is the person pressing Done. A Done that applied
        // nothing still ended the trim, and a guide that sat there after it
        // would be waiting on something the person has already finished doing.
        TutorialController.shared.note(.trimApplied, from: self)
    }

    /// Cancel trimming, restoring the selection from when the mode began.
    func cancelTrim() {
        isTrimming = false
        if let prev = trimBeforeSession { trim = prev }
        trimBeforeSession = nil
        trimSnapHold = VideoCutSnapHold()
    }

    /// Apply the live trim: shrink the working clip to `[in, out]`. The timeline,
    /// duration, and playhead re-seat to the kept range so further edits compose
    /// on top; the cumulative window maps back onto the original file. Nothing
    /// on disk changes until a save — undo via `undoLastEdit` before then.
    func applyTrim() {
        guard trim.isTrimmed else { return }
        var next = cuts
        guard next.keep(fromTimeline: trim.inPoint, toTimeline: trim.outPoint) else { return }
        apply(next, kind: .trim, playheadAt: 0)
    }

    /// Undo the most recent applied edit, restoring the editable state captured
    /// before it. Undoing a trim re-opens trim mode so the restored selection is
    /// visible (handles only show there); undoing a crop just puts the region
    /// back without disturbing the working window or playback.
    func undoLastEdit() {
        guard let prev = editUndo.popLast() else { return }
        let cutsChanged = prev.cuts != cuts
        cuts = prev.cuts
        trim = prev.trim
        crop = prev.crop
        switch prev.kind {
        case .trim:
            pause()
            if trim.isTrimmed, !isCropping {
                trimBeforeSession = trim
                isTrimming = true
            }
            rebuildPlayer(resumeAt: trim.inPoint, keepPlaying: false)
        case .cut, .deletePiece:
            // Land the playhead back on the cut that just came back, so what
            // undo did is the thing you are looking at. The trim session's
            // baseline comes back with it, so Cancel after an undone delete
            // still restores the window the mode opened with.
            if isTrimming { trimBeforeSession = prev.trimSessionBaseline }
            pause()
            currentTime = min(max(0, prev.playheadAfterUndo), cuts.timelineDuration)
            if cutsChanged { rebuildPlayer(resumeAt: currentTime, keepPlaying: false) }
        case .crop:
            // A crop never moves the pieces; only rebuild if one somehow did.
            if cutsChanged { rebuildPlayer(resumeAt: currentTime, keepPlaying: isPlaying) }
        }
    }

    // MARK: - Crop editing (phase 13.4)

    /// Begin cropping: show the overlay. No region is seeded — the user drags
    /// one out (an existing crop comes back adjustable).
    func beginCrop() {
        guard naturalSize.width > 0, naturalSize.height > 0 else { return }
        cropBeforeSession = crop
        cropAspectSelection = crop?.aspect ?? .free
        isCropping = true
        pause()
    }

    /// Replace the crop region (already in natural-video pixels; clamped here).
    func setCropRect(_ rect: CGRect) {
        crop = VideoCrop(rect: rect, videoSize: naturalSize, aspect: cropAspectSelection)
    }

    /// Set the crop aspect lock, re-fitting any existing crop; with none yet,
    /// it applies to the next drag-defined region.
    func setCropAspect(_ aspect: CropAspect) {
        cropAspectSelection = aspect
        if var c = crop {
            c.setAspect(aspect, videoSize: naturalSize)
            crop = c
        }
    }

    /// Clear the region but stay in crop mode — back to drag-to-select.
    func resetCropRegion() {
        crop = nil
    }

    /// Finish cropping, keeping the chosen region (cleared if it's full-frame).
    /// A region that actually changed becomes an undoable step, so Undo restores
    /// the crop that existed before this cropping session.
    func commitCrop() {
        isCropping = false
        if let c = crop, !c.isCropped(videoSize: naturalSize) { crop = nil }
        if crop != cropBeforeSession {
            editUndo.append(EditStep(kind: .crop, cuts: cuts, trim: trim, crop: cropBeforeSession))
        }
        cropBeforeSession = nil
    }

    /// Cancel cropping, restoring whatever region existed when it began.
    func cancelCrop() {
        isCropping = false
        crop = cropBeforeSession
    }

    /// Reset to the full frame.
    func clearCrop() {
        crop = nil
        isCropping = false
    }

    /// The pieces to write at export, in **source-file** seconds: the applied
    /// cuts composed with any live (un-applied) trim, so Export and Copy always
    /// give back exactly what the window is playing.
    var exportCuts: VideoCutList {
        guard trim.isTrimmed else { return cuts }
        var composed = cuts
        composed.keep(fromTimeline: trim.inPoint, toTimeline: trim.outPoint)
        return composed
    }

    /// The same thing as a trim window, for the paths that predate cutting.
    /// Only meaningful while the recording is in one piece.
    var exportTrim: VideoTrim {
        exportCuts.singleTrim ?? VideoTrim(duration: originalDuration)
    }

    /// True when the recording has any edit that requires re-encoding on export.
    var hasEdits: Bool {
        !exportCuts.isWholeClip || (crop?.isCropped(videoSize: naturalSize) ?? false)
    }

    /// The kind of applied edit an undo step reverts, carrying its user-facing
    /// name for the action-specific Undo tooltip.
    private enum EditKind {
        case trim, crop, cut, deletePiece
        var name: String {
            switch self {
            case .trim: "Trim"
            case .crop: "Crop"
            case .cut: "Cut"
            case .deletePiece: "Delete Piece"
            }
        }
    }

    /// A snapshot of the editable state before an applied edit, so `undoLastEdit`
    /// can revert the most recent trim/crop/cut one step at a time.
    private struct EditStep {
        let kind: EditKind
        let cuts: VideoCutList
        let trim: VideoTrim
        let crop: VideoCrop?
        /// The window trim mode opened with, when a mode was open — what Cancel
        /// restores. Carried here because an edit made DURING a trim session
        /// moves it, and undoing that edit has to move it back.
        var trimSessionBaseline: VideoTrim?
        /// Where to put the playhead after this step is undone, in the restored
        /// timeline's own time.
        var playheadAfterUndo: TimeInterval = 0
    }
}
