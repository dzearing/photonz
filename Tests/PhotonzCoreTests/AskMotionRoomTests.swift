import CoreGraphics
import Foundation
@testable import PhotonzCore
import Testing

/// The user's trash of 2026-11-10 ("the ugliest trashcan icon i've ever
/// seen"): the model drew a can 12 across on the 24 grid, its lid swung open
/// past the top edge, and the frame grew evenly about the middle to 32.9, so
/// the can played at 73 percent of its size with its lines still 2 thick on
/// the final grid: crowded, heavy, its ribs merged into a W. Room is made
/// round what is drawn and what moves, as near the middle as that allows, so
/// a drawing grows only by what its motion really needs.
@Suite("Ask's moving icons: room is made round the drawing and its motion, not about the middle")
struct AskMotionRoomTests {

    static func view(_ steps: [AskStep]) throws -> CGRect {
        let svg = try #require(steps.first { $0.tool == "add_drawing" }?.arguments["svg"]?.stringValue)
        return try #require(try SVGArtwork.parse(svg).get().viewBox)
    }

    @Test("The trash whose lid swings past the top keeps over four fifths of its size, near the middle, and every resting line and the open lid stay in the frame")
    func trashKeepsItsSize() throws {
        let steps = try AskMotionBounceTests.steps()
        let landed = AskMotion.planned(steps)
        let box = try Self.view(landed)
        #expect(abs(box.width - box.height) < 0.01)
        #expect(box.width <= 24 / 0.84, "the can stays near the size it was drawn: \(box)")
        let art = try SVGArtwork.parse(try #require(landed.first?.arguments["svg"]?.stringValue), keepingGroups: true).get()
        let ink = art.parts.map { SVGArtwork.shapeBounds($0.shape).insetBy(dx: -$0.strokeWidth / 2, dy: -$0.strokeWidth / 2) }
            .reduce(CGRect.null) { $0.union($1) }
        #expect(box.insetBy(dx: 0.5, dy: 0.5).contains(ink), "resting ink \(ink) clear of the edge of \(box)")
        // Near the middle: off it by a twelfth of the drawing at most.
        #expect(abs(box.midX - 12) <= 2 + 0.01 && abs(box.midY - 12) <= 2 + 0.01, "\(box)")
        let lid = try #require(landed.first { $0.arguments["layer"]?.stringValue == "$1/lid" })
        #expect(box.contains(AskMotionCheck.reach(of: [lid], in: art)), "the open lid is in the frame")
    }

    @Test("Motion that needs room on one side only takes it from the other side first: a shift by whole units, nothing shrinks")
    func shiftsBeforeItGrows() throws {
        // A body low on the grid, a part that hops 4 above the top edge.
        let svg = ##"<svg viewBox="0 0 24 24" fill="none" stroke="#1D1D1F" stroke-width="2"><path id="body" d="M6 10 L18 10 L18 18 L6 18 Z"/><path id="top" d="M9 4 L15 4"/></svg>"##
        let drawing = AskStep(tool: "add_drawing", arguments: ["subject": "thing", "svg": .string(svg)])
        let hop = AskStep(tool: "set_keys", arguments: try AgentJSON.parse(Data(#"{"layer":"$1/top","property":"position","keys":[{"seconds":0,"value":{"x":0,"y":0}},{"seconds":0.5,"value":{"x":0,"y":-4}},{"seconds":1,"value":{"x":0,"y":0}}]}"#.utf8)))
        let box = try Self.view(AskMotion.fitted([drawing, hop]))
        #expect(box.width == 24, "\(box)")
        #expect(box.minY < 0 && box.minY == box.minY.rounded(), "\(box)")
        #expect(box.minX == 0)
    }

    @Test("Motion even all round still grows about the middle")
    func evenStaysCentred() throws {
        let svg = ##"<svg viewBox="0 0 24 24" fill="none" stroke="#1D1D1F" stroke-width="2"><path id="body" d="M4 4 L20 4 L20 20 L4 20 Z"/></svg>"##
        let drawing = AskStep(tool: "add_drawing", arguments: ["subject": "thing", "svg": .string(svg)])
        let grow = AskStep(tool: "set_keys", arguments: try AgentJSON.parse(Data(#"{"layer":"$1/body","property":"scale","pivot":{"x":0.5,"y":0.5},"keys":[{"seconds":0,"value":100},{"seconds":0.5,"value":150},{"seconds":1,"value":100}]}"#.utf8)))
        let box = try Self.view(AskMotion.fitted([drawing, grow]))
        #expect(box.width > 24)
        #expect(abs(box.midX - 12) < 0.01 && abs(box.midY - 12) < 0.01, "\(box)")
    }

    /// Where a part's points land on the final 24 grid, in units.
    static func landed(_ part: String, in frame: Layer) -> [CGPoint]? {
        func find(_ layer: Layer, at origin: CGPoint) -> [CGPoint]? {
            let here = CGPoint(x: origin.x + layer.frame.minX, y: origin.y + layer.frame.minY)
            if layer.name == part, case .path(let content) = layer.content {
                return content.anchors.map { CGPoint(x: (here.x + $0.point.x) / (512 / 24), y: (here.y + $0.point.y) / (512 / 24)) }
            }
            for child in layer.children { if let found = find(child, at: here) { return found } }
            return nil
        }
        return find(frame, at: .zero)
    }

    @Test("A moving icon whose frame grew lands on half units: a line drawn leaning half a unit never leans a whole one, and a small corner keeps its two ends apart")
    func grownLandsFinely() throws {
        let landed = AskMotion.planned(try AskMotionBounceTests.steps())
        let svg = try #require(landed.first?.arguments["svg"]?.stringValue)
        let art = try SVGArtwork.parse(svg, keepingGroups: true).get()
        let grew = try #require(art.viewBox).width / 24
        #expect(grew > 1.01, "this plan needs room")
        let frame = art.iconFrame(named: "Trash", side: 512, origin: .zero, onGrid: true)
        for rib in ["Rib left", "Rib right"] {
            let points = try #require(Self.landed(rib, in: frame), "\(rib)")
            #expect(points.count == 2)
            // Drawn leaning 0.5 in 6; scaled, under half a unit.
            #expect(abs(points[1].x - points[0].x) <= 0.5 + 1e-6, "\(rib) \(points)")
            for point in points { #expect(abs(point.x * 2 - (point.x * 2).rounded()) < 1e-6, "half units: \(point)") }
        }
        // The body's rounded bottom corners: drawn from left to right, every
        // anchor still steps right of the one before, so no corner folds
        // back into a hook.
        let body = try #require(Self.landed("Body", in: frame))
        for (a, b) in zip(body, body.dropFirst()) { #expect(b.x - a.x > 0.25, "\(body)") }
        // Its line weight is the drawing's 2 on the final grid.
        let text = SVGExport.write(PhotonzDocument(canvasSize: CGSize(width: 512, height: 512), layers: [frame])).text
        #expect(text.contains(#"stroke-width="2""#))
        #expect(!text.contains(#"stroke-width="1""#))
    }

    @Test("A moving icon on its own 24 grid still lands on whole units")
    func ownGridStaysWhole() throws {
        let svg = ##"<svg viewBox="0 0 24 24" fill="none" stroke="#1D1D1F" stroke-width="2"><path id="leaning" d="M10 6 L10.5 18"/></svg>"##
        let art = try SVGArtwork.parse(svg, keepingGroups: true).get()
        let frame = art.iconFrame(named: "Thing", side: 512, origin: .zero, onGrid: true)
        let points = try #require(Self.landed("Leaning", in: frame))
        for point in points { #expect(abs(point.x - point.x.rounded()) < 1e-6 && abs(point.y - point.y.rounded()) < 1e-6, "\(points)") }
    }

    @Test("A swing's reach counts its widest key: a bell swung -12 then +14 degrees is measured at 14, not at 3")
    func swingReachesItsWidestKey() throws {
        // The bell of 2026-11-11, run 20261111-061223: angles were sampled
        // every 15 degrees from the least, -12 and 3, never 14, so the room
        // was made for a swing to the left a fifth the size and the rim was
        // cut by the frame at 0.48 s.
        let svg = ##"<svg viewBox="0 0 24 24" fill="none" stroke="#1D1D1F" stroke-width="2"><line id="mount" x1="9" y1="3" x2="15" y2="3"/><g id="bell"><path id="body" d="M12 4 C8 4 6 7 6 11 L6 14 L4 17 L20 17 L18 14 L18 11 C18 7 16 4 12 4 Z"/><circle id="clapper" cx="12" cy="19" r="1.5"/></g></svg>"##
        let art = try SVGArtwork.parse(svg, keepingGroups: true).get()
        let swing = AskStep(tool: "set_keys", arguments: try AgentJSON.parse(Data(#"{"keys":[{"seconds":0,"value":0},{"seconds":0.5,"value":14},{"seconds":0.8,"value":-12},{"seconds":1.2,"value":0}],"layer":"$1/bell","pivot":{"x":12,"y":3},"property":"rotation"}"#.utf8)))
        let reach = AskMotionCheck.reach(of: [swing], in: art)
        // The box's bottom left corner (3, 21.5) turned 14 degrees about (12, 3).
        let turn = 14 * CGFloat.pi / 180
        let corner = 12 + (3 - 12) * cos(turn) - (21.5 - 3) * sin(turn)
        #expect(reach.minX <= corner + 0.01, "\(reach)")
        // And the room made holds it, the drawing kept in the middle.
        let drawing = AskStep(tool: "add_drawing", arguments: ["subject": "bell", "svg": .string(svg)])
        let box = try Self.view(AskMotion.fitted([drawing, swing]))
        #expect(box.insetBy(dx: -AskMotionCheck.edgeSlack, dy: -AskMotionCheck.edgeSlack).contains(reach), "\(box) \(reach)")
    }
}

/// The heart of run 20261111-200328 ("a heart beats twice then breaks"): each
/// half turned 20 degrees about its own middle as it moved 5 out, and the
/// judges saw both halves cut off by the frame from 1.28 to 1.70 s. A turn
/// about a part's middle was taken to need no room (true of a ring, not of a
/// half heart), so the room held the move and not the turn.
@Suite("Ask's moving icons: a part turning about its own middle gets room for what it really sweeps")
struct AskMotionTurnInPlaceRoomTests {

    static let svg = ##"<svg viewBox="0 0 24 24" fill="none" stroke="#1D1D1F" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><g id="left-half"><path id="left-outline" d="M12 20 C10 18 4 14 4 9 C4 6 6 4 8.5 4 C10 4 11.5 5 12 7"/></g><g id="right-half"><path id="right-outline" d="M12 20 C14 18 20 14 20 9 C20 6 18 4 15.5 4 C14 4 12.5 5 12 7"/></g></svg>"##

    static func keys(_ json: String) throws -> AskStep {
        AskStep(tool: "set_keys", arguments: try AgentJSON.parse(Data(json.utf8)))
    }

    /// The half's outline, walked finely, turned about its box's middle and moved.
    static func swept(_ path: String, degrees: CGFloat, dx: CGFloat) throws -> CGRect {
        let art = try SVGArtwork.parse(svg, keepingGroups: true).get()
        let part = try #require(art.parts.first { $0.name.map(AskMotion.plain) == AskMotion.plain(path) })
        let rings = BrushSketch.outline(part.shape)
        let box = SVGArtwork.shapeBounds(part.shape)
        let turn = degrees * .pi / 180
        var out = CGRect.null
        for point in rings.flatMap({ $0 }) {
            let (x, y) = (point.x - box.midX, point.y - box.midY)
            out = out.union(CGRect(x: box.midX + x * cos(turn) - y * sin(turn) + dx, y: box.midY + x * sin(turn) + y * cos(turn), width: 0, height: 0))
        }
        return out.insetBy(dx: -1, dy: -1)
    }

    @Test("The heart's halves, turned 20 degrees about their middles and moved 5 apart, stay inside the frame made for them")
    func halvesStayInTheFrame() throws {
        let drawing = AskStep(tool: "add_drawing", arguments: ["subject": "heart", "svg": .string(Self.svg)])
        let steps = [drawing,
            try Self.keys(#"{"layer":"$1/left-half","property":"position","keys":[{"seconds":0,"value":{"x":0,"y":0}},{"seconds":0.9,"value":{"x":0,"y":0}},{"seconds":1.4,"value":{"x":-5,"y":0}},{"seconds":3.2,"value":{"x":0,"y":0}}]}"#),
            try Self.keys(#"{"layer":"$1/right-half","property":"position","keys":[{"seconds":0,"value":{"x":0,"y":0}},{"seconds":0.9,"value":{"x":0,"y":0}},{"seconds":1.4,"value":{"x":5,"y":0}},{"seconds":3.2,"value":{"x":0,"y":0}}]}"#),
            try Self.keys(#"{"layer":"$1/left-half","property":"rotation","keys":[{"seconds":0,"value":0},{"seconds":0.9,"value":0},{"seconds":1.4,"value":-20},{"seconds":3.2,"value":0}]}"#),
            try Self.keys(#"{"layer":"$1/right-half","property":"rotation","keys":[{"seconds":0,"value":0},{"seconds":0.9,"value":0},{"seconds":1.4,"value":20},{"seconds":3.2,"value":0}]}"#)]
        let box = try AskMotionRoomTests.view(AskMotion.fitted(steps))
        let left = try Self.swept("left-outline", degrees: -20, dx: -5)
        let right = try Self.swept("right-outline", degrees: 20, dx: 5)
        let held = box.insetBy(dx: -AskMotionCheck.edgeSlack, dy: -AskMotionCheck.edgeSlack)
        #expect(held.contains(left), "left half at its widest \(left) in \(box)")
        #expect(held.contains(right), "right half at its widest \(right) in \(box)")
    }

    @Test("A ring spinning about its middle still needs no room: its outline turned stays where it was")
    func ringNeedsNoRoom() throws {
        let wide = ##"<svg viewBox="0 0 24 24" fill="none" stroke="#1D1D1F" stroke-width="2"><circle id="ring" cx="12" cy="12" r="10"/></svg>"##
        let ring = AskStep(tool: "add_drawing", arguments: ["subject": "thing", "svg": .string(wide)])
        let turning = try Self.keys(#"{"layer":"$1/ring","property":"rotation","keys":[{"seconds":0,"value":0},{"seconds":1,"value":360}]}"#)
        #expect(AskMotion.fitted([ring, turning]) == [ring, turning])
    }
}
