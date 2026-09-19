import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// A locked Mac takes the NAME off every control, which is how a walk finds
/// one. It does not stop the app being drawn, driven or photographed: a walk
/// run under a lock on 2026-09-17 dragged shapes out, measured them and wrote
/// six real pictures of the window.
///
/// So the question "may this walk run with the screen locked" has an answer,
/// and it is per step: a walk built out of clicks, drags, keys, snapshots and
/// the app's own control registry runs perfectly, while one that asks
/// accessibility for a field or opens a panel menu cannot find anything.
///
/// This is the part of that which can be decided without an app, off the walk
/// alone, so a walk knows before it launches whether its answer would be worth
/// anything.
@Suite("Which walks can run with the screen locked")
struct PlaytestLockSafetyTests {

    @Test("A walk of clicks, drags and snapshots runs under a lock")
    func plainWalkRuns() {
        let steps: [PlaytestStep] = [
            .blank(canvas: CGSize(width: 800, height: 600), window: nil, card: nil, pixelScale: 1),
            .click(PlaytestPoint(CGPoint(x: 100, y: 100), space: .window), count: 1, modifiers: []),
            .drag(from: PlaytestPoint(CGPoint(x: 10, y: 10)), to: PlaytestPoint(CGPoint(x: 90, y: 90)),
                  steps: 8, modifiers: [], halfway: nil, hold: nil, readout: nil,
                  wobble: 0, cancel: false, showsBox: nil),
            .snapshot(name: "a-drawn", window: nil),
        ]
        #expect(PlaytestLockSafety.nameLookups(in: steps).isEmpty)
        #expect(PlaytestLockSafety.canRunLocked(steps))
        #expect(PlaytestLockSafety.refusal(for: steps) == nil)
    }

    @Test("A walk that types into a field by name cannot")
    func focusCannot() {
        let steps: [PlaytestStep] = [
            .snapshot(name: "a-start", window: nil),
            .focus(field: "Corner radius"),
            .type("12"),
        ]
        let blocked = PlaytestLockSafety.nameLookups(in: steps)
        #expect(blocked.count == 1)
        #expect(blocked.first?.step == 2)
        #expect(blocked.first?.name == "focus")
        #expect(!PlaytestLockSafety.canRunLocked(steps))
    }

    @Test("The refusal names the first step that needs a name and what is still there to photograph")
    func refusalSaysWhatIsLost() {
        let steps: [PlaytestStep] = [
            .snapshot(name: "a-start", window: nil),
            .snapshot(name: "b-styled", window: nil),
            .panelMenu(menu: "Add Effect", in: nil, shot: nil, choose: "Shadow", clicking: nil),
            .snapshot(name: "c-shadow", window: nil),
        ]
        let said = PlaytestLockSafety.refusal(for: steps)
        #expect(said?.contains("step 3 (panelMenu)") == true)
        // What a runner decides with: forcing it still gets the first two.
        #expect(said?.contains("2 of its 3 pictures") == true)
    }

    @Test("Waiting on a tutorial card cannot run: the login window is over it")
    func tutorialCardsCannot() {
        #expect(PlaytestLockSafety.lockTrouble(with: .waitFor(.tutorialStep("put-it-back"), timeout: 5)) != nil)
        #expect(PlaytestLockSafety.lockTrouble(with: .waitFor(.tutorialFinished("redline"), timeout: 5)) != nil)
        #expect(PlaytestLockSafety.lockTrouble(with: .startGuide("redline", window: nil)) != nil)
        #expect(PlaytestLockSafety.lockTrouble(with: .expectTutorialStep("put-it-back")) != nil)
        // ...while every other thing a walk waits for is read off the app itself.
        #expect(PlaytestLockSafety.lockTrouble(with: .waitFor(.sectionInView("Effects"), timeout: 5)) == nil)
        #expect(PlaytestLockSafety.lockTrouble(with: .waitFor(.dialog("Export", up: true), timeout: 5)) == nil)
    }

    @Test("Pressing and reading a control by name is fine: those names are the app's own")
    func registryNamesSurvive() {
        #expect(PlaytestLockSafety.lockTrouble(with: .press(control: "Add Layer", in: nil, count: 1, modifiers: [], across: nil)) == nil)
        #expect(PlaytestLockSafety.lockTrouble(with: .selectRow(row: "Background", modifiers: [])) == nil)
    }

