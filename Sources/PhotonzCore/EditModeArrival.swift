/// The order the editor arrives in when Edit mode comes to a recording that
/// was open in View (`ViewEditMode`).
///
/// Building all of it in the pass that answers the key held a five minute
/// captioned recording's window for about 190ms on 2026-09-28, so the slide
/// stuttered before it started: the panel was about 110ms of that, the tracks
/// about 60, the tool bar about 30. Each piece is quick on its own, so the
/// editor comes in over a few passes, one heavy piece to a pass:
///
/// 1. the key pass: the mode flips and the frames start moving, the
///    timeline's bar over an empty space the tracks' height, the panel's
///    empty body;
/// 2. the ruler, the playhead and the tracks' scroller, and the tool bar;
/// 3. the rows of the tracks;
/// 4. the panel's sections, one a pass, top down (`DockArrival`).
///
/// The key pass is the only one the slide carries. Building the rest while
/// the frames moved cost every pass its frame and more: filmed on 2026-09-30,
/// the slide drew 8 or 9 pictures in its first 330ms, 90 to 120ms apart, while
/// the slide back to View drew one every 8 to 20. So the pieces after it wait
/// for the slide to land (`nextWaitsForTheSlide`) and then come in a pass
/// each, top of the tracks first, onto a window that has stopped moving: the
/// slide draws 23 to 26 pictures, never more than 20ms apart.
///
/// Waiting still left the tool bar, the rows and the panel coming in up to
/// 0.7s after the key (2026-10-02). So a recording open in View has Edit's
/// tool bar and tracks built BEHIND it, out of sight, a pass at a time once
/// the window has been still a moment, and keeps them for as long as it holds
/// the recording: Cmd-2 builds nothing for them and they come in with the
/// slide (`switchingToEdit`). The panel slides in empty and fills a section a
/// pass once the slide lands, unless `next-panel-with-the-slide` keeps it
/// built behind View too: a panel full of sections sliding in cost the slide
/// about half its pictures. Only a Cmd-2 that comes before the build behind
/// View has started still arrives over the passes above.
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

    /// Whether the stage after this one waits for the slide to land rather
    /// than coming in on the next pass.
    public var nextWaitsForTheSlide: Bool { self == .keyPass }

    /// Where Edit stands the moment the window switches into it, and whether
    /// the switch has to set the passes going itself (the window already
    /// stood at the start, so nothing watching for a change would notice).
    /// `current` is wherever the build behind View had got to.
    public static func switchingToEdit(hasTime: Bool, keptBehindView: Bool,
                                       current: EditModeArrival) -> (arrival: EditModeArrival, startsArriving: Bool) {
        guard hasTime else { return (.settled, false) }
        if keptBehindView { return (current, false) }
        return (.start, true)
    }

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
