import PhotonzCore
import SwiftUI

/// Shared capture thumbnail for the overlays (phase 11.4 / 11.7 / 12.4): the
/// screenshot or a recording's poster frame, with a play badge + duration pill
/// for videos, and drag-the-file-out. `fixedHeight` gives the history strip its
/// row height; nil fills the available space (the Quick Access card).
struct CaptureThumbnailView: View {
    let entry: CaptureEntry
    let store: CaptureStore
    var fixedHeight: CGFloat? = nil
    /// Floor on the tile width so extreme aspect ratios (a 5px-wide image) still
    /// present a real hover/tap target instead of a sliver.
    var minWidth: CGFloat? = nil
    /// Tapping the tile itself runs this (e.g. play a recording). Nil = no tap.
    var onActivate: (() -> Void)? = nil

    var body: some View {
        Group {
            if let image = store.image(for: entry) {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .modifier(SizeModifier(fixedHeight: fixedHeight))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.primary.opacity(0.15)))
                    .overlay(videoBadge)
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.quaternary)
                    .modifier(SizeModifier(fixedHeight: fixedHeight, fallbackWidth: 140))
            }
        }
        // Pad the tile out to the floor width (image stays centered) so the whole
        // rectangle — not just the sliver — is the hover/tap/drag target.
        .frame(minWidth: minWidth)
        .contentShape(Rectangle())
        // Click the tile (incl. the play badge) to activate — e.g. play a video.
        .onTapGesture { onActivate?() }
        .help(onActivate != nil ? "Play" : "")
        // Drag the capture's media (PNG or MP4) straight out to Finder / apps.
        .onDrag { NSItemProvider(contentsOf: store.fileURL(for: entry)) ?? NSItemProvider() }
    }

    @ViewBuilder
    private var videoBadge: some View {
        if entry.kind == .video {
            ZStack {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(.white, .black.opacity(0.45))
                    .shadow(radius: 3)
                if let duration = store.duration(for: entry) {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Text(RecordingClock.elapsedString(duration))
                                .font(.caption2.weight(.semibold).monospacedDigit())
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(.black.opacity(0.55), in: Capsule())
                                .foregroundStyle(.white)
                                .padding(5)
                        }
                    }
                }
            }
        }
    }
}

/// Either a fixed thumbnail height (history strip) or fill-available (card).
private struct SizeModifier: ViewModifier {
    let fixedHeight: CGFloat?
    var fallbackWidth: CGFloat? = nil

    func body(content: Content) -> some View {
        if let fixedHeight {
            content.frame(width: fallbackWidth, height: fixedHeight)
        } else {
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
