import AppKit
import AVKit
import PhotonzCore
import SwiftUI

/// The video editor's preview surface: an `AVPlayerView` positioned by a
/// `Viewport`, so recordings pan and zoom exactly like images in the canvas —
/// two-finger scroll pans, pinch zooms around the cursor, a two-finger
/// double-tap toggles fit and pixel-perfect, and double-clicking the empty
/// surround performs the window's title-bar action (we hide the real title
/// bar). The viewport is published to `VideoEditorState` so the crop overlay
/// maps video pixels ↔ view points through the same camera.
struct VideoPreviewView: NSViewRepresentable {
    let player: AVPlayer
    let state: VideoEditorState

    func makeNSView(context: Context) -> VideoPreviewNSView {
        let view = VideoPreviewNSView()
        view.onViewportChange = { [weak state] viewport in
            // Defer: viewport changes can land mid-layout (view resize), and
            // observable mutation during a SwiftUI update is illegal.
            Task { @MainActor in state?.previewViewport = viewport }
        }
        view.onWindowChange = { [weak state] window in
            state?.hostWindow = window
            // Keep the window invisible until metadata lands and it's been
            // sized to the recording — it then appears fully formed instead of
            // opening small and visibly resizing. VideoEditorView reveals it.
            if let window, state?.metadataDidLoad == false {
                window.alphaValue = 0
            }
        }
        return view
    }

    func updateNSView(_ view: VideoPreviewNSView, context: Context) {
        view.configure(player: player)
        view.videoSize = state.naturalSize
        view.isCropping = state.isCropping
        view.cropRect = state.crop?.rect
    }
}

/// The AppKit half: owns the `AVPlayerView` subview and the viewport, and
/// translates trackpad gestures into viewport mutations (mirroring
/// `CanvasNSView`'s pan/zoom behavior).
final class VideoPreviewNSView: NSView {
    /// Clips the player to the committed crop: only the region inside
    /// `contentRect` is visible, so a crop applies to the preview instantly.
    private let contentClipView = FlippedClipView()
    private let playerView = AVPlayerView()
    private(set) var viewport: Viewport?
    /// While true (the initial state), window/view resizes re-fit the video
    /// instead of preserving zoom — so the auto-sized window lands pixel-exact.
    /// Any explicit zoom/pan hands control to the user.
    private var followsFit = true

    var onViewportChange: ((Viewport) -> Void)?
    var onWindowChange: ((NSWindow?) -> Void)?
    /// Crop mode owns double-clicks (defining/committing a region), so the
    /// title-bar action must not fire underneath it. It also shows the whole
    /// frame (the overlay dims outside the region) rather than the crop.
    var isCropping = false {
        didSet { if isCropping != oldValue { contentRectMayHaveChanged() } }
    }
    /// The committed crop region (video pixels); nil = full frame.
    var cropRect: CGRect? {
        didSet { if cropRect != oldValue { contentRectMayHaveChanged() } }
    }

    /// Natural pixel size of the video; setting it (metadata loaded) fits it.
    var videoSize: CGSize = .zero {
        didSet { if videoSize != oldValue { contentRectMayHaveChanged() } }
    }

    /// What the viewport frames: the committed crop when there is one — so the
    /// preview reflects the cropped state immediately — or the whole frame
    /// while cropping (the overlay needs full-video coordinates) and when
    /// uncropped.
    private var contentRect: CGRect {
        let full = CGRect(origin: .zero, size: videoSize)
        guard !isCropping, let cropRect, !cropRect.isEmpty else { return full }
        return cropRect
    }
    /// Last contentRect a viewport was built for, so live crop edits (which
    /// mutate `cropRect` every pointer move while `isCropping` hides them)
    /// don't thrash re-fits.
    private var framedContentRect: CGRect = .null

    // Viewport math is top-left origin; flipping makes view coords match (and
    // line up with the SwiftUI crop overlay drawn on top).
    override var isFlipped: Bool { true }

    override init(frame: CGRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true
        contentClipView.wantsLayer = true
        contentClipView.layer?.masksToBounds = true
        playerView.controlsStyle = .none
        playerView.videoGravity = .resizeAspect
        addSubview(contentClipView)
        contentClipView.addSubview(playerView)
    }

    required init?(coder: NSCoder) { nil }

    func configure(player: AVPlayer) {
        if playerView.player !== player { playerView.player = player }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onWindowChange?(window)
    }

