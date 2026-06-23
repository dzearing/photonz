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
    /// The AVKit player driving the preview. Created on `seed`.
    private(set) var player: AVPlayer?
    /// Source length in seconds (loaded asynchronously).
    private(set) var duration: TimeInterval = 0
    /// Natural pixel size of the video, oriented (after `preferredTransform`),
    /// for the crop overlay. `.zero` until loaded.
    private(set) var naturalSize: CGSize = .zero
    /// A poster frame for the empty/loading state.
    private(set) var poster: CGImage?

    /// Non-destructive trim window. Full-clip until the user drags a handle.
    private(set) var trim = VideoTrim(duration: 0)
    /// Non-destructive crop region in natural-video-pixel space, top-left
    /// origin (phase 13.4). Nil = full frame.
    private(set) var crop: VideoCrop?
    /// Whether the crop overlay is active (the user is choosing a region).
    var isCropping = false

    /// Live playback head in seconds, updated by the periodic observer so the
    /// scrubber's playhead tracks playback.
    private(set) var currentTime: TimeInterval = 0
    /// Whether the player is currently playing (drives the play/pause button).
    private(set) var isPlaying = false

    /// True once metadata (duration/size) has loaded, so the timeline can render.
    private(set) var isReady = false

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
                self.currentTime = time.seconds.isFinite ? time.seconds : 0
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
        // The asset reference is intentionally unused past metadata; AVPlayerItem
        // holds its own.
        _ = asset
        self.duration = seconds
        self.naturalSize = oriented
        self.poster = poster
        self.trim = VideoTrim(duration: seconds)
        self.isReady = seconds > 0
    }

    // MARK: - Playback

    func togglePlayPause() {
        guard let player else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            // Restart from the in-point if we're at/after the out-point.
            if currentTime >= trim.outPoint - 1e-3 || currentTime < trim.inPoint {
                seek(to: trim.inPoint)
            }
            player.play()
            isPlaying = true
        }
    }

    func pause() {
        player?.pause()
        isPlaying = false
    }

    /// Seek the player to `seconds` (frame-accurate within tolerance).
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

    // MARK: - Crop editing (phase 13.4)

    /// Begin cropping: show the overlay, seeding a full-frame region if none.
    func beginCrop() {
        guard naturalSize.width > 0, naturalSize.height > 0 else { return }
        if crop == nil { crop = VideoCrop(fullFrame: naturalSize) }
        isCropping = true
        pause()
    }

    /// Replace the crop region (already in natural-video pixels; clamped here).
    func setCropRect(_ rect: CGRect) {
        crop = VideoCrop(rect: rect, videoSize: naturalSize, aspect: crop?.aspect ?? .free)
    }

    /// Set the crop aspect lock, re-fitting any existing crop (or starting one).
    func setCropAspect(_ aspect: CropAspect) {
        if var c = crop {
            c.setAspect(aspect, videoSize: naturalSize)
            crop = c
        } else if naturalSize.width > 0 {
            crop = VideoCrop(fullFrame: naturalSize, aspect: aspect)
        }
    }

    /// Finish cropping, keeping the chosen region (cleared if it's full-frame).
    func commitCrop() {
        isCropping = false
        if let c = crop, !c.isCropped(videoSize: naturalSize) { crop = nil }
    }

    /// Cancel cropping, dropping the region.
    func cancelCrop() {
        isCropping = false
        crop = nil
    }

    /// Reset to the full frame.
    func clearCrop() {
        crop = nil
        isCropping = false
    }

    /// True when the recording has any edit that requires re-encoding on export.
    var hasEdits: Bool {
        trim.isTrimmed || (crop?.isCropped(videoSize: naturalSize) ?? false)
    }
}
