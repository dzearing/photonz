import CoreGraphics
import Foundation
@testable import PhotonzCore
import Testing

/// The user's trash story, walked on 2026-11-11 at 12:28 (task
/// `an-animated-icon-told-as-a-little-story-moves-th`), the plan exactly as the
/// model wrote it: thrown in, off the lid at 0.8 s, then landing at 1.1 s at
/// the can's mouth, across the line where the shut lid goes, and fading out
/// there. Played, the trash "vanishes in place" (the agent's own look) and a
/// grey ghost of it sits on the shut lid. What goes out of sight where
/// something closes over it goes in past it first: pushed across that part's
/// resting line, the way it closes.
@Suite("Ask's story icons: what goes in under a closing part goes in past it")
struct AskMotionTuckedInTests {

    static func args(_ json: String) throws -> AgentJSON { try AgentJSON.parse(Data(json.utf8)) }
    static let bin = ##"<svg viewBox="0 0 24 24" fill="none" stroke="#1D1D1F" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><g id="bin"><path id="body" d="M7 9 L8 20 Q8 21 9 21 L15 21 Q16 21 16 20 L17 9"/><line id="rib-left" x1="10" y1="11" x2="10.5" y2="19"/><line id="rib-right" x1="14" y1="11" x2="13.5" y2="19"/></g><g id="lid"><line id="lid-bar" x1="6" y1="8" x2="18" y2="8"/><line id="lid-knob" x1="11" y1="6" x2="13" y2="6"/></g><path id="trash" d="M19 3 L21 4 L20 6 L18 5 Z" fill="#1D1D1F" stroke="none"/></svg>"##
    static let lid = #"{"keys":[{"curve":"Hold","seconds":0,"value":0},{"curve":"Ease out","seconds":0.2,"value":0},{"curve":"Hold","seconds":0.5,"value":-40},{"curve":"Ease in out","seconds":0.8,"value":-40},{"curve":"Ease out back","seconds":0.95,"value":-30},{"curve":"Hold","seconds":1.3,"value":0},{"seconds":1.5,"value":0}],"layer":"$1/lid","pivot":{"x":6,"y":8},"property":"rotation"}"#

