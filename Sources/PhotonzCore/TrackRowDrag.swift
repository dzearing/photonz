import CoreGraphics
import Foundation

/// A track carried up or down the timeline by its header, the same physical
/// way a row of the layers list is carried (`LayerRowDrag`), and drawn by the
/// same lift (`RowLift`): the track lifts and rides the pointer, the tracks
/// around it move out of its way, and the gap they leave IS where it will
/// land. What is the timeline's own is where a place under the pointer lands.
///
/// Tracks are not all one height (a sound lane is taller, and a track draws
/// the lanes of whatever moves on its clips under it), so every row carries
/// its own top and height, measured in the tracks' own points, top down. The
/// gap is the carried track's own height.
///
/// Where it lands is read from which HALF of which row the pointer is over, as
/// the timeline is drawn right now, gap and all (the user's rule for the
/// layers list, 2026-09-30):
///
/// - the top half of a track puts it above that track, the bottom half below
///   it, in that track's group if it is in one;
/// - the top half of a group's heading puts it above the group, outside it;
///   the bottom half of an OPEN group's heading is the group's first slot,
///   and of a folded one is under the whole group;
/// - so at the foot of an open group, the bottom half of its last track keeps
///   it inside, and the top half of the row under the group puts it outside.
///   Both open the same gap; what tells them apart is how far in it is drawn.
///
/// A pointer over the gap changes nothing, so a track swaps once as the
/// pointer crosses the middle of its neighbour and never flickers back.
public struct TrackRowDrag: Equatable, Sendable {

    /// One row of the timeline as it is laid out.
    public struct Row: Equatable, Sendable {
        public enum Kind: Equatable, Sendable {
            /// A track, in a group or not.
            case track(group: UUID?)
            /// A group's heading, open with its tracks under it or folded.
            case heading(isOpen: Bool)
        }

        public var id: UUID
        public var top: CGFloat
        public var height: CGFloat
        public var kind: Kind

        public init(id: UUID, top: CGFloat, height: CGFloat, kind: Kind) {
            self.id = id
            self.top = top
            self.height = height
            self.kind = kind
        }

        /// The group this row's track sits in, nil for a heading or a loose
        /// track.
        public var group: UUID? {
            if case .track(let group) = kind { return group }
            return nil
        }
    }

    /// The track under the pointer when the drag began.
    public let grabbedID: UUID
    /// The rows the timeline is showing, top down, exactly as laid out.
    public let rows: [Row]
    /// Every row left standing: what the gap opens between.
    public let rest: [Row]
    /// The group the gap would put the track in, which is how far in it is
    /// drawn.
    public private(set) var gapGroup: UUID?
    /// Where letting go would put the track, nil while the gap is still the
    /// one it left.
    public private(set) var landing: TrackLanding?
    /// Where everything is drawn, the same lift the layers list uses
    /// (`RowLift`).
    private var lift: RowLift

    /// The row in the air.
    public let grabbed: Row
    /// The space between two rows.
    public var spacing: CGFloat { lift.spacing }
    /// Where the gap sits when the track is back where it came from.
    public var homeGap: Int { lift.homeGap }
    /// Where the gap is now, counted in rows of `rest`: 0 is above the first.
    public var gap: Int { lift.gap }
    /// The pointer, in the tracks' points.
    public var pointerY: CGFloat { lift.pointerY }
    /// How far below the track's top edge the pointer took hold of it.
    public var grabOffset: CGFloat { lift.grabOffset }

    /// Picks `grabbing` up with the pointer at `pointerY`. Nil when there is
    /// nothing to carry it past, or when it is not a track on the timeline.
    public init?(grabbing: UUID, rows: [Row], spacing: CGFloat, pointerY: CGFloat) {
        guard let grabbed = rows.first(where: { $0.id == grabbing }),
              case .track = grabbed.kind,
              let lift = RowLift(grabbing: grabbing,
                                 rows: rows.map { RowLift.Row(id: $0.id, top: $0.top, height: $0.height) },
                                 spacing: spacing, pointerY: pointerY) else { return nil }
        self.grabbedID = grabbing
        self.grabbed = grabbed
        self.rows = rows
        self.rest = rows.filter { $0.id != grabbing }
        self.lift = lift
        self.gapGroup = grabbed.group
    }

    // MARK: - Where things are drawn

    /// Where the gap's top edge is drawn.
    public var gapTop: CGFloat { lift.gapTop }

    /// How tall the gap is: the carried track's own height.
    public var gapHeight: CGFloat { lift.gapHeight }

    /// Where the lifted track's top edge is drawn: under the pointer, and
    /// never past the first or last place a track could stand.
    public var liftedTop: CGFloat { lift.liftedTop }

    /// How far a standing row is drawn from where the timeline laid it out.
    /// Zero for the carried track, which is drawn lifted instead.
    public func offset(of id: UUID) -> CGFloat { lift.offset(of: id) }

    // MARK: - Moving

    /// The pointer moved.
    public mutating func move(pointerY: CGFloat) {
        lift.pointerY = pointerY
        guard let (landing, gap, group) = reading(pointerY) else { return }
        self.landing = landing
        lift.gap = gap
        gapGroup = group
    }

    /// What the pointer at `y` is asking for, as drawn now: nil while it is
    /// over the gap, which changes nothing.
    private func reading(_ y: CGFloat) -> (TrackLanding, Int, UUID?)? {
        guard let first = rest.first, let last = rest.last else { return nil }
        switch lift.spot(y) {
        case .gap:
            return nil
        case .aboveAll:
            // The very top, in nothing.
            return (.above(first.id), 0, nil)
        case .pastAll:
            // The very bottom, outside any group.
            if let group = last.group { return (.below(group), rest.count, nil) }
            return (.below(last.id), rest.count, nil)
        case .row(let standing, let upper):
            let row = rest[standing]
            switch row.kind {
            case .track(let group):
                return upper ? (.above(row.id), standing, group) : (.below(row.id), standing + 1, group)
            case .heading(let isOpen):
                if upper { return (.above(row.id), standing, nil) }
                return isOpen ? (.inside(row.id), standing + 1, row.id) : (.below(row.id), standing + 1, nil)
            }
        }
    }

    /// Called off: the gap goes back to the slot the track came from, and
    /// letting go now changes nothing.
    public mutating func returnHome() {
        landing = nil
        lift.gap = homeGap
        gapGroup = grabbed.group
    }
}
