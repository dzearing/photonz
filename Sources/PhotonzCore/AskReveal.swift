/// What an ask brings out so the person sees the Agent group and its new row
/// (`docs/design/ask.md`, the user 2026-10-20: "when i ask something, but the
/// left pane is minimized or a video is not in edit mode, we need to reveal
/// what we need to in order for the agent pane to be visible").
///
/// A video in View is switched to Edit rather than given a panel in View:
/// View is for watching and has no panel at all, and an ask is an edit, the
/// same rule every other edit made in View follows. The panel comes out for
/// this window only, so a person who keeps it closed still gets a closed one
/// in their next window, and closing it again is remembered as before.
public struct AskReveal: Equatable, Sendable {
    /// The window leaves View for Edit.
    public let switchesToEdit: Bool
    /// The panel comes out.
    public let bringsPanelOut: Bool
    /// The Agent group is unfolded and scrolled into view. Always.
    public let opensAgentGroup: Bool
    /// Whether bringing the panel out is written as the person's choice for
    /// new windows. Never: only their own show or hide is.
    public let remembersPanelChoice: Bool

    /// - Parameters:
    ///   - watching: a video is in View.
    ///   - panelOut: the panel would be on screen in Edit (not closed by the
    ///     person, not taken away by a narrow window).
    public static func plan(watching: Bool, panelOut: Bool) -> AskReveal {
        AskReveal(switchesToEdit: watching, bringsPanelOut: !panelOut,
                  opensAgentGroup: true, remembersPanelChoice: false)
    }
}
