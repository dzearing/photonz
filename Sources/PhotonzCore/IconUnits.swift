import CoreGraphics
import Foundation

/// An icon's artboard ruled into its own units, with the Grid on
/// (`a-24-unit-artboard-rules-itself-into-units`, icon-draw-wt.html step 1:
/// "the artboard rules itself into 24 units").
///
/// The canvas grid counts from its own zero point at its own spacing, so over
/// an icon it reaches one unit in four and lands wherever the frame happens to
/// sit. Inside the artboard these lines take its place: one on every unit,
/// counted from the artboard's corner, with the stronger line every fourth unit
/// the mock draws. Outside the artboard the canvas grid carries on as it was.
///
/// It is **not a second grid setting**. There is nothing here to set: the
/// switch is the Grid's own, and the frame's size says the rest, which is the
/// rule `IconKeylines` follows too. With the Grid off nothing is ruled, as
/// the mock has it: the artboard stays plain until step 1 turns the grid on.
///
/// The artboard's own edges are not lines of the ruling. Lines on all four
/// would trace a closed box, and that is the selection's mark and no guide's
/// (UX-PATTERNS D16 rule 3).
public enum IconUnits {

    /// Closer together than this on screen the units are a grey wash, and the
    /// canvas grid is left to draw over the artboard as it always has.
    public static let smallestOnScreenGap: CGFloat = 6

    /// Every Nth unit is stronger, so the eye can count without measuring. The
    /// mock's own major line (`igMajorPat`).
    public static let strongEvery = 4

    /// The side of the picture File, New, Image, Icon makes. It is 24 units
    /// across at this size, which does not divide: one unit there is 512 / 24
    /// points, and only the SVG says the units as numbers
    /// (`PhotonzDocument.pictureIconUnit`).
    public static let pictureSide: CGFloat = 512

    /// Whether there is room on screen to rule units this long at this zoom.
    public static func fit(zoom: CGFloat, unit: CGFloat = 1) -> Bool {
        // A pinch comes to rest a rounding error either side of the zoom it
        // was heading for, and six is six.
        zoom.isFinite && zoom * unit >= smallestOnScreenGap - 1e-6
    }

    /// The lines ruled on an icon sitting at `box`, in canvas coordinates, or
    /// nil when it is not an icon or the units are too close together to draw.
    ///
    /// Only the lines inside `showing` come back, so a big icon zoomed right in
    /// costs what the window holds rather than what the icon holds.
    public static func ruling(of box: CGRect, zoom: CGFloat, showing: CGRect,
                              unit: CGFloat = 1) -> IconUnitRuling? {
        guard fit(zoom: zoom, unit: unit), box.minX.isFinite, box.minY.isFinite,
              IconPreviews.isIconSize(box.size) else { return nil }
        let columns = units(across: box.width, from: box.minX,
                            showing: showing.minX, to: showing.maxX, unit: unit)
        let rows = units(across: box.height, from: box.minY,
                         showing: showing.minY, to: showing.maxY, unit: unit)
        func position(_ count: Int, from start: CGFloat) -> CGFloat { start + CGFloat(count) * unit }
        func strong(_ count: Int) -> Bool { count % strongEvery == 0 }
        return IconUnitRuling(frame: box,
                              columns: columns.map { position($0, from: box.minX) },
                              rows: rows.map { position($0, from: box.minY) },
                              strongColumns: columns.filter(strong).map { position($0, from: box.minX) },
                              strongRows: rows.filter(strong).map { position($0, from: box.minY) })
    }

    /// The whole units strictly inside a side of `length`, counted from
    /// `start`, that fall between two canvas positions.
    private static func units(across length: CGFloat, from start: CGFloat,
                              showing low: CGFloat, to high: CGFloat, unit: CGFloat) -> [Int] {
        guard low.isFinite, high.isFinite, unit > 0 else { return [] }
        let first = max(1, ((low - start) / unit).rounded(.up))
        // A side of 24 units divides back to a hair over or under 24.
        let across = ((length / unit) * 1e6).rounded() / 1e6
        let last = min(across.rounded(.up) - 1, ((high - start) / unit).rounded(.down))
        guard first <= last else { return [] }
        return Array(Int(first)...Int(last))
    }