    override func layout() {
        super.layout()
        guard videoSize.width > 0, bounds.width > 0 else {
            contentClipView.frame = bounds
            playerView.frame = contentClipView.bounds
            return
        }
        if followsFit || viewport == nil {
            resetToFit()
        } else if let viewport, viewport.viewSize != bounds.size {
            commit(viewport.resized(viewSize: bounds.size))
        } else {
            positionPlayer()
        }
    }

    // MARK: - Gestures (mirrors CanvasNSView)

    /// Two-finger scroll pans. Deltas arrive in natural-scrolling orientation
    /// and the view is flipped, so they apply directly.
    override func scrollWheel(with event: NSEvent) {
        guard let viewport else { return }
        let scale: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 10
        followsFit = false
        commit(viewport.panned(by: CGPoint(x: event.scrollingDeltaX * scale,
                                           y: event.scrollingDeltaY * scale)))
    }

    /// Pinch zooms around the cursor.
    override func magnify(with event: NSEvent) {
        guard let viewport else { return }
        let anchor = convert(event.locationInWindow, from: nil)
        followsFit = false
        commit(viewport.zoomed(to: viewport.zoom * (1 + event.magnification), anchorInView: anchor))
    }

    /// Two-finger double-tap: toggle between fit and pixel-perfect at the
    /// cursor (or 2× when fit already IS pixel-perfect).
    override func smartMagnify(with event: NSEvent) {
        guard let viewport else { return }
        let fit = fitViewport()
        if abs(viewport.zoom - fit.zoom) < 0.001 {
            let pixelPerfect = pixelPerfectZoom
            let target = abs(fit.zoom - pixelPerfect) < 0.001 ? pixelPerfect * 2 : pixelPerfect
            let anchor = convert(event.locationInWindow, from: nil)
            followsFit = false
            commit(viewport.zoomed(to: target, anchorInView: anchor))
        } else {
            followsFit = true
            commit(fit)
        }
    }

    /// Double-click on the empty surround = the window title-bar action, same
    /// as the image canvas (the real title bar is hidden).
    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2, !isCropping,
           let viewport,
           !viewport.documentFrameInView.contains(convert(event.locationInWindow, from: nil)) {
            WindowTitleBarAction.perform(on: window)
            return
        }
        super.mouseDown(with: event)
    }

    // MARK: - Viewport

    /// Zoom at which one video pixel maps to one device pixel — "100%" for a
    /// screen recording (it appears exactly as recorded, and crisp).
    private var pixelPerfectZoom: CGFloat {
        1 / max(1, window?.backingScaleFactor ?? 2)
    }

    /// Whole-content fit (the crop when committed, else the whole video),
    /// capped at pixel-perfect: a small recording in a big window centers at
    /// 100% rather than upscaling.
    private func fitViewport() -> Viewport {
        let content = contentRect.size
        let fit = Viewport.fit(documentSize: content, in: bounds.size, padding: 0)
        let cap = pixelPerfectZoom
        guard fit.zoom > cap else { return fit }
        return Viewport(documentSize: content, viewSize: bounds.size, zoom: cap, origin: .zero)
            .clamped()
    }

    /// Re-fit when the effective content actually changed (crop committed /
    /// cleared / metadata loaded) — not for every live edit inside crop mode.
    private func contentRectMayHaveChanged() {
        let content = contentRect
        guard content != framedContentRect else { return }
        framedContentRect = content
        resetToFit()
    }

    private func resetToFit() {
        guard videoSize.width > 0, bounds.width > 0 else { return }
        followsFit = true
        commit(fitViewport())
    }

    private func commit(_ next: Viewport) {
        guard next != viewport else { return }
        viewport = next
        positionPlayer()
        onViewportChange?(next)
    }

    /// The clip view shows exactly `contentRect`; the player is laid out at
    /// full-video size inside it, offset so the content region lands on top.
    private func positionPlayer() {
        guard let viewport else { return }
        let content = contentRect
        contentClipView.frame = viewport.documentFrameInView
        playerView.frame = CGRect(x: -content.minX * viewport.zoom,
                                  y: -content.minY * viewport.zoom,
                                  width: videoSize.width * viewport.zoom,
                                  height: videoSize.height * viewport.zoom)
    }
}

/// Top-left-origin clipping container, so the player's offset math matches the
/// flipped preview view.
private final class FlippedClipView: NSView {
    override var isFlipped: Bool { true }
}
