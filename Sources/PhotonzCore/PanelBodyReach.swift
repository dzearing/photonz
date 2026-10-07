import CoreGraphics

/// Which of the dock's sections have their settings built, and which wait
/// under their header as an empty space of the same height until somebody
/// scrolls near them.
///
/// On a video the dock is long: a clip's twelve sections stand about 2200pt
/// tall in a 600pt view. Every one of them used to be built, and that cost
/// nothing while the clip stayed picked. It cost when the clip was let go: a
/// click on a cut takes nine of those sections away in its own frame, and
/// pulling down a section is paid for control by control (every text field,
/// slider and dropdown leaves AppKit and the accessibility tree one at a
/// time). The four of them below the fold, Audio Fades, Audio Gain, Audio
/// Effects and Captions, were about 12ms of a 67ms cut that nobody had ever
/// looked at (`clip-click-cost-walk`, 2026-10-07, interleaved runs).
///
/// So a section that ARRIVES starting further below the bottom of the dock
/// than `reach` waits. Nothing else does:
/// - the top section, and any section whose neighbour above has not been
///   placed yet (a window opening places nothing, so it builds everything, as
///   it always has);
/// - a section already built, wherever it goes. Edit point, built at the top
///   when a cut is picked and carried down to 974pt by the next clip pick,
///   stays built, so the cut after that finds it already there. Holding it
///   too was measured and is worse: the cut then has to BUILD three sections
///   in its frame, and that cost more than the teardown it saved.
///
/// A waiting section is built once it comes within `reach` of the view, the
/// topmost first, one per pass (`nextToBuild`), and then stays built until it
/// leaves the dock.
///
/// Section ids are plain strings, as in `PanelSectionArrival`.
public struct PanelBodyReach: Sendable, Equatable {
    /// How far below the bottom of the view a section may start and still be
    /// built straight away. A little under a section's height, so a slow
    /// scroll meets a section that is already there.
    public static let reach: CGFloat = 120

    /// The sections waiting to be built.
    public private(set) var held: Set<String> = []
    /// The sections the dock drew last pass, in order.
    private var drawn: [String] = []

    public init() {}

    /// The sections the dock is drawing this pass, in order.
    ///
    /// - Parameters:
    ///   - bottoms: where each section drawn last pass ended, measured from
    ///     the top of the view. A new section starts where the one above it
    ///     ended, as long as that one was already in the dock last pass.
    ///   - viewport: how tall the view is, nil until it has been measured.
    public mutating func draw(_ sections: [String], bottoms: [String: CGFloat], viewport: CGFloat?) {
        let before = Set(drawn)
        held.formIntersection(sections)
        for (index, id) in sections.enumerated() where !before.contains(id) {
            guard index > 0, let viewport, viewport > 0 else { continue }
            let above = sections[index - 1]
            guard before.contains(above), let top = bottoms[above] else { continue }
            if top > viewport + Self.reach { held.insert(id) }
        }
        drawn = sections
    }

    public func isHeld(_ id: String) -> Bool { held.contains(id) }

    /// True when a waiting section, measured starting at `top`, has come
    /// within reach of the view and should be built.
    public func comesNear(_ id: String, top: CGFloat, viewport: CGFloat) -> Bool {
        held.contains(id) && viewport > 0 && top <= viewport + Self.reach
    }

    /// Of the waiting sections in `near`, the one highest in the dock.
    public func nextToBuild(among near: Set<String>) -> String? {
        drawn.first { held.contains($0) && near.contains($0) }
    }

    public mutating func build(_ id: String) { held.remove(id) }

    public mutating func buildAll() { held.removeAll() }

    // MARK: Rows inside a section

    /// How long rows built inside a section stay built once they are out of
    /// reach. A big section's late rows (Captions' styles, colours and timing,
    /// `PanelRowsArrival`) are let go when a pick has carried them far below
    /// the fold and nothing has brought them back for this long, so that the
    /// next click, the one that takes the section away, has nothing of theirs
    /// to pull down. Long enough that a scroll past them does not throw them
    /// away and build them again, short enough to be over before the click
    /// after a pick.
    public static let letGoAfter: Double = 0.5

    /// Whether something standing from `top` to `bottom`, in a view `viewport`
    /// tall measured from its top edge, is within `reach` of being seen.
    public static func isWithinReach(top: CGFloat, bottom: CGFloat, viewport: CGFloat) -> Bool {
        top <= viewport + reach && bottom >= -reach
    }
}
