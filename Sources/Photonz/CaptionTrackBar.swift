import PhotonzCore
import SwiftUI

/// **Caption track**: the bar over the Captions track, as the captions mock
/// draws its dock's bar (`.tlbar` in `pages/video-captions.html`): what the
/// track is and how it was written, Clear and Reset, then the word being said
/// and the playhead over the length.
///
/// The readouts are a view of their own because they follow the playhead: the
/// rest of the bar, and the track row it sits in, are not drawn again on every
/// frame of playback.
struct CaptionTrackBarView: View {
    @Environment(EditorState.self) private var editorState

    static let height: CGFloat = 30

    var body: some View {
        ViewThatFits(in: .horizontal) {
            bar(mode: true, readouts: true)
            bar(mode: true, readouts: false)
            bar(mode: false, readouts: false)
        }
        .frame(height: Self.height)
        .overlay(alignment: .bottom) { Rectangle().fill(VideoKit.Palette.edgeLo).frame(height: 1) }
        .playtestField(CaptionTrackBar.title)
    }

    private func bar(mode: Bool, readouts: Bool) -> some View {
        HStack(spacing: 8) {
            Text(CaptionTrackBar.title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .kerning(0.9)
                .foregroundStyle(VideoKit.Palette.faint)
                .fixedSize()
            if mode {
                HStack(spacing: 5) {
                    Image(systemName: "sparkles").font(.system(size: 9, weight: .semibold))
                    Text(CaptionTrackBar.mode).font(.system(size: 10, weight: .semibold))
                }
                .foregroundStyle(VideoKit.Palette.comp)
                .fixedSize()
            }
            Rectangle().fill(VideoKit.Palette.line).frame(width: 1, height: 14)
            Button { editorState.clearCaptions() } label: {
                Label("Clear", systemImage: "xmark")
            }
            .buttonStyle(CaptionBarButtonStyle())
            .disabled(!editorState.canClearCaptions)
            .panelHelp("Clear the caption track")
            .playtestControl("Caption Track Clear")
            Button { editorState.resetCaptions() } label: {
                Label("Reset", systemImage: "arrow.uturn.backward")
            }
            .buttonStyle(CaptionBarButtonStyle())
            .disabled(!editorState.canResetCaptions)
            .panelHelp("Reset the captions' look and place")
            .playtestControl("Caption Track Reset")
            Spacer(minLength: 8)
            if readouts { CaptionTrackReadouts() }
        }
    }
}

/// `Active word <w>` and `1.30s / 6.00s`, the mock's two pills.
private struct CaptionTrackReadouts: View {
    @Environment(EditorState.self) private var editorState

    var body: some View {
        let word = editorState.captionWordBeingSaid
        HStack(spacing: 6) {
            HStack(spacing: 6) {
                Text(CaptionTrackBar.activeWord).foregroundStyle(VideoKit.Palette.ink)
                Text(word ?? "·").bold().foregroundStyle(VideoKit.Palette.accent)
                    .lineLimit(1).truncationMode(.tail)
                    .frame(maxWidth: 110, alignment: .leading)
                    .fixedSize()
            }
            .modifier(Pill())
            .accessibilityElement(children: .combine)
            .accessibilityLabel(CaptionTrackBar.activeWord)
            .accessibilityValue(word ?? "")
            Text(CaptionTrackBar.time(atMS: editorState.documentTimeMS, ofMS: editorState.documentLengthMS))
                .foregroundStyle(VideoKit.Palette.ink)
                .modifier(Pill())
        }
        .fixedSize()
    }

    private struct Pill: ViewModifier {
        func body(content: Content) -> some View {
            content
                .font(.system(size: 10.5, design: .monospaced))
                .monospacedDigit()
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 7).fill(VideoKit.Palette.panel2))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(VideoKit.Palette.edgeLo))
        }
    }
}

/// The mock's small buttons: `.btn.ghost.sm`, quiet until pointed at, and
/// `.btn.secondary.sm` (`filled`), a glass face at rest, which is how the
/// Safe areas button says it is on.
struct CaptionBarButtonStyle: ButtonStyle {
    var filled = false

    func makeBody(configuration: Configuration) -> some View {
        Face(configuration: configuration, filled: filled)
    }

    private struct Face: View {
        let configuration: Configuration
        let filled: Bool
        @State private var hovering = false
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            let lit = filled || hovering || configuration.isPressed
            configuration.label
                .labelStyle(Tight())
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(lit ? VideoKit.Palette.ink : VideoKit.Palette.dim)
                .padding(.horizontal, 8)
                .frame(height: 22)
                .background(RoundedRectangle(cornerRadius: 7)
                    .fill(lit ? AnyShapeStyle(VideoKit.Palette.glassThin) : AnyShapeStyle(Color.clear)))
                .overlay(RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(lit ? AnyShapeStyle(VideoKit.Palette.edgeLo) : AnyShapeStyle(Color.clear)))
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .contentShape(RoundedRectangle(cornerRadius: 7))
                .opacity(isEnabled ? 1 : 0.4)
                .fixedSize()
                .playtestHover { hovering = $0 }
                .animation(.easeOut(duration: 0.12), value: hovering)
        }
    }

    private struct Tight: LabelStyle {
        func makeBody(configuration: Configuration) -> some View {
            HStack(spacing: 5) {
                configuration.icon.font(.system(size: 9.5, weight: .semibold))
                configuration.title
            }
        }
    }
}