    /// What is left of a straight line once it has stepped round `boxes`.
    ///
    /// `position` is where the line sits across its run and `start`...`end` is
    /// how far it runs. A line lying along a box's edge is outside that box.
    public static func spans(ofLineAt position: CGFloat, running axis: CanvasGuideAxis,
                             from start: CGFloat, to end: CGFloat,
                             clearOf boxes: [CGRect]) -> [ClosedRange<CGFloat>] {
        guard start < end else { return [] }
        let blocked = boxes.compactMap { box -> ClosedRange<CGFloat>? in
            let across = axis == .vertical ? (box.minX, box.maxX) : (box.minY, box.maxY)
            let along = axis == .vertical ? (box.minY, box.maxY) : (box.minX, box.maxX)
            guard across.0 < position, position < across.1 else { return nil }
            return along.0...along.1
        }.sorted { $0.lowerBound < $1.lowerBound }

        var spans: [ClosedRange<CGFloat>] = []
        var cursor = start
        for block in blocked {
            if block.lowerBound > cursor {
                spans.append(cursor...min(block.lowerBound, end))
            }
            cursor = max(cursor, block.upperBound)
            if cursor >= end { return spans }
        }
        spans.append(cursor...end)
        return spans
    }
}

/// One artboard's unit lines, in canvas coordinates.
public struct IconUnitRuling: Hashable, Sendable {
    /// The artboard. Every line runs from one edge of this to the other.
    public var frame: CGRect
    /// Where the lines running down the artboard sit, one per unit.
    public var columns: [CGFloat]
    /// Where the lines running across it sit, one per unit.
    public var rows: [CGFloat]
    /// The columns and rows that are also a fourth unit, drawn again on top so
    /// a line they share comes out stronger, as the canvas grid's rungs do.
    public var strongColumns: [CGFloat]
    public var strongRows: [CGFloat]

    public init(frame: CGRect, columns: [CGFloat], rows: [CGFloat],
                strongColumns: [CGFloat], strongRows: [CGFloat]) {
        self.frame = frame
        self.columns = columns
        self.rows = rows
        self.strongColumns = strongColumns
        self.strongRows = strongRows
    }
}

/// The lines a drag or an arrow key lands on.
public struct CanvasGridPull: Equatable, Sendable {
    /// How far apart they are, or nil when nothing is pulling.
    public var spacing: CGFloat?
    /// Where they count from.
    public var origin: CGPoint
    public var axes: CanvasGridAxes

    public init(spacing: CGFloat?, origin: CGPoint, axes: CanvasGridAxes) {
        self.spacing = spacing
        self.origin = origin
        self.axes = axes
    }
}

extension PhotonzDocument {

    /// Every icon on show, a canvas made as one first: what is ruled, and what
    /// the canvas grid steps round.
    public var shownIconIDs: [UUID] {
        let framed = frames.filter { $0.isVisible && isIconFrame(id: $0.id) }.map(\.id)
        return (isIconCanvas ? [Self.iconCanvasID] : []) + framed
    }

    /// The artboard whose units these layers land on at this zoom, or nil when
    /// the canvas grid has them: nothing held, a layer on no icon, layers on
    /// two different icons, the icon itself being moved, or no room to rule.
    ///
    /// A drag lands on lines it can see, so wherever the units replace the
    /// canvas grid they replace its pull as well.
    public func iconUnitBox(holding ids: [UUID], zoom: CGFloat) -> CGRect? {
        guard let first = ids.first,
              let icon = iconFrameID(containing: first), !ids.contains(icon),
              IconUnits.fit(zoom: zoom, unit: iconUnit(of: icon)),
              ids.allSatisfy({ iconFrameID(containing: $0) == icon }),
              shownIconIDs.contains(icon) else { return nil }
        return iconBox(of: icon)
    }

    /// The artboard whose units a point put down here lands on, at this zoom.
    public func iconUnitBox(under point: CGPoint, zoom: CGFloat) -> CGRect? {
        guard let icon = iconFrameID(under: point),
              IconUnits.fit(zoom: zoom, unit: iconUnit(of: icon)),
              shownIconIDs.contains(icon) else { return nil }
        return iconBox(of: icon)
    }
}
