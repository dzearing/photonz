import PhotonzCore
import SwiftUI

/// The icon previews strip (Next, `next-icon-previews`).
///
/// A glass row in the canvas's top left corner, one chip per size, holding the
/// icon frame you are working in drawn at 16, 24, 32, 48 and 64 pixels with the
/// number under each. It appears when an icon frame is what you are in and goes
/// the moment you pick anything else.
///
/// Two things about it are deliberate and are the whole reason it works:
///
///  - **Each picture is drawn AT that many pixels**, by the same path Export
///    takes (`DocumentRenderer.iconPreview`). A big picture shrunk smoothly
///    looks plausible and averages a hairline into a believable grey, which
///    would hide the exact thing the strip is for.
///  - **Nothing is smoothed on the way to the screen** (`.interpolation(.none)`),
///    so on a retina display you are looking at the icon's own pixels made
///    square rather than at a softened guess at them.
///
/// Chrome, like the measure legend and the canvas hints: it takes no clicks, so
/// it can never eat a drag, and it is never in an export.
struct IconPreviewsStrip: View {
    let tiles: [IconPreviewTile]

    /// Between two chips.
    static let gap: CGFloat = 10
    /// Inside the glass, on every side.
    static let padding: CGFloat = 10
    /// The number under a chip, and the air above it.
    static let labelHeight: CGFloat = 16
    /// The corner every chip is cut with.
    private static let chipRadius: CGFloat = 7

    var body: some View {
        HStack(alignment: .bottom, spacing: Self.gap) {
            ForEach(tiles) { tile in
                VStack(spacing: 4) {
                    chip(tile)
                    Text("\(Int(tile.side))")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
                // A walk can name one preview and read its size off the label.
                .playtestControl("Icon preview \(Int(tile.side))",
                                 detail: tile.image == nil ? "Drawing" : "Drawn")
            }
        }
        .padding(Self.padding)
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
        .padding(EditorChromeLayout.cornerInset)
        .allowsHitTesting(false)
        .transition(.opacity)
    }

    /// One preview on its chip. The chip is what makes a picture visible at
    /// all: a frame that paints no surface of its own comes back transparent,
    /// and transparent on glass is nothing.
    private func chip(_ tile: IconPreviewTile) -> some View {
        RoundedRectangle(cornerRadius: Self.chipRadius)
            .fill(.quaternary)
            .overlay {
                if let image = tile.image {
                    // Exactly `side` points across, which is the size the icon
                    // will really be: not resizable, not scaled to fit, and
                    // never smoothed.
                    Image(decorative: image, scale: 1)
                        .interpolation(.none)
                        .frame(width: tile.side, height: tile.side)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: Self.chipRadius)
                    .strokeBorder(.separator, lineWidth: 1)
            }
            .frame(width: IconPreviews.chipSide(for: tile.side),
                   height: IconPreviews.chipSide(for: tile.side))
    }
}