    @Test("Every step kind has a verdict, so a new one cannot slip through unjudged")
    func everyStepKindIsJudged() {
        let judged = PlaytestLockSafety.stepsThatSurviveALock
            .union(PlaytestLockSafety.stepsALockStops)
        #expect(judged == Set(PlaytestStep.names))
        // and nothing is claimed both ways
        #expect(PlaytestLockSafety.stepsThatSurviveALock
            .isDisjoint(with: PlaytestLockSafety.stepsALockStops))
    }

    @Test("A picture taken under a lock carries the label that says so")
    func labelSaysWhatItCostsToPhotographUnderALock() {
        let label = PlaytestLockSafety.pictureLabel
        #expect(label.contains("locked"))
        // the two known costs, so nobody reads a dimmed colour as a bug
        #expect(label.lowercased().contains("colour") || label.lowercased().contains("color"))
        #expect(label.contains("tutorial"))
    }

    /// Writing a file is not looking at the screen. `writePicture` renders the
    /// document offscreen and encodes it, exactly as `writeSVG` does, and it
    /// was refused only because nobody had watched it. Watched on 2026-09-17
    /// under a three-day lock: `png-export-size-walk` wrote both PNGs and
    /// weighed them, 21396 bytes with nothing behind the drawing and 22069
    /// with the canvas in. That un-refuses `png-export-background-walk` too,
    /// which is a walk about the very same box.
    @Test("Writing a picture to disk needs no name, so a lock cannot stop it")
    func writingAPictureRunsUnderALock() {
        #expect(PlaytestLockSafety.stepsThatSurviveALock.contains("writePicture"))
        #expect(!PlaytestLockSafety.stepsALockStops.contains("writePicture"))
    }

    /// Writing a RECORDING to disk is the same kind of thing: it hands the
    /// exporter the open recording and then opens the file that landed to read
    /// its length and its pixel size. No name is asked for at any point.
    /// Watched on 2026-09-19 under a lock: `recording-export-sheet-walk` ran
    /// all 55 of its steps, three of them `writeRecording`, and each read back
    /// the right thing — 8.0s at 1280 × 800 byte for byte the recording, then
    /// 4.0s at 640 × 400 re-encoded, then a 40 frame GIF at 480 × 300.
    @Test("Writing a recording to disk needs no name, so a lock cannot stop it")
    func writingARecordingRunsUnderALock() {
        #expect(PlaytestLockSafety.stepsThatSurviveALock.contains("writeRecording"))
        #expect(!PlaytestLockSafety.stepsALockStops.contains("writeRecording"))
    }

    /// `expectRecording` asks the open recording what it is made of — how many
    /// pieces, which one is picked, how long the trim window is, whether the
    /// handles are open. Every one of those is read off the app's own state,
    /// and none of them is a name, so a lock has nothing to take away. It was
    /// refused only because nobody had watched it. Watched on 2026-09-17 under
    /// a lock: `undo-while-trimming-walk` ran all 35 of its steps, three of
    /// them `expectRecording`, and the readings were right each time ("3
    /// pieces, piece 2 picked, window 8.00s, trim open"). That un-refuses the
    /// five video walks whose only blocked step was this one.
    @Test("Asking what the recording is made of needs no name, so a lock cannot stop it")
    func readingTheRecordingRunsUnderALock() {
        #expect(PlaytestLockSafety.stepsThatSurviveALock.contains("expectRecording"))
        #expect(!PlaytestLockSafety.stepsALockStops.contains("expectRecording"))
        let steps: [PlaytestStep] = [
            .action(.openSampleRecording),
            .action(.videoBeginTrim),
            .expectRecording(pieces: 3, picked: 2, keeps: nil, seconds: nil,
                             starts: nil, caught: nil),
            .snapshot(name: "a-trimming", window: nil),
        ]
        #expect(PlaytestLockSafety.nameLookups(in: steps).isEmpty)
        #expect(PlaytestLockSafety.canRunLocked(steps))
    }

    /// A `menus` step is still refused, and the reason it gave was wrong. It
    /// used to say it "opens a real menu", which it does not: it reads
    /// `NSApp.mainMenu` inside the app's own process and never pops anything
    /// up. That sent a runner on 2026-09-19 to read the harness source to find
    /// out what the real objection was, on a task whose whole job was reading
    /// one menu.
    ///
    /// The real objection is the frozen menu bar. A walk never brings the probe
    /// to the front, so the only thing that ever gives it a live menu is one of
    /// its own windows taking key. A locked Mac gives nothing key: forced on
    /// 2026-09-19, `save-is-live-after-a-trim-walk` opened the Capture History
    /// overlay as usual and the menu reading still came back "nothing in the
    /// probe has focus", which is the step admitting its own answer is worth
    /// nothing. So what is dimmed reads dimmed whatever the document says.
    @Test("A menus step is refused for the frozen menu bar, not for opening a menu")
    func menusIsRefusedForTheRightReason() {
        let why = PlaytestLockSafety.lockTrouble(with: .menus(stage: "file", menu: "File"))
        #expect(why != nil)
        #expect(why?.contains("opens a real menu") == false)
        // it names what actually goes wrong: nothing can take key, so every
        // window command reads dimmed
        #expect(why?.contains("key") == true)
        #expect(why?.contains("dimmed") == true)
        // ...while the three that really do put a menu on screen keep that reason
        for step in [PlaytestStep.menuShot(menu: "File", name: "a-file", ticked: [], unticked: []),
                     .rightClick(on: "Background", at: nil, shot: nil, choose: nil,
                                 ticked: [], unticked: [])] {
            #expect(PlaytestLockSafety.lockTrouble(with: step)?.contains("opens a real menu") == true)
        }
    }
}
