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
                        TrimTimeline(state: state)
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
    }

    @ViewBuilder
    private var player: some View {
        if let player = state.player {
            VideoPlayerView(player: player)
                .background(Color.black)
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
            Button {
                state.togglePlayPause()
            } label: {
                Image(systemName: state.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .help(state.isPlaying ? "Pause" : "Play")

            Text(VideoTimecode.label(state.currentTime))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)

            Spacer()

            if state.trim.isTrimmed {
                Label(VideoTimecode.label(state.trim.effectiveDuration),
                      systemImage: "scissors")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(VideoTimecode.label(state.duration))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
        }
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
