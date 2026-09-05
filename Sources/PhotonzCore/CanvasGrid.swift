import CoreGraphics
import Foundation

/// Which way a canvas grid's lines run.
public enum CanvasGridAxes: String, Codable, Sendable, CaseIterable {
    /// Vertical lines only: the column rhythm on its own.
    case columns
    /// Vertical and horizontal: graph paper.
    case columnsAndRows

    public var label: String {
        switch self {
        case .columns: "Columns"
        case .columnsAndRows: "Columns and rows"
        }
    }

    public var drawsRows: Bool { self == .columnsAndRows }
}

/// The grid you build against, drawn over the whole canvas.
///
/// It is a **view preference**, not document content: it is remembered between
/// launches, it is the same in every window, and no document carries it. It is
/// also drawn by the canvas rather than the renderer, so it never reaches an
/// export, a copied picture or a redline sheet.
///
/// Not to be confused with a screen's column overlay, which is the other thing
/// a person might call a grid: that one belongs to one frame, is set by a
/// column count with a gutter and a margin, is saved with the document, and is
/// the only one of the two that pulls at a drag.
public struct CanvasGridSettings: Equatable, Sendable, Codable {

    /// Four points: the unit almost every UI scale is built on.
    public static let defaultSpacing: CGFloat = 4
    /// Below one point there is nothing to see; above five hundred and twelve
    /// there is nothing left on screen.
    public static let spacingRange: ClosedRange<CGFloat> = 1...512
    /// Every eighth line stronger, which with a four point unit puts the strong
    /// lines on thirty two points — a rhythm real UI is already built on.
    public static let defaultMajorEvery = 8
    public static let majorEveryRange: ClosedRange<Int> = 2...100
    /// A smallest cell of one point is no floor at all: the finest thing the
    /// grid can draw is the spacing, and the spacing can never go below one.
    /// So this is what "I have not asked for a floor" looks like, and a grid
    /// nobody has touched draws exactly what it drew before the floor existed.
    public static let noMinimumCell: CGFloat = 1
    /// Bigger than this and the floor would swallow the whole picture.
    public static let minimumCellRange: ClosedRange<CGFloat> = 1...256

    /// Whether the grid is drawn OVER the picture. The surround around the
    /// picture carries it either way: that is the surface you work on, and
    /// graph paper is what a surface for building UI looks like.
    public var isVisible: Bool
    /// Whether a drag pulls to the grid while the grid is showing. On unless
    /// someone turns it off, and turning it off leaves the lines exactly where
    /// they were: it stops the magnet, not the picture.
    public var snapsToGrid: Bool
    public var axes: CanvasGridAxes
    /// The gap between two neighbouring lines, in document points.
    public var spacing: CGFloat
    /// Every Nth line is stronger than the rest, so the eye can count without
    /// measuring. It is also the step of the level-of-detail ladder, so the
    /// strong lines are never knocked out of step by a fade.
    public var majorEvery: Int
    /// Where the grid's zero point sits, in document points. Every line, and
    /// every pull, is measured from here rather than from the corner of the
    /// picture: a screenshot whose content starts twenty four points in can
    /// have the grid lined up with what is already in it. The corner is the
    /// default, so a grid nobody has moved is where it has always been.
    public var origin: CGPoint
    /// The finest cell the grid may DRAW, in document points, however far you
    /// zoom in. Because a drag pulls to the lines that are actually drawn, it
    /// is also the finest cell anything can land on: asking to look at eight
    /// point cells is asking to work in eights. One point means no floor.
    public var minimumCell: CGFloat

    public init(isVisible: Bool = false,
                snapsToGrid: Bool = true,
                axes: CanvasGridAxes = .columnsAndRows,
                spacing: CGFloat = defaultSpacing,
                majorEvery: Int = defaultMajorEvery,
                origin: CGPoint = .zero,
                minimumCell: CGFloat = noMinimumCell) {
        self.isVisible = isVisible
        self.snapsToGrid = snapsToGrid
        self.axes = axes
        self.spacing = Self.clamped(spacing: spacing)
        self.majorEvery = Self.clamped(majorEvery: majorEvery)
        self.origin = Self.clamped(origin: origin)
        self.minimumCell = Self.clamped(minimumCell: minimumCell)
    }

