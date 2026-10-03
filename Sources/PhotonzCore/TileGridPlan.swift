import CoreGraphics

/// How a grid of equal tiles (the video picker grids, `.libgrid`) splits its
/// width: as many columns as fit at `minimumWidth` or wider, or a pinned
/// count, every tile the same width.
///
/// An offer with no usable width (none at all, or an unbounded one SwiftUI
/// makes while measuring) is answered with the narrowest two-tile grid,
/// never by laying out across infinity: that width becomes a column count,
/// and turning an infinite count into an `Int` traps (the probe died of
/// exactly that on 2026-10-01).
public struct TileGridPlan: Equatable, Sendable {
    /// The most columns a grid is ever split into, whatever it is offered.
    public static let maximumColumns = 1000

    /// The width the grid lays out across.
    public let width: CGFloat
    public let columns: Int
    public let tileWidth: CGFloat

    public init(offeredWidth: CGFloat?, minimumWidth: CGFloat, spacing: CGFloat, columns pinned: Int?) {
        let width = offeredWidth.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
            ?? minimumWidth * 2 + spacing
        let columns: Int
        if let pinned {
            columns = min(max(pinned, 1), Self.maximumColumns)
        } else {
            let ratio = ((width + spacing) / (minimumWidth + spacing)).rounded(.down)
            columns = ratio.isFinite ? Int(min(max(ratio, 1), CGFloat(Self.maximumColumns))) : 1
        }
        self.width = width
        self.columns = columns
        self.tileWidth = max(0, (width - spacing * CGFloat(columns - 1)) / CGFloat(columns))
    }
}
