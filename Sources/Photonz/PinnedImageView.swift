import PhotonzCore
import SwiftUI

/// Contents of a pin-to-screen floating window (phase 11.8): the pinned image
/// fills the window; an opacity slider and a close button fade in on hover so the
/// chrome stays out of the way. Window placement / drag / always-on-top live in
/// `PinnedWindowController`; opacity is applied to the image only (not the whole
/// window) so the controls stay fully legible while you dial it down.
struct PinnedImageView: View {
    let image: CGImage
    let onClose: () -> Void

    @State private var opacity: CGFloat = 1.0
    @State private var hovering = false

    var body: some View {
        Image(decorative: image, scale: 1)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fill)
            .opacity(opacity)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(alignment: .topTrailing) { if hovering { closeButton } }
            .overlay(alignment: .bottom) { if hovering { opacityControl } }
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.18)))
            .contentShape(RoundedRectangle(cornerRadius: 10))
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.15), value: hovering)
    }

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
        }
        .buttonStyle(IconActionButtonStyle(diameter: 24))
        .padding(6)
    }

    private var opacityControl: some View {
        HStack(spacing: 8) {
            Image(systemName: "circle.lefthalf.filled").font(.system(size: 11))
            Slider(
                value: Binding(
                    get: { opacity },
                    set: { opacity = PinnedImageMetrics.clampOpacity($0) }),
                in: PinnedImageMetrics.minOpacity...PinnedImageMetrics.maxOpacity)
            .controlSize(.small)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: 200)
        .glassEffect(.regular, in: .capsule)
        .padding(8)
    }
}
