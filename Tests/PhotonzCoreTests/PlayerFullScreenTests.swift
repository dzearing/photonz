import Foundation
import Testing
@testable import PhotonzCore

// F fills the screen with the video you are watching, the way a player does,
// and View ▸ Enter Full Screen carries the Mac's own ⌃⌘F everywhere. Asked for
// on 2026-10-11: "the video's fullscreen feature lists ctrl-cmd-f as the
// shortcut but that does not work. and it's a bad shortcut. i expected 'f' to
// just fullscreen it but it puts it into edit mode".
@Suite("Full screen for a player")
struct PlayerFullScreenKeyTests {

    private func press(_ key: TimelineKey, _ modifiers: TimelineKeyModifiers = [],
                       repeating: Bool = false) -> TimelineKeyPress {
        TimelineKeyPress(key: key, modifiers: modifiers, isRepeat: repeating)
    }

    @Test("F while watching toggles full screen, in and out")
    func fToggles() {
        #expect(PlayerFullScreen.command(for: press(.letter("f")), watching: true, isFullScreen: false) == .toggle)
        #expect(PlayerFullScreen.command(for: press(.letter("f")), watching: true, isFullScreen: true) == .toggle)
    }

    @Test("F in the editor is left to the Frame tool")
    func fInTheEditorIsTheFrameTool() {
        #expect(PlayerFullScreen.command(for: press(.letter("f")), watching: false, isFullScreen: false) == nil)
        #expect(PlayerFullScreen.command(for: press(.letter("f")), watching: false, isFullScreen: true) == nil)
    }

    @Test("Escape leaves full screen while watching, and only then")
    func escapeLeaves() {
        #expect(PlayerFullScreen.command(for: press(.escape), watching: true, isFullScreen: true) == .leave)
        // Not full screen: Escape carries on to whatever had it before.
        #expect(PlayerFullScreen.command(for: press(.escape), watching: true, isFullScreen: false) == nil)
        // The editor's Escape lets go of a pick and clears marks.
        #expect(PlayerFullScreen.command(for: press(.escape), watching: false, isFullScreen: true) == nil)
    }

    @Test("a held F does not flicker the window in and out")
    func heldFIsOnePress() {
        #expect(PlayerFullScreen.command(for: press(.letter("f"), repeating: true),
                                         watching: true, isFullScreen: false) == nil)
    }

    @Test("F with a modifier is somebody else's chord")
    func chordsAreNotF() {
        for modifiers: TimelineKeyModifiers in [.command, .shift, .option, .control, [.control, .command]] {
            #expect(PlayerFullScreen.command(for: press(.letter("f"), modifiers),
                                             watching: true, isFullScreen: false) == nil)
        }
    }

    @Test("no other key is full screen's")
    func otherKeys() {
        for key: TimelineKey in [.letter("e"), .letter("k"), .space, .left] {
            #expect(PlayerFullScreen.command(for: press(key), watching: true, isFullScreen: true) == nil)
        }
    }

    @Test("F is not a key the timeline already answers")
    func fIsFreeOnTheTimeline() {
        // The player reads F before the timeline does, so if the timeline ever
        // took F for something (Premiere's Match Frame) this would hide it.
        #expect(TimelineKeys.command(for: press(.letter("f")), timelineFocused: true, kHeld: false) == nil)
    }

    @Test("the menu row says what a pick will do")
    func menuTitles() {
        #expect(PlayerFullScreen.menuTitle(isFullScreen: false) == "Enter Full Screen")
        #expect(PlayerFullScreen.menuTitle(isFullScreen: true) == "Exit Full Screen")
    }

    @Test("the transport button's tip names F")
    func tooltip() {
        #expect(PlayerFullScreen.tooltip == "Full Screen (F)")
    }
}

@Suite("A walk checks full screen")
struct PlayerFullScreenWalkClaimTests {

    @Test("expectTimeline claims the window fills the screen, and the transport is tucked away")
    func claims() throws {
        let script = try PlaytestScript.decode(Data("""
        { "steps": [ { "do": "expectTimeline", "fullScreen": true },
                     { "do": "expectTimeline", "controlsTucked": false } ] }
        """.utf8))
        guard case .expectTimeline(let first) = script.steps[0],
              case .expectTimeline(let second) = script.steps[1] else {
            Issue.record("expectTimeline"); return
        }
        #expect(first.fullScreen == true)
        #expect(first.claimsSomething)
        #expect(second.controlsTucked == false)
        #expect(second.claimsSomething)
        #expect(PlaytestTimelineClaim().fullScreen == nil)
        #expect(PlaytestTimelineClaim().controlsTucked == nil)
    }

    @Test("expectTimeline claims the faded controls hide the pointer")
    func pointerHidden() throws {
        let script = try PlaytestScript.decode(Data("""
        { "steps": [ { "do": "expectTimeline", "pointerHidden": true } ] }
        """.utf8))
        guard case .expectTimeline(let claim) = script.steps[0] else {
            Issue.record("expectTimeline"); return
        }
        #expect(claim.pointerHidden == true)
        #expect(claim.claimsSomething)
        #expect(PlaytestTimelineClaim().pointerHidden == nil)
    }
}
