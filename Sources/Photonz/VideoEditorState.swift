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
    /// The working window into the source file, in original-file seconds. Apply
    /// Trim narrows it; everything the UI shows (timeline, playhead, live trim) is
    /// expressed relative to this window. Starts at the whole clip.
    private(set) var appliedIn: TimeInterval = 0
    private(set) var appliedOut: TimeInterval = 0
    /// The working clip length the UI edits within — the applied window's span.
    var duration: TimeInterval { max(0, appliedOut - appliedIn) }
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
                // Player runs in original-file time; the UI works in window time.
                let working = (time.seconds.isFinite ? time.seconds : self.appliedIn) - self.appliedIn
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

    /// Re-point the player at `source` (the preserved original, after the first
    /// save turned the recording itself into the trimmed output), keeping the
    /// playhead and play state.
    private func rebindPlayer(to source: URL) {
        guard let player else { return }
        let wasPlaying = isPlaying
        let resumeAt = currentTime
        player.replaceCurrentItem(with: AVPlayerItem(url: source))
        installEndObserver(on: player)
        seek(to: resumeAt)
        if wasPlaying { player.play() }
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
        self.appliedIn = 0
        self.appliedOut = seconds
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
                if let saved = edits.trim, saved.isTrimmed {
                    self.appliedIn = saved.inPoint
                    self.appliedOut = saved.outPoint
                    self.trim = VideoTrim(duration: duration)
                }
                self.crop = edits.crop
            }
        }
        self.isReady = seconds > 0
        self.metadataDidLoad = true
        if isReady {
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

    /// Seek to `seconds` in **working** time (frame-accurate within tolerance);
    /// the player itself is offset into the applied window.
    func seek(to seconds: TimeInterval) {
        guard let player else { return }
        let clamped = min(max(0, seconds), max(0, duration))
        let time = CMTime(seconds: appliedIn + clamped, preferredTimescale: 600)
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
        VideoEdits(trim: exportTrim, crop: crop).normalized(videoSize: naturalSize)
    }

    /// The edits the stored recording already has baked in — the clean
    /// baseline, the video sibling of `EditorState.savedDocument`. Observed, so
    /// the dirty dot and the Save affordance track it live.
    private(set) var committedEdits = VideoEdits()

    /// True while a save's re-encode is in flight.
    private(set) var isSaving = false

    /// Whether closing this window would lose work — the same question
    /// `EditorState.hasUnsavedChanges` answers for an image.
    var hasUnsavedChanges: Bool {
        guard isReady, url != nil else { return false }
        return VideoSaveState.needsSave(edits: exportEdits, committed: committedEdits)
    }

    /// True when there is a save to perform (drives ⌘S / the Save button).
    var canSave: Bool { isReady && url != nil && !isSaving }

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
            completion?(true) // nothing loaded, nothing to lose
            return
        }
        // Never claim "saved" while an earlier commit is still running — edits
        // made since it started would be dropped on the floor.
        guard !isSaving else {
            completion?(false)
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
                    let source = VideoOriginals.url(for: mediaURL)
                    editSourceURL = source
                    rebindPlayer(to: source)
                }
                isSaving = false
                // The stored media changed: refresh the history thumbnail and
                // duration pill.
                capture?.store.reload()
                completion?(true)
            } catch {
                isSaving = false
                presentSaveFailure(error)
                completion?(false)
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
        editUndo.append(EditStep(kind: .trim, appliedIn: appliedIn, appliedOut: appliedOut,
                                 trim: trim, crop: crop))
        appliedIn = 0
        appliedOut = originalDuration
        trim = VideoTrim(duration: originalDuration)
        crop = nil
        isTrimming = false
        isCropping = false
        pause()
        seek(to: 0)
    }

    private func presentSaveFailure(_ error: Error) {
        NSLog("Couldn't save the recording: \(error)")
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Couldn't save the recording"
        alert.informativeText = String(describing: error)
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
    }

    /// Drag the out-handle; seeking to the out-point so the preview shows it.
    func setTrimOut(_ seconds: TimeInterval) {
        pause()
        trim.setOut(seconds, duration: duration)
        seek(to: trim.outPoint)
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
        if trim.isTrimmed { applyTrim() }
    }

    /// Cancel trimming, restoring the selection from when the mode began.
    func cancelTrim() {
        isTrimming = false
        if let prev = trimBeforeSession { trim = prev }
        trimBeforeSession = nil
    }

    /// Apply the live trim: shrink the working clip to `[in, out]`. The timeline,
    /// duration, and playhead re-seat to the kept range so further edits compose
    /// on top; the cumulative window maps back onto the original file. Nothing
    /// on disk changes until a save — undo via `undoLastEdit` before then.
    func applyTrim() {
        guard trim.isTrimmed else { return }
        editUndo.append(EditStep(kind: .trim, appliedIn: appliedIn, appliedOut: appliedOut,
                                 trim: trim, crop: crop))
        appliedOut = appliedIn + trim.outPoint
        appliedIn += trim.inPoint
        trim = VideoTrim(duration: duration)
        pause()
        seek(to: 0)
    }

    /// Undo the most recent applied edit, restoring the editable state captured
    /// before it. Undoing a trim re-opens trim mode so the restored selection is
    /// visible (handles only show there); undoing a crop just puts the region
    /// back without disturbing the working window or playback.
    func undoLastEdit() {
        guard let prev = editUndo.popLast() else { return }
        appliedIn = prev.appliedIn
        appliedOut = prev.appliedOut
        trim = prev.trim
        crop = prev.crop
        if prev.kind == .trim {
            pause()
            if trim.isTrimmed, !isCropping {
                trimBeforeSession = trim
                isTrimming = true
            }
            seek(to: trim.inPoint)
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
            editUndo.append(EditStep(kind: .crop, appliedIn: appliedIn, appliedOut: appliedOut,
                                     trim: trim, crop: cropBeforeSession))
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

    /// The trim to apply at export, in **source-file** seconds: the cumulative
    /// applied window composed with any live (un-applied) trim.
    var exportTrim: VideoTrim {
        VideoTrim(inPoint: appliedIn + trim.inPoint,
                  outPoint: appliedIn + trim.outPoint,
                  duration: originalDuration)
    }

    /// True when the recording has any edit that requires re-encoding on export.
    var hasEdits: Bool {
        exportTrim.isTrimmed || (crop?.isCropped(videoSize: naturalSize) ?? false)
    }

    /// The kind of applied edit an undo step reverts, carrying its user-facing
    /// name for the action-specific Undo tooltip.
    private enum EditKind {
        case trim, crop
        var name: String {
            switch self {
            case .trim: "Trim"
            case .crop: "Crop"
            }
        }
    }

    /// A snapshot of the editable state before an applied edit, so `undoLastEdit`
    /// can revert the most recent trim/crop one step at a time.
    private struct EditStep {
        let kind: EditKind
        let appliedIn: TimeInterval
        let appliedOut: TimeInterval
        let trim: VideoTrim
        let crop: VideoCrop?
    }
}
