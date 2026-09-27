import PhotonzCore
import SwiftUI

// MARK: - The one tile every Library shelf draws

/// A tile on the Library shelf, whatever it holds: a picture, a recording, a
/// sound, a component or a style. Each shelf hands it a picture, a name and a
/// quiet second line, and this decides what a tile looks like, so the Media,
/// Components and Styles shelves cannot drift apart.
///
/// In Next it is the video mock's card (`video.html`, the Library group,
/// `.libtile`): a bordered, rounded card with the picture edge to edge across
/// its top, the name left aligned under it in brighter type, and a mono line
/// under the name saying how long, how big or what kind. That card is
/// `VideoKit.Tile`, the same one the transition picker and the caption styles
/// draw, so a person learns one grammar for "pick one of these".
///
/// Current keeps the tile it shipped: a padded picture with a centred grey
/// name and no second line (`LibraryShelfLayout.Sizing.compact`).
///
/// The picture is handed in UNROUNDED and filling whatever it is given: the
/// card's own corners cut the top of it, and the compact tile rounds it
/// itself.
struct LibraryShelfTile<Picture: View>: View {
    /// How big the shelf is drawing its tiles right now (`LibraryTileMetrics`).
    @Environment(\.libraryTile) private var tileMetrics
    let name: String
    /// The quiet line under the name: a length, a size, or a kind. Only a
    /// card has room for it.
    var meta: String = ""
    var isSelected = false
    /// A component is picked in the component colour, as the mock's
    /// `.libtile.comp.sel` is.
    var isComponent = false
    @ViewBuilder let picture: Picture

    var body: some View {
        if tileMetrics.isCard { card } else { compact }
    }

    private var card: some View {
        // A blank line rather than no line, so every card on a row is the
        // height the shelf's arithmetic says it is.
        VideoKit.Tile(name: name, detail: meta.isEmpty ? " " : meta,
                      isSelected: isSelected,
                      emphasis: isComponent ? .component : .accent,
                      thumbnailHeight: tileMetrics.pictureHeight) {
            picture
        }
        // The tile folds its words together for accessibility; a tile is
        // still found by its name alone.
        .accessibilityLabel(name)
    }

    private var compact: some View {
        VStack(spacing: LibraryShelfLayout.captionSpacing) {
            picture
                .frame(maxWidth: .infinity)
                .frame(height: tileMetrics.pictureHeight)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.primary.opacity(0.12)))
            Text(name)
                .font(.system(size: LibraryShelfLayout.captionFontSize))
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(isSelected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
        }
        .frame(maxWidth: .infinity)
        .padding(LibraryShelfLayout.tilePadding)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(isSelected ? AnyShapeStyle(.tint.opacity(0.18)) : AnyShapeStyle(.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .strokeBorder(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear), lineWidth: 1.5)
        )
        .contentShape(Rectangle())
    }
}

/// One little word in the corner of a tile picture: a component's version,
/// or on Current's compact tile a length or where a component came from. A
/// LABEL, not a control: the tile is already a click, a double click and a
/// drag, and a fourth gesture on a nine point badge is a gesture nobody lands.
struct LibraryTileCornerWord: View {
    let text: String
    var monospaced = false

    var body: some View {
        Text(text)
            .font(.system(size: LibraryShelfLayout.tileBadgeFontSize, weight: .medium,
                          design: monospaced ? .monospaced : .default))
            .monospacedDigit()
            .lineLimit(1)
            .truncationMode(.tail)
            .foregroundStyle(.secondary)
            .padding(.horizontal, LibraryShelfLayout.tileBadgeHorizontalPadding)
            .padding(.vertical, LibraryShelfLayout.tileBadgeVerticalPadding)
            .background(Capsule().fill(.regularMaterial))
            .padding(LibraryShelfLayout.tileBadgeInset)
    }
}
