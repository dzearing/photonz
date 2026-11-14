import CoreGraphics
import Foundation
@testable import PhotonzCore
import Testing

/// What drops into something drawn open at the top (a can, a cup, a bag
/// drawn as a U) goes behind its front as it drops, the way a thing put in a
/// bin is hidden by the bin. On pass seventeen's reel (2026-11-13) the
/// user's trash went into the can and faded there drawn OVER the can's ribs,
/// a dark blob on the front of the can that read as stuck to it, because an
/// open outline has no inside to hide anything: the app draws it as a line.
@Suite("Ask's story icons: what drops into an open container goes behind its front")
struct AskMotionDropsBehindTests {
    static func drawing(_ steps: [AskStep]) throws -> String {
        try #require(steps.first { $0.tool == "add_drawing" }?.arguments["svg"]?.stringValue)
    }

    static func ids(_ svg: String) -> [String] {
        let pattern = try? NSRegularExpression(pattern: #"\bid="([^"]*)""#)
        let range = NSRange(svg.startIndex..., in: svg)
        return (pattern?.matches(in: svg, range: range) ?? []).compactMap { match in
            Range(match.range(at: 1), in: svg).map { String(svg[$0]) }
        }
    }

    /// The user's own sentence, walked on 2026-11-13 (pass seventeen's walk
    /// two): after landing, the trash is drawn before the can, a closed white
    /// inside sits just under the can's outline, the ribs stay over it, and
    /// where the trash lands its middle is inside that white.
    @Test("The user's trash goes behind the can's front, ribs and all")
    func walkTwo() throws {
        let landed = AskMotion.planned(try AskMotionInBeforeShutWalkTwo.steps())
        let svg = try Self.drawing(landed)
        let order = Self.ids(svg)
        let trash = try #require(order.firstIndex(of: "trash"))
        let inside = try #require(order.firstIndex(of: "body-inside"), "no inside drawn for the can: \(svg)")
        let body = try #require(order.firstIndex(of: "body"))
        let rib = try #require(order.firstIndex(of: "rib-left"))
        #expect(trash < inside && inside < body && body < rib, "order \(order)")
        // The inside is closed, white and draws no line of its own.
        let art = try #require(try? SVGArtwork.parse(svg, keepingGroups: true).get())
        let cover = try #require(art.parts.first { $0.name.map(AskMotion.plain) == "bodyinside" })
        #expect(cover.fill?.uppercased() == "#FFFFFF")
        #expect(cover.stroke == nil)
        guard case .path(let outline) = cover.shape else { Issue.record("inside is not a path"); return }
        #expect(outline.closed)
        // The trash keeps its own group and never joins the can's.
        let crumple = try #require(art.parts.first { $0.name.map(AskMotion.plain) == "crumple" })
        #expect(crumple.groups.map(AskMotion.plain) == ["trash"])
        // Where it was last seen, its middle is behind the white.
        let lap = try #require(AskMotion.Lap(landed))
        var last: Double?
        var moment = 0.5
        while moment < 1.5 { if lap.placed("trash", at: moment)?.seen ?? false { last = moment }; moment += 0.01 }
        let at = try #require(last)
        let points = lap.ink("trash", at: at).flatMap { $0 }
        let middle = CGPoint(x: points.map(\.x).reduce(0, +) / CGFloat(points.count), y: points.map(\.y).reduce(0, +) / CGFloat(points.count))
        let region = AskMotion.hull(lap.ink("body-inside", at: at).flatMap { $0 })
        #expect(region.count > 2 && AskMotion.inside(middle, region), "last seen at \(at) with its middle at \(middle), outside the can")
    }

    @Test("Pass sixteen's walk too: the trash goes behind the can")
    func walkOne() throws {
        let landed = AskMotion.planned(try AskMotionInBeforeShutWalk.steps())
        let order = Self.ids(try Self.drawing(landed))
        let trash = try #require(order.firstIndex(of: "trash"))
        let inside = try #require(order.firstIndex(of: "body-inside"), "order \(order)")
        let body = try #require(order.firstIndex(of: "body"))
        #expect(trash < inside && inside < body)
    }

    /// Thrown past the can and landing beside it: nothing to go behind.
    @Test("A part that never lands inside the open outline is drawn as it was")
    func landsBeside() throws {
        let args = AskMotionInBeforeShutWalk.args
        let bin = AskMotionInBeforeShutWalkTwo.bin
        let steps: [AskStep] = [
            AskStep(tool: "add_drawing", arguments: ["icon": true, "subject": "a bin and a ball", "svg": .string(bin)]),
            AskStep(tool: "set_timing", arguments: ["loop": true, "seconds": .number(1.5)]),
            AskStep(tool: "set_keys", arguments: try args(#"{"keys":[{"seconds":0,"value":{"x":0,"y":0}},{"seconds":0.6,"value":{"x":1,"y":14}},{"seconds":1.5,"value":{"x":1,"y":14}}],"layer":"$1/trash","property":"position"}"#)),
        ]
        let landed = AskMotion.planned(steps)
        let svg = try Self.drawing(landed)
        #expect(!svg.contains("body-inside"))
        let order = Self.ids(svg)
        #expect((order.firstIndex(of: "trash") ?? 0) > (order.firstIndex(of: "body") ?? 0))
    }

    /// A stroke with no mouth (a single bent line) holds nothing.
    @Test("A plain line or a shallow bend is not a container")
    func notAContainer() throws {
        #expect(AskMotion.vesselRegion(of: CGPoint(x: 2, y: 2), CGPoint(x: 20, y: 20), points: [CGPoint(x: 2, y: 2), CGPoint(x: 20, y: 20)]) == nil)
        // A shallow arc: ends 16 apart, sags 1.
        #expect(AskMotion.vesselRegion(of: CGPoint(x: 2, y: 10), CGPoint(x: 18, y: 10),
                                       points: [CGPoint(x: 2, y: 10), CGPoint(x: 10, y: 11), CGPoint(x: 18, y: 10)]) == nil)
        // A U: ends 14 apart, 12 deep.
        #expect(AskMotion.vesselRegion(of: CGPoint(x: 5, y: 8), CGPoint(x: 19, y: 8),
                                       points: [CGPoint(x: 5, y: 8), CGPoint(x: 6, y: 20), CGPoint(x: 18, y: 20), CGPoint(x: 19, y: 8)]) != nil)
    }
}

