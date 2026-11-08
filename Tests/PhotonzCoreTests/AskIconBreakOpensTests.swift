import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// Something round bursts open; anything else tears (2026-11-08).
///
/// A bite out of a round line reads as eaten whatever the object is: two
/// judges in three named a torn bubble a cracked egg or a bitten cookie. With a
/// gap in its line and the stretch that went flying off in pieces along the
/// curve, three in three named it a bubble. The tool tells round from not round
/// by the outline alone; nothing here knows what the object is.
@Suite("A round outline bursts open")
struct AskIconBreakOpensTests {

    static let unit = AskIconBreakUnitsTests.unit

    /// The torn file landed as an icon frame, its biggest outline and the pieces.
    static func landed(_ svg: String) throws -> (body: Layer, pieces: [(start: CGPoint, end: CGPoint)], frame: Layer) {
        let frame = try AskIconBreakUnitsTests.landed(svg).frame
        let body = try #require(frame.children.filter { $0.path != nil && !$0.name.lowercased().hasPrefix("burst") }
            .max { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height })
        return (body, AskIconBreakUnitsTests.marks(frame), frame)
    }

    /// The outline's points as landed, in units.
    static func outline(_ layer: Layer) throws -> [CGPoint] {
        let path = try #require(layer.path)
        return path.flattened().map { CGPoint(x: ($0.x + layer.frame.minX) / unit, y: ($0.y + layer.frame.minY) / unit) }
    }

    @Test("A round line opens: its outline is left open, with no bite across it",
          arguments: AskIconBreakUnitsTests.round.sorted())
    func opens(_ name: String) throws {
        let (body, _, _) = try Self.landed(AskIconBreakUnitsTests.drawing(name))
        let path = try #require(body.path)
        #expect(!path.isClosed, "\(name)")
        // What is left of it is still round: every point the same way from
        // its middle, give or take a unit.
        let points = try Self.outline(body)
        let box = points.reduce(CGRect.null) { $0.union(CGRect(origin: $1, size: .zero)) }
        let middle = CGPoint(x: box.minX + box.height / 2, y: box.midY)
        let far = points.map { hypot($0.x - middle.x, $0.y - middle.y) }
        #expect((far.max() ?? 0) - (far.min() ?? 0) < 1, "\(name): \(far.min() ?? 0) to \(far.max() ?? 0)")
    }

    @Test("Its pieces fly out past where its line was, at its upper right, and touch nothing",
          arguments: AskIconBreakUnitsTests.round.sorted())
    func piecesFly(_ name: String) throws {
        let (body, pieces, frame) = try Self.landed(AskIconBreakUnitsTests.drawing(name))
        #expect(pieces.count == AskIconBreak.pieceCount, "\(name)")
        let points = try Self.outline(body)
        let box = points.reduce(CGRect.null) { $0.union(CGRect(origin: $1, size: .zero)) }
        // The loop's bottom and left survive the gap, so its middle is found from them.
        let radius = box.height / 2
        let middle = CGPoint(x: box.minX + radius, y: box.maxY - radius)
        let weight = (frame.children.compactMap { $0.path?.strokeWidth }.max() ?? 0) / Self.unit
        for piece in pieces {
            for step in 0...4 {
                let t = CGFloat(step) / 4
                let along = CGPoint(x: piece.start.x + (piece.end.x - piece.start.x) * t,
                                    y: piece.start.y + (piece.end.y - piece.start.y) * t)
                #expect(hypot(along.x - middle.x, along.y - middle.y) > radius + weight / 2, "\(name): \(along)")
                #expect(along.x > middle.x - 1 && along.y < middle.y + 1, "\(name): \(along) is not at the upper right")
                let nearest = points.map { hypot($0.x - along.x, $0.y - along.y) }.min() ?? .infinity
                #expect(nearest >= weight, "\(name): \(along) is \(nearest) from the outline")
            }
            #expect(hypot(piece.end.x - piece.start.x, piece.end.y - piece.start.y) >= 2 - 1e-6, "\(name)")
        }
        for (index, piece) in pieces.enumerated() {
            for other in pieces[(index + 1)...] {
                let gaps = [piece.start, piece.end].flatMap { a in [other.start, other.end].map { hypot(a.x - $0.x, a.y - $0.y) } }
                #expect((gaps.min() ?? 0) >= weight, "\(name): two pieces touch")
            }
        }
    }

    @Test("A piece lies along the curve it came from, not pointing out from the middle")
    func piecesLieAlong() throws {
        let (body, pieces, _) = try Self.landed(AskIconBreakUnitsTests.drawing("a circle with a small part inside"))
        let points = try Self.outline(body)
        let box = points.reduce(CGRect.null) { $0.union(CGRect(origin: $1, size: .zero)) }
        let middle = CGPoint(x: box.minX + box.height / 2, y: box.maxY - box.height / 2)
        for piece in pieces {
            let run = CGPoint(x: piece.end.x - piece.start.x, y: piece.end.y - piece.start.y)
            let centre = CGPoint(x: (piece.start.x + piece.end.x) / 2 - middle.x, y: (piece.start.y + piece.end.y) / 2 - middle.y)
            let cosine = abs(run.x * centre.x + run.y * centre.y) / (hypot(run.x, run.y) * hypot(centre.x, centre.y))
            #expect(cosine < 0.6, "a piece points out from the middle: \(piece)")
        }
    }

    @Test("Not round, it tears: a balloon's body, an egg-shaped line and a solid disc all keep a bite",
          arguments: ["hangs below the live area", "hangs, with a narrower neck", "an oval line", "a solid disc"])
    func notRoundTears(_ name: String) throws {
        let svg = switch name {
        case "an oval line": """
            <svg viewBox="0 0 24 24" fill="none" stroke="#1D1D1F" stroke-width="2"><ellipse id="drum" cx="12" cy="12" rx="8" ry="6.5"/></svg>
            """
        case "a solid disc": """
            <svg viewBox="0 0 24 24"><circle id="coin" cx="12" cy="12" r="8" fill="#1D1D1F" stroke="none"/></svg>
            """
        default: AskIconBreakUnitsTests.drawing(name)
        }
        let (body, marks, _) = try Self.landed(svg)
        #expect(body.path?.isClosed == true, "\(name)")
        #expect(marks.count == AskIconBreak.markCount, "\(name)")
    }

    @Test("The legs of a tear's teeth do not run straight up or across", arguments: AskIconBreakUnitsTests.tearing)
    func teethLegsSlant(_ drawing: (name: String, svg: String)) throws {
        let frame = try AskIconBreakUnitsTests.landed(drawing.svg).frame
        let body = try #require(frame.children.filter { $0.path?.isClosed == true }
            .max { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }?.path)
        let points = body.anchors.suffix(4).map(\.point) + body.anchors.prefix(1).map(\.point)
        let square = zip(points, points.dropFirst()).filter { abs($0.x - $1.x) < 1e-6 || abs($0.y - $1.y) < 1e-6 }
        #expect(square.isEmpty, "\(drawing.name): \(points.map { "\($0.x / Self.unit),\($0.y / Self.unit)" })")
    }

    @Test("Torn on the grid, a line lands at 1.5 at the heaviest")
    func notHeavy() throws {
        for drawing in AskIconBreakUnitsTests.drawings {
            let frame = try AskIconBreakUnitsTests.landed(drawing.svg).frame
            let heaviest = (frame.children.compactMap { $0.path?.strokeWidth }.max() ?? 0) / Self.unit
            #expect(heaviest <= AskIconBreak.heaviestTornLine + 1e-6, "\(drawing.name): \(heaviest)")
        }
    }

    @Test("The model is told to draw no drops or drips around the object")
    func noDrips() {
        let asked = AskIconBreak.wholeRequest(object: "a soap bubble", request: "an icon of a soap bubble bursting")
        #expect(asked.contains("no marks, drops or drips around it"))
    }
}