    public static func clamped(spacing: CGFloat) -> CGFloat {
        guard spacing.isFinite else { return defaultSpacing }
        return min(max(spacing, spacingRange.lowerBound), spacingRange.upperBound)
    }

    public static func clamped(majorEvery: Int) -> Int {
        min(max(majorEvery, majorEveryRange.lowerBound), majorEveryRange.upperBound)
    }

    /// A zero point that is not a number is no zero point: the corner is a
    /// grid you can still see, and a NaN is a canvas with nothing drawn on it.
    public static func clamped(origin: CGPoint) -> CGPoint {
        guard origin.x.isFinite, origin.y.isFinite else { return .zero }
        return origin
    }

    public static func clamped(minimumCell: CGFloat) -> CGFloat {
        guard minimumCell.isFinite else { return noMinimumCell }
        return min(max(minimumCell, minimumCellRange.lowerBound), minimumCellRange.upperBound)
    }

    /// The finest cell the grid actually draws: the spacing, unless a smallest
    /// cell has been asked for that is coarser than it. Raising the BASE of
    /// the ladder rather than skipping its bottom rungs keeps every drawn line
    /// a whole number of spacings from the zero point, so a snapped edge still
    /// lands on a line you can see.
    public var drawnSpacing: CGFloat {
        max(Self.clamped(spacing: spacing), Self.clamped(minimumCell: minimumCell))
    }

    // Stored settings outlive the shape of this type, so a blob written before
    // a field existed still reads back, and a number edited by hand into
    // something undrawable is clamped rather than obeyed.
    private enum CodingKeys: String, CodingKey {
        case isVisible, snapsToGrid, axes, spacing, majorEvery
        case originX, originY, minimumCell
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(isVisible: try c.decodeIfPresent(Bool.self, forKey: .isVisible) ?? false,
                  snapsToGrid: try c.decodeIfPresent(Bool.self, forKey: .snapsToGrid) ?? true,
                  axes: try c.decodeIfPresent(CanvasGridAxes.self, forKey: .axes) ?? .columnsAndRows,
                  spacing: try c.decodeIfPresent(CGFloat.self, forKey: .spacing) ?? Self.defaultSpacing,
                  majorEvery: try c.decodeIfPresent(Int.self, forKey: .majorEvery) ?? Self.defaultMajorEvery,
                  origin: CGPoint(x: try c.decodeIfPresent(CGFloat.self, forKey: .originX) ?? 0,
                                  y: try c.decodeIfPresent(CGFloat.self, forKey: .originY) ?? 0),
                  minimumCell: try c.decodeIfPresent(CGFloat.self, forKey: .minimumCell)
                      ?? Self.noMinimumCell)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(isVisible, forKey: .isVisible)
        try c.encode(snapsToGrid, forKey: .snapsToGrid)
        try c.encode(axes, forKey: .axes)
        try c.encode(spacing, forKey: .spacing)
        try c.encode(majorEvery, forKey: .majorEvery)
        try c.encode(origin.x, forKey: .originX)
        try c.encode(origin.y, forKey: .originY)
        try c.encode(minimumCell, forKey: .minimumCell)
    }

