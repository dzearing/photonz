// The Style row of an arrow: five picture tiles, each the real renderer's drawing of that style.

import AppKit
import PhotonzCore
import PhotonzRender
import SwiftUI

/// How an arrow is drawn, picked by looking rather than reading: each tile is
/// an arrow drawn by the very rasterizer the canvas uses, in that style
/// (`ArrowStyle.swift`, `HandMadeArrow.swift`).
///
/// One control, used in two places: the picked arrow's section in the dock
/// (what THIS arrow is drawn in) and the arrow tool's popover (what the NEXT
/// one is). The tiles are the design system's picker tile
/// (`VideoKit.Tile`), the one card every "pick one of these" uses, so it reads
/// the same as the caption styles and the transitions.
struct ArrowStyleTiles: View, Equatable {
    /// The style that is on, or nil over a mixture of picked arrows.
    let selection: ArrowStyle?
    /// The label's size: the dock's caption, or the popover's callout, so the
    /// row reads like its neighbours wherever it is.
    var labelFont: Font = .caption
    let pick: (ArrowStyle) -> Void

    /// Which tile is lit, and nothing else; what a press does is looked up
    /// when it happens.
    nonisolated static func == (a: ArrowStyleTiles, b: ArrowStyleTiles) -> Bool {
        a.selection == b.selection && a.labelFont == b.labelFont
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text("Style").font(labelFont).foregroundStyle(.secondary)
                if let selection {
                    Text(selection.title).font(labelFont).foregroundStyle(.secondary)
                } else {
                    MixedWord()
                }
                Spacer(minLength: 0)
            }
            VideoKit.TileGrid(minimumWidth: 60, columns: 3, spacing: 6) {
                ForEach(ArrowStyle.allCases, id: \.self) { style in
                    tile(style)
                }
            }
        }
        .playtestField("Arrow Style")
    }

    private func tile(_ style: ArrowStyle) -> some View {
        let isOn = selection == style
        return Button { pick(style) } label: {
            VideoKit.Tile(name: style.title, isSelected: isOn, thumbnailHeight: 30) {
                ArrowStyleThumbnail(style: style)
            }
        }
        .buttonStyle(.plain)
        .playtestControl("Arrow style \(style.title)", detail: isOn ? "on" : "off")
        .accessibilityLabel(style.title)
        .panelHelp(Self.help(style))
    }

    static func help(_ style: ArrowStyle) -> String {
        switch style {
        case .clean: "A straight line with a geometric head"
        case .handDrawn: "A thin pen line with an open head"
        case .marker: "A bold marker stroke with a loose head"
        case .brush: "A brush stroke that tapers and swells"
        case .sketch: "A rough outline arrow in dry ink"
        }
    }
}

/// One style, drawn by the rasterizer at the screen's scale and tinted with the
/// tile's own ink, so it reads on the tile in light and dark alike.
private struct ArrowStyleThumbnail: View {
    let style: ArrowStyle
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        GeometryReader { proxy in
            if let image = ArrowStyleThumbnail.image(style, size: proxy.size, scale: displayScale) {
                Image(decorative: image, scale: displayScale)
                    .renderingMode(.template)
                    .foregroundStyle(VideoKit.Palette.ink)
                    .frame(width: proxy.size.width, height: proxy.size.height)
            }
        }
        .accessibilityHidden(true)
    }

    private struct Key: Hashable {
        let style: ArrowStyle
        let width: Int
        let height: Int
        let scale: CGFloat
    }

    @MainActor private static var drawn: [Key: CGImage] = [:]

    /// The hand every tile is drawn with, picked because it reads clearly at
    /// tile size in all four hand-made styles.
    static let thumbnailSeed: UInt32 = 0x00A7_4E11

    /// A short rising arrow across the tile, one fixed hand per style so the
    /// tiles never change between panels.
    @MainActor
    static func image(_ style: ArrowStyle, size: CGSize, scale: CGFloat) -> CGImage? {
        guard size.width > 8, size.height > 8 else { return nil }
        let key = Key(style: style, width: Int(size.width.rounded()), height: Int(size.height.rounded()),
                      scale: scale)
        if let ready = drawn[key] { return ready }
        // A sketch is an outline of a wide arrow, so at tile size it is drawn
        // with a finer line or its two passes fill the whole band.
        var content = AnnotationContent(shape: .arrow, strokeWidth: style == .sketch ? 1.1 : 2,
                                        colorHex: "#000000", arrowheadScale: 0.32)
        content.arrowStyle = style
        content.styleSeed = thumbnailSeed
        content.start = CGPoint(x: 9, y: size.height * 0.66)
        content.end = CGPoint(x: size.width - 9, y: size.height * 0.34)
        guard let image = AnnotationRasterizer.rasterize(content, size: size, scale: scale) else {
            return nil
        }
        drawn[key] = image
        return image
    }
}
