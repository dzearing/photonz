import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// **Premiere's keys on the timeline** (`TimelineKeys.swift`).
///
/// A Premiere editor reaches for J/K/L, I/O, the arrows and ⌘K without looking.
/// Most of those letters are Photoshop tool keys here too, so which one a press
/// means depends on whether the timeline has the keyboard. These pin the map,
/// the shuttle's ladder and the edit points the up and down arrows walk.
///
/// Written before the keys, which is the rule for `PhotonzCore`.
@Suite("Premiere's keys on the timeline")
struct TimelineKeysTests {

    private func command(_ key: TimelineKey, _ modifiers: TimelineKeyModifiers = [],
                         focused: Bool = true, repeating: Bool = false,
                         kHeld: Bool = false) -> TimelineKeyCommand? {
        TimelineKeys.command(for: TimelineKeyPress(key: key, modifiers: modifiers, isRepeat: repeating),
                             timelineFocused: focused, kHeld: kHeld)
    }

    private func press(_ shuttle: inout TimelineShuttle, _ key: ShuttleKey) -> Double {
        shuttle.press(key)
    }

    private func clear(_ doc: inout PhotonzDocument, out: Bool) -> Bool {
        out ? doc.clearMarkOut() : doc.clearMarkIn()
    }

    // MARK: - The map

    @Test("Space plays and pauses wherever the keyboard is")
    func spacePlays() {
        #expect(command(.space, focused: true) == .playPause)
        #expect(command(.space, focused: false) == .playPause)
    }

    @Test("J, K and L shuttle on a focused timeline and nowhere else")
    func jklShuttle() {
        #expect(command(.letter("j")) == .shuttle(.reverse))
        #expect(command(.letter("k")) == .shuttle(.stop))
        #expect(command(.letter("l")) == .shuttle(.forward))
        // L is the Line tool and K the Lens when the canvas has the keyboard.
        #expect(command(.letter("l"), focused: false) == nil)
        #expect(command(.letter("k"), focused: false) == nil)
        #expect(command(.letter("j"), focused: false) == nil)
    }

    @Test("Holding K turns J and L into a frame at a time")
    func kInches() {
        #expect(command(.letter("l"), kHeld: true) == .stepFrames(1))
        #expect(command(.letter("j"), kHeld: true) == .stepFrames(-1))
        // Held down, the key repeats, and each repeat is one more frame:
        // that is the slow creep Premiere gives K+L.
        #expect(command(.letter("l"), repeating: true, kHeld: true) == .stepFrames(1))
        // A held L WITHOUT K does not speed the shuttle up on every repeat.
        #expect(command(.letter("l"), repeating: true) == nil)
    }

    @Test("Shift-K and Option-K are not Stop: they step between keys")
    func kChordsAreNotStop() {
        #expect(command(.letter("k"), .shift) == nil)
        #expect(command(.letter("k"), .option) == nil)
    }

    @Test("I and O mark, Option-I and Option-O clear")
    func inAndOut() {
        #expect(command(.letter("i")) == .markIn)
        #expect(command(.letter("o")) == .markOut)
        #expect(command(.letter("i"), focused: false) == nil)   // Measure
        #expect(command(.letter("o"), focused: false) == nil)   // Ellipse
        #expect(command(.letter("i"), .option) == .clearIn)
        #expect(command(.letter("o"), .option) == .clearOut)
        #expect(command(.letter("i"), .option, focused: false) == .clearIn)
        // ⌥X is the menu's Clear In and Out, not a key of this map.
        #expect(command(.letter("x"), .option) == nil)
    }

    @Test("M drops a marker on a focused timeline")
    func markerKey() {
        #expect(command(.letter("m")) == .addMarker)
        #expect(command(.letter("m"), focused: false) == nil)   // the marquee
    }

    @Test("Q and W ripple trim to the playhead on a focused timeline")
    func qAndWTrim() {
        #expect(command(.letter("q")) == .rippleTrimToPlayhead(.start))
        #expect(command(.letter("w")) == .rippleTrimToPlayhead(.end))
        // On the canvas W is still the magic wand, and ⌘Q still quits.
        #expect(command(.letter("w"), focused: false) == nil)
        #expect(command(.letter("q"), focused: false) == nil)
        #expect(command(.letter("q"), .command) == nil)
        // A held Q is one trim, not thirty.
        #expect(command(.letter("q"), repeating: true) == nil)
    }

