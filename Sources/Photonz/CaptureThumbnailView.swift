import PhotonzCore
import SwiftUI

/// Shared capture thumbnail for the overlays (phase 11.4 / 11.7 / 12.4): the
/// screenshot or a recording's poster frame, with a play badge + duration pill
/// for videos, and drag-the-file-out. `fixedHeight` gives the history strip its
/// row height; nil fills the available space it is given.
///
/// What size to draw at is `ThumbnailFit`'s decision, not this view's: a capture
/// far wider (or taller) than the cap is cropped rather than running on, and a
/// capture smaller than the tile is drawn at its own size rather than blown up.
/// This view just draws what it is told and puts the badges on top.
struct CaptureThumbnailView: View {
    let entry: CaptureEntry
    let store: CaptureStore
    var fixedHeight: CGFloat? = nil
    /// Floor on the tile width so extreme aspect ratios (a 5px-wide image) still
    /// present a real hover/tap target instead of a sliver.
    var minWidth: CGFloat? = nil
    /// Draw the accent ring on the PICTURE (focused or just-captured tile). It
    /// belongs here rather than on the caller's frame because a small capture is
    /// drawn at its own size inside a wider hit target, and a ring around the
    /// empty hit target would be ringing nothing.
    var ringed: Bool = false
    /// Tapping the tile itself runs this (e.g. play a recording). Nil = no tap.
    var onActivate: (() -> Void)? = nil
    /// Double-clicking the tile runs this (e.g. open in the editor). Nil = no
    /// double-click action.
    var onDoubleClick: (() -> Void)? = nil

    var body: some View {
        Group {
            if let image = store.image(for: entry) {
                if let fixedHeight {
                    // The history strip: a fixed row height, and as much width
                    // as the picture's own shape asks for (up to the ratio cap).
                    CaptureThumbnailImage(entry: entry, store: store, image: image,
                                          available: CGSize(width: .infinity, height: fixedHeight),
                                          ringed: ringed)
                        .frame(height: fixedHeight)
                } else {
                    // The card: fill what we are given, but still never draw the
                    // capture bigger than it really is.
                    GeometryReader { geo in
                        CaptureThumbnailImage(entry: entry, store: store, image: image,
                                              available: geo.size, ringed: ringed)
                            .frame(width: geo.size.width, height: geo.size.height)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
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
        // Click / double-click the tile to activate — e.g. play a video, or
        // open a screenshot in the editor.
        .modifier(TapActions(onActivate: onActivate, onDoubleClick: onDoubleClick))
        .help(onActivate != nil ? "Play" : "")
        // Drag the capture's media (PNG or MP4) straight out to Finder / apps.
        .onDrag { NSItemProvider(contentsOf: store.fileURL(for: entry)) ?? NSItemProvider() }
    }
}

/// The picture inside a capture thumbnail, drawn at the size `ThumbnailFit` says
/// it may be drawn and centred in whatever space the tile occupies. The history
/// tiles and the capture toast both go through this, so the two rules — cropped
/// past the ratio cap, never bigger than life — hold wherever a capture is shown
/// small.
struct CaptureThumbnailImage: View {
    let entry: CaptureEntry
    let store: CaptureStore
    let image: CGImage
    /// The room the picture has, in points. `.infinity` on a side means "as much
    /// as the picture's own shape asks for" — the history strip's free width.
    let available: CGSize
    var cornerRadius: CGFloat = 8
    /// Accent ring on the PICTURE (the focused or just-captured history tile),
    /// rather than on the wider hit target around a small capture.
    var ringed: Bool = false

    var body: some View {
        let fit = ThumbnailFit.fit(pixelSize: CGSize(width: image.width, height: image.height),
                                   pixelScale: store.pixelScale(for: entry),
                                   available: available)
        // The store does the cropping: the rect is already whole pixels, and it
        // keeps the result, so a redraw hands back the same image object rather
        // than a new one to upload.
        let shown = store.thumbnail(for: entry, cropped: fit.cropPixels) ?? image
        Image(decorative: shown, scale: 1)
            .resizable()
            .frame(width: fit.drawnSize.width, height: fit.drawnSize.height)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius)
                .strokeBorder(.primary.opacity(0.15)))
            .overlay(croppedEdge(fit.croppedEdge))
            .overlay {
                if entry.kind == .video {
                    VideoBadgeOverlay(duration: store.duration(for: entry))
                }
            }
            .overlay {
                if ringed {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(Color.accentColor, lineWidth: 3)
                }
            }
    }

    /// A cropped tile says so quietly: the cut edge fades out, the way a list
    /// that scrolls past its own bottom does, so "there is more of this picture"
    /// reads without a badge or a word.
    @ViewBuilder
    private func croppedEdge(_ edge: ThumbnailFit.CroppedEdge?) -> some View {
        if let edge {
            let horizontal = edge == .trailing
            LinearGradient(colors: [.clear, .black.opacity(0.34)],
                           startPoint: horizontal ? .leading : .top,
                           endPoint: horizontal ? .trailing : .bottom)
                .frame(width: horizontal ? 20 : nil, height: horizontal ? nil : 20)
                .frame(maxWidth: .infinity, maxHeight: .infinity,
                       alignment: horizontal ? .trailing : .bottom)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                .allowsHitTesting(false)
        }
    }
}

/// Play badge + duration pill overlaid on a recording's poster frame. Shared by
/// the history tiles and the capture toasts so videos read the same everywhere.
struct VideoBadgeOverlay: View {
    let duration: TimeInterval?

    var body: some View {
        ZStack {
            Image(systemName: "play.circle.fill")
                .font(.system(size: 34))
                .foregroundStyle(.white, .black.opacity(0.45))
                .shadow(radius: 3)
            if let duration {
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

/// Attaches only the tap recognizers actually in use, so a single-tap action
/// never waits out a double-tap window it doesn't need (and vice versa). When
/// both are set, the double-click takes priority and the single tap fires only
/// after the double-click window lapses.
private struct TapActions: ViewModifier {
    let onActivate: (() -> Void)?
    let onDoubleClick: (() -> Void)?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let onDoubleClick, onActivate == nil {
            content.onTapGesture(count: 2) { onDoubleClick() }
        } else if let onActivate, onDoubleClick == nil {
            content.onTapGesture { onActivate() }
        } else if let onActivate, let onDoubleClick {
            content.gesture(
                TapGesture(count: 2).onEnded { onDoubleClick() }
                    .exclusively(before: TapGesture().onEnded { onActivate() }))
        } else {
            content
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
