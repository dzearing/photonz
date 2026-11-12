import CoreGraphics
import Foundation
@testable import PhotonzCore
import Testing

/// The bell of run 20261111-200328 ("a bell swings, rings twice and
/// settles"): drawn as a body and a short bar it hangs from, the body swung
/// about a point on the bar and the bar stayed level. Nine looks of nine read
/// the bell as shearing under a fixed cap.
@Suite("Ask's moving icons: a small still part a swing hangs from swings with it")
struct AskMotionCarriedTests {

    static let bell = ##"<svg viewBox="0 0 24 24" fill="none" stroke="#1D1D1F" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><line id="mount" x1="9" y1="3" x2="15" y2="3"/><g id="bell"><path id="body" d="M12 4 C8 4 6 7 6 11 L6 14 L4 17 L20 17 L18 14 L18 11 C18 7 16 4 12 4 Z"/><line id="clapper" x1="12" y1="17" x2="12" y2="20"/></g><path id="ring-left" d="M4 8 C2.5 9 2.5 11 4 12"/><path id="ring-right" d="M20 8 C21.5 9 21.5 11 20 12"/></svg>"##

    static func keys(_ json: String) throws -> AskStep {
        AskStep(tool: "set_keys", arguments: try AgentJSON.parse(Data(json.utf8)))
    }

    static let swing = #"{"keys":[{"curve":"Hold","seconds":0,"value":0},{"curve":"Ease in out","seconds":0.2,"value":0},{"curve":"Ease in out","seconds":0.5,"value":14},{"curve":"Ease in out","seconds":0.8,"value":-12},{"curve":"Ease out","seconds":2.4,"value":0}],"layer":"$1/bell","pivot":{"x":12,"y":3},"property":"rotation"}"#

