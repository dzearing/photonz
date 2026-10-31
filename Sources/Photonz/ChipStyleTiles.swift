// The Chip and Marker rows of an arrow: ten picture tiles, each a real chip drawn by the renderer, and the six markers.

import AppKit
import PhotonzCore
import PhotonzRender
import SwiftUI

/// Which chip an arrow's label sits on, picked by looking: each tile is a chip
/// drawn by the very rasterizer the canvas uses, in that style and in the
/// arrow's own colour (`ChipStyle.swift`, `ChipRasterizer.swift`).
///
/// Used in the same two places as the arrow style tiles: the picked arrow's
/// Appearance (what THIS label is) and the arrow tool's popover (what the NEXT
/// one is). Rows of five, as the design system's specimen lays them out
/// (`docs/design/markup.md` section 8).
struct ChipStyleTiles: View, Equatable {
    /// The style that is on, or nil over a mixture.
    let selection: ChipStyle?
    /// The arrow's colour, so the tiles show the chips this arrow would wear.
    let ink: String
    var labelFont: Font = .caption
    let pick: (ChipStyle) -> Void

    nonisolated static func == (a: ChipStyleTiles, b: ChipStyleTiles) -> Bool {
        a.selection == b.selection && a.ink == b.ink && a.labelFont == b.labelFont
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text("Chip").font(labelFont).foregroundStyle(.secondary)
                if let selection {
                    Text(selection.title).font(labelFont).foregroundStyle(.secondary)
                } else {
                    MixedWord()
                }
                Spacer(minLength: 0)
            }
            VideoKit.TileGrid(minimumWidth: 40, columns: 5, spacing: 4) {
                ForEach(ChipStyle.allCases, id: \.self) { style in
                    tile(style)
                }
            }
        }
        .playtestField("Chip Style")
    }

    private func tile(_ style: ChipStyle) -> some View {
        let isOn = selection == style
        return Button { pick(style) } label: {
            ChipStyleThumbnail(style: style, ink: ink)
                .frame(height: 30)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(nsColor: .quaternaryLabelColor).opacity(0.35)))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(isOn ? Color.accentColor : Color.clear, lineWidth: 2))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .playtestControl("Chip style \(style.title)", detail: isOn ? "on" : "off")
        .accessibilityLabel(style.title)
        .panelHelp("\(style.title): \(style.help)")
    }
}

/// One chip style, drawn by the renderer at the screen's scale reading "48".
private struct ChipStyleThumbnail: View {
    let style: ChipStyle
    let ink: String
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        GeometryReader { proxy in
            if let image = Self.image(style, ink: ink, size: proxy.size, scale: displayScale) {
                Image(decorative: image, scale: displayScale)
                    .frame(width: proxy.size.width, height: proxy.size.height)
            }
        }
        .accessibilityHidden(true)
    }

    private struct Key: Hashable {
        let style: ChipStyle
        let ink: String
        let width: Int
        let height: Int
        let scale: CGFloat
    }

    @MainActor private static var drawn: [Key: CGImage] = [:]

    @MainActor
    static func image(_ style: ChipStyle, ink: String, size: CGSize, scale: CGFloat) -> CGImage? {
        guard size.width > 8, size.height > 8 else { return nil }
        let key = Key(style: style, ink: ink, width: Int(size.width.rounded()),
                      height: Int(size.height.rounded()), scale: scale)
        if let ready = drawn[key] { return ready }
        let image = AnnotationRasterizer.chipSample("48", style: style, ink: ink, fontSize: 10,
                                                    size: size, scale: scale)
        if drawn.count > 400 { drawn.removeAll() }
        drawn[key] = image
        return image
    }
}

/// What sits at the front of the label chip: None, the style's own Accent, or
/// one of four status icons.
struct ChipMarkerPicker: View, Equatable {
    let selection: ChipMarker?
    var labelFont: Font = .caption
    let pick: (ChipMarker) -> Void

    nonisolated static func == (a: ChipMarkerPicker, b: ChipMarkerPicker) -> Bool {
        a.selection == b.selection && a.labelFont == b.labelFont
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text("Marker").font(labelFont).foregroundStyle(.secondary)
                if let selection {
                    Text(selection.title).font(labelFont).foregroundStyle(.secondary)
                } else {
                    MixedWord()
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 2) {
                ForEach(ChipMarker.allCases, id: \.self) { marker in
                    button(marker)
                }
            }
            .padding(2)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color(nsColor: .quaternaryLabelColor).opacity(0.35)))
        }
        .playtestField("Marker")
    }

    private func button(_ marker: ChipMarker) -> some View {
        let isOn = selection == marker
        return Button { pick(marker) } label: {
            Group {
                switch marker {
                case .none, .accent:
                    Text(marker.title).font(.caption)
                case .error: icon("xmark.circle.fill", .white, .red)
                case .warning: icon("exclamationmark.triangle.fill", Color(white: 0.11), .yellow)
                case .success: icon("checkmark.circle.fill", .white, .green)
                case .info: icon("info.circle.fill", .white, .blue)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 20)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(isOn ? Color(nsColor: .controlBackgroundColor) : Color.clear)
                .shadow(color: .black.opacity(isOn ? 0.15 : 0), radius: 1, y: 0.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .playtestControl("Marker \(marker.title)", detail: isOn ? "on" : "off")
        .accessibilityLabel(marker.title)
        .panelHelp(marker == .accent ? "The style's own stripe or dot" : marker.title)
    }

    private func icon(_ name: String, _ glyph: Color, _ color: Color) -> some View {
        Image(systemName: name)
            .symbolRenderingMode(.palette)
            .foregroundStyle(glyph, color)
            .font(.system(size: 13))
    }
}