    @Test("Command-K splits at the playhead wherever the keyboard is")
    func commandKSplits() {
        #expect(command(.letter("k"), .command) == .splitAtPlayhead)
        #expect(command(.letter("k"), .command, focused: false) == .splitAtPlayhead)
        // ⇧⌘K is the menu's Split Everything, not this.
        #expect(command(.letter("k"), [.command, .shift]) == nil)
    }

    @Test("Delete lifts and Shift-Delete ripples, on a focused timeline")
    func deleteKeys() {
        #expect(command(.delete) == .lift)
        #expect(command(.forwardDelete) == .lift)
        #expect(command(.delete, .shift) == .rippleDelete)
        // On the canvas ⌫ still means what it always meant there.
        #expect(command(.delete, focused: false) == nil)
        #expect(command(.delete, .shift, focused: false) == nil)
        // ⌥⌫ is the menu's Ripple Delete, and the canvas's Fill: not this map.
        #expect(command(.delete, .option) == nil)
    }

    @Test("Left and right step a frame, five with Shift")
    func arrowsStep() {
        #expect(command(.right) == .stepFrames(1))
        #expect(command(.left) == .stepFrames(-1))
        #expect(command(.right, .shift) == .stepFrames(5))
        #expect(command(.left, .shift) == .stepFrames(-5))
        // A held arrow keeps stepping.
        #expect(command(.right, repeating: true) == .stepFrames(1))
        // On the canvas the arrows nudge a picked layer, so they are not ours.
        #expect(command(.right, focused: false) == nil)
        // ⌥⇧→ is the menu's Captions Later.
        #expect(command(.right, [.option, .shift]) == nil)
    }

    @Test("Up and down go to the previous and next edit point")
    func upDownEditPoints() {
        #expect(command(.up) == .editPoint(forward: false))
        #expect(command(.down) == .editPoint(forward: true))
        #expect(command(.down, focused: false) == nil)
    }

    @Test("Home and End go to the ends wherever the keyboard is")
    func homeEnd() {
        #expect(command(.home) == .goToStart)
        #expect(command(.end) == .goToEnd)
        #expect(command(.home, focused: false) == .goToStart)
        #expect(command(.end, focused: false) == .goToEnd)
    }

    @Test("V, B and A pick the timeline's tools on a focused timeline")
    func toolKeys() {
        #expect(command(.letter("v")) == .selectTool)
        #expect(command(.letter("b")) == .bladeTool)
        #expect(command(.letter("a")) == .trackSelectForwardTool)
        // The Arrow tool keeps A when the canvas has the keyboard.
        #expect(command(.letter("a"), focused: false) == nil)
        #expect(command(.letter("v"), focused: false) == nil)
    }

    @Test("Equals and minus zoom the timeline, backslash fits it")
    func zoomKeys() {
        #expect(command(.letter("=")) == .zoomIn)
        #expect(command(.letter("+")) == .zoomIn)
        #expect(command(.letter("-")) == .zoomOut)
        #expect(command(.letter("\\")) == .zoomToFit)
        // ⌘= and ⌘- zoom the canvas, as they always have.
        #expect(command(.letter("="), .command) == nil)
        #expect(command(.letter("-"), .command) == nil)
        #expect(command(.letter("-"), focused: false) == nil)
    }

    @Test("A letter Premiere gives the timeline nothing is left alone")
    func otherLettersPass() {
        #expect(command(.letter("t")) == nil)
        #expect(command(.letter("r")) == nil)
        #expect(command(.letter("z"), .command) == nil)
        #expect(command(.letter("j"), .command) == nil)
    }

