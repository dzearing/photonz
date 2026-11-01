// The Style row of an arrow: ten picture tiles in rows of five, each the real renderer's drawing of that style.

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
    /// The arrow's colour, so the tiles show the arrows this one would be, as
    /// the chip tiles beside them do; nil draws them in the panel's ink.
    var ink: String? = nil
    let pick: (ArrowStyle) -> Void

    /// Which tile is lit, and nothing else; what a press does is looked up
    /// when it happens.
    nonisolated static func == (a: ArrowStyleTiles, b: ArrowStyleTiles) -> Bool {
        a.selection == b.selection && a.labelFont == b.labelFont && a.ink == b.ink
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text("Arrow").font(labelFont).foregroundStyle(.secondary)
                if let selection {
                    Text(selection.title).font(labelFont).foregroundStyle(.secondary)
                } else {
                    MixedWord()
                }
                Spacer(minLength: 0)
            }
            VideoKit.TileGrid(minimumWidth: 40, columns: 5, spacing: 4) {
                ForEach(ArrowStyle.allCases, id: \.self) { style in
                    tile(style)
                }
            }
        }
        .playtestField("Arrow Style")
    }

    private func tile(_ style: ArrowStyle) -> some View {
        let isOn = selection == style
        // A picture and nothing else, the same tile as the Chip row under it:
        // ten names do not fit five across, the header names the one that is
        // on, and the tip names each.
        return Button { pick(style) } label: {
            ArrowStyleThumbnail(style: style, ink: ink)
                .frame(height: 30)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(nsColor: .quaternaryLabelColor).opacity(0.35)))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(isOn ? Color.accentColor : Color.clear, lineWidth: 2))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .playtestControl("Arrow style \(style.title)", detail: isOn ? "on" : "off")
        .accessibilityLabel(style.title)
        .panelHelp("\(style.title): \(Self.help(style))")
    }

    static func help(_ style: ArrowStyle) -> String {
        switch style {
        case .clean: "A straight line with a geometric head"
        case .handDrawn: "A thin pen line with an open head"
        case .marker: "A bold marker stroke with a loose head"
        case .brush: "A brush stroke that tapers and swells"
        case .sketch: "A rough outline arrow in dry ink"
        case .dashed: "A dashed line with a solid head"
        case .block: "A bold arrow that widens into its head"
        case .neon: "A glowing line with an open head"
        case .dotted: "A line of dots with a chevron head"
        case .elbow: "A right-angle connector for diagrams"
        }
    }
}

/// One style, drawn by the rasterizer at the screen's scale and tinted with the
/// tile's own ink, so it reads on the tile in light and dark alike.
private struct ArrowStyleThumbnail: View {
    let style: ArrowStyle
    let ink: String?
    @Environment(\.displayScale) private var displayScale
    @Environment(\.colorScheme) private var colorScheme

    /// The arrow's colour, unless it would all but vanish on the tile (a
    /// black arrow on the dark panel, a white one on the light), where the
    /// panel's own ink draws it instead.
    private var tint: AnyShapeStyle {
        guard let ink, let rgba = RGBA(hex: ink) else { return AnyShapeStyle(VideoKit.Palette.ink) }
        let lum = rgba.relativeLuminance
        if colorScheme == .dark, lum < 0.06 { return AnyShapeStyle(VideoKit.Palette.ink) }
        if colorScheme == .light, lum > 0.8 { return AnyShapeStyle(VideoKit.Palette.ink) }
        return AnyShapeStyle(Color(hex: ink))
    }

    var body: some View {
        GeometryReader { proxy in
            if let image = ArrowStyleThumbnail.image(style, size: proxy.size, scale: displayScale) {
                Image(decorative: image, scale: displayScale)
                    .renderingMode(.template)
                    .foregroundStyle(tint)
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
        // An elbow needs a rise tall enough to hold its head, or it turns up
        // first; with one it reads as the mock draws it, across then up.
        let rise: CGFloat = style == .elbow ? 0.3 : 0.16
        content.start = CGPoint(x: 9, y: size.height * (0.5 + rise))
        content.end = CGPoint(x: size.width - 9, y: size.height * (0.5 - rise))
        guard let image = AnnotationRasterizer.rasterize(content, size: size, scale: scale) else {
            return nil
        }
        drawn[key] = image
        return image
    }
}