extension AskMotionDropsBehindTests {
    /// Pass nineteen's walk of the user's sentence (2026-11-14): the model
    /// drew the trash FIRST, already behind the can's lines, so nothing was
    /// moved and no inside was drawn. The can's open outline hid nothing:
    /// the scrap showed through the can over its back and sat on the shut
    /// can's front as it faded (1.2 to 1.3 s on the walk's reel). A part
    /// already drawn behind a container needs the container's inside just
    /// the same.
    @Test("Drawn behind the can already, the trash still gets the can's inside in front of it")
    func alreadyBehind() throws {
        var steps = try AskMotionInBeforeShutWalkTwo.steps()
        let index = try #require(steps.firstIndex { $0.tool == "add_drawing" })
        let trash = #"<g id="trash"><path id="crumple" d="M18 2 L21 3 L20 5 L17 4 Z"/></g>"#
        let svg = AskMotionInBeforeShutWalkTwo.bin.replacingOccurrences(of: trash, with: "")
            .replacingOccurrences(of: #"stroke-linejoin="round">"#, with: #"stroke-linejoin="round">"# + trash)
        #expect(Self.ids(svg).first == "trash")
        var object = try #require(steps[index].arguments.objectValue)
        object["svg"] = .string(svg)
        steps[index] = AskStep(tool: "add_drawing", arguments: .object(object))
        let landed = AskMotion.planned(steps)
        let order = Self.ids(try Self.drawing(landed))
        let at = try #require(order.firstIndex(of: "trash"))
        let inside = try #require(order.firstIndex(of: "body-inside"), "no inside drawn for the can: \(order)")
        let body = try #require(order.firstIndex(of: "body"))
        #expect(at < inside && inside < body, "order \(order)")
    }
}

