import CoreGraphics
import Foundation

/// The column layout one screen is designed to: twelve columns with a gutter on
/// a desktop, four on a phone.
///
/// It belongs to the SCREEN, is saved with the document, and is the only thing
/// in the app that pulls a drag to a column edge. That is what tells it apart
/// from the canvas grid (`CanvasGridSettings`), which covers the whole canvas,
/// is set by a spacing, is a view preference no document carries, and never
/// pulls at anything. Two different ideas, two different words, two different
/// places to set them: Columns on a selected screen, Grid on the canvas.
///
/// Three things are worth knowing about the numbers:
///
/// - **The edges land on whole points.** Twelve columns across 1440 with a 24
///   gutter and a 32 margin gives a column 85.666… wide, and a tool for
///   building UI must not hand anybody an x of 151.333. So each band's edges
///   are rounded, the remainder spread over the row a point at a time, and the
///   outer two edges stay exactly on the margins. What is drawn and what a
///   drag lands on are the same rounded number, so you always land on a line
///   you can see.
/// - **They are drawn inside the screen's own room.** A screen has ONE inset
///   from its edge: the padding it keeps for its contents. The columns start
///   where that padding starts, on all four sides, so a box the screen lays
///   out at its padding lands on the first column exactly. A screen that keeps
///   no room falls back to the columns' own `margin`, which is what every
///   screen drawn before this had.
/// - **Switching them off leaves the numbers alone.** `isVisible` is the whole
///   switch: no bands are described, so nothing is drawn and nothing pulls,
///   and the count, gutter and margin are still there when it goes back on.
public struct FrameColumns: Hashable, Codable, Sendable {

    /// One column, as a range across the screen it is drawn on.
    public struct Band: Hashable, Sendable {
        public var start: CGFloat
        public var end: CGFloat

        public init(start: CGFloat, end: CGFloat) {
            self.start = start
            self.end = end
        }

        public var width: CGFloat { end - start }
    }

    /// Twelve is what nearly every design system on a wide screen is built on.
    public static let defaultCount = 12
    public static let defaultGutter: CGFloat = 24
    public static let defaultMargin: CGFloat = 32
    /// One column is a content area with margins, which is a real layout. Past
    /// four dozen the bands are thinner than the gutters between them.
    public static let countRange: ClosedRange<Int> = 1...48
    public static let gutterRange: ClosedRange<CGFloat> = 0...512
    public static let marginRange: ClosedRange<CGFloat> = 0...2048
    /// Narrower than this and a screen is a phone, which is laid out on four
    /// columns rather than twelve.
    public static let phoneWidth: CGFloat = 600

    /// Whether the columns are drawn on the screen — and, because they are the
    /// same switch, whether a drag pulls to them.
    public var isVisible: Bool
    public var count: Int
    /// The gap between two neighbouring columns, in document points.
    public var gutter: CGFloat
    /// The gap between the screen's edge and the first column, on both sides,
    /// for a screen that has no room of its own at its edges.
    ///
    /// A screen with padding does not use this at all: one screen has ONE
    /// inset from its edge, and the columns are drawn inside the padding the
    /// screen was given (`inset(inside:)`). This is what is left for a screen
    /// that has none, which is every screen drawn before there was any, so
    /// nothing anybody has already made moves.
    public var margin: CGFloat

    public init(isVisible: Bool = true,
                count: Int = defaultCount,
                gutter: CGFloat = defaultGutter,
                margin: CGFloat = defaultMargin) {
        self.isVisible = isVisible
        self.count = Self.clamped(count: count)
        self.gutter = Self.clamped(gutter: gutter)
        self.margin = Self.clamped(margin: margin)
    }

    public static func clamped(count: Int) -> Int {
        min(max(count, countRange.lowerBound), countRange.upperBound)
    }

    /// Whole points, because a gutter of 23.6 is nobody's design system and a
    /// gutter that is not a number is a screen with nothing drawn on it.
    public static func clamped(gutter: CGFloat) -> CGFloat {
        guard gutter.isFinite else { return defaultGutter }
        return min(max(gutter.rounded(), gutterRange.lowerBound), gutterRange.upperBound)
    }

    public static func clamped(margin: CGFloat) -> CGFloat {
        guard margin.isFinite else { return defaultMargin }
        return min(max(margin.rounded(), marginRange.lowerBound), marginRange.upperBound)
    }

    /// The columns a screen of this width should start with, so switching them
    /// on gives you something already close to right: a phone gets four with a
    /// snug gutter, anything wider gets twelve.
    public static func suggested(forWidth width: CGFloat) -> FrameColumns {
        guard width.isFinite, width >= phoneWidth else {
            return FrameColumns(count: 4, gutter: 16, margin: 16)
        }
        return FrameColumns()
    }

    /// The room the columns are drawn inside on a screen padded like this.
    ///
    /// A screen has ONE inset from its edge and it is the padding, so the
    /// columns start where the screen's contents start: give a screen 12 all
    /// round and the first column begins at 12, on all four sides, whatever
    /// any other number says. A screen with no room at its edges — nothing
    /// typed, or zero typed — falls back to the columns' own `margin`, which
    /// is what such a screen has always drawn, so switching this on moved
    /// nobody's columns under them.
    public func inset(inside padding: GroupPadding) -> GroupPadding {
        let room = padding.used
        guard room == .none else { return room }
        return GroupPadding(top: 0, right: margin, bottom: 0, left: margin)
    }

