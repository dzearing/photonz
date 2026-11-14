import CoreGraphics
import Foundation
@testable import PhotonzCore
import Testing

/// The eval's bell of 2026-11-14 (run 20261114-032205-ask, task
/// `an-animated-icon-told-as-a-little-story-moves-th`, pass twenty): two ring
/// marks drawn beside the bell's rim slide 4 out while they show, past the
/// frame. The frame grew to hold them with a quarter of a unit to spare, so
/// at its widest each mark sat on the frame's edge, and every look of the
/// last two runs said "the ring marks are cut off at the right edge". What
/// moves inside the frame keeps an icon's margin, as what rests does.
enum AskMotionRingsWalk {
    static func args(_ json: String) throws -> AgentJSON { try AgentJSON.parse(Data(json.utf8)) }

    static func steps() throws -> [AskStep] {
        let svg = ##"<svg viewBox="0 0 24 24" fill="none" stroke="#1D1D1F" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><g id="bell"><path id="body" d="M12 3 C8 3 6 6 6 10 L6 14 L4 16 L20 16 L18 14 L18 10 C18 6 16 3 12 3 Z"/><circle id="clapper" cx="12" cy="18" r="2"/><circle id="knob" cx="12" cy="3" r="1.5"/></g><path id="arc-right" d="M19 11 C21 12 21 14 19 15"/><path id="arc-left" d="M5 11 C3 12 3 14 5 15"/></svg>"##
        return [
            AskStep(tool: "add_drawing", arguments: ["icon": true, "subject": "bell", "svg": .string(svg)]),
            AskStep(tool: "set_timing", arguments: try args(#"{"loop":true,"seconds":2.6}"#)),
            AskStep(tool: "set_keys", arguments: try args(#"{"keys":[{"curve":"Ease in","seconds":0,"value":0},{"curve":"Ease out back","seconds":0.15,"value":-6},{"curve":"Ease in out","seconds":0.45,"value":14},{"curve":"Ease in out","seconds":0.85,"value":-14},{"curve":"Ease in out","seconds":1.3,"value":6},{"curve":"Ease in out","seconds":1.7,"value":-3},{"curve":"Ease out","seconds":2.1,"value":0},{"seconds":2.6,"value":0}],"layer":"$1/bell","pivot":{"x":12,"y":3},"property":"rotation"}"#)),
            AskStep(tool: "set_keys", arguments: try args(#"{"keys":[{"seconds":0,"value":0},{"seconds":0.45,"value":0},{"seconds":0.55,"value":100},{"seconds":0.95,"value":0},{"seconds":2.6,"value":0}],"layer":"$1/arc-right","property":"opacity"}"#)),
            AskStep(tool: "set_keys", arguments: try args(#"{"keys":[{"seconds":0,"value":30},{"seconds":0.45,"value":30},{"seconds":0.55,"value":100},{"seconds":0.95,"value":100},{"seconds":2.6,"value":30}],"layer":"$1/arc-right","property":"scale"}"#)),
            AskStep(tool: "set_keys", arguments: try args(#"{"keys":[{"seconds":0,"value":0},{"seconds":0.85,"value":0},{"seconds":0.95,"value":100},{"seconds":1.35,"value":0},{"seconds":2.6,"value":0}],"layer":"$1/arc-left","property":"opacity"}"#)),
            AskStep(tool: "set_keys", arguments: try args(#"{"keys":[{"seconds":0,"value":30},{"seconds":0.85,"value":30},{"seconds":0.95,"value":100},{"seconds":1.35,"value":100},{"seconds":2.6,"value":30}],"layer":"$1/arc-left","property":"scale"}"#)),
            AskStep(tool: "set_keys", arguments: try args(#"{"keys":[{"seconds":0,"value":{"x":0,"y":0}},{"seconds":0.45,"value":{"x":0,"y":0}},{"seconds":0.55,"value":{"x":4,"y":0}},{"seconds":0.95,"value":{"x":4,"y":0}},{"seconds":2.6,"value":{"x":0,"y":0}}],"layer":"$1/arc-right","property":"position","replace":true}"#)),
            AskStep(tool: "set_keys", arguments: try args(#"{"keys":[{"seconds":0,"value":{"x":0,"y":0}},{"seconds":0.85,"value":{"x":0,"y":0}},{"seconds":0.95,"value":{"x":-4,"y":0}},{"seconds":1.35,"value":{"x":-4,"y":0}},{"seconds":2.6,"value":{"x":0,"y":0}}],"layer":"$1/arc-left","property":"position","replace":true}"#)),
        ]
    }
}

@Suite("Ask's moving icons: what moves inside the frame keeps an icon's margin")
struct AskMotionRoomMarginTests {
    /// The least gap, in units of the final 24 grid, between the frame's
    /// edge and the furthest `part`'s keys take its ink (its lines' true
    /// bounds, each as wide as its stroke).
    static func leastGap(_ landed: [AskStep], _ part: String) throws -> CGFloat {
        let svg = try #require(landed.first { $0.tool == "add_drawing" }?.arguments["svg"]?.stringValue)
        let art = try SVGArtwork.parse(svg, keepingGroups: true).get()
        let view = try #require(art.viewBox)
        let far = try #require(AskMotionCheck.reach(of: landed.filter { $0.tool == "set_keys" }, in: art, only: part))
        let least = min(far.minX - view.minX, view.maxX - far.maxX, far.minY - view.minY, view.maxY - far.maxY)
        return least * 24 / view.width
    }

    @Test("The bell's ring marks, slid out past the frame, keep three quarters of a unit from its edge while they show")
    func ringsKeepTheirMargin() throws {
        let landed = AskMotion.planned(try AskMotionRingsWalk.steps())
        for ring in ["arc-right", "arc-left"] {
            let gap = try Self.leastGap(landed, ring)
            #expect(gap >= 0.7, "\(ring) comes \(gap) from the edge")
        }
    }

    @Test("What flies off the frame still leaves it: the margin is only for what stays in")
    func leavingStillLeaves() throws {
        let svg = ##"<svg viewBox="0 0 24 24" fill="none" stroke="#1D1D1F" stroke-width="2"><g id="plane"><path d="M4 12 L20 6 L14 20 Z"/></g></svg>"##
        let drawing = AskStep(tool: "add_drawing", arguments: ["subject": "plane", "svg": .string(svg)])
        let fly = AskStep(tool: "set_keys", arguments: try AgentJSON.parse(Data(#"{"layer":"$1/plane","property":"position","keys":[{"seconds":0,"value":{"x":0,"y":0}},{"curve":"Ease in","seconds":0.5,"value":{"x":0,"y":0}},{"seconds":1,"value":{"x":30,"y":-30}},{"seconds":2,"value":{"x":30,"y":-30}}]}"#.utf8)))
        let landed = AskMotion.fitted([drawing, fly])
        let view = try AskMotionRoomTests.view(landed)
        #expect(view.width <= 24 * AskMotion.mostRoom + 0.01, "\(view)")
    }
}

