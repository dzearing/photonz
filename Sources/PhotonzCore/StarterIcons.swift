import CoreGraphics
import Foundation

/// The icons a starter Button can lead with, as the variants mock offers them
/// (`docs/design/mocks/pages/ui-variants.html`, the Icon menu): Sparkle, Wand,
/// Swatch, Layers and Brush, in that order.
///
/// Each is drawn from the design system's own outline
/// (`docs/design/mocks/shared/icons.mjs`), numbers copied verbatim, on the same
/// 24 point grid with the same 1.75 line, then scaled to the size the button
/// wears it at. A glyph is a group of ordinary path layers, so once it is in a
/// document it is a drawing like any other: recolour it, reshape it, swap it.
public enum StarterIcon: String, CaseIterable, Hashable, Sendable {
    case sparkle
    case wand
    case swatch
    case layers
    case brush

    /// The name the Icon menu and the layers list print.
    public var name: String {
        switch self {
        case .sparkle: return "Sparkle"
        case .wand: return "Wand"
        case .swatch: return "Swatch"
        case .layers: return "Layers"
        case .brush: return "Brush"
        }
    }

    /// The grid every icon is drawn on, and the line it is drawn with.
    public static let grid: CGFloat = 24
    public static let line: CGFloat = 1.75

    /// One mark of the glyph: an outline, and whether it is filled solid or
    /// drawn as a line.
    struct Mark {
        var runs: [IconPathData.Run]
        var solid: Bool

        static func line(_ data: String) -> Mark { Mark(runs: IconPathData.runs(data), solid: false) }
        static func solid(_ data: String) -> Mark { Mark(runs: IconPathData.runs(data), solid: true) }
        static func dot(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) -> Mark {
            Mark(runs: [IconPathData.circle(center: CGPoint(x: x, y: y), radius: r)], solid: true)
        }
    }

    /// The glyph as the design system writes it.
    var marks: [Mark] {
        switch self {
        case .sparkle:
            return [.solid("M12 2.8l2.05 5.9 5.9 2.05-5.9 2.05L12 18.7l-2.05-5.9L4.05 10.75l5.9-2.05z"),
                    .solid("M18.8 15.2l.85 2.35 2.35.85-2.35.85-.85 2.35-.85-2.35-2.35-.85 2.35-.85z")]
        case .wand:
            return [.line("M3.8 20.2L13 11"),
                    .solid("M16.8 2.9l1.32 3.09 3.09 1.32-3.09 1.32-1.32 3.09-1.32-3.09L12.39 7.31l3.09-1.32z"),
                    .solid("M7.4 3.2l.68 1.6 1.6.68-1.6.68L7.4 7.76l-.68-1.6-1.6-.68 1.6-.68z"),
                    .solid("M20.2 14.4l.62 1.46 1.46.62-1.46.62-.62 1.46-.62-1.46-1.46-.62 1.46-.62z")]
        case .swatch:
            return [.line("M12 3.4a8.6 8.6 0 0 0 0 17.2c1.25 0 1.9-.85 1.9-1.8 0-.5-.2-.95-.55-1.3"
                          + "a1.75 1.75 0 0 1 1.25-3h2.1a4.05 4.05 0 0 0 4-4.05c0-4.05-3.9-7.05-8.7-7.05z"),
                    .dot(8.4, 8.6, 1.15), .dot(12.4, 7.2, 1.15), .dot(7.2, 13, 1.15)]
        case .layers:
            return [.line("M12 3.2L3.1 7.6 12 12l8.9-4.4z"),
                    .line("M3.1 16.4L12 20.8l8.9-4.4M3.1 12L12 16.4 20.9 12")]
        case .brush:
            return [.line("M9.6 12.2l8.2-8.2a2.1 2.1 0 0 1 3 3l-8.2 8.2"),
                    .line("M7.2 14.2a3.1 3.1 0 0 0-3.1 3.1c0 1.4-2 1.6-2 2.1 1 1 2.6 2.1 4.1 2.1"
                          + "a4.1 4.1 0 0 0 4.1-4.1 3.1 3.1 0 0 0-3.1-3.2z")]
        }
    }

    /// The glyph as a group `size` points square, every mark a path layer
    /// painted `colorHex` and pointed at `styleID` when there is one, so
    /// re-colouring the style re-colours the icon with the words beside it.
    ///
    /// The group is a box of the icon's size whatever the glyph covers, the
    /// way an icon in a row of text always is: a wand and a sparkle sit in the
    /// same place beside a label.
    public func layer(size: CGFloat, colorHex: String, styleID: UUID? = nil) -> Layer {
        let scale = size / Self.grid
        var children: [Layer] = []
        for mark in marks {
            for run in mark.runs {
                let anchors = run.anchors.map { anchor in
                    PathAnchor(point: CGPoint(x: anchor.point.x * scale, y: anchor.point.y * scale),
                               handleIn: anchor.handleIn.map { CGPoint(x: $0.x * scale, y: $0.y * scale) },
                               handleOut: anchor.handleOut.map { CGPoint(x: $0.x * scale, y: $0.y * scale) },
                               kind: anchor.kind)
                }
                let paint = Paint(hex: colorHex)
                let content = PathContent(anchors: anchors, isClosed: run.isClosed,
                                          paint: paint,
                                          strokeWidth: mark.solid ? 0 : Self.line * scale,
                                          fill: mark.solid ? paint : nil,
                                          lineEnd: .round, lineCorner: .round)
                var piece = PathBuilder.layer(content, at: content.bounds.origin,
                                              name: mark.solid ? "Fill" : "Line")
                if let styleID {
                    piece.colorStyleBindings = mark.solid
                        ? [ColorStyleBinding(slot: .fill, styleID: styleID)]
                        : [ColorStyleBinding(slot: .stroke, styleID: styleID)]
                }
                children.append(piece)
            }
        }
        var group = GroupContent(children: children)
        group.layout = .free(width: size, height: size)
        return Layer(name: name, content: .group(group),
                     frame: CGRect(x: 0, y: 0, width: size, height: size))
    }
}
