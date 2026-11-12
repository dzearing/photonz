import PhotonzCore
import SwiftUI

/// **Caption track**: the bar over the Captions track, as the captions mock
/// draws its dock's bar (`.tlbar` in `pages/video-captions.html`): what the
/// track is and how it was written.
///
/// The mock also draws Clear and Reset on this bar, and the word being said
/// and the playhead over the length beside them. Those are one-shot verbs and
/// readouts of the moment, not what the track is, so they are on the Captions
/// track's right-click and in the menu bar (Clear Captions, Reset Captions),
/// and the word and the time are where the playhead already says them (the
/// card "How many buttons may the right hand panel keep?", answered
/// 2026-10-20: one main action per section, the rest on right-click and the
/// menu bar).
struct CaptionTrackBarView: View {
    static let height: CGFloat = 30

    var body: some View {
        ViewThatFits(in: .horizontal) {
            bar(mode: true)
            bar(mode: false)
        }
        .frame(height: Self.height)
        .overlay(alignment: .bottom) { Rectangle().fill(VideoKit.Palette.edgeLo).frame(height: 1) }
        .playtestField(CaptionTrackBar.title)
    }

    private func bar(mode: Bool) -> some View {
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
            Spacer(minLength: 8)
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
        @Environment(\.shownPointer) private var shown

        var body: some View {
            // A button that cannot be pressed sits still under the pointer.
            let look = ButtonPointerLook(enabled: isEnabled, hovering: hovering,
                                         pressed: configuration.isPressed || shown == .pressed)
            let lit = filled || look.isLit
            configuration.label
                .labelStyle(Tight())
                .measuredInk()
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(lit ? VideoKit.Palette.ink : VideoKit.Palette.dim)
                .padding(.horizontal, 8)
                .frame(height: 22)
                .background(RoundedRectangle(cornerRadius: 7)
                    .fill(lit ? AnyShapeStyle(VideoKit.Palette.glassThin) : AnyShapeStyle(Color.clear)))
                .overlay(RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(lit ? AnyShapeStyle(VideoKit.Palette.edgeLo) : AnyShapeStyle(Color.clear)))
                .scaleEffect(look.isPressed ? 0.97 : 1)
                .contentShape(RoundedRectangle(cornerRadius: 7))
                .opacity(isEnabled ? 1 : 0.55)
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
