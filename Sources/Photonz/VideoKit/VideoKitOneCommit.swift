import QuartzCore

extension CATransaction {
    /// Layer changes made in `body`, without animation, carried by the commit
    /// this turn of the main run loop makes anyway, rather than by a commit of
    /// their own.
    ///
    /// A `begin` with no transaction open is a transaction of its own, and its
    /// `commit` is a message to the window server right then. While a hand
    /// scrubbed the 6 minute reference edit the canvas's picture and the four
    /// pieces that follow the playhead (the line across the tracks, the scrub
    /// bar, the time, the scroller's mark) each made one, five a refresh on
    /// top of the window's own; the window server let one of them wait 8 to
    /// 30 ms every drag or so, and the picture fell 3 to 5 refreshes behind
    /// the hand (`scrubbing-a-long-edit-never-trails-the-pointer-b`). Asking
    /// for the turn's own transaction first (setting one of its values to what
    /// it already is opens it) makes the `begin` here a nested one, whose
    /// changes wait for the turn's commit with everything else.
    @MainActor static func inThisTurnsCommit(_ body: () -> Void) {
        setDisableActions(disableActions())
        begin()
        setDisableActions(true)
        body()
        commit()
    }
}
