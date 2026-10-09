import Foundation

/// When Undo or Redo on a video hands the pick to another clip a pass after
/// the step itself.
///
/// A step that moves the pick from one clip to another does two jobs in one
/// press: the timeline and the picture change, and the right hand panel
/// stops describing one clip and starts describing the other. The panel keeps
/// the sections the two have in common and refills every one of them, so the
/// second job alone cost about 20ms of a 50 to 56ms Redo (Redo of a cut with
/// Captions in hand, Redo of a b-roll clip let go on V1;
/// `undo-redo-cost-walk`, 2026-10-08). Done in the press's own pass the two
/// together held the window past the 50ms the Premiere goal sets.
///
/// So the step lands first, and the pick follows in the next pass, about a
/// frame later. Nobody sees the frame; what they see is a press that answers
/// at once. `PanelSectionArrival` does the same for sections new to the dock.
///
/// Only when both ends are real clips: the pick never stands on something the
/// step took away (Undo of a drop takes the b-roll away, and a pick left on it
/// for a frame would describe nothing), a pick from or to nothing already
/// costs the panel little, and several things coming back into hand is a band
/// pick, which this was never measured against.
public enum UndoPickFollows {

    /// True when the pick should move a pass after the step lands.
    ///
    /// - Parameters:
    ///   - from: what is in hand now.
    ///   - to: what the step puts back in hand.
    ///   - restoredMulti: everything the step puts back in hand, when it was
    ///     more than one thing.
    ///   - leavingStillStands: whether `from` is still in the document once the
    ///     step has landed.
    ///   - documentHasTime: a video, whose dock is the long one.
    public static func aPassLater(from: UUID?, to: UUID?, restoredMulti: Set<UUID>,
                                  leavingStillStands: Bool, documentHasTime: Bool) -> Bool {
        guard documentHasTime, restoredMulti.isEmpty,
              let from, let to, from != to else { return false }
        return leavingStillStands
    }
}
