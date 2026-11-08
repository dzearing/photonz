import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// A tear is a ragged edge, not a bite (2026-11-08).
///
/// The tear crossed its gap in two long straight legs meeting near the middle,
/// and nine judges in nine called the torn balloon a Pac-Man, a pie chart or a
/// clock; its three marks, landing straight up, at 45 degrees and straight
/// across, were read as a clock's hours. Crossed in short teeth that go in and
/// come back in turn (on whole units, across a diagonal, a staircase), with
/// marks fanning out from the tear, the same drawing was judged to do what was
/// asked in 17 looks of 18 against none. Nothing here knows what the object
/// is: the drawings are the model's own.
@Suite("A tear is a ragged edge")
struct AskIconBreakRaggedTests {

    static let unit = AskIconBreakUnitsTests.unit

    /// The model's balloon as it drew it on 2026-11-08, its knot a small bent line.
    static let bentKnot = """
        <svg viewBox="0 0 24 24" fill="none" stroke="#1D1D1F" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path id="balloon" d="M12 2 C15.5 2 18 5 18 9 C18 12.5 15.5 15.5 12 15.5 C8.5 15.5 6 12.5 6 9 C6 5 8.5 2 12 2 Z"/><path id="knot" d="M11 15.5 L12 17 L13 15.5"/><path id="string" d="M12 17 C12 19 11 20 12 22"/></svg>
        """

    static var tearing: [(name: String, svg: String)] {
        AskIconBreakUnitsTests.tearing + [("a body with a bent knot", bentKnot)]
    }

    /// The corners of the tear as landed, in units: where the kept outline
    /// ends, every tooth, and where it starts again.
    static func tear(_ svg: String) throws -> [CGPoint] {
        let frame = try AskIconBreakUnitsTests.landed(svg).frame
        let layer = try #require(frame.children.filter { $0.path?.isClosed == true }
            .max { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height })
        let body = try #require(layer.path)
        let corners = body.anchors.suffix(AskIconBreak.toothCount + 1).map(\.point) + body.anchors.prefix(1).map(\.point)
        return corners.map { CGPoint(x: ($0.x + layer.frame.minX) / unit, y: ($0.y + layer.frame.minY) / unit) }
    }

    @Test("It crosses the gap in short teeth: no leg runs more than a third of the way across", arguments: tearing)
    func shortLegs(_ drawing: (name: String, svg: String)) throws {
        let corners = try Self.tear(drawing.svg)
        let across = hypot(corners[corners.count - 1].x - corners[0].x, corners[corners.count - 1].y - corners[0].y)
        for (from, to) in zip(corners, corners.dropFirst()) {
            #expect(hypot(to.x - from.x, to.y - from.y) <= across / 3 + 1e-6,
                    "\(drawing.name): a leg of \(hypot(to.x - from.x, to.y - from.y)) across \(across): \(corners)")
        }
    }

    @Test("Its teeth go in and come back in turn, each a unit or more", arguments: tearing)
    func inAndBack(_ drawing: (name: String, svg: String)) throws {
        let corners = try Self.tear(drawing.svg)
        let (from, to) = (corners[0], corners[corners.count - 1])
        let across = CGPoint(x: to.x - from.x, y: to.y - from.y)
        let length = hypot(across.x, across.y)
        let frame = try AskIconBreakUnitsTests.landed(drawing.svg).frame
        let box = frame.children.filter { $0.path?.isClosed == true }
            .max { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }?.frame ?? .zero
        let middle = CGPoint(x: box.midX / Self.unit, y: box.midY / Self.unit)
        let inward: CGFloat = ((middle.x - from.x) * across.y - (middle.y - from.y) * across.x) < 0 ? -1 : 1
        func depth(_ point: CGPoint) -> CGFloat {
            inward * ((point.x - from.x) * across.y - (point.y - from.y) * across.x) / length
        }
        let teeth = Array(corners.dropFirst().dropLast())
        #expect(teeth.count == AskIconBreak.toothCount)
        for (index, tooth) in teeth.enumerated() where index % 2 == 0 {
            #expect(depth(tooth) >= 0.99, "\(drawing.name): tooth \(index) at \(depth(tooth)): \(corners)")
        }
        for index in stride(from: 1, to: teeth.count, by: 2) {
            #expect(depth(teeth[index]) <= min(depth(teeth[index - 1]), depth(teeth[index + 1])) - 0.6,
                    "\(drawing.name): tooth \(index) at \(depth(teeth[index])): \(corners)")
        }
    }

    @Test("No mark runs straight up or straight across, so they fan out rather than tell the time", arguments: tearing)
    func noSquareMarks(_ drawing: (name: String, svg: String)) throws {
        let marks = AskIconBreakUnitsTests.marks(try AskIconBreakUnitsTests.landed(drawing.svg).frame)
        #expect(marks.count == AskIconBreak.markCount)
        for mark in marks {
            #expect(abs(mark.end.x - mark.start.x) > 1e-6 && abs(mark.end.y - mark.start.y) > 1e-6,
                    "\(drawing.name): \(mark)")
        }
    }
}