    /// How far apart the lines a drag pulls to are, in document points, or nil
    /// when a drag should pull to nothing.
    ///
    /// It is the spacing being DRAWN at this zoom, which is not always the
    /// spacing that was typed in. The level-of-detail ladder draws only the
    /// rungs a person can read: at 100% a four point grid would be four screen
    /// points apart and would read as a grey wash, so the canvas draws its
    /// thirty two point lines instead. Pulling to the fours underneath them is
    /// what makes snapping feel broken — every position is a snap position, so
    /// nothing is ever caught, and an edge comes to rest between two lines
    /// looking like it missed.
    ///
    /// So the pull follows the picture. Zoom in until the fine lines arrive and
    /// the pull gets finer with them; zoom out and it gets coarser. What you
    /// land on is always something you can see yourself land on, and ⌘ is still
    /// how you get away from it.
    public func snapSpacing(atZoom zoom: CGFloat) -> CGFloat? {
        guard isVisible, snapsToGrid, spacing.isFinite, spacing > 0,
              zoom.isFinite, zoom > 0 else { return nil }
        return CanvasGridLevels.snapSpacing(among: CanvasGridLevels.levels(spacing: drawnSpacing,
                                                                          majorEvery: majorEvery,
                                                                          zoom: zoom))
    }
}

/// One rung of the grid's level-of-detail ladder: a spacing and how strongly to
/// draw it right now.
public struct CanvasGridLevel: Equatable, Sendable {
    /// The gap between this rung's lines, in document points.
    public let spacing: CGFloat
    /// The same gap in view points, which is what a person actually sees.
    public let onScreenSpacing: CGFloat
    /// How strongly to draw it, 0 to `CanvasGridLevels.maximumOpacity`.
    public let opacity: CGFloat

    public init(spacing: CGFloat, onScreenSpacing: CGFloat, opacity: CGFloat) {
        self.spacing = spacing
        self.onScreenSpacing = onScreenSpacing
        self.opacity = opacity
    }
}

/// Deciding what a grid shows at a given zoom, so it never turns to mush and
/// never quietly vanishes.
///
/// The ladder is `spacing × majorEvery^k`. The finest rung drawn is the first
/// one whose lines are at least `minimumOnScreenSpacing` apart, and at most
/// three rungs are drawn at once. Because each rung's lines are a subset of the
/// finer rung's, the rungs stack: a line that several rungs share comes out
/// stronger than one only the finest rung draws, which is what makes every Nth
/// line stand out without a second rule that could fall out of step.
///
/// A rung's strength depends only on how far apart its lines are on screen: at
/// the band's floor it is nothing, by `fullStrengthOnScreenSpacing` it is full,
/// and the coarsest rung of the three fades back out the same way. That is
/// continuous at BOTH ends of the ladder, so nothing pops when the ladder
/// shifts: the rung dropping off the bottom is already at zero when it goes,
/// and the rung arriving at the top arrives at zero.
public enum CanvasGridLevels {

    /// Closer together than this on screen and lines read as a grey wash, so
    /// nothing finer is ever drawn.
    public static let minimumOnScreenSpacing: CGFloat = 8
    /// Once a rung's lines are this far apart on screen it is fully there. In
    /// between it fades, so a rung arrives and leaves rather than appearing.
    public static let fullStrengthOnScreenSpacing: CGFloat = 32
    /// The strongest a single rung is ever drawn. The grid is a surface it
    /// helps to be aware of, not a thing to look at.
    public static let maximumOpacity: CGFloat = 0.30
    /// Fainter than this is invisible and not worth a draw.
    public static let minimumDrawnOpacity: CGFloat = 0.004
    /// Three rungs is a fine level, its strong lines, and the strong lines'
    /// own strong lines. A fourth is drawn on top of lines that are already
    /// there.
    public static let maximumLevels = 3
    /// A guard against a zoom so far out the ladder would climb forever.
    private static let maximumRungs = 16
    /// How far apart a rung's lines must be ON SCREEN before a drag will pull
    /// to them. A rung fades in from nothing at `minimumOnScreenSpacing` to
    /// full at `fullStrengthOnScreenSpacing`, and this is the midpoint of that
    /// fade: half drawn is the point where a line stops being a suggestion of
    /// a line and becomes something you can aim at. Pulling to a rung fainter
    /// than that is the same complaint as pulling to one that is not drawn at
    /// all.
    public static let minimumSnapOnScreenSpacing: CGFloat = 16

