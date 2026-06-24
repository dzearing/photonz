import AppKit
import AVKit
import PhotonzCore
import SwiftUI

/// Root of a video-editor window (phase 13.3): an AVKit preview above a custom
/// Liquid-Glass timeline with draggable in/out trim handles. Trim is
/// non-destructive (applied at export). Mirrors `EditorView`'s layout idioms.
struct VideoEditorView: View {
    @Environment(VideoEditorState.self) private var state
    @Environment(AppCoordinator.self) private var coordinator
    /// Keeps keyboard transport (space / ←·→) routed to this view rather than the
    /// AVPlayerView. Re-asserted once the clip is ready.
    @FocusState private var keyboardFocused: Bool

    var body: some View {
        ZStack {
            Color(nsColor: .underPageBackgroundColor)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                player
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(16)

                if state.isReady {
                    VStack(spacing: 10) {
                        if state.isCropping {
                            cropRow
                        } else {
                            TrimTimeline(state: state)
                        }
                        transportRow
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                    .glassEffect(.regular, in: .rect(cornerRadius: 18))
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                } else {
                    ProgressView()
                        .padding(.bottom, 24)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .focusable(state.isReady)
        .focusEffectDisabled()
        .focused($keyboardFocused)
        .onAppear { keyboardFocused = true }
        .onChange(of: state.isReady) { _, ready in if ready { keyboardFocused = true } }
        .onKeyPress(phases: [.down, .repeat]) { press in handleKey(press) }
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
            VideoPlayerView(player: player)
                .background(Color.black)
                .overlay {
                    if state.isCropping {
                        VideoCropOverlay(state: state)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(radius: 12, y: 4)
        } else if let poster = state.poster {
            Image(decorative: poster, scale: 1)
                .resizable()
                .scaledToFit()
        } else {
            Color.black
        }
    }

    private var transportRow: some View {
        HStack(spacing: 14) {
            transportCluster

            Text(VideoTimecode.label(state.currentTime))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)

            Spacer()

            if state.canApplyTrim {
                Label(VideoTimecode.label(state.trim.effectiveDuration),
                      systemImage: "scissors")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Apply Trim") { state.applyTrim() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .help("Shrink the working clip to the selected range")
            }
            if state.canUndoTrim {
                Button { state.undoApplyTrim() } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .buttonStyle(IconActionButtonStyle())
                .help("Undo applied trim")
            }
            if let crop = state.crop, crop.isCropped(videoSize: state.naturalSize) {
                Label("\(Int(crop.outputSize.width))×\(Int(crop.outputSize.height))",
                      systemImage: "crop")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !state.isCropping {
                Button { state.beginCrop() } label: {
                    Image(systemName: "crop")
                }
                .buttonStyle(IconActionButtonStyle())
                .help("Crop to Region")

                exportMenu
            }

            Text(VideoTimecode.label(state.duration))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }

    /// Step-back · play/pause · step-forward, sharing the app's circular icon
    /// design language. The step buttons follow the keyboard: ±5s while playing,
    /// ±1 frame while paused (icons + tooltips reflect the active mode).
    private var transportCluster: some View {
        HStack(spacing: 8) {
            Button { state.stepBackward() } label: {
                Image(systemName: state.isPlaying ? "gobackward" : "backward.frame.fill")
            }
            .buttonStyle(IconActionButtonStyle())
            .help(state.isPlaying ? "Back 1 second (←)" : "Previous frame (←)")

            Button { state.togglePlayPause() } label: {
                Image(systemName: state.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 17, weight: .bold))
            }
            .buttonStyle(IconActionButtonStyle(diameter: 42))
            .help(state.isPlaying ? "Pause (space)" : "Play (space)")

            Button { state.stepForward() } label: {
                Image(systemName: state.isPlaying ? "goforward" : "forward.frame.fill")
            }
            .buttonStyle(IconActionButtonStyle())
            .help(state.isPlaying ? "Forward 1 second (→)" : "Next frame (→)")
        }
        .disabled(state.isCropping)
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
        .menuIndicator(.hidden)
        .frame(width: 28)
        .disabled(coordinator.isExportingRecording)
        .help("Export…")
    }

    /// Crop controls replace the timeline while a region is being chosen.
    private var cropRow: some View {
        HStack(spacing: 12) {
            ForEach(CropAspect.allCases, id: \.self) { aspect in
                Button(aspect.label) { state.setCropAspect(aspect) }
                    .buttonStyle(.plain)
                    .font(.caption.weight(state.crop?.aspect == aspect ? .bold : .regular))
                    .foregroundStyle(state.crop?.aspect == aspect ? Color.accentColor : .secondary)
            }
            Spacer()
            Button("Reset") { state.setCropRect(CGRect(origin: .zero, size: state.naturalSize)) }
                .buttonStyle(.plain)
                .font(.caption)
            Button("Cancel") { state.cancelCrop() }
                .keyboardShortcut(.cancelAction)
            Button("Done") { state.commitCrop() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
        }
        .frame(height: 44)
    }
}

/// AVKit player surface. `VideoPlayer` (SwiftUI) doesn't expose enough control
/// for our chromeless preview, so we wrap `AVPlayerView` directly with its own
/// controls hidden — the Liquid-Glass timeline IS the transport.
private struct VideoPlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .none
        view.videoGravity = .resizeAspect
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        if nsView.player !== player { nsView.player = player }
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
