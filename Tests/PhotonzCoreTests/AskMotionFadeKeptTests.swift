import CoreGraphics
import Foundation
@testable import PhotonzCore
import Testing

/// The user's trash story, walked on 2026-11-11 at 10:28 (task
/// `an-animated-icon-told-as-a-little-story-moves-th`, pass twelve's walk 4),
/// the plan exactly as the model wrote it: the trash fades from 0.5 s to gone
/// at 1.1 s, where it is in the can, then goes back to where it started by
/// the lap's end. Landed, `travelsSeen` read the lap's end as where it
/// arrives, moved the fade to 1.38 to 1.48 s, 20 ms before the key at 1.5 s,
/// and the app refuses two keys that close ("two keys at 1.48 s are one
/// key"). The whole fade went, the row said "Left out a layer: it could not
/// be done", and the trash sat beside the can all lap.
@Suite("Ask's story icons: a fade the model planned is never landed as keys the app refuses")
struct AskMotionFadeKeptTests {

    static func args(_ json: String) throws -> AgentJSON { try AgentJSON.parse(Data(json.utf8)) }
    static let bin = ##"<svg viewBox="0 0 24 24" fill="none" stroke="#1D1D1F" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><g id="bin"><path id="body" d="M7 9 L8 20 L16 20 L17 9"/><line id="rib-left" x1="10" y1="11" x2="10.5" y2="18"/><line id="rib-right" x1="14" y1="11" x2="13.5" y2="18"/></g><g id="lid"><line id="lid-bar" x1="6" y1="8" x2="18" y2="8"/><line id="lid-knob" x1="11" y1="6" x2="13" y2="6"/></g><path id="trash" d="M18 2 L21 3 L20 6 L17 5 Z"/></svg>"##
    static let fade = #"{"keys":[{"seconds":0,"value":100},{"seconds":0.5,"value":100},{"seconds":1.1,"value":0},{"seconds":1.5,"value":100}],"layer":"$1/trash","property":"opacity"}"#