    /// Which of the rungs being drawn a drag should pull to: the finest one far
    /// enough apart on screen to aim at, or nil when there is nothing worth
    /// pulling to. `levels` comes back finest first, so this is the first that
    /// clears the bar.
    public static func snapSpacing(among levels: [CanvasGridLevel]) -> CGFloat? {
        levels.first { $0.onScreenSpacing >= minimumSnapOnScreenSpacing - 1e-9
            && $0.opacity >= minimumDrawnOpacity }?.spacing
    }

    public static func levels(spacing: CGFloat,
                              majorEvery: Int,
                              zoom: CGFloat,
                              minimumCell: CGFloat = 0,
                              maximumOpacity: CGFloat = maximumOpacity) -> [CanvasGridLevel] {
        guard spacing.isFinite, spacing > 0, zoom.isFinite, zoom > 0 else { return [] }
        let step = CGFloat(CanvasGridSettings.clamped(majorEvery: majorEvery))
        // A smallest cell raises the BASE of the ladder rather than knocking
        // rungs off the bottom of it, so the cells drawn stay whole multiples
        // of the spacing and the rungs still stack.
        let spacing = minimumCell.isFinite ? max(spacing, minimumCell) : spacing
        let unitOnScreen = spacing * zoom
        guard unitOnScreen.isFinite, unitOnScreen > 0 else { return [] }

        // The first rung far enough apart on screen to read as lines.
        var rung = 0
        if unitOnScreen < minimumOnScreenSpacing {
            rung = Int(ceil(log(minimumOnScreenSpacing / unitOnScreen) / log(step)))
            rung = min(max(rung, 0), maximumRungs)
        }
        let finest = spacing * pow(step, CGFloat(rung))
        let finestOnScreen = finest * zoom
        guard finest.isFinite, finestOnScreen.isFinite, finestOnScreen > 0 else { return [] }

        // Where the finest rung sits on the ladder, measured in whole steps
        // above the band's floor. The rungs above it are one and two steps
        // further along, and a rung's strength depends on nothing else — which
        // is what lets the ladder shift under them without anything moving.
        let climb = min(max(log(finestOnScreen / minimumOnScreenSpacing) / log(step), 0), 1)
        // The fade takes this much of a step. Capped well under a whole step so
        // that however small the multiple is there is still a stretch in the
        // middle where a rung is simply there, rather than three rungs all
        // permanently half faded.
        let fade = min(log(fullStrengthOnScreenSpacing / minimumOnScreenSpacing) / log(step), 0.9)

        var drawn: [CanvasGridLevel] = []
        for index in 0..<maximumLevels {
            let opacity = strength(atStep: climb + CGFloat(index),
                                   fade: fade, maximumOpacity: maximumOpacity)
            guard opacity >= minimumDrawnOpacity else { continue }
            let levelSpacing = finest * pow(step, CGFloat(index))
            guard levelSpacing.isFinite else { continue }
            drawn.append(CanvasGridLevel(spacing: levelSpacing,
                                         onScreenSpacing: levelSpacing * zoom,
                                         opacity: opacity))
        }
        return drawn
    }

    /// How strongly to draw a rung sitting `step` whole ladder steps above the
    /// band's floor: up from nothing over the first `fade` of a step, full
    /// across the middle, and back down to nothing by the top of the ladder.
    /// Eased at both ends, so the fade has no corners in it.
    private static func strength(atStep step: CGFloat,
                                 fade: CGFloat,
                                 maximumOpacity: CGFloat) -> CGFloat {
        let top = CGFloat(maximumLevels)
        let ramp: CGFloat
        if step <= 0 || step >= top {
            ramp = 0
        } else if step < fade {
            ramp = step / fade
        } else if step <= top - fade {
            ramp = 1
        } else {
            ramp = (top - step) / fade
        }
        return maximumOpacity * ramp * ramp * (3 - 2 * ramp)
    }

