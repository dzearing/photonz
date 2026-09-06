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
/// launches, it is the same in every window, and no document carries it.
/// Two things that USED to sit here no longer do, because they describe one
/// picture rather than how you like to work: where the grid counts from, and
/// the guides pinned onto it. Both live on `PhotonzDocument`. It is
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
                minimumCell: CGFloat = noMinimumCell) {
        self.isVisible = isVisible
        self.snapsToGrid = snapsToGrid
        self.axes = axes
        self.spacing = Self.clamped(spacing: spacing)
        self.majorEvery = Self.clamped(majorEvery: majorEvery)
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
    /// The zero point itself lives on the DOCUMENT (`PhotonzDocument.gridOrigin`);
    /// this stays here because it is the grid's own rule about its own number.
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

    /// The spacing as it was TYPED, with its unit. This is what the Spacing
    /// field holds; what the canvas is drawing right now is `liveSpacing`.
    public var spacingText: String { "\(CanvasGridNumber.text(spacing)) pt" }

    // Stored settings outlive the shape of this type, so a blob written before
    // a field existed still reads back, and a number edited by hand into
    // something undrawable is clamped rather than obeyed.
    private enum CodingKeys: String, CodingKey {
        case isVisible, snapsToGrid, axes, spacing, majorEvery, minimumCell
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(isVisible: try c.decodeIfPresent(Bool.self, forKey: .isVisible) ?? false,
                  snapsToGrid: try c.decodeIfPresent(Bool.self, forKey: .snapsToGrid) ?? true,
                  axes: try c.decodeIfPresent(CanvasGridAxes.self, forKey: .axes) ?? .columnsAndRows,
                  spacing: try c.decodeIfPresent(CGFloat.self, forKey: .spacing) ?? Self.defaultSpacing,
                  majorEvery: try c.decodeIfPresent(Int.self, forKey: .majorEvery) ?? Self.defaultMajorEvery,
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

    /// What the lines on screen are WORTH right now, in document points.
    ///
    /// A grid set to four points draws thirty two point lines at 100%, because
    /// four screen points apart is a grey wash rather than a grid. So the
    /// number that describes the picture is not always the number that was
    /// typed, and this is the one that describes the picture: the finest rung
    /// far enough apart on screen to aim at, which is the same rung a drag
    /// lands on.
    ///
    /// It does NOT depend on the magnet. Turning snapping off changes what a
    /// drag does, not what the lines are worth, so the readout stays put.
    public func liveSpacing(atZoom zoom: CGFloat) -> CGFloat {
        let base = drawnSpacing
        guard zoom.isFinite, zoom > 0 else { return base }
        let levels = CanvasGridLevels.levels(spacing: base, majorEvery: majorEvery, zoom: zoom)
        return CanvasGridLevels.snapSpacing(among: levels) ?? levels.first?.spacing ?? base
    }

    /// The chip in the tool bar: one number while the grid you set is the grid
    /// you see, and both numbers the moment they part company. The set number
    /// stays on the left because the chip is the door to the field holding it,
    /// and the arrow says which way the canvas went.
    public func spacingChipText(atZoom zoom: CGFloat) -> String {
        let live = liveSpacing(atZoom: zoom)
        guard abs(live - spacing) > 1e-9 else { return spacingText }
        return "\(CanvasGridNumber.text(spacing)) \u{2192} \(CanvasGridNumber.text(live)) pt"
    }

    /// The one line under the Spacing field that explains the second number,
    /// or nil when there is no second number to explain.
    public func liveSpacingNote(atZoom zoom: CGFloat) -> String? {
        let live = liveSpacing(atZoom: zoom)
        guard abs(live - spacing) > 1e-9 else { return nil }
        return CanvasGridCopy.liveSpacingNote(set: spacing, live: live, snaps: snapsToGrid)
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

/// Adjusting the grid: what the canvas is holding while the zero point is being
/// placed and guides are being pinned onto it.
///
/// It is a snapshot and a working copy. The snapshot is everything the mode can
/// touch as it was on the way in — the whole grid, the zero point, the guides —
/// so leaving without keeping it puts all of it back, including the fact that
/// adjusting switches the grid on, because nobody adjusts a grid they cannot
/// see. The working copy is the four things being adjusted, and `liveSettings`
/// with `origin` is what the canvas draws meanwhile, so the grid updates under
/// the lines rather than after them.
///
/// Two of those four now belong to the DOCUMENT rather than to the app, so the
/// session carries them separately from the settings: `committedOrigin` and
/// `committedGuides` are written into the document as ONE undoable edit when
/// you accept, which is what makes Clear Guides one undo step rather than one
/// per guide.
///
/// The pull is not here: the two markers catch layer edges and canvas edges
/// through `Snapping.snapFrameOrigin` with no box around them, which is the
/// same call a dragged layer makes, so they behave like everything else that
/// moves on this canvas.
public struct CanvasGridAdjustment: Equatable, Sendable {
    /// The grid exactly as it was on the way in.
    public let originalSettings: CanvasGridSettings
    /// The document's zero point on the way in.
    public let originalOrigin: CGPoint
    /// The document's guides on the way in.
    public let originalGuides: [CanvasGuide]

    /// Where the two markers are now, in document points.
    public var origin: CGPoint
    /// The cell the slider is currently sitting on.
    public var minimumCell: CGFloat
    /// The guides as they stand right now.
    public private(set) var guides: [CanvasGuide]
    /// The guide the mode is holding: the one a drag moves and backspace
    /// deletes. Nil until something is pinned or picked up.
    public private(set) var selectedGuideID: UUID?

    public init(settings: CanvasGridSettings, origin: CGPoint, guides: [CanvasGuide]) {
        originalSettings = settings
        originalOrigin = CanvasGridSettings.clamped(origin: origin)
        originalGuides = guides
        self.origin = CanvasGridSettings.clamped(origin: origin)
        minimumCell = settings.minimumCell
        self.guides = guides
        selectedGuideID = nil
    }

    public var hasGuides: Bool { !guides.isEmpty }

    public var selectedGuide: CanvasGuide? {
        guides.first { $0.id == selectedGuideID }
    }

    /// What the canvas draws right now: the grid you came in with, with the
    /// cell you are holding, and switched on.
    public var liveSettings: CanvasGridSettings {
        var settings = originalSettings
        settings.isVisible = true
        settings.minimumCell = CanvasGridSettings.clamped(minimumCell: minimumCell)
        return settings
    }

    /// What to keep when you accept.
    public var committedSettings: CanvasGridSettings { liveSettings }
    public var committedOrigin: CGPoint { CanvasGridSettings.clamped(origin: origin) }
    public var committedGuides: [CanvasGuide] { guides }

    /// What to put back when you leave without keeping it.
    public var cancelledSettings: CanvasGridSettings { originalSettings }
    public var cancelledOrigin: CGPoint { originalOrigin }
    public var cancelledGuides: [CanvasGuide] { originalGuides }

    /// Pins the line under the pointer, and holds whatever is now on it.
    /// Clicking a line that already carries a guide picks that one up rather
    /// than stacking a second guide on top of it.
    public mutating func pin(_ line: CanvasGuideLine) {
        let pinned = CanvasGuides.pinning(guides, line)
        guides = pinned.guides
        selectedGuideID = pinned.id
    }

    public mutating func select(_ id: UUID?) {
        selectedGuideID = id.flatMap { candidate in
            guides.contains { $0.id == candidate } ? candidate : nil
        }
    }

    public mutating func moveSelectedGuide(to line: CanvasGuideLine) {
        guard let selectedGuideID else { return }
        guides = CanvasGuides.moving(guides, id: selectedGuideID, to: line)
    }

    public mutating func deleteSelectedGuide() {
        guard let selectedGuideID else { return }
        guides = CanvasGuides.removing(guides, id: selectedGuideID)
        self.selectedGuideID = nil
    }

    public mutating func clearGuides() {
        guides = []
        selectedGuideID = nil
    }

    /// One arrow-key press: the same step a nudged layer travels, so the keys
    /// mean here what they already mean everywhere else on the canvas.
    public mutating func nudge(_ delta: CGVector) {
        guard delta.dx.isFinite, delta.dy.isFinite else { return }
        origin = CGPoint(x: origin.x + delta.dx, y: origin.y + delta.dy)
    }
}

/// The cells the slider stops on: the sizes real UI is actually built in.
///
/// A continuous one to sixty four slider can be left on fourteen, and a
/// fourteen point cell is not a cell anybody wants — it is also the one that
/// makes the grid look broken, because fourteen points on screen is too close
/// together to aim at, so the lines drawn are fourteens while a drag lands on
/// hundred and twelves. Stopping on the numbers a person would type removes
/// both problems at once, and one is still the first stop, which means no floor
/// at all.
public enum CanvasGridCellStops {
    public static let all: [CGFloat] = [1, 2, 4, 8, 12, 16, 24, 32, 48, 64]

    /// Where a cell sits on the slider. A cell set some other way — typed into
    /// the settings, or restored from before the stops existed — lands on the
    /// nearest stop rather than knocking the knob off the track. A number
    /// exactly between two stops goes to the COARSER one, because a coarser
    /// cell is always drawable and a finer one may not be.
    public static func index(of cell: CGFloat) -> Int {
        guard cell.isFinite else { return 0 }
        var best = 0
        for (index, stop) in all.enumerated()
        where abs(stop - cell) <= abs(all[best] - cell) {
            best = index
        }
        return best
    }

    public static func cell(at index: Int) -> CGFloat {
        all[min(max(index, 0), all.count - 1)]
    }
}

/// One of the grid's numbers, as a person reads it: whole where the number is
/// whole and to the half point where it is not, because a readout that quietly
/// rounded would be a lie about the grid it is describing.
public enum CanvasGridNumber {
    public static func text(_ value: CGFloat) -> String {
        guard value.isFinite else { return "0" }
        let rounded = (value * 2).rounded() / 2
        if rounded == rounded.rounded() { return String(Int(rounded.rounded())) }
        return String(format: "%.1f", Double(rounded))
    }
}

/// Where the grid starts, as a person reads it: two numbers, in the same
/// wording as every other number the grid shows.
public enum CanvasGridOriginLabel {
    public static func text(_ point: CGPoint) -> String {
        "\(CanvasGridNumber.text(point.x)), \(CanvasGridNumber.text(point.y))"
    }
}

/// What the grid's controls are called, and what each of its numbers actually
/// does, in the words a person reads.
///
/// The wording lives here rather than in a view because the SAME controls are
/// drawn in two places — the settings popover the grid itself opens, and the
/// Canvas section of the panel — and two copies of a sentence drift. It is
/// also the only part of the grid a test can hold to a standard: every caption
/// says what the number DOES, not what it is called again.
public enum CanvasGridCopy {
    /// "Show grid", not "Grid": it sits directly above "Snap to grid", it is
    /// the same switch as View \u{25B8} Show Grid, and under a popover titled
    /// Grid a checkbox also called Grid reads as the app stuttering.
    public static let grid = "Show grid"
    public static let gridCaption = "Draw the grid over the picture so you can build to it."

    public static let snap = "Snap to grid"
    public static let snapCaption =
        "Dragging pulls to the nearest line you can see, and the arrow keys step by those lines. "
        + "Hold Command to get away from it."

    public static let lines = "Lines"
    public static let linesCaption = "Up and down only, or both ways like graph paper."

    public static let spacing = "Spacing"
    public static let spacingCaption = "How far apart the lines are, in points."

    public static let majorEvery = "Bold every"
    public static let majorEveryCaption =
        "Draw every Nth line stronger, so you can count cells without measuring."

    public static let minimumCell = "Smallest cell"
    public static let minimumCellCaption =
        "The finest cell the grid will ever draw, however far you zoom in. "
        + "Set it to 8 and you are working in eights."

    /// The mode's own readout. Not a panel row any more: where the grid starts
    /// is set by taking the canvas over, so the number lives beside the two
    /// markers that are placing it.
    public static let origin = "Grid starts at"

    /// The button on the tool bar that takes the canvas over, and the same
    /// thing on the View menu.
    public static let adjust = "Adjust Grid"
    public static let adjustMenuItem = "Adjust Grid\u{2026}"
    public static let adjustHelp =
        "Place where the grid starts, and pin guides onto it."

    /// The one line inside the mode. Everything the mode does, in the order a
    /// person meets it, because none of it is guessable from an empty canvas
    /// with two accent lines on it.
    public static let adjustHint =
        "Click a line to pin a guide. Drag the dot to move where the grid starts."

    public static let clearGuides = "Clear Guides"
    public static let clearGuidesHelp = "Take every pinned guide off this picture."

    /// The cell the slider drives, on the tool bar and in the mode.
    public static let cell = "Cell"
    public static let cellHelp =
        "The cell you are working to. The grid never draws finer than this, so a drag lands on it."

    /// The one line under the controls, in both places they are drawn.
    public static let footnote =
        "Zoom out and the fine lines fade away, zoom in and they come back, so the grid stays readable. "
        + "It is drawn on the canvas, never into the picture."

    /// Said under the Spacing field when the canvas cannot draw the spacing
    /// that was asked for and is drawing a coarser rung instead. It names both
    /// numbers, because the whole complaint was that only one of them was ever
    /// on screen.
    public static func liveSpacingNote(set: CGFloat, live: CGFloat, snaps: Bool) -> String {
        let setText = CanvasGridNumber.text(set)
        let liveText = CanvasGridNumber.text(live)
        let pull = snaps ? ", and a drag lands on those" : ""
        // Two lines in the popover, not three: the first says what is on
        // screen, the second says how to get what was asked for.
        return "Showing \(liveText) pt lines at this zoom" + pull
            + ". Zoom in for \(setText) pt."
    }

    /// What the button that opens all of this is called, on the View menu.
    public static let settingsMenuItem = "Grid Settings\u{2026}"
    /// The title over the settings when they are opened from the canvas.
    public static let settingsTitle = "Grid"

    /// Every caption, for a test that holds them all to the same standard.
    public static let captions = [gridCaption, snapCaption, linesCaption, spacingCaption,
                                  majorEveryCaption, minimumCellCaption, footnote]
}

