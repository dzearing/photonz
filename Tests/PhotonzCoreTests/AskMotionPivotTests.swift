import Foundation
import Testing
@testable import PhotonzCore

/// A part that swings turns about a point on it or on what it is fixed to,
/// never about a point in empty space (`AskMotionCheck.turnsAboutNothing`).
/// The judge, 2026-11-14, of plans for several different subjects: "floats
/// off its hinge", "detached up and to the left", "swings from nowhere".
@Suite struct AskMotionPivotTests {
    static let svg = ##"""
    <svg viewBox="0 0 24 24" fill="none" stroke="#1D1D1F" stroke-width="2"><rect id="base" x="4" y="16" width="16" height="4"/><g id="arm"><line id="rod" x1="12" y1="6" x2="12" y2="15"/></g></svg>
    """##
    static let drawing = AskStep(tool: "add_drawing", arguments: ["subject": "thing", "svg": .string(svg)])

    static func turn(pivotX: Double, pivotY: Double, to value: Int = 30) throws -> AskStep {
        AskStep(tool: "set_keys", arguments: try AskMotionTests.args(#"{"layer":"$1/arm","property":"rotation","pivot":{"x":\#(pivotX),"y":\#(pivotY)},"keys":[{"seconds":0,"value":0},{"seconds":0.5,"value":\#(value)},{"seconds":1,"value":0}]}"#))
    }

    @Test("A swing about a point well away from the part and from everything still is sent back, saying where the joint goes")
    func emptySpace() throws {
        let said = AskMotionCheck.problems([Self.drawing, try Self.turn(pivotX: 21, pivotY: 3)]).joined(separator: " ")
        #expect(said.contains("arm turns about x 21 y 3"), "\(said)")
        #expect(said.contains("joint"), "\(said)")
    }

    @Test("A swing about its own end, about a point on what it stands on, or about its own middle is left alone")
    func onAJoint() throws {
        #expect(AskMotionCheck.problems([Self.drawing, try Self.turn(pivotX: 12, pivotY: 15)]).isEmpty)
        #expect(AskMotionCheck.problems([Self.drawing, try Self.turn(pivotX: 12, pivotY: 17)]).isEmpty)
        #expect(AskMotionCheck.problems([Self.drawing, try Self.turn(pivotX: 12, pivotY: 10)]).isEmpty)
        // A pivot said as fractions of the part is on the part.
        #expect(AskMotionCheck.problems([Self.drawing, try Self.turn(pivotX: 0.5, pivotY: 1)]).isEmpty)
    }

    @Test("A turn all the way round about a far centre is an orbit, and is left alone")
    func orbit() throws {
        #expect(AskMotionCheck.problems([Self.drawing, try Self.turn(pivotX: 21, pivotY: 3, to: 360)]).allSatisfy { !$0.contains("turns about") })
    }
}