    static func steps(lid: String = lid) throws -> [AskStep] {
        [AskStep(tool: "add_drawing", arguments: ["icon": true, "subject": "trash bin with hinged lid", "svg": .string(bin)]),
         AskStep(tool: "set_timing", arguments: ["loop": true, "seconds": .number(1.5)]),
         AskStep(tool: "set_keys", arguments: try args(lid)),
         AskStep(tool: "set_keys", arguments: try args(#"{"keys":[{"seconds":0,"value":{"x":0,"y":0}},{"seconds":0.5,"value":{"x":0,"y":0}},{"seconds":0.8,"value":{"x":-6,"y":3}},{"seconds":0.95,"value":{"x":-7,"y":1}},{"seconds":1.1,"value":{"x":-7,"y":5}},{"seconds":1.2,"value":{"x":-7,"y":5}},{"seconds":1.5,"value":{"x":0,"y":0}}],"layer":"$1/trash","property":"position"}"#)),
         AskStep(tool: "set_keys", arguments: try args(#"{"keys":[{"seconds":0,"value":100},{"seconds":0.5,"value":100},{"seconds":1.1,"value":0},{"seconds":1.2,"value":0},{"seconds":1.5,"value":100}],"layer":"$1/trash","property":"opacity"}"#)),
         AskStep(tool: "set_keys", arguments: try args(#"{"keys":[{"seconds":0,"value":{"x":0,"y":0}},{"seconds":0.5,"value":{"x":0,"y":0}},{"seconds":0.8,"touches":"lid","value":{"x":-6,"y":3}},{"seconds":0.95,"value":{"x":-7,"y":1}},{"seconds":1.1,"value":{"x":-7,"y":5}},{"seconds":1.2,"value":{"x":-7,"y":5}},{"seconds":1.5,"value":{"x":0,"y":0}}],"layer":"$1/trash","property":"position","replace":true}"#)),
         AskStep(tool: "set_keys", arguments: try args(#"{"keys":[{"seconds":0,"value":{"x":0,"y":0}},{"seconds":0.5,"value":{"x":0,"y":0}},{"seconds":0.8,"value":{"x":-6,"y":3}},{"seconds":0.95,"value":{"x":-5,"y":1}},{"seconds":1.1,"value":{"x":-4,"y":5}},{"seconds":1.2,"value":{"x":-4,"y":5}},{"seconds":1.5,"value":{"x":0,"y":0}}],"layer":"$1/trash","property":"position","replace":true}"#))]
    }

    /// The plan as it reaches `tuckedIn` when it lands (`AskMotion.planned`).
    static func beforeTuck(_ steps: [AskStep]) -> [AskStep] {
        AskMotion.touchesPlaced(AskMotion.hitStarts(AskMotion.travelsSeen(AskMotion.holdsMove(AskMotion.drawnNotFaded(
            AskMotion.swingsFitted(AskMotion.landingFolded(AskMotion.touchesKept(steps))))))))
    }

    /// The moments, a hundredth apart from `from`, the trash is being faded
    /// out (seen, but visibly grey: under 90) and its ink comes within `gap` of the shut
    /// lid's line: the grey ghost on the lid. Crossing the mouth on the way
    /// in, fully seen, while the lid is still open, is the throw.
    static func onTheShutLine(_ steps: [AskStep], from: Double, gap: CGFloat) throws -> [Double] {
        let lap = try #require(AskMotion.Lap(steps))
        let shut = lap.ink("lid", at: 1.5)
        var hits: [Double] = []
        var moment = from
        while moment < 1.5 {
            let opacity = lap.value("trash", .opacity, at: moment)?.doubleValue ?? 100
            if opacity > 1, opacity < 90, AskMotion.inkMeets(lap.ink("trash", at: moment), shut, within: gap) { hits.append(moment) }
            moment += 0.01
        }
        return hits
    }

    @Test("Before: the walk's trash fades out across the shut lid's line")
    func reproduced() throws {
        // Landed by the app as it was (no tuck), the trash sits on the line
        // the lid shuts onto while it is still being faded out.
        let landed = Self.beforeTuck(try Self.steps())
        let onLine = try Self.onTheShutLine(landed, from: 0.95, gap: 0)
        #expect(!onLine.isEmpty)
    }

    @Test("Landed, the trash goes in past the shut lid's line before it is gone, and never through the lid")
    func goesInPast() throws {
        let landed = AskMotion.planned(try Self.steps())
        let onLine = try Self.onTheShutLine(landed, from: 0.95, gap: 0)
        #expect(onLine.isEmpty, "\(onLine)")
        let lap = try #require(AskMotion.Lap(landed))
        var moment = 0.5
        while moment < 1.5 {
            if lap.placed("trash", at: moment)?.seen ?? false {
                #expect(!AskMotion.inkMeets(lap.ink("trash", at: moment), lap.ink("lid", at: moment), within: -AskMotion.passesThrough), "through at \(moment)")
            }
            moment += 0.01
        }
    }

    @Test("It goes in the way the lid closes, and not far: down, by under a quarter of the drawing")
    func theWayItCloses() throws {
        let raw = Self.beforeTuck(try Self.steps())
        let tucked = AskMotion.tuckedIn(raw)
        let before = try #require(AskMotion.Lap(raw)), after = try #require(AskMotion.Lap(tucked))
        let was = try #require(before.value("trash", .position, at: 1.1)), now = try #require(after.value("trash", .position, at: 1.1))
        let dx = (now["x"]?.doubleValue ?? 0) - (was["x"]?.doubleValue ?? 0)
        let dy = (now["y"]?.doubleValue ?? 0) - (was["y"]?.doubleValue ?? 0)
        #expect(dy > 0.5 && dy < 6, "\(dx), \(dy)")
        #expect(abs(dx) < dy)
        // The hold after the landing went with it.
        #expect(after.value("trash", .position, at: 1.2) == now)
        // Everything before the landing is where it was.
        #expect(after.value("trash", .position, at: 0.95) == before.value("trash", .position, at: 0.95))
    }

    /// The same story walked again on 2026-11-11 at 13:20, after the trash was
    /// sent back to be drawn in lines: the model moved its landing onto the
    /// can's right rim, (-2, 3), and pushed the way the lid's end sweeps
    /// (down and to the right) the trash went down the outside of the wall.
    static let stroked = ##"<svg viewBox="0 0 24 24" fill="none" stroke="#1D1D1F" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><g id="bin"><path id="body" d="M7 9 L8 20 Q8 21 9 21 L15 21 Q16 21 16 20 L17 9"/><line id="rib-left" x1="10" y1="11" x2="10.5" y2="19"/><line id="rib-right" x1="14" y1="11" x2="13.5" y2="19"/></g><g id="lid"><line id="lid-bar" x1="6" y1="8" x2="18" y2="8"/><line id="lid-knob" x1="11" y1="6" x2="13" y2="6"/></g><path id="trash" d="M19 3 L21 4 L20 6 L18 5 Z"/></svg>"##

    static func rimSteps() throws -> [AskStep] {
        [AskStep(tool: "add_drawing", arguments: ["icon": true, "subject": "trash bin with hinged lid", "svg": .string(stroked)]),
         AskStep(tool: "set_timing", arguments: ["loop": true, "seconds": .number(1.5)]),
         AskStep(tool: "set_keys", arguments: try args(#"{"keys":[{"curve":"Hold","seconds":0,"value":0},{"curve":"Ease out","seconds":0.2,"value":0},{"curve":"Hold","seconds":0.5,"value":-40},{"curve":"Ease in","seconds":0.8,"value":-40},{"curve":"Ease out back","seconds":0.95,"value":-25},{"curve":"Hold","seconds":1.3,"value":0},{"seconds":1.5,"value":0}],"layer":"$1/lid","pivot":{"x":6,"y":8},"property":"rotation"}"#)),
         AskStep(tool: "set_keys", arguments: try args(#"{"keys":[{"seconds":0,"value":100},{"seconds":0.5,"value":100},{"seconds":1.1,"value":0},{"seconds":1.2,"value":0},{"seconds":1.5,"value":100}],"layer":"$1/trash","property":"opacity"}"#)),
         AskStep(tool: "set_keys", arguments: try args(#"{"keys":[{"seconds":0,"value":{"x":0,"y":0}},{"seconds":0.5,"value":{"x":0,"y":0}},{"seconds":0.8,"touches":"lid","value":{"x":-4,"y":3}},{"seconds":0.95,"value":{"x":-5,"y":1}},{"seconds":1.1,"touches":"bin","value":{"x":-5,"y":5}},{"seconds":1.2,"value":{"x":-5,"y":5}},{"seconds":1.5,"value":{"x":0,"y":0}}],"layer":"$1/trash","property":"position"}"#)),
         AskStep(tool: "set_keys", arguments: try args(#"{"keys":[{"seconds":0,"value":{"x":0,"y":0}},{"seconds":0.5,"value":{"x":0,"y":0}},{"seconds":0.8,"value":{"x":-4,"y":3}},{"seconds":0.95,"value":{"x":-3,"y":1}},{"seconds":1.1,"value":{"x":-2,"y":3}},{"seconds":1.2,"value":{"x":-2,"y":3}},{"seconds":1.5,"value":{"x":0,"y":0}}],"layer":"$1/trash","property":"position","replace":true}"#))]
    }

    @Test("Landing on the rim, the trash goes in past the lid into the can, never down the outside of its wall")
    func intoTheCan() throws {
        let raw = Self.beforeTuck(try Self.rimSteps())
        let tucked = AskMotion.tuckedIn(raw)
        #expect(tucked != raw)
        let lap = try #require(AskMotion.Lap(tucked))
        let ink = lap.ink("trash", at: 1.1).flatMap { $0 }
        let middle = CGPoint(x: ink.map(\.x).reduce(0, +) / CGFloat(ink.count), y: ink.map(\.y).reduce(0, +) / CGFloat(ink.count))
        // Between the can's walls (7 to 17 at the top, 8 to 16 at the foot), below the shut lid.
        #expect(middle.x > 8.5 && middle.x < 15.5, "\(middle)")
        #expect(middle.y > 10 && middle.y < 20, "\(middle)")
        #expect(!AskMotion.inkMeets(lap.ink("trash", at: 1.1), lap.ink("lid", at: 1.5), within: 0))
    }

    @Test("A part that goes out of sight clear of what closes keeps its keys")
    func leftAlone() throws {
        // The lid stays open to the lap's end: nothing closes over the trash.
        let open = #"{"keys":[{"seconds":0,"value":-40},{"seconds":1.5,"value":-40}],"layer":"$1/lid","pivot":{"x":6,"y":8},"property":"rotation"}"#
        let raw = Self.beforeTuck(try Self.steps(lid: open))
        #expect(AskMotion.tuckedIn(raw) == raw)
    }
}