    @Test("The bell's bar turns with the bell, about the same point, on the same keys; the ring marks beside it stay as they were")
    func barSwingsWithTheBell() throws {
        let drawing = AskStep(tool: "add_drawing", arguments: ["subject": "bell", "svg": .string(Self.bell)])
        let swing = try Self.keys(Self.swing)
        let fade = try Self.keys(#"{"keys":[{"seconds":0,"value":0},{"seconds":0.35,"value":100},{"seconds":0.45,"value":0},{"seconds":2.4,"value":0}],"layer":"$1/ring-left","property":"opacity"}"#)
        let out = AskMotion.carried([drawing, swing, fade])
        #expect(out.count == 4)
        let bar = try #require(out.first { $0.arguments["layer"]?.stringValue?.lowercased() == "$1/mount" })
        #expect(bar.arguments["property"]?.stringValue == "rotation")
        #expect(bar.arguments["pivot"]?["x"]?.doubleValue == 12 && bar.arguments["pivot"]?["y"]?.doubleValue == 3)
        #expect(bar.arguments["keys"] == swing.arguments["keys"])
        #expect(!out.contains { ["$1/ring-left", "$1/ring-right"].contains($0.arguments["layer"]?.stringValue) && $0.arguments["property"]?.stringValue == "rotation" })
        // And it lands through the whole plan.
        #expect(AskMotion.planned([drawing, swing, fade]).contains { $0.arguments["layer"]?.stringValue?.lowercased() == "$1/mount" })
    }

    @Test("A swing that hangs from a wide bar, a part with keys of its own, or a turn about the part's own middle carries nothing")
    func leavesTheRestAlone() throws {
        // A sign swinging under a beam wider than itself: the beam stays.
        let sign = ##"<svg viewBox="0 0 24 24" fill="none" stroke="#1D1D1F" stroke-width="2"><line id="beam" x1="2" y1="4" x2="22" y2="4"/><path id="sign" d="M8 5 L16 5 L16 12 L8 12 Z"/></svg>"##
        let hung = AskStep(tool: "add_drawing", arguments: ["subject": "sign", "svg": .string(sign)])
        let swaying = try Self.keys(#"{"keys":[{"seconds":0,"value":0},{"seconds":0.5,"value":10},{"seconds":1,"value":0}],"layer":"$1/sign","pivot":{"x":12,"y":4},"property":"rotation"}"#)
        #expect(AskMotion.carried([hung, swaying]) == [hung, swaying])
        // The bar already keyed by the model is left to the model.
        let drawing = AskStep(tool: "add_drawing", arguments: ["subject": "bell", "svg": .string(Self.bell)])
        let own = try Self.keys(#"{"keys":[{"seconds":0,"value":{"x":0,"y":0}},{"seconds":1,"value":{"x":0,"y":-1}}],"layer":"$1/mount","property":"position"}"#)
        let swing = try Self.keys(Self.swing)
        #expect(AskMotion.carried([drawing, swing, own]) == [drawing, swing, own])
        // A spin about its own middle hangs from nothing.
        let spin = try Self.keys(#"{"keys":[{"seconds":0,"value":0},{"seconds":1,"value":360}],"layer":"$1/bell","property":"rotation"}"#)
        #expect(AskMotion.carried([drawing, spin]) == [drawing, spin])
    }

    @Test("A lid swinging on its hinge does not carry the can it sits on")
    func lidLeavesTheCan() throws {
        let trash = ##"<svg viewBox="0 0 24 24" fill="none" stroke="#1D1D1F" stroke-width="2"><path id="can" d="M6 8 L7 21 L17 21 L18 8"/><line id="lid" x1="4" y1="6" x2="20" y2="6"/></svg>"##
        let drawing = AskStep(tool: "add_drawing", arguments: ["subject": "trash", "svg": .string(trash)])
        let open = try Self.keys(#"{"keys":[{"seconds":0,"value":0},{"seconds":0.5,"value":-60},{"seconds":1,"value":0}],"layer":"$1/lid","pivot":{"x":4,"y":6},"property":"rotation"}"#)
        #expect(AskMotion.carried([drawing, open]) == [drawing, open])
    }
}

/// The same bell: its right ring mark flashed from 0.55 to 0.75 s as the
/// bell swung to -12 degrees, rim towards the mark, and every look saw a
/// blob run into the outline.
@Suite("Ask's moving icons: a mark is never drawn over a part that moves while it shows")
struct AskMotionMarksClearTests {

    /// The left ring flashes at 0.7 to 0.86 s, as the bell swings right, away from it.
    static func plan(ringRight: String) throws -> [AskStep] {
        let drawing = AskStep(tool: "add_drawing", arguments: ["subject": "bell", "svg": .string(AskMotionCarriedTests.bell)])
        return [drawing, try AskMotionCarriedTests.keys(AskMotionCarriedTests.swing),
                try AskMotionCarriedTests.keys(#"{"keys":[{"seconds":0,"value":0},{"seconds":0.7,"value":0},{"seconds":0.76,"value":100},{"seconds":0.86,"value":0},{"seconds":2.4,"value":0}],"layer":"$1/ring-left","property":"opacity"}"#),
                try AskMotionCarriedTests.keys(ringRight)]
    }

    @Test("The ring that flashes as the rim swings into it is told back to the model, with when")
    func ringOverTheRimIsSaid() throws {
        let steps = try Self.plan(ringRight: #"{"keys":[{"seconds":0,"value":0},{"seconds":0.55,"value":0},{"seconds":0.65,"value":100},{"seconds":0.75,"value":0},{"seconds":2.4,"value":0}],"layer":"$1/ring-right","property":"opacity"}"#)
        let said = AskMotionCheck.marksOver(steps)
        #expect(said.count == 1, "\(said)")
        #expect(said.first?.hasPrefix("ringright is drawn over bell from 0.") ?? false, "\(said)")
        #expect(AskMotionCheck.problems(steps).contains { $0.contains("drawn clear of it, never over it") })
    }

    @Test("Shown while the bell swings away from it, or the left ring as the bell swings right, nothing is said")
    func ringClearOfTheRimIsFine() throws {
        // The bell swings to +14 (its rim away to the left) by 0.5 s.
        let steps = try Self.plan(ringRight: #"{"keys":[{"seconds":0,"value":0},{"seconds":0.35,"value":0},{"seconds":0.42,"value":100},{"seconds":0.52,"value":0},{"seconds":2.4,"value":0}],"layer":"$1/ring-right","property":"opacity"}"#)
        #expect(AskMotionCheck.marksOver(steps).isEmpty, "\(AskMotionCheck.marksOver(steps))")
    }
}

extension AskMotionMarksClearTests {
    @Test("What is thrown in, hidden at rest and travelling far, is not a mark: its hit on what it meets is meant")
    func thrownIsNoMark() throws {
        let svg = ##"<svg viewBox="0 0 24 24" fill="none" stroke="#1D1D1F" stroke-width="2"><path id="can" d="M6 8 L7 21 L17 21 L18 8"/><line id="lid" x1="4" y1="6" x2="20" y2="6"/><circle id="trash" cx="22" cy="2" r="1.5"/></svg>"##
        let drawing = AskStep(tool: "add_drawing", arguments: ["subject": "trash", "svg": .string(svg)])
        let steps = [drawing,
            try AskMotionCarriedTests.keys(#"{"keys":[{"seconds":0,"value":0},{"seconds":0.5,"value":-60},{"seconds":1,"value":0}],"layer":"$1/lid","pivot":{"x":4,"y":6},"property":"rotation"}"#),
            try AskMotionCarriedTests.keys(#"{"keys":[{"seconds":0,"value":0},{"seconds":0.3,"value":100},{"seconds":1,"value":0}],"layer":"$1/trash","property":"opacity"}"#),
            try AskMotionCarriedTests.keys(#"{"keys":[{"seconds":0,"value":{"x":0,"y":0}},{"seconds":0.5,"value":{"x":-10,"y":2}},{"seconds":0.9,"value":{"x":-10,"y":14}},{"seconds":1,"value":{"x":0,"y":0}}],"layer":"$1/trash","property":"position"}"#)]
        #expect(AskMotionCheck.marksOver(steps).isEmpty, "\(AskMotionCheck.marksOver(steps))")
    }
}
