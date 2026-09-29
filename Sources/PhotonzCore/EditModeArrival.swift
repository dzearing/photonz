/// The order the editor arrives in when Edit mode comes to a recording that
/// was open in View (`ViewEditMode`).
///
/// Building all of it in the pass that answers the key held a five minute
/// captioned recording's window for about 190ms on 2026-09-28, so the slide
/// stuttered before it started: the panel was about 110ms of that, the tracks
/// about 60, the tool bar about 30. Each piece is quick on its own, so the
/// editor comes in over a few passes while it is still sliding, one heavy
/// piece to a pass:
///
/// 1. the key pass: the mode flips and the frames start moving, the
///    timeline's bar over an empty space the tracks' height, the panel's
///    empty body;
/// 2. the ruler, the playhead and the tracks' scroller, and the tool bar;
/// 3. the rows of the tracks;
/// 4. the panel's sections, one a pass, top down (`DockArrival`).
///
/// A pass is about a frame, and everything is on its way in from an edge
/// while this happens, so nobody sees the order; they see a slide that starts
/// when they press the key.
public enum EditModeArrival: Int, Sendable, Hashable, CaseIterable {
    case keyPass
    case timeline
    case trackRows
    case panelSections

    /// Where an arrival starts.
    public static let start = EditModeArrival.keyPass
    /// Everything built: a window that is not arriving.
    public static let settled = EditModeArrival.panelSections

    /// The next pass's stage, nil once everything is in.
    public var next: EditModeArrival? { EditModeArrival(rawValue: rawValue + 1) }

    /// The ruler, the playhead and the tracks' scroller.
    public var showsTimeline: Bool { self >= .timeline }
    public var showsToolBar: Bool { self >= .timeline }
    public var showsTrackRows: Bool { self >= .trackRows }
    public var panelMayFill: Bool { self >= .panelSections }
}

extension EditModeArrival: Comparable {
    public static func < (lhs: EditModeArrival, rhs: EditModeArrival) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
