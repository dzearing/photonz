import Foundation
import Testing
@testable import PhotonzCore

// While a video plays in View the controls fade away, QuickTime's way, and
// come back on a mouse move, a key or a pause; paused, they fade after a
// longer while. Asked for on 2026-11-25: "when in playback mode, and we start
// a video, i'd like the controls to fade out and only show up on mouse move or
// spacebar to pause", "when we're paused, they can also fade out after some
// time (5s?)" and "if themouse is over the controls they stay visible".
@Suite("The player's controls fade away")
struct PlayerControlsFadeTests {

    private func faded(watching: Bool = true, playing: Bool = true, idle: Double = 10,
                       overControls: Bool = false, held: Bool = false) -> Bool {
        PlayerControlsFade.faded(.init(watching: watching, playing: playing, secondsIdle: idle,
                                       pointerOverControls: overControls, held: held))
    }

    @Test("playing, they go about two seconds after the last thing a person did")
    func playingFadesAfterTwoSeconds() {
        #expect(PlayerControlsFade.secondsBeforeFadeWhilePlaying == 2)
        #expect(!faded(idle: 0))
        #expect(!faded(idle: 1.9))
        #expect(faded(idle: 2))
    }

    @Test("paused, they stay longer and go after about five seconds")
    func pausedFadesAfterFiveSeconds() {
        #expect(PlayerControlsFade.secondsBeforeFadeWhilePaused == 5)
        #expect(!faded(playing: false, idle: 2))
        #expect(!faded(playing: false, idle: 4.9))
        #expect(faded(playing: false, idle: 5))
    }

    @Test("with the pointer resting on them they stay, however long, playing or paused")
    func pointerOnThemKeepsThem() {
        #expect(!faded(idle: 600, overControls: true))
        #expect(!faded(playing: false, idle: 600, overControls: true))
    }

    @Test("a menu, popover, guide or a hand on the play bar holds them up")
    func heldKeepsThem() {
        #expect(!faded(idle: 600, held: true))
        #expect(!faded(playing: false, idle: 600, held: true))
    }

    @Test("the editor never fades anything")
    func editNeverFades() {
        #expect(!faded(watching: false, idle: 600))
        #expect(!faded(watching: false, playing: false, idle: 600))
    }

    @Test("fading out is a short ease and coming back is quicker, neither a cut")
    func fadeTimes() {
        #expect(PlayerControlsFade.fadeOutSeconds > 0.2 && PlayerControlsFade.fadeOutSeconds <= 0.5)
        #expect(PlayerControlsFade.fadeInSeconds > 0 && PlayerControlsFade.fadeInSeconds < PlayerControlsFade.fadeOutSeconds)
    }

    @Test("the pointer is looked at often enough that a move brings them back at once")
    func lookOften() {
        #expect(PlayerControlsFade.pointerLookSeconds <= 0.2)
    }

    @Test("the longest wait from the last move to gone is the wait plus a look plus the fade")
    func longestToGone() {
        #expect(PlayerControlsFade.secondsToFullyFaded(playing: true)
                == PlayerControlsFade.secondsBeforeFadeWhilePlaying + PlayerControlsFade.pointerLookSeconds
                    + PlayerControlsFade.fadeOutSeconds)
        #expect(PlayerControlsFade.secondsToFullyFaded(playing: false)
                == PlayerControlsFade.secondsBeforeFadeWhilePaused + PlayerControlsFade.pointerLookSeconds
                    + PlayerControlsFade.fadeOutSeconds)
    }
}
