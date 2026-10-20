import Testing
@testable import PhotonzCore

/// Asking always shows the Agent group with its new row (the user,
/// 2026-10-20: "when i ask something, but the left pane is minimized or a
/// video is not in edit mode, we need to reveal what we need to in order for
/// the agent pane to be visible"). The panel comes out for this window only:
/// the person's own choice of a closed panel is what the next window gets.
@Suite("What an ask brings out so the Agent group is seen")
struct AskRevealTests {

    @Test("A picture with the panel open: nothing to bring out, the group is opened and scrolled to")
    func openPanelNeedsNothing() {
        let reveal = AskReveal.plan(watching: false, panelOut: true)
        #expect(!reveal.switchesToEdit)
        #expect(!reveal.bringsPanelOut)
        #expect(reveal.opensAgentGroup)
    }

    @Test("The panel closed: it comes out")
    func closedPanelComesOut() {
        let reveal = AskReveal.plan(watching: false, panelOut: false)
        #expect(!reveal.switchesToEdit)
        #expect(reveal.bringsPanelOut)
        #expect(reveal.opensAgentGroup)
    }

    @Test("A video in View switches to Edit, the one mode with a panel, and its panel stays as it was left")
    func viewSwitchesToEdit() {
        let reveal = AskReveal.plan(watching: true, panelOut: true)
        #expect(reveal.switchesToEdit)
        #expect(!reveal.bringsPanelOut)
    }

    @Test("A video in View with its panel closed: Edit and the panel both")
    func viewWithClosedPanel() {
        let reveal = AskReveal.plan(watching: true, panelOut: false)
        #expect(reveal.switchesToEdit)
        #expect(reveal.bringsPanelOut)
    }

    @Test("Bringing the panel out never writes the person's choice for the next window")
    func neverRemembered() {
        for watching in [false, true] {
            for out in [false, true] {
                #expect(!AskReveal.plan(watching: watching, panelOut: out).remembersPanelChoice)
            }
        }
    }
}
