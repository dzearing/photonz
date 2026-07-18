import AppKit
import AVKit
import PhotonzCore
import SwiftUI

/// Root of a video-editor window (phase 13.3): an AVKit preview with a floating,
/// QuickTime-style glass controller that auto-hides during playback and returns
/// on mouse movement or a keypress. The controller carries a neutral scrubber,
/// centered transport, volume, and the explicit trim/crop edit modes. Trim and
/// crop are non-destructive (applied at export). Mirrors `EditorView`'s idioms.
struct VideoEditorView: View {
    @Environment(VideoEditorState.self) private var state
    @Environment(AppCoordinator.self) private var coordinator
    /// Keeps keyboard transport (space / ←·→) routed to this view rather than the
    /// AVPlayerView. Re-asserted once the clip is ready.
    @FocusState private var keyboardFocused: Bool
    /// Live size of the preview area, for sizing the window to the recording.
    @State private var playerAreaSize: CGSize = .zero

    // Auto-hide + drag state for the floating controller.
    /// Controls start hidden and only reveal when the pointer moves into the
    /// bottom band (or a transport key is pressed); they fade back out shortly
    /// after the pointer leaves, whether playing or paused.
    @State private var controlsVisible = false
    /// True while the pointer rests on the controller itself — pins it visible
    /// (no auto-fade) until the pointer leaves or the user hits play.
    @State private var hoveringControls = false
    @State private var hideTask: Task<Void, Never>?
    /// Local size of the root view, so hover locations can be tested against the
    /// bottom reveal band.
    @State private var viewSize: CGSize = .zero
    @State private var controlsDragOffset: CGSize = .zero
    @GestureState private var controlsDragTranslation: CGSize = .zero

    /// Height of the bottom-of-window band that reveals the controller on mouse
    /// movement — sized to comfortably cover the controller plus a little above.
    private let revealBand: CGFloat = 200

    /// True while an explicit edit mode is active — the controller stays pinned
    /// (never auto-hides) so the mode's chrome is always reachable.
    private var editing: Bool { state.isTrimming || state.isCropping }