    @Test("Uppercase letters read the same as lowercase")
    func caseDoesNotMatter() {
        #expect(TimelineKeyPress(characters: "L", keyCode: 37, modifiers: [], isRepeat: false)?.key
                == .letter("l"))
    }

    @Test("Named keys come from their key codes")
    func keyCodes() {
        #expect(TimelineKeyPress(characters: "", keyCode: 123, modifiers: [], isRepeat: false)?.key == .left)
        #expect(TimelineKeyPress(characters: "", keyCode: 124, modifiers: [], isRepeat: false)?.key == .right)
        #expect(TimelineKeyPress(characters: "", keyCode: 125, modifiers: [], isRepeat: false)?.key == .down)
        #expect(TimelineKeyPress(characters: "", keyCode: 126, modifiers: [], isRepeat: false)?.key == .up)
        #expect(TimelineKeyPress(characters: "", keyCode: 115, modifiers: [], isRepeat: false)?.key == .home)
        #expect(TimelineKeyPress(characters: "", keyCode: 119, modifiers: [], isRepeat: false)?.key == .end)
        #expect(TimelineKeyPress(characters: "", keyCode: 51, modifiers: [], isRepeat: false)?.key == .delete)
        #expect(TimelineKeyPress(characters: "", keyCode: 117, modifiers: [], isRepeat: false)?.key == .forwardDelete)
        #expect(TimelineKeyPress(characters: " ", keyCode: 49, modifiers: [], isRepeat: false)?.key == .space)
    }

    // MARK: - The shuttle

    @Test("L plays forward, and each L again goes faster")
    func lLadder() {
        var shuttle = TimelineShuttle()
        #expect(press(&shuttle, .forward) == 1)
        #expect(press(&shuttle, .forward) == 2)
        #expect(press(&shuttle, .forward) == 4)
        #expect(press(&shuttle, .forward) == 8)
        // The top of the ladder is as fast as it goes.
        #expect(press(&shuttle, .forward) == 8)
    }

    @Test("J plays backward and climbs the same ladder")
    func jLadder() {
        var shuttle = TimelineShuttle()
        #expect(press(&shuttle, .reverse) == -1)
        #expect(press(&shuttle, .reverse) == -2)
        #expect(press(&shuttle, .reverse) == -4)
    }

    @Test("The other direction starts again at normal speed")
    func switchingDirection() {
        var shuttle = TimelineShuttle()
        _ = shuttle.press(.forward)
        _ = shuttle.press(.forward)
        #expect(press(&shuttle, .reverse) == -1)
        #expect(press(&shuttle, .forward) == 1)
    }

    @Test("K stops, and the next L starts at normal speed")
    func kStops() {
        var shuttle = TimelineShuttle()
        _ = shuttle.press(.forward)
        _ = shuttle.press(.forward)
        #expect(press(&shuttle, .stop) == 0)
        #expect(press(&shuttle, .forward) == 1)
    }

    @Test("A shuttle that was stopped some other way starts from rest")
    func resetFromOutside() {
        var shuttle = TimelineShuttle()
        _ = shuttle.press(.forward)
        _ = shuttle.press(.forward)
        shuttle.stopped()
        #expect(press(&shuttle, .forward) == 1)
    }

    @Test("L on a playhead already playing at normal speed goes to double")
    func lWhilePlaying() {
        // Space started it: the shuttle is told it is running at 1.
        var shuttle = TimelineShuttle()
        shuttle.playing(at: 1)
        #expect(press(&shuttle, .forward) == 2)
    }

    // MARK: - Edit points

    static let movie = MovieRef(pixelSize: CGSize(width: 100, height: 100),
                                durationMS: 8000, hasSound: false)

    @Test("A clip's ends and its cuts are edit points, in order")
    func editPointsOfOneClip() throws {
        var doc = PhotonzDocument.recording(Self.movie, name: "take")
        let id = doc.layers[0].id
        doc.splitClip(id, atMS: 2000)
        doc.splitClip(id, atMS: 5000)
        #expect(doc.editPointMoments() == [0, 2000, 5000, 8000])
    }

    @Test("Up and down walk the edit points and stop at the ends")
    func neighbours() {
        var doc = PhotonzDocument.recording(Self.movie, name: "take")
        let id = doc.layers[0].id
        doc.splitClip(id, atMS: 2000)
        #expect(doc.neighbourEditPoint(from: 1000, forward: true) == 2000)
        #expect(doc.neighbourEditPoint(from: 2000, forward: true) == 8000)
        #expect(doc.neighbourEditPoint(from: 2000, forward: false) == 0)
        #expect(doc.neighbourEditPoint(from: 0, forward: false) == nil)
        #expect(doc.neighbourEditPoint(from: 8000, forward: true) == nil)
    }

    @Test("Every layer with time adds its in and out")
    func titlesAreEditPoints() throws {
        var doc = PhotonzDocument.recording(Self.movie, name: "take")
        var title = Layer(name: "Title", content: .text(TextContent(string: "Hi")),
                          frame: CGRect(x: 0, y: 0, width: 80, height: 20))
        title.time = LayerTime(inMS: 1500, outMS: 3500)
        doc.layers.append(title)
        #expect(doc.editPointMoments() == [0, 1500, 3500, 8000])
    }

    // MARK: - Clearing one mark

    @Test("Option-I clears only the In, Option-O only the Out")
    func clearOneMark() {
        var doc = PhotonzDocument.recording(Self.movie, name: "take")
        doc.setMarkIn(atMS: 1000)
        doc.setMarkOut(atMS: 3000)
        #expect(clear(&doc, out: false))
        #expect(doc.markInMS == nil)
        #expect(doc.markOutMS == 3000)
        #expect(!clear(&doc, out: false))
        #expect(clear(&doc, out: true))
        #expect(doc.markOutMS == nil)
        #expect(!clear(&doc, out: true))
    }
}