    static func steps() throws -> [AskStep] {
        [AskStep(tool: "add_drawing", arguments: ["icon": true, "subject": "trash bin with hinged lid", "svg": .string(bin)]),
         AskStep(tool: "set_timing", arguments: ["loop": true, "seconds": .number(1.5)]),
         AskStep(tool: "set_keys", arguments: try args(#"{"keys":[{"curve":"Hold","seconds":0,"value":0},{"curve":"Ease out","seconds":0.2,"value":0},{"curve":"Hold","seconds":0.5,"value":-40},{"curve":"Ease in","seconds":0.8,"value":-40},{"curve":"Ease out back","seconds":0.95,"value":-25},{"curve":"Hold","seconds":1.3,"value":0},{"seconds":1.5,"value":0}],"layer":"$1/lid","pivot":{"x":6,"y":8},"property":"rotation"}"#)),
         AskStep(tool: "set_keys", arguments: try args(#"{"keys":[{"seconds":0,"value":{"x":0,"y":0}},{"seconds":0.5,"value":{"x":0,"y":0}},{"seconds":0.8,"value":{"x":-4,"y":3}},{"seconds":0.95,"value":{"x":-5,"y":1}},{"seconds":1.1,"value":{"x":-5,"y":6}},{"seconds":1.5,"value":{"x":0,"y":0}}],"layer":"$1/trash","property":"position"}"#)),
         AskStep(tool: "set_keys", arguments: try args(fade)),
         AskStep(tool: "set_keys", arguments: try args(#"{"keys":[{"seconds":0,"value":{"x":0,"y":0}},{"seconds":0.5,"value":{"x":0,"y":0}},{"seconds":0.8,"touches":"$1/lid","value":{"x":-4,"y":3}},{"seconds":0.95,"value":{"x":-5,"y":1}},{"seconds":1.1,"touches":"$1/bin","value":{"x":-5,"y":6}},{"seconds":1.5,"value":{"x":0,"y":0}}],"layer":"$1/trash","property":"position","replace":true}"#)),
         AskStep(tool: "set_keys", arguments: try args(#"{"keys":[{"seconds":0,"value":{"x":0,"y":0}},{"seconds":0.5,"value":{"x":0,"y":0}},{"seconds":0.8,"value":{"x":-4,"y":3}},{"seconds":0.95,"value":{"x":-3,"y":1}},{"seconds":1.1,"value":{"x":-2,"y":4}},{"seconds":1.5,"value":{"x":0,"y":0}}],"layer":"$1/trash","property":"position","replace":true}"#))]
    }

    /// Every landed set_keys as the app's own tool reads it.
    static func refusals(_ steps: [AskStep]) -> [String] {
        steps.filter { $0.tool == "set_keys" }.compactMap { step in
            guard case .failure(let refused) = AgentTools.keyRequest("set_keys", step.arguments.objectValue ?? [:], document: nil) else { return nil }
            return refused.message
        }
    }

    static func opacity(_ steps: [AskStep], _ layer: String) -> AskStep? {
        steps.last { $0.tool == "set_keys" && $0.arguments["layer"]?.stringValue == layer && $0.arguments["property"]?.stringValue == "opacity" }
    }

    @Test("The walk's plan lands with no key the app refuses, its fade kept")
    func walkLands() throws {
        let landed = AskMotion.planned(try Self.steps())
        #expect(Self.refusals(landed).isEmpty, "\(Self.refusals(landed))")
        #expect(Self.opacity(landed, "$1/trash") != nil)
    }

    @Test("Faded out by the key it was gone at, where it lands in the can, not at the lap's end")
    func goneWhereItLands() throws {
        let seen = AskMotion.travelsSeen(try Self.steps())
        let fade = try #require(Self.opacity(seen, "$1/trash"))
        let keys = AskMotionCheck.timed(fade)
        // Seen the whole throw (0.5 to 1.0 s), faded over the last 0.1 s of it.
        let at = { (seconds: Double) in AskMotionCheck.value(of: fade, at: seconds)?.doubleValue ?? -1 }
        #expect(at(0.95) >= 90, "\(keys.map { ($0.seconds, $0.value) })")
        #expect(at(1.1) <= 1, "\(keys.map { ($0.seconds, $0.value) })")
    }

    @Test("No two keys the landing makes are closer than the app takes")
    func neverTooClose() throws {
        // A key the app would read as one with its neighbour is merged into
        // it, whichever step of the landing put it there.
        let close = AskStep(tool: "set_keys", arguments: try Self.args(#"{"keys":[{"seconds":0,"value":100},{"seconds":1.38,"value":100},{"seconds":1.48,"value":0},{"seconds":1.5,"value":100}],"layer":"$1/trash","property":"opacity"}"#))
        let apart = AskMotion.keysApart([close])
        #expect(Self.refusals(apart).isEmpty, "\(Self.refusals(apart))")
        let seconds = AskMotionCheck.timed(apart[0]).map(\.seconds)
        #expect(seconds.first == 0 && seconds.last == 1.5, "\(seconds)")
        #expect(AskMotionCheck.timed(apart[0]).contains { $0.value.doubleValue == 0 }, "the fade out is kept")
    }
}

/// Frames of a landed plan, for eyes: every drawn part's line at each
/// moment, as the contact checks read it, written as JSON for
/// `Scripts/ask-eval/lap-frames.py`.
enum LapDump {
    static func write(_ steps: [AskStep], to path: String, frames: Int = 32) throws {
        guard let lap = AskMotion.Lap(steps) else { return }
        let lapEnd = steps.last { $0.tool == "set_timing" }?.arguments["seconds"]?.doubleValue ?? 1
        let svg = steps.first { $0.tool == "add_drawing" }?.arguments["svg"]?.stringValue ?? ""
        var view: [Double] = [0, 0, 24, 24]
        if let found = svg.range(of: #"viewBox="[^"]*""#, options: .regularExpression) {
            view = svg[found].dropFirst(9).dropLast().split(separator: " ").compactMap { Double($0) }
        }
        var out: [[String: Any]] = []
        for frame in 0..<frames {
            let at = lapEnd * Double(frame) / Double(frames - 1)
            var parts: [[String: Any]] = []
            for part in lap.art.parts {
                guard case .path(let outline) = part.shape else {
                    let box = SVGArtwork.shapeBounds(part.shape)
                    parts.append(contentsOf: [line([CGPoint(x: box.minX, y: box.minY), CGPoint(x: box.maxX, y: box.minY), CGPoint(x: box.maxX, y: box.maxY), CGPoint(x: box.minX, y: box.maxY)], part, lap, at, true)])
                    continue
                }
                for ring in outline.rings { parts.append(line(ring.map(\.point), part, lap, at, outline.closed)) }
            }
            out.append(["t": at, "parts": parts])
        }
        let data = try JSONSerialization.data(withJSONObject: ["view": view, "frames": out])
        try data.write(to: URL(fileURLWithPath: path))
    }

    static func line(_ points: [CGPoint], _ part: SVGArtwork.Part, _ lap: AskMotion.Lap, _ at: Double, _ closed: Bool) -> [String: Any] {
        let chain = ([part.name].compactMap { $0 } + part.groups.reversed()).compactMap { group in
            lap.movers.first { AskMotion.plain($0) == AskMotion.plain(group) }
        }
        var moved = points
        var opacity = 100.0
        for mover in chain {
            moved = lap.moved(moved, by: mover, at: at)
            opacity = min(opacity, lap.value(mover, .opacity, at: at)?.doubleValue ?? 100)
        }
        return ["points": moved.map { [$0.x, $0.y] }, "closed": closed, "width": part.strokeWidth,
                "filled": part.fill != nil && part.fill != "none", "opacity": opacity, "name": part.name ?? ""]
    }
}

/// The same walk's plan, landed: the trash is thrown in from off the frame
/// (the last of its way in meets the lid's underside, and that is the hit
/// the model planned, not a new crossing). Off the lid a bounce turns a
/// right angle or more where there is room to, clear of the walls. Before, it faded in beside the lid and slid down the
/// lid's underside: "no visible bounce", "fades in from nowhere".
@Suite("Ask's story icons: thrown in from outside, and a bounce that turns")
struct AskMotionBounceTurnsTests {

    static func point(_ value: AgentJSON?) -> CGPoint? {
        guard let x = value?["x"]?.doubleValue, let y = value?["y"]?.doubleValue else { return nil }
        return CGPoint(x: x, y: y)
    }

    @Test("First seen off the frame, not in mid-air")
    func thrownFromOutside() throws {
        let landed = AskMotion.planned(try AskMotionFadeKeptTests.steps())
        let lap = try #require(AskMotion.Lap(landed))
        let svg = try #require(landed.first { $0.tool == "add_drawing" }?.arguments["svg"]?.stringValue)
        guard case .success(let art) = SVGArtwork.parse(svg, keepingGroups: true) else { Issue.record("no drawing"); return }
        let view = try #require(art.viewBox)
        let first = try #require(stride(from: 0.0, through: 1.5, by: 0.01).first { lap.placed("trash", at: $0)?.seen ?? false })
        let quad = try #require(lap.placed("trash", at: first)?.quad)
        #expect(quad.contains { !view.contains($0) }, "first seen at \(first) s at \(quad), inside \(view)")
    }

    @Test("Off the lid never back through it; with no room for a turn clear of the can, the way off the model's landing asks")
    func bounceTurns() throws {
        let landed = AskMotion.planned(try AskMotionFadeKeptTests.steps())
        let trash = try #require(landed.last { $0.tool == "set_keys" && $0.arguments["layer"]?.stringValue == "$1/trash" && $0.arguments["property"]?.stringValue == "position" })
        let keys = AskMotionCheck.timed(trash)
        let lap = try #require(AskMotion.Lap(landed))
        // The hit: the key where it meets the lid.
        let hit = try #require(keys.firstIndex { key in
            key.seconds > 0.6 && AskMotion.inkMeets(lap.ink("trash", at: key.seconds), lap.ink("lid", at: key.seconds))
        })
        let at = try #require(Self.point(keys[hit].value))
        let before = try #require(Self.point(AskMotionCheck.value(of: trash, at: keys[hit].seconds - 0.05)))
        let after = try #require(Self.point(keys[hit + 1].value))
        // No turn clears the can here (see below), so none is forced into its wall.
        _ = (at, before)
        // This trash is 6 across with its line in a mouth 6 across between
        // the walls' lines: no way off the lid clears the rim, so it is
        // judged on the lid it hit.
        var moment = keys[hit].seconds + 0.02
        while moment <= keys[hit + 1].seconds {
            #expect(!AskMotion.inkMeets(lap.ink("trash", at: moment), lap.ink("lid", at: moment), within: -AskMotion.passesThrough), "through the lid at \(moment)")
            moment += 0.02
        }
    }
}

extension AskMotionFadeKeptTests {
    /// Frames of this plan, landed, for eyes:
    /// `PHOTONZ_LAP_DUMP=/tmp/lap.json swift test --filter AskMotionFadeKept`, then
    /// `python3 Scripts/ask-eval/lap-frames.py /tmp/lap.json /tmp/lap.png`.
    @Test("The landed plan's frames, written out on request",
          .enabled(if: ProcessInfo.processInfo.environment["PHOTONZ_LAP_DUMP"] != nil))
    func dump() throws {
        let path = try #require(ProcessInfo.processInfo.environment["PHOTONZ_LAP_DUMP"])
        try LapDump.write(AskMotion.planned(try Self.steps()), to: path)
    }
}

extension AskMotionBounceTurnsTests {
    @Test("A part with room goes off what it hit clear of the walls beside it")
    func clearOfWalls() throws {
        // A small ball thrown at a raised flap above a wide open box: room
        // enough to come off the flap without touching the box's walls.
        let svg = ##"<svg viewBox="0 0 24 24" fill="none" stroke="#1D1D1F" stroke-width="2"><g id="box"><path id="walls" d="M4 10 L4 21 L20 21 L20 10"/></g><g id="flap"><line id="flap-bar" x1="4" y1="9" x2="20" y2="9"/></g><circle id="ball" cx="20" cy="4" r="1"/></svg>"##
        let steps = [AskStep(tool: "add_drawing", arguments: ["icon": true, "subject": "box", "svg": .string(svg)]),
                     AskStep(tool: "set_timing", arguments: ["loop": true, "seconds": .number(2)]),
                     AskStep(tool: "set_keys", arguments: try AskMotionFadeKeptTests.args(#"{"keys":[{"seconds":0,"value":0},{"seconds":0.3,"value":-40},{"seconds":1.2,"value":-40},{"seconds":1.5,"value":0},{"seconds":2,"value":0}],"layer":"$1/flap","pivot":{"x":4,"y":9},"property":"rotation"}"#)),
                     AskStep(tool: "set_keys", arguments: try AskMotionFadeKeptTests.args(#"{"keys":[{"seconds":0,"value":{"x":0,"y":0}},{"seconds":0.5,"value":{"x":0,"y":0}},{"seconds":0.8,"touches":"$1/flap","value":{"x":-8,"y":3}},{"seconds":0.95,"value":{"x":-9,"y":5}},{"seconds":1.2,"value":{"x":-8,"y":14}},{"seconds":2,"value":{"x":0,"y":0}}],"layer":"$1/ball","property":"position"}"#))]
        let landed = AskMotion.touchesPlaced(steps)
        let ball = try #require(landed.last { $0.arguments["layer"]?.stringValue == "$1/ball" })
        let keys = AskMotionCheck.timed(ball)
        let hit = try #require(keys.firstIndex { abs($0.seconds - 0.8) < 0.001 })
        let at = try #require(Self.point(keys[hit].value)), after = try #require(Self.point(keys[hit + 1].value))
        let before = try #require(Self.point(AskMotionCheck.value(of: ball, at: 0.75)))
        let into = CGVector(dx: at.x - before.x, dy: at.y - before.y), out = CGVector(dx: after.x - at.x, dy: after.y - at.y)
        #expect(into.dx * out.dx + into.dy * out.dy <= 0.001, "in \(into), out \(out)")
        let lap = try #require(AskMotion.Lap(landed))
        let walls = AskMotion.lines(of: "box", in: lap)
        var moment = 0.82
        while moment <= keys[hit + 1].seconds {
            #expect(!AskMotion.inkMeets(lap.ink("ball", at: moment), walls, within: -AskMotion.passesThrough), "through the box at \(moment)")
            moment += 0.02
        }
    }
}

/// The walk's trash lands 2.6 right of the can's middle, across its right
/// wall's line, and fades there: in every frame of pass twelve and thirteen it
/// sat on the rim as it went "in". What lands in an open outline (a can, a
/// box, a cup) lands across its mouth's middle.
@Suite("Ask's story icons: what lands in an opening lands in its middle")
struct AskMotionLandsInTheMiddleTests {

    static func middleX(_ steps: [AskStep], at seconds: Double) throws -> CGFloat {
        let lap = try #require(AskMotion.Lap(steps))
        let points = lap.ink("trash", at: seconds).flatMap { $0 }
        return (points.map(\.x).min()! + points.map(\.x).max()!) / 2
    }

    @Test("Landed, the walk's trash goes out of sight across the can's middle")
    func walk() throws {
        let landed = AskMotion.planned(try AskMotionFadeKeptTests.steps())
        // The can's mouth runs from x 7 to 17: its middle is 12.
        // Before: 14.6, across the right wall. The tuck may still turn it a
        // little as it pushes it in past the lid's line.
        let x = try Self.middleX(landed, at: 1.1)
        #expect(abs(x - 12) <= 0.75, "\(x)")
        // Going in, it is clear of the can's outline (its ribs are inside).
        let lap = try #require(AskMotion.Lap(landed))
        let walls = AskMotion.lines(of: "body", in: lap)
        #expect(!AskMotion.inkMeets(lap.ink("trash", at: 1.08), walls, within: -AskMotion.passesThrough))
    }

    @Test("A part that lands on something closed, or in no opening, keeps its landing")
    func onlyOpenings() throws {
        let svg = ##"<svg viewBox="0 0 24 24" fill="none" stroke="#1D1D1F" stroke-width="2"><rect id="table" x="4" y="16" width="16" height="4"/><circle id="ball" cx="20" cy="4" r="1.5"/></svg>"##
        let steps = [AskStep(tool: "add_drawing", arguments: ["icon": true, "subject": "ball", "svg": .string(svg)]),
                     AskStep(tool: "set_timing", arguments: ["loop": true, "seconds": .number(2)]),
                     AskStep(tool: "set_keys", arguments: try AskMotionFadeKeptTests.args(#"{"keys":[{"seconds":0,"value":{"x":0,"y":0}},{"seconds":0.5,"value":{"x":-3,"y":10}},{"seconds":1,"value":{"x":-3,"y":10}},{"seconds":2,"value":{"x":0,"y":0}}],"layer":"$1/ball","property":"position"}"#)),
                     AskStep(tool: "set_keys", arguments: try AskMotionFadeKeptTests.args(#"{"keys":[{"seconds":0,"value":100},{"seconds":0.5,"value":100},{"seconds":0.6,"value":0},{"seconds":2,"value":0}],"layer":"$1/ball","property":"opacity"}"#))]
        #expect(AskMotion.landsInTheMiddle(steps) == steps)
    }
}

/// Walk 1 of pass thirteen: the model faded the trash from 1.1 to 1.2 s, and
/// from 1.1 s it is already on its way back to where it started: a grey
/// ghost of it rose out of the can over the shutting lid at 1.16 s.
@Suite("Ask's story icons: a part fading where it landed stays there until it is gone")
struct AskMotionStaysTillGoneTests {

    static func steps() throws -> [AskStep] {
        var steps = try AskMotionFadeKeptTests.steps()
        steps.removeLast(3)
        return steps + [
            AskStep(tool: "set_keys", arguments: try AskMotionFadeKeptTests.args(#"{"keys":[{"seconds":0,"value":100},{"seconds":0.5,"value":100},{"seconds":1.1,"value":100},{"seconds":1.2,"value":0},{"seconds":1.4,"value":0},{"seconds":1.5,"value":100}],"layer":"$1/trash","property":"opacity"}"#)),
            AskStep(tool: "set_keys", arguments: try AskMotionFadeKeptTests.args(#"{"keys":[{"seconds":0,"value":{"x":0,"y":0}},{"seconds":0.5,"value":{"x":0,"y":0}},{"seconds":0.8,"touches":"lid","value":{"x":-4,"y":3}},{"seconds":0.95,"value":{"x":-5,"y":1}},{"seconds":1.1,"touches":"bin","value":{"x":-5,"y":6}},{"seconds":1.5,"value":{"x":0,"y":0}}],"layer":"$1/trash","property":"position","replace":true}"#)),
        ]
    }

    @Test("Seen, it never starts back the way it came")
    func neverSeenGoingBack() throws {
        let landed = AskMotion.planned(try Self.steps())
        let lap = try #require(AskMotion.Lap(landed))
        let position = try #require(landed.last { $0.tool == "set_keys" && $0.arguments["layer"]?.stringValue == "$1/trash" && $0.arguments["property"]?.stringValue == "position" })
        let at = { (s: Double) -> CGPoint in
            let v = AskMotionCheck.value(of: position, at: s)
            return CGPoint(x: v?["x"]?.doubleValue ?? 0, y: v?["y"]?.doubleValue ?? 0)
        }
        // From where it is at 1.1 s on, while it can still be seen, it moves
        // no more than a hair.
        let landedAt = at(1.1)
        var moment = 1.11
        while moment < 1.5 {
            if lap.placed("trash", at: moment)?.seen ?? false {
                let now = at(moment)
                #expect(hypot(now.x - landedAt.x, now.y - landedAt.y) < 0.3, "moved to \(now) at \(moment), landed at \(landedAt)")
            }
            moment += 0.01
        }
    }
}