    var body: some View {
        ZStack {
            Color(nsColor: .underPageBackgroundColor)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                // The title bar is hidden; a double-click on the empty
                // background stands in for double-clicking it (zoom/minimize
                // per the system preference), matching the image canvas.
                .onTapGesture(count: 2) { WindowTitleBarAction.perform(on: state.hostWindow) }

            player
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(16)

            if state.isReady {
                VStack {
                    Spacer()
                    controlsPanel
                        .padding(.horizontal, 16)
                        .padding(.bottom, 20)
                }
                .opacity(controlsVisible ? 1 : 0)
                .allowsHitTesting(controlsVisible)
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onGeometryChange(for: CGSize.self, of: { $0.size }) { viewSize = $0 }
        .focusable(state.isReady)
        .focusEffectDisabled()
        .focused($keyboardFocused)
        .onAppear { keyboardFocused = true }
        .onChange(of: state.isReady) { _, ready in if ready { keyboardFocused = true } }
        // Hitting play hides the controller even if the pointer is resting on
        // it (the one case that overrides the hover pin); moving the mouse
        // brings it back. Pausing reveals it.
        .onChange(of: state.isPlaying) { _, playing in playing ? forceHide() : reveal() }
        // Entering an edit mode reveals the controller and pins it (it never
        // auto-hides while editing). Leaving a mode re-arms the fade.
        .onChange(of: state.isTrimming) { _, _ in reveal() }
        .onChange(of: state.isCropping) { _, _ in reveal() }
        .onChange(of: state.metadataDidLoad) { _, loaded in
            guard loaded else { return }
            // Next runloop tick: the timeline panel has just appeared, so let
            // layout settle before measuring the player area for the resize.
            // The window was kept invisible for this; reveal it once sized so
            // it opens fully formed instead of visibly bouncing.
            DispatchQueue.main.async {
                sizeWindowToRecording()
                if let window = state.hostWindow, window.alphaValue < 1 {
                    window.alphaValue = 1
                }
            }
        }
        // Moving the pointer into the bottom band reveals the controller;
        // moving elsewhere (or off the window) fades it back out.
        .onContinuousHover { phase in
            switch phase {
            case .active(let location):
                if pointerInRevealBand(location) { reveal() } else { hideSoon() }
            case .ended:
                hideSoon()
            }
        }
        .onKeyPress(phases: [.down, .repeat]) { press in
            let result = handleKey(press)
            if result == .handled { reveal() }
            return result
        }
    }

    // MARK: - Auto-hide

    /// True when a hover location sits within the reveal band at the bottom of
    /// the window, where the controller lives.
    private func pointerInRevealBand(_ location: CGPoint) -> Bool {
        guard viewSize.height > 0 else { return false }
        return location.y >= viewSize.height - revealBand
    }

    /// Show the controller now and re-arm the fade-out.
    private func reveal() {
        if !controlsVisible {
            withAnimation(.easeOut(duration: 0.18)) { controlsVisible = true }
        }
        scheduleHide()
    }

    /// Fade the controller after a beat. Stays pinned while the pointer rests on
    /// it or an edit mode is active, so it never vanishes out from under the
    /// cursor; only leaving it (or hitting play) starts the fade.
    private func scheduleHide(after seconds: Double = 2.4) {
        hideTask?.cancel()
        guard !editing, !hoveringControls, controlsVisible else { return }
        hideTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.45)) { controlsVisible = false }
        }
    }

    /// Fade sooner when the pointer leaves the band or the window entirely.
    private func hideSoon() { scheduleHide(after: 0.5) }

    /// Hide immediately, overriding the hover pin — used when playback starts so
    /// the controller gets out of the way even with the cursor on it.
    private func forceHide() {
        hideTask?.cancel()
        guard controlsVisible else { return }
        withAnimation(.easeInOut(duration: 0.35)) { controlsVisible = false }
    }

    /// Open at "100% video": grow/shrink the window so the preview area shows
    /// the recording (or its committed crop) pixel-exact, clamped to the
    /// screen. One video pixel maps to one device pixel, so the clip appears
    /// exactly as recorded.
    private func sizeWindowToRecording() {
        guard let window = state.hostWindow, state.displayContentSize != .zero,
              playerAreaSize != .zero,
              let screen = window.screen ?? NSScreen.main else { return }
        let scale = max(1, window.backingScaleFactor)
        let target = CGSize(width: state.displayContentSize.width / scale,
                            height: state.displayContentSize.height / scale)
        let minSize = CGSize(width: max(window.minSize.width, 760),
                             height: max(window.minSize.height, 520))
        let frame = VideoWindowLayout.frame(
            current: window.frame, playerArea: playerAreaSize,
            targetPlayerArea: target, minSize: minSize,
            visible: screen.visibleFrame)
        // Invisible while opening → snap straight to the target frame; visible
        // (shouldn't normally happen) → animate.
        window.setFrame(frame, display: true, animate: window.alphaValue >= 1)
    }

    /// Transport keys. Space toggles play/pause on key-down only (so holding it
    /// doesn't stutter); ←/→ fire on key-down *and* auto-repeat, so holding an
    /// arrow scrubs continuously — frame-by-frame while paused, in 5s jumps while
    /// playing. Crop mode hands keys back (Esc/Return drive the crop sheet).
    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        guard state.isReady, !state.isCropping else { return .ignored }
        switch press.key {
        case .space:
            if press.phase == .down { state.togglePlayPause() }
            return .handled
        case .leftArrow:
            state.stepBackward()
            return .handled
        case .rightArrow:
            state.stepForward()
            return .handled
        default:
            return .ignored
        }
    }

    @ViewBuilder
    private var player: some View {
        if let player = state.player {
            VideoPreviewView(player: player, state: state)
                .background(Color.black)
                .overlay {
                    if state.isCropping {
                        VideoCropOverlay(state: state)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(radius: 12, y: 4)
                .onGeometryChange(for: CGSize.self, of: { $0.size }) { playerAreaSize = $0 }
        } else if let poster = state.poster {
            Image(decorative: poster, scale: 1)
                .resizable()
                .scaledToFit()
        } else {
            Color.black
        }
    }

    // MARK: - Floating controller

    /// The glass controller: transport row on top (volume · transport · edit),
    /// scrubber (or the active mode's timeline) below — QuickTime's order. It
    /// floats over the video, auto-hides, and can be dragged to reposition.
    private var controlsPanel: some View {
        VStack(spacing: 8) {
            topRow
            bottomRow
                .frame(height: 44)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
        .offset(x: controlsDragOffset.width + controlsDragTranslation.width,
                y: controlsDragOffset.height + controlsDragTranslation.height)
        .gesture(panelDrag)
        // Resting the pointer on the controller pins it (never fades); leaving
        // re-arms the fade. Hitting play still overrides this via forceHide().
        .onHover { hovering in
            hoveringControls = hovering
            if hovering {
                hideTask?.cancel()
                if !controlsVisible {
                    withAnimation(.easeOut(duration: 0.18)) { controlsVisible = true }
                }
            } else {
                scheduleHide(after: 0.5)
            }
        }
    }

    /// Drag the whole controller to reposition it, like QuickTime. Child controls
    /// (buttons, scrubber, volume) keep gesture priority in their own areas, so
    /// only a drag on the panel chrome moves it.
    private var panelDrag: some Gesture {
        DragGesture(minimumDistance: 8)
            .updating($controlsDragTranslation) { value, translation, _ in
                translation = value.translation
            }
            .onEnded { value in
                var offset = controlsDragOffset
                offset.width += value.translation.width
                offset.height += value.translation.height
                controlsDragOffset = clampOffset(offset)
            }
    }

    /// Keep the dragged controller within the player area so it stays grabbable.
    private func clampOffset(_ offset: CGSize) -> CGSize {
        guard playerAreaSize != .zero else { return offset }
        let maxX = max(0, playerAreaSize.width / 2 - 80)
        let maxUp = max(0, playerAreaSize.height - 130)
        return CGSize(width: min(max(offset.width, -maxX), maxX),
                      height: min(max(offset.height, -maxUp), 8))
    }

    /// Top row: volume + status on the left, transport centered, edit actions
    /// (or the active mode's session buttons) on the right.
    private var topRow: some View {
        ZStack {
            transportCluster

            HStack(spacing: 10) {
                VolumeControl(state: state)
                statusLabels
                Spacer(minLength: 12)
                if state.isTrimming {
                    trimModeButtons
                } else if !state.isCropping {
                    editButtons
                }
            }
        }
    }

    /// Bottom row: the playback scrubber, or the active edit mode's timeline.
    /// Constant 44pt height so switching modes never jumps the controller.
    @ViewBuilder
    private var bottomRow: some View {
        if state.isCropping {
            cropRow
        } else if state.isTrimming {
            TrimTimeline(state: state)
        } else {
            scrubberRow
        }
    }

    /// Playback position line: current time · scrubber · total duration.
    private var scrubberRow: some View {
        HStack(spacing: 10) {
            timecode(state.currentTime)
            PlaybackScrubber(state: state)
            timecode(state.duration)
        }
    }

    private func timecode(_ seconds: TimeInterval) -> some View {
        Text(VideoTimecode.label(seconds))
            .font(.system(size: 12, weight: .regular))
            .monospacedDigit()
            .foregroundStyle(.secondary)
    }

    /// Quiet secondary readouts beside the volume control: trimmed length while
    /// trimming, cropped output size once a crop exists.
    @ViewBuilder
    private var statusLabels: some View {
        if state.isTrimming, state.trim.isTrimmed {
            Label(VideoTimecode.label(state.trim.effectiveDuration), systemImage: "scissors")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        if let crop = state.crop, crop.isCropped(videoSize: state.naturalSize), !state.isCropping {
            Label("\(Int(crop.outputSize.width))×\(Int(crop.outputSize.height))", systemImage: "crop")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    /// The right-side actions, all sharing the circular icon style: undo (when
    /// there's an applied edit to revert), trim, crop, copy, export.
    private var editButtons: some View {
        HStack(spacing: 6) {
            if let action = state.lastEditActionName {
                Button { state.undoLastEdit() } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .buttonStyle(IconActionButtonStyle())
                .help("Undo \(action)")
            }
            Button { state.beginTrim() } label: {
                Image(systemName: "scissors")
            }
            .buttonStyle(IconActionButtonStyle())
            .help("Trim")

            Button { state.beginCrop() } label: {
                Image(systemName: "crop")
            }
            .buttonStyle(IconActionButtonStyle())
            .help("Crop to Region")

            copyMenu
            exportMenu
        }
    }

    /// Trim-mode session chrome, mirroring the crop row's Reset/Cancel/Done.
    private var trimModeButtons: some View {
        HStack(spacing: 12) {
            Button("Reset") { state.resetTrimSelection() }
                .buttonStyle(.plain)
                .font(.caption)
                .disabled(!state.trim.isTrimmed)
            Button("Cancel") { state.cancelTrim() }
                .keyboardShortcut(.cancelAction)
            Button("Done") { state.commitTrim() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
        }
    }

    /// Step-back · play/pause · step-forward. The play button is deliberately
    /// larger than the step buttons, QuickTime-style. Steps follow the keyboard:
    /// ±5s while playing, ±1 frame while paused (icons/tooltips reflect the mode).
    private var transportCluster: some View {
        HStack(spacing: 10) {
            Button { state.stepBackward() } label: {
                Image(systemName: state.isPlaying ? "gobackward" : "backward.frame.fill")
            }
            .buttonStyle(IconActionButtonStyle())
            .help(state.isPlaying ? "Back 1 second (←)" : "Previous frame (←)")

            Button { state.togglePlayPause() } label: {
                Image(systemName: state.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 28, weight: .bold))
            }
            .buttonStyle(IconActionButtonStyle(diameter: 50))
            .help(state.isPlaying ? "Pause (space)" : "Play (space)")

            Button { state.stepForward() } label: {
                Image(systemName: state.isPlaying ? "goforward" : "forward.frame.fill")
            }
            .buttonStyle(IconActionButtonStyle())
            .help(state.isPlaying ? "Forward 1 second (→)" : "Next frame (→)")
        }
        .disabled(state.isCropping)
    }

    /// Copy the (trimmed/cropped) recording to the clipboard as the video file
    /// or as an animated GIF — the paste-into-chat counterpart of Export.
    private var copyMenu: some View {
        Menu {
            Button("Copy Video") { coordinator.copyRecording(state, as: .mp4) }
            Button("Copy GIF") { coordinator.copyRecording(state, as: .gif) }
        } label: {
            Image(systemName: "doc.on.doc")
        }
        .menuStyle(.button)
        .buttonStyle(IconActionButtonStyle())
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(coordinator.isExportingRecording)
        .help("Copy to Clipboard…")
    }

    private var exportMenu: some View {
        Menu {
            Button("Export MP4…") { coordinator.saveRecording(state, as: .mp4) }
            Menu("Export GIF") {
                ForEach(VideoExportQuality.allCases, id: \.self) { quality in
                    Button(quality.label) { coordinator.saveRecording(state, as: .gif, quality: quality) }
                }
            }
            Menu("Export HEIC") {
                ForEach(VideoExportQuality.allCases, id: \.self) { quality in
                    Button(quality.label) { coordinator.saveRecording(state, as: .heic, quality: quality) }
                }
            }
        } label: {
            if coordinator.isExportingRecording {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: "square.and.arrow.down")
            }
        }
        .menuStyle(.button)
        .buttonStyle(IconActionButtonStyle())
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(coordinator.isExportingRecording)
        .help("Export…")
    }

    /// Crop controls replace the timeline while a region is being chosen.
    private var cropRow: some View {
        HStack(spacing: 12) {
            ForEach(CropAspect.allCases, id: \.self) { aspect in
                Button(aspect.label) { state.setCropAspect(aspect) }
                    .buttonStyle(.plain)
                    .font(.caption.weight(state.cropAspectSelection == aspect ? .bold : .regular))
                    .foregroundStyle(state.cropAspectSelection == aspect ? Color.accentColor : .secondary)
            }
            Spacer()
            Button("Reset") { state.resetCropRegion() }
                .buttonStyle(.plain)
                .font(.caption)
                .disabled(state.crop == nil)
            Button("Cancel") { state.cancelCrop() }
                .keyboardShortcut(.cancelAction)
            Button("Done") { state.commitCrop() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
        }
        .frame(height: 44)
    }
}

/// Pure timecode formatting for the transport labels.
enum VideoTimecode {
    static func label(_ seconds: TimeInterval) -> String {
        let total = max(0, seconds)
        let m = Int(total) / 60
        let s = Int(total) % 60
        let cs = Int((total - Double(Int(total))) * 100)
        return String(format: "%d:%02d.%02d", m, s, cs)
    }
}