/// The walk step that checks what the timeline keys did: where the playhead is
/// to the millisecond, who has the keyboard, how fast it is playing.
@Suite("The expectTimeline walk step")
struct ExpectTimelineStepTests {

    @Test("It reads every claim it can make")
    func readsClaims() throws {
        let script = try PlaytestScript.decode(Data("""
        { "steps": [ { "do": "expectTimeline", "playheadMS": 1033, "withinMS": 5, "keyboard": "timeline",
                       "rate": 2, "blade": true, "markInMS": 400, "hasOut": false, "markers": 1 } ] }
        """.utf8))
        guard case .expectTimeline(let claim) = script.steps[0] else {
            Issue.record("expectTimeline"); return
        }
        #expect(claim.playheadMS == 1033)
        #expect(claim.withinMS == 5)
        #expect(claim.keyboard == .timeline)
        #expect(claim.rate == 2)
        #expect(claim.blade == true)
        #expect(claim.markInMS == 400)
        #expect(claim.hasOut == false)
        #expect(claim.markers == 1)
        #expect(script.steps[0].name == "expectTimeline")
        #expect(PlaytestStep.names.contains("expectTimeline"))
    }

    @Test("The playhead is claimed to the millisecond unless it says otherwise")
    func exactByDefault() throws {
        let script = try PlaytestScript.decode(Data("""
        { "steps": [ { "do": "expectTimeline", "playheadMS": 33 } ] }
        """.utf8))
        guard case .expectTimeline(let claim) = script.steps[0] else {
            Issue.record("expectTimeline"); return
        }
        #expect(claim.withinMS == 0)
        #expect(claim.keyboard == nil)
    }

    @Test("It can claim the ruler is drawn where its numbers say, and which number is under the playhead")
    func readsRulerClaims() throws {
        let script = try PlaytestScript.decode(Data("""
        { "steps": [ { "do": "expectTimeline", "rulerMatches": true, "rulerAtPlayhead": "1:15" } ] }
        """.utf8))
        guard case .expectTimeline(let claim) = script.steps[0] else {
            Issue.record("expectTimeline"); return
        }
        #expect(claim.rulerMatches == true)
        #expect(claim.rulerAtPlayhead == "1:15")
        #expect(claim.claimsSomething)
        #expect(claim.playheadMS == nil)
    }

    @Test("A ruler claim on its own is a claim")
    func rulerAloneClaims() throws {
        let script = try PlaytestScript.decode(Data("""
        { "steps": [ { "do": "expectTimeline", "rulerAtPlayhead": "0:04" } ] }
        """.utf8))
        guard case .expectTimeline(let claim) = script.steps[0] else {
            Issue.record("expectTimeline"); return
        }
        #expect(claim.rulerMatches == nil)
        #expect(claim.claimsSomething)
    }

    @Test("A step that claims nothing is refused")
    func claimsSomething() {
        #expect(throws: PlaytestScriptError.self) {
            _ = try PlaytestScript.decode(Data(#"{ "steps": [ { "do": "expectTimeline" } ] }"#.utf8))
        }
    }

    @Test("The keyboard is the timeline or the canvas and nothing else")
    func keyboardWords() {
        #expect(throws: PlaytestScriptError.self) {
            _ = try PlaytestScript.decode(Data(#"{ "steps": [ { "do": "expectTimeline", "keyboard": "panel" } ] }"#.utf8))
        }
    }
}

@Suite("Walk keys for the timeline")
struct TimelineWalkKeysTests {
    @Test("A walk can press Home, End and forward delete")
    func namedKeys() throws {
        let script = try PlaytestScript.decode(Data("""
        { "steps": [ { "do": "key", "key": "home" }, { "do": "key", "key": "end" },
                     { "do": "key", "key": "forwarddelete" } ] }
        """.utf8))
        let codes: [UInt16] = script.steps.compactMap {
            if case .key(let key, _) = $0 { return key.keyCode }
            return nil
        }
        #expect(codes == [115, 119, 117])
    }
}
