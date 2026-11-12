import CoreGraphics
import Foundation
@testable import PhotonzCore
import Testing

/// The story eval's envelope of 2026-11-12 (run 20261112-095935-ask, task
/// `an-animated-icon-told-as-a-little-story-moves-th`, pass sixteen), the plan
/// exactly as the model left it after its look and mend: the letter drawn
/// above the envelope drops 8 down into it and fades there.
enum AskMotionLetterGoesIn {
    static let svg = ##"<svg viewBox="0 0 24 24" fill="none" stroke="#1D1D1F" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><g id="envelope"><rect id="body" x="3" y="9" width="18" height="12" rx="1"/><path id="flap" d="M3 9 L12 15 L21 9"/></g><rect id="letter" x="7" y="2" width="10" height="6" rx="1"/></svg>"##

    static func steps() throws -> [AskStep] {
        let args = AskMotionBounceSeenTests.args
        return [AskStep(tool: "add_drawing", arguments: ["icon": true, "subject": "envelope with letter", "svg": .string(svg)]),
                AskStep(tool: "set_timing", arguments: ["loop": true, "seconds": .number(2)]),
                AskStep(tool: "set_keys", arguments: try args(#"{"keys":[{"curve":"Ease in out","seconds":0,"value":{"x":0,"y":0}},{"curve":"Hold","seconds":0.5,"value":{"x":0,"y":8}},{"curve":"Hold","seconds":1.7,"value":{"x":0,"y":8}},{"seconds":2,"value":{"x":0,"y":0}}],"layer":"$1/letter","property":"position"}"#)),
                AskStep(tool: "set_keys", arguments: try args(#"{"keys":[{"curve":"Hold","seconds":0,"value":100},{"curve":"Ease in out","seconds":0.5,"value":100},{"curve":"Hold","seconds":0.6,"value":0},{"curve":"Ease in out","seconds":1.9,"value":0},{"seconds":2,"value":100}],"layer":"$1/letter","property":"opacity"}"#)),
                AskStep(tool: "set_keys", arguments: try args(#"{"keys":[{"curve":"Hold","seconds":0,"value":0},{"curve":"Ease in out","seconds":0.5,"value":0},{"curve":"Hold","seconds":0.9,"value":180},{"curve":"Ease in out","seconds":1.7,"value":180},{"seconds":2,"value":0}],"layer":"$1/flap","pivot":{"x":12,"y":9},"property":"rotationX"}"#)),
                AskStep(tool: "set_keys", arguments: try args(#"{"keys":[{"curve":"Hold","seconds":0,"value":{"x":0,"y":0}},{"curve":"Ease in","seconds":1.1,"value":{"x":0,"y":0}},{"curve":"Hold","seconds":1.7,"value":{"x":12,"y":-16}},{"seconds":2,"value":{"x":0,"y":0}}],"layer":"$1/envelope","property":"position"}"#)),
                AskStep(tool: "set_keys", arguments: try args(#"{"keys":[{"curve":"Ease in out","seconds":0,"value":{"x":0,"y":0}},{"curve":"Hold","seconds":0.5,"value":{"x":0,"y":8}},{"curve":"Ease in out","seconds":1.7,"value":{"x":0,"y":8}},{"seconds":2,"value":{"x":0,"y":0}}],"layer":"$1/letter","property":"position","replace":true}"#)),
                AskStep(tool: "set_keys", arguments: try args(#"{"keys":[{"curve":"Hold","seconds":0,"value":100},{"curve":"Ease in out","seconds":0.5,"value":100},{"curve":"Hold","seconds":0.6,"value":0},{"curve":"Ease in out","seconds":1.7,"value":0},{"seconds":2,"value":100}],"layer":"$1/letter","property":"opacity","replace":true}"#)),
                AskStep(tool: "set_keys", arguments: try args(#"{"keys":[{"curve":"Hold","seconds":0,"value":0},{"curve":"Ease in out","seconds":0.5,"value":0},{"curve":"Hold","seconds":0.9,"value":180},{"curve":"Ease in out","seconds":1.7,"value":180},{"seconds":2,"value":0}],"layer":"$1/flap","pivot":{"x":12,"y":9},"property":"rotationX","replace":true}"#)),
                AskStep(tool: "set_keys", arguments: try args(#"{"keys":[{"curve":"Hold","seconds":0,"value":{"x":0,"y":0}},{"curve":"Ease in","seconds":1.1,"value":{"x":0,"y":0}},{"curve":"Ease in out","seconds":1.7,"value":{"x":12,"y":-16}},{"seconds":2,"value":{"x":0,"y":0}}],"layer":"$1/envelope","property":"position","replace":true}"#)),
                AskStep(tool: "set_keys", arguments: try args(#"{"keys":[{"seconds":0,"value":{"x":0,"y":0}},{"seconds":0.5,"touches":"envelope","value":{"x":0,"y":8}},{"seconds":1.7,"value":{"x":0,"y":8}},{"seconds":2,"value":{"x":0,"y":0}}],"layer":"$1/letter","property":"position","replace":true}"#)),
                AskStep(tool: "set_keys", arguments: try args(#"{"keys":[{"curve":"Hold","seconds":0,"value":{"x":0,"y":0}},{"curve":"Ease in","seconds":1.1,"value":{"x":0,"y":0}},{"curve":"Ease in out","seconds":1.7,"value":{"x":24,"y":-24}},{"seconds":2,"value":{"x":0,"y":0}}],"layer":"$1/envelope","property":"position","replace":true}"#))]
    }
}

@Suite("Ask's story icons: what goes into something goes in")
struct AskMotionLetterGoesInTests {
    @Test("The landed plan's frames, written out on request",
          .enabled(if: ProcessInfo.processInfo.environment["PHOTONZ_LAP_DUMP3"] != nil))
    func dump() throws {
        let path = try #require(ProcessInfo.processInfo.environment["PHOTONZ_LAP_DUMP3"])
        let landed = AskMotion.planned(try AskMotionLetterGoesIn.steps())
        for step in landed { print("LANDED", step.tool, step.arguments.encodedString()) }
        try LapDump.write(landed, to: path, frames: 32)
    }
}

extension AskMotionLetterGoesInTests {
    @Test("Each landing stage's letter, printed on request",
          .enabled(if: ProcessInfo.processInfo.environment["PHOTONZ_LAP_DUMP3"] != nil))
    func stages() throws {
        func letter(_ name: String, _ s: [AskStep]) {
            let k = s.filter { $0.tool == "set_keys" && $0.arguments["layer"]?.stringValue == "$1/letter" }
            print("STAGE", name, k.map { "\($0.arguments["property"]?.stringValue ?? ""): \($0.arguments["keys"]?.encodedString() ?? "")" }.joined(separator: " | "))
        }
        var s = try AskMotionLetterGoesIn.steps()
        let chain: [(String, ([AskStep]) -> [AskStep])] = [
            ("carried", AskMotion.carried), ("touchesKept", AskMotion.touchesKept), ("landingFolded", AskMotion.landingFolded),
            ("swingsFitted", AskMotion.swingsFitted), ("drawnNotFaded", AskMotion.drawnNotFaded), ("holdsMove", AskMotion.holdsMove),
            ("travelsSeen", AskMotion.travelsSeen), ("staysTillGone", AskMotion.staysTillGone), ("hitStarts", AskMotion.hitStarts),
            ("landsInTheMiddle", AskMotion.landsInTheMiddle), ("touchesPlaced", AskMotion.touchesPlaced), ("tuckedIn", AskMotion.tuckedIn),
            ("foldsLand", AskMotion.foldsLand), ("foldsOpen", AskMotion.foldsOpen)]
        for (name, f) in chain { s = f(s); letter(name, s) }
    }
}

extension AskMotionLetterGoesInTests {
    static func y(_ value: AgentJSON?) -> Double? { value?["y"]?.doubleValue }

    /// The model keyed the letter 8 down into the envelope at 0.5 s and said
    /// it touches the envelope there. The envelope flies off later in the lap,
    /// so it counted as a moving part the letter was buried in, and the letter
    /// was pushed out of it the shortest way: up, 1 unit above where it was
    /// drawn. Nine looks of nine read "the letter rises up instead of going in".
    /// A part lying wholly inside a closed outline it touches has gone in.
    @Test("A part keyed wholly inside the closed outline it touches stays in it")
    func staysIn() throws {
        let placed = AskMotion.touchesPlaced(try AskMotionLetterGoesIn.steps())
        let letter = try #require(placed.last { $0.arguments["layer"]?.stringValue == "$1/letter" && $0.arguments["property"]?.stringValue == "position" })
        let keys = AskMotionCheck.timed(letter)
        let atHalf = try #require(keys.first { abs($0.seconds - 0.5) < 0.001 })
        #expect(Self.y(atHalf.value) == 8, "\(keys)")
    }

    @Test("The landed letter goes down into the envelope, never up out of it")
    func landsDown() throws {
        let landed = AskMotion.planned(try AskMotionLetterGoesIn.steps())
        let letter = try #require(landed.last { $0.arguments["layer"]?.stringValue == "$1/letter" && $0.arguments["property"]?.stringValue == "position" })
        for key in AskMotionCheck.timed(letter) {
            #expect((Self.y(key.value) ?? 0) >= 0, "the letter went up at \(key.seconds): \(AskMotionCheck.timed(letter))")
        }
        #expect(AskMotionCheck.timed(letter).contains { (Self.y($0.value) ?? 0) >= 6 }, "it never went in: \(AskMotionCheck.timed(letter))")
    }
}

extension AskMotionLetterGoesInTests {
    /// Moved to just before the body, the letter would have joined the
    /// envelope's group (and flown off with it), so it stayed drawn after the
    /// envelope and showed over its front all the way in.
    @Test("What drops into an outline inside a group goes behind that group, the outline filled white")
    func behindTheGroup() throws {
        let landed = AskMotion.planned(try AskMotionLetterGoesIn.steps())
        let svg = try #require(landed.first { $0.tool == "add_drawing" }?.arguments["svg"]?.stringValue)
        let letter = try #require(svg.range(of: #"id="letter""#)), group = try #require(svg.range(of: #"id="envelope""#))
        #expect(letter.lowerBound < group.lowerBound, "\(svg)")
        #expect(svg.contains(##"fill="#FFFFFF""##), "\(svg)")
        // Still its own part, in no group.
        guard case .success(let art) = SVGArtwork.parse(svg, keepingGroups: true) else { Issue.record("unparsed"); return }
        #expect(art.parts.first { $0.name.map(AskMotion.plain) == "letter" }?.groups == [], "\(art.parts.map { ($0.name ?? "-", $0.groups) })")
    }
}
