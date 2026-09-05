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

    public init(isVisible: Bool = false,
                snapsToGrid: Bool = true,
                axes: CanvasGridAxes = .columnsAndRows,
                spacing: CGFloat = defaultSpacing,
                majorEvery: Int = defaultMajorEvery) {
        self.isVisible = isVisible
        self.snapsToGrid = snapsToGrid
        self.axes = axes
        self.spacing = Self.clamped(spacing: spacing)
        self.majorEvery = Self.clamped(majorEvery: majorEvery)
    }

    public static func clamped(spacing: CGFloat) -> CGFloat {
        guard spacing.isFinite else { return defaultSpacing }
        return min(max(spacing, spacingRange.lowerBound), spacingRange.upperBound)
    }

    public static func clamped(majorEvery: Int) -> Int {
        min(max(majorEvery, majorEveryRange.lowerBound), majorEveryRange.upperBound)
    }

    // Stored settings outlive the shape of this type, so a blob written before
    // a field existed still reads back, and a number edited by hand into
    // something undrawable is clamped rather than obeyed.
    private enum CodingKeys: String, CodingKey {
        case isVisible, snapsToGrid, axes, spacing, majorEvery
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(isVisible: try c.decodeIfPresent(Bool.self, forKey: .isVisible) ?? false,
                  snapsToGrid: try c.decodeIfPresent(Bool.self, forKey: .snapsToGrid) ?? true,
                  axes: try c.decodeIfPresent(CanvasGridAxes.self, forKey: .axes) ?? .columnsAndRows,
                  spacing: try c.decodeIfPresent(CGFloat.self, forKey: .spacing) ?? Self.defaultSpacing,
                  majorEvery: try c.decodeIfPresent(Int.self, forKey: .majorEvery) ?? Self.defaultMajorEvery)
    }

    /// How far apart the lines a drag pulls to are, in document points, or nil
    /// when a drag should pull to nothing.
    ///
    /// It is the spacing that was TYPED IN, and it does not change with the
    /// zoom. A grid set to four means things land on fours, and they land on
    /// the same fours whether you are looking at the whole picture or at one
    /// corner of it — a pull that got coarser as you zoomed out would mean the
    /// same drag gave a different answer depending on how close you happened to
    /// be standing, which is its own kind of jumping.
    ///
    /// The lines DRAWN are a different question, and the level-of-detail ladder
    /// answers it: zoomed far enough out, fine lines would be a grey wash, so
    /// the canvas draws only the strong ones. A snapped edge can therefore land
    /// between two drawn lines, on a line that is really there but too fine to
    /// show at this zoom. Zooming in brings it back.
    public var snapSpacing: CGFloat? {
        guard isVisible, snapsToGrid, spacing.isFinite, spacing > 0 else { return nil }
        return spacing
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

    public static func levels(spacing: CGFloat,
                              majorEvery: Int,
                              zoom: CGFloat,
                              maximumOpacity: CGFloat = maximumOpacity) -> [CanvasGridLevel] {
        guard spacing.isFinite, spacing > 0, zoom.isFinite, zoom > 0 else { return [] }
        let step = CGFloat(CanvasGridSettings.clamped(majorEvery: majorEvery))
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
                             limit: Int = 4096) -> [CGFloat] {
        guard spacing.isFinite, spacing > 0, lower.isFinite, upper.isFinite, upper >= lower else {
            return []
        }
        // A line landing exactly on either end is on screen, and floating point
        // must not be the reason it is missed.
        let slack = max(spacing, abs(lower), abs(upper)) * 1e-9
        let first = Int(((lower - slack) / spacing).rounded(.up))
        let last = Int(((upper + slack) / spacing).rounded(.down))
        guard last >= first else { return [] }
        let count = min(last - first + 1, limit)
        return (0..<count).map { CGFloat(first + $0) * spacing }
    }
}