    /// Where one rung's lines fall along an axis: every whole multiple of
    /// `spacing` between `lower` and `upper`, both ends counting.
    ///
    /// `limit` is a floor under the worst case rather than a real constraint —
    /// the level-of-detail rule already keeps the count near the view's width
    /// divided by eight — but a spacing typed into a field should never be able
    /// to stall the canvas.
    public static func lines(spacing: CGFloat,
                             from lower: CGFloat,
                             to upper: CGFloat,
                             origin: CGFloat = 0,
                             limit: Int = 4096) -> [CGFloat] {
        guard spacing.isFinite, spacing > 0, lower.isFinite, upper.isFinite, upper >= lower,
              origin.isFinite else {
            return []
        }
        // Everything is counted in whole steps FROM the zero point, so a line
        // is always exactly `origin + k × spacing`: the offset can move the
        // grid but it can never put a line a fraction of a point off the step
        // a drag snapped to.
        let low = lower - origin
        let high = upper - origin
        // A line landing exactly on either end is on screen, and floating point
        // must not be the reason it is missed.
        let slack = max(spacing, abs(low), abs(high)) * 1e-9
        let first = Int(((low - slack) / spacing).rounded(.up))
        let last = Int(((high + slack) / spacing).rounded(.down))
        guard last >= first else { return [] }
        let count = min(last - first + 1, limit)
        return (0..<count).map { origin + CGFloat(first + $0) * spacing }
    }
}

/// Placing the grid's zero point: what the canvas is holding while two lines,
/// one across and one down, are being moved about to say where the grid starts.
///
/// It is a snapshot and a working copy. The snapshot is the WHOLE grid as it
/// was on the way in, so leaving without keeping it puts back everything the
/// mode touched — including the fact that placing switches the grid on, because
/// nobody adjusts a grid they cannot see. The working copy is the two things
/// being adjusted, the zero point and the smallest cell, and `live` is what the
/// canvas draws while you move them, so the grid updates under the lines rather
/// than after them.
///
/// The pull is not here: the two lines catch layer edges and canvas edges
/// through `Snapping.snapFrameOrigin` with no box around them, which is the
/// same call a dragged layer makes, so they behave like everything else that
/// moves on this canvas.
public struct CanvasGridOriginAdjustment: Equatable, Sendable {
    /// The grid exactly as it was on the way in.
    public let original: CanvasGridSettings
    /// Where the two lines are now, in document points.
    public var origin: CGPoint
    /// The smallest cell the slider is currently sitting on.
    public var minimumCell: CGFloat

    public init(settings: CanvasGridSettings) {
        original = settings
        origin = settings.origin
        minimumCell = settings.minimumCell
    }

    /// What the canvas draws right now: the grid you came in with, with the
    /// zero point and the smallest cell you are holding, and switched on.
    public var live: CanvasGridSettings {
        var settings = original
        settings.isVisible = true
        settings.origin = CanvasGridSettings.clamped(origin: origin)
        settings.minimumCell = CanvasGridSettings.clamped(minimumCell: minimumCell)
        return settings
    }

    /// What to keep when you accept: the live grid, unchanged.
    public var committed: CanvasGridSettings { live }

    /// What to put back when you leave without keeping it.
    public var cancelled: CanvasGridSettings { original }

    /// One arrow-key press: the same step a nudged layer travels, so the keys
    /// mean here what they already mean everywhere else on the canvas.
    public mutating func nudge(_ delta: CGVector) {
        guard delta.dx.isFinite, delta.dy.isFinite else { return }
        origin = CGPoint(x: origin.x + delta.dx, y: origin.y + delta.dy)
    }
}

/// Where the grid starts, as a person reads it: two numbers, whole where the
/// number is whole and to the half point where it is not, because a readout
/// that quietly rounded would be a lie about where the grid actually is.
public enum CanvasGridOriginLabel {
    public static func text(_ point: CGPoint) -> String {
        "\(number(point.x)), \(number(point.y))"
    }

    private static func number(_ value: CGFloat) -> String {
        guard value.isFinite else { return "0" }
        let rounded = (value * 2).rounded() / 2
        if rounded == rounded.rounded() { return String(Int(rounded.rounded())) }
        return String(format: "%.1f", Double(rounded))
    }
}

