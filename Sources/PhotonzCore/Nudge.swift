import CoreGraphics

/// The grid an arrow key steps by, as the canvas sees it right now.
///
/// `spacing` is the LIVE cell — what the lines on screen are worth at this
/// zoom (`CanvasGridSettings.snapSpacing(atZoom:)`), not the number typed into
/// the Spacing field. A four point grid draws thirty two point lines at 100%
/// and a drag lands on those, so a key stepping four would disagree with the
/// drag all over again. What you nudge by is always something you can see.
public struct NudgeGrid: Equatable, Sendable {
    /// The gap between the lines a drag is landing on, in document points.
    public let spacing: CGFloat
    /// Where the grid counts from, so a nudged edge lands on a line that is
    /// actually drawn rather than beside it.
    public let origin: CGPoint
    /// Which ways the lines run. A grid of columns has nothing to land on
    /// going up or down, so that axis nudges the way it always has.
    public let axes: CanvasGridAxes

    public init(spacing: CGFloat, origin: CGPoint = .zero,
                axes: CanvasGridAxes = .columnsAndRows) {
        self.spacing = spacing
        self.origin = origin
        self.axes = axes
    }

    /// Whether this grid has lines to land on along the given axis.
    fileprivate func pulls(horizontally: Bool) -> Bool {
        guard spacing.isFinite, spacing > 0 else { return false }
        return horizontally || axes.drawsRows
    }
}

/// Arrow-key nudging for the selected layer: 1pt per press, 10pt with ⇧
/// (macOS convention), and whole grid cells while the grid is pulling.
/// Deltas are in document coordinates (y grows down).
public enum Nudge {

    /// One press with nothing pulling.
    public static let step: CGFloat = 1
    /// One press with ⇧ and nothing pulling.
    public static let coarseStep: CGFloat = 10

    /// The move for a key press, or nil when the key is not an arrow.
    /// Key codes: 123 ←, 124 →, 125 ↓, 126 ↑.
    public static func delta(keyCode: UInt16, large: Bool) -> CGVector? {
        let step: CGFloat = large ? coarseStep : step
        switch keyCode {
        case 123: return CGVector(dx: -step, dy: 0)
        case 124: return CGVector(dx: step, dy: 0)
        case 125: return CGVector(dx: 0, dy: step)
        case 126: return CGVector(dx: 0, dy: -step)
        default: return nil
        }
    }

    /// The move for a key press while the grid is pulling: from `point` to the
    /// next line along, so the keys and a drag put a layer in the same places.
    ///
    /// `point` is the corner the move carries — the frame's leading edge, which
    /// is the same edge a drag hands to the grid. A layer that is already off
    /// the grid REJOINS it on the first press rather than travelling a whole
    /// cell and staying off by the same amount, so one press is always enough
    /// to get back on.
    ///
    /// No grid, no lines along this axis, or a spacing that is not a real
    /// number, and the keys are exactly the one and ten points they have always
    /// been.
    public static func delta(keyCode: UInt16, large: Bool,
                             grid: NudgeGrid?, from point: CGPoint) -> CGVector? {
        guard let direction = direction(keyCode: keyCode) else { return nil }
        let horizontal = direction.dx != 0
        guard let grid, grid.pulls(horizontally: horizontal),
              point.x.isFinite, point.y.isFinite else {
            return delta(keyCode: keyCode, large: large)
        }
        let cells = large ? coarseCells(spacing: grid.spacing) : 1
        let value = horizontal ? point.x : point.y
        let start = horizontal ? grid.origin.x : grid.origin.y
        guard start.isFinite,
              let landed = line(from: value, spacing: grid.spacing, start: start,
                                cells: cells, direction: horizontal ? direction.dx : direction.dy)
        else {
            return delta(keyCode: keyCode, large: large)
        }
        let travel = landed - value
        return horizontal ? CGVector(dx: travel, dy: 0) : CGVector(dx: 0, dy: travel)
    }

    /// How many cells ⇧ travels: the same ten points the coarse nudge has
    /// always covered, rounded up to whole cells, and never fewer than two.
    ///
    /// Ten CELLS would be absurd on a grid whose cell is already thirty two
    /// points — a single press covers real ground there — and one cell would
    /// make ⇧ do nothing at all, which is why the floor is two. A one point
    /// grid comes out at exactly the ten points it was before.
    public static func coarseCells(spacing: CGFloat) -> CGFloat {
        guard spacing.isFinite, spacing > 0 else { return 2 }
        return max(2, (coarseStep / spacing).rounded(.up))
    }

    /// Whether a key is one of the four arrows, without working out how far
    /// it would travel: what a canvas asks before it goes looking for the
    /// layers a nudge would move.
    public static func isArrow(keyCode: UInt16) -> Bool { direction(keyCode: keyCode) != nil }

    /// Which way an arrow key points, as unit steps in document coordinates.
    private static func direction(keyCode: UInt16) -> (dx: Int, dy: Int)? {
        switch keyCode {
        case 123: return (-1, 0)
        case 124: return (1, 0)
        case 125: return (0, 1)
        case 126: return (0, -1)
        default: return nil
        }
    }

    /// The line `cells` steps away from `value` in `direction`, counted from
    /// where the grid starts. A value already on a line steps off it by whole
    /// cells; a value between two lines counts the line it is heading towards
    /// as its first step.
    private static func line(from value: CGFloat, spacing: CGFloat, start: CGFloat,
                             cells: CGFloat, direction: Int) -> CGFloat? {
        let units = (value - start) / spacing
        guard units.isFinite, abs(units) < 1e12 else { return nil }
        // A drag leaves fractions nobody typed, so "on a line" has to mean
        // near enough to one: without this, a layer resting on 96.00000001
        // would first travel a hundredth of a point and look stuck.
        let nearest = units.rounded()
        let onGrid = abs(units - nearest) <= 1e-6 * max(1, abs(units))
        let base = onGrid ? nearest : (direction > 0 ? units.rounded(.down) : units.rounded(.up))
        let landed = start + (base + CGFloat(direction.signum()) * cells) * spacing
        return landed.isFinite ? landed : nil
    }
}