    /// Where the columns fall across a screen this wide, measured from its left
    /// edge and inside the room the screen keeps at its edges. Empty when the
    /// numbers leave no room for a column at all, which is a screen with
    /// nothing drawn on it rather than columns drawn backwards.
    ///
    /// This ignores `isVisible` on purpose: it is the arithmetic, and a panel
    /// showing a column width while the overlay is off is still telling the
    /// truth. What honours the switch is `bands(in:padding:)`, which is what
    /// the canvas and the snapping both read.
    public func bands(inWidth width: CGFloat, padding: GroupPadding) -> [Band] {
        guard width.isFinite, width > 0 else { return [] }
        let room = inset(inside: padding)
        let content = width - room.horizontal
        let gutters = gutter * CGFloat(count - 1)
        let available = content - gutters
        // Every column needs at least a point of its own, or there is nothing
        // to draw and nothing to aim at.
        guard available >= CGFloat(count) else { return [] }
        let columnWidth = available / CGFloat(count)
        let step = columnWidth + gutter
        return (0..<count).map { index in
            let start = room.left + CGFloat(index) * step
            return Band(start: start.rounded(), end: (start + columnWidth).rounded())
        }
    }

    /// The same columns as boxes on the canvas: inside the screen's padding on
    /// all four sides, at the x positions the arithmetic gave. Empty while the
    /// columns are switched off, so one check covers the drawing and the
    /// pulling alike, and empty when the room at the top and bottom leaves no
    /// height to draw — a column with no height is nothing to aim at.
    public func bands(in screen: CGRect, padding: GroupPadding) -> [CGRect] {
        guard isVisible else { return [] }
        let room = inset(inside: padding)
        let height = screen.height - room.vertical
        guard height >= 1 else { return [] }
        return bands(inWidth: screen.width, padding: padding).map { band in
            CGRect(x: screen.minX + band.start, y: screen.minY + room.top,
                   width: band.width, height: height)
        }
    }
}

public extension Layer {
    /// The room this screen keeps inside its own edges, which is what its
    /// columns are drawn inside. A screen nobody has given a layout keeps no
    /// room, and its columns fall back to their own margin.
    var columnPadding: GroupPadding { group?.layout?.usedPadding ?? .none }

    /// Every column this screen draws, as boxes on the canvas, given where the
    /// screen sits. The ONE place the drawing and the snapping both read, so a
    /// column can never be drawn in one place and pull from another.
    func columnBands(inCanvas box: CGRect) -> [CGRect] {
        columns?.bands(in: box, padding: columnPadding) ?? []
    }

    /// The column layout this screen is designed to, or nil for a screen
    /// nobody has given one — which is every screen made before this existed.
    /// Only a frame ever holds one.
    var columns: FrameColumns? {
        get { group?.isFrame == true ? group?.columns : nil }
        set {
            guard case .group(var content) = content, content.isFrame else { return }
            content.columns = newValue
            self.content = .group(content)
        }
    }
}

public extension PhotonzDocument {

    /// Gives a screen its column layout, or takes it away with nil. Anything
    /// that is not a screen is left alone: a rectangle has no columns.
    mutating func setFrameColumns(id: UUID, _ columns: FrameColumns?) {
        guard layer(id: id)?.isFrame == true else { return }
        updateLayer(id: id) { $0.columns = columns }
    }

    /// Switches a screen's columns on or off without touching its numbers. A
    /// screen that has never had any gets numbers picked for its width, so the
    /// first thing anybody sees is already close to right.
    mutating func setFrameColumnsVisible(id: UUID, _ visible: Bool) {
        guard let frame = layer(id: id), frame.isFrame else { return }
        var columns = frame.columns
            ?? FrameColumns.suggested(forWidth: canvasBounds(of: id)?.width ?? frame.frame.width)
        columns.isVisible = visible
        setFrameColumns(id: id, columns)
    }

    /// Every column a drag could catch, as boxes on the canvas.
    ///
    /// A screen whose columns are switched off, or that is hidden, or that is
    /// travelling with the drag, offers nothing. The screen a dragged layer
    /// LIVES in does offer its columns: it is holding still while the layer
    /// moves inside it, which is the whole point of the feature.
    ///
    /// A document with no screens in it — every screenshot anybody has taken —
    /// gets an empty list without walking anything twice.
    func columnBands(excluding ids: Set<UUID>) -> [CGRect] {
        guard hasFrames else { return [] }
        var travelling: Set<UUID> = ids
        for id in ids {
            travelling.formUnion(layer(id: id)?.selfAndDescendants.map(\.id) ?? [])
        }
        var bands: [CGRect] = []
        // The same walk `snapPeers` makes, for the same reasons: a hidden
        // screen, or a screen inside a hidden group, is not on screen, and
        // nothing may stick to something nobody can see.
        func collect(_ list: [Layer], origin: CGPoint) {
            for layer in list {
                guard layer.isVisible, !travelling.contains(layer.id) else { continue }
                if layer.columns?.isVisible == true {
                    let box = layer.frame.offsetBy(dx: origin.x, dy: origin.y)
                    bands.append(contentsOf: layer.columnBands(inCanvas: box))
                }
                if layer.isGroup {
                    collect(layer.children,
                            origin: CGPoint(x: origin.x + layer.frame.minX,
                                            y: origin.y + layer.frame.minY))
                }
            }
        }
        collect(layers, origin: .zero)
        return bands
    }
}
