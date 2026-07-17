import AppKit
import AVFoundation
import CoreGraphics
import Observation
import PhotonzCore
import SwiftUI

/// Per-window state for the in-app video editor (phase 13.3). The sibling of
/// `EditorState` for recordings: it keeps `EditorState` image-pure by owning the
/// `AVPlayer`/`AVPlayerItem` (both non-Sendable, so this whole type is
/// `@MainActor`) plus the pure, non-destructive `VideoTrim`/`VideoCrop`. Trim
/// and crop live only in memory for v1 — they're applied at export, never baked
/// into the source file.
@MainActor
@Observable
final class VideoEditorState {
    /// The recording being edited; nil until `seed`.
    private(set) var url: URL?
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

    @ObservationIgnored private var sidecarSaveTask: Task<Void, Never>?
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

        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        // Looping is handled within [in, out]; never let AVPlayer overshoot.
        player.actionAtItemEnd = .pause
        self.player = player
        self.cleanupPlayer = player

        installObservers(on: player)
        Task { await loadMetadata(url: url) }
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
        self.appliedIn = 0
        self.appliedOut = seconds
        self.naturalSize = oriented
        self.poster = poster
        self.frameRate = fps
        self.trim = VideoTrim(duration: seconds)
        // Recall persisted edits (sidecar) so a trim/crop made in an earlier
        // session survives the window closing. A saved trim is the recording's
        // state, not a pending action, so it folds straight into the applied
        // window with NO undo step — opening a previously trimmed video shows it
        // trimmed with nothing to undo. Trim handles only appear in trim mode,
        // where Reset restores the full length.
        if let edits = VideoEditsSidecar.load(for: url) {
            if let saved = edits.trim, saved.isTrimmed {
                self.appliedIn = saved.inPoint
                self.appliedOut = saved.outPoint
                self.trim = VideoTrim(duration: duration)
            }
            self.crop = edits.crop
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

    // MARK: - Edits persistence

    /// The cumulative edits every export/copy path should honor — the composed
    /// trim plus the crop, with no-op edits dropped.
    var exportEdits: VideoEdits {
        VideoEdits(trim: exportTrim, crop: crop).normalized(videoSize: naturalSize)
    }

    /// Persist the current edits to the `.photonzedits` sidecar (debounced —
    /// handle drags mutate the trim once per pointer move). This is what lets
    /// the history overlay's export/copy honor edits after this window closes.
    private func persistEdits() {
        guard url != nil, isReady else { return }
        sidecarSaveTask?.cancel()
        sidecarSaveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, let self, let url = self.url else { return }
            VideoEditsSidecar.save(self.exportEdits, for: url)
        }
    }

    // MARK: - Trim editing

    /// Drag the in-handle; seeking to the new in-point so the preview shows it.
    func setTrimIn(_ seconds: TimeInterval) {
        pause()
        trim.setIn(seconds, duration: duration)
        seek(to: trim.inPoint)
        persistEdits()
    }

    /// Drag the out-handle; seeking to the out-point so the preview shows it.
    func setTrimOut(_ seconds: TimeInterval) {
        pause()
        trim.setOut(seconds, duration: duration)
        seek(to: trim.outPoint)
        persistEdits()
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
        persistEdits()
    }

    /// Finish trimming: fold any selection into the working window (undoable
    /// via `undoLastEdit`, same as the old Apply Trim).
    func commitTrim() {
        isTrimming = false
        trimBeforeSession = nil
        if trim.isTrimmed { applyTrim() } else { persistEdits() }
    }

    /// Cancel trimming, restoring the selection from when the mode began.
    func cancelTrim() {
        isTrimming = false
        if let prev = trimBeforeSession { trim = prev }
        trimBeforeSession = nil
        persistEdits()
    }

    /// Apply the live trim: shrink the working clip to `[in, out]`. The timeline,
    /// duration, and playhead re-seat to the kept range so further edits compose
    /// on top; export maps the cumulative window back onto the source file. The
    /// source file is never modified — undo via `undoLastEdit`.
    func applyTrim() {
        guard trim.isTrimmed else { return }
        editUndo.append(EditStep(kind: .trim, appliedIn: appliedIn, appliedOut: appliedOut,
                                 trim: trim, crop: crop))
        appliedOut = appliedIn + trim.outPoint
        appliedIn += trim.inPoint
        trim = VideoTrim(duration: duration)
        pause()
        seek(to: 0)
        persistEdits()
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
        persistEdits()
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
        persistEdits()
    }

    /// Set the crop aspect lock, re-fitting any existing crop; with none yet,
    /// it applies to the next drag-defined region.
    func setCropAspect(_ aspect: CropAspect) {
        cropAspectSelection = aspect
        if var c = crop {
            c.setAspect(aspect, videoSize: naturalSize)
            crop = c
            persistEdits()
        }
    }

    /// Clear the region but stay in crop mode — back to drag-to-select.
    func resetCropRegion() {
        crop = nil
        persistEdits()
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
        persistEdits()
    }

    /// Cancel cropping, restoring whatever region existed when it began.
    func cancelCrop() {
        isCropping = false
        crop = cropBeforeSession
        persistEdits()
    }

    /// Reset to the full frame.
    func clearCrop() {
        crop = nil
        isCropping = false
        persistEdits()
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
