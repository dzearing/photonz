import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// Painting a sketch with brush strokes (`docs/design/brushes.md`, decision 10):
/// the shapes of a flat SVG sketch filled the way a painter fills them, big
/// to small, each with strokes that run the way the shape runs.
@Suite("Brush sketch: a flat sketch painted stroke by stroke")
struct BrushSketchTests {

    static let canvas = CGSize(width: 960, height: 640)

    static func art(_ body: String, viewBox: String = "0 0 960 640") throws -> SVGArtwork {
        try SVGArtwork.parse(##"<svg xmlns="http://www.w3.org/2000/svg" viewBox="\##(viewBox)">\##(body)</svg>"##).get()
    }

    static func paint(_ body: String, medium: BrushMedium = .oil, viewBox: String = "0 0 960 640") throws -> [BrushSketch.Stroke] {
        BrushSketch.strokes(try art(body, viewBox: viewBox), canvas: canvas, medium: medium, seed: 7)
    }

    /// The distance from `point` to the polyline through `points`.
    static func distance(_ point: CGPoint, _ points: [CGPoint]) -> CGFloat {
        var best = CGFloat.infinity
        for (a, b) in zip(points, points.dropFirst()) {
            let dx = b.x - a.x, dy = b.y - a.y
            let length = dx * dx + dy * dy
            let t = length > 0 ? max(0, min(1, ((point.x - a.x) * dx + (point.y - a.y) * dy) / length)) : 0
            best = min(best, hypot(point.x - (a.x + t * dx), point.y - (a.y + t * dy)))
        }
        return best
    }

    static func covered(_ point: CGPoint, by strokes: [BrushSketch.Stroke]) -> Bool {
        strokes.contains { distance(point, $0.points) <= $0.size / 2 }
    }

    static func direction(_ stroke: BrushSketch.Stroke) -> CGFloat {
        let a = stroke.points[0], b = stroke.points[stroke.points.count - 1]
        return abs(atan2(b.y - a.y, b.x - a.x))
    }

    @Test("A sky over the whole canvas is covered to every edge with no bare canvas showing")
    func coversTheCanvas() throws {
        let strokes = try Self.paint(##"<rect x="0" y="0" width="960" height="640" fill="#7FA6D6"/>"##)
        var bare = 0, total = 0
        for x in stride(from: 4.0, to: 960, by: 24) {
            for y in stride(from: 4.0, to: 640, by: 24) {
                total += 1
                if !Self.covered(CGPoint(x: x, y: y), by: strokes) { bare += 1 }
            }
        }
        #expect(Double(bare) / Double(total) < 0.02, "\(bare) of \(total) sample points bare")
        #expect(strokes.count >= 12)
    }

    @Test("A wide band is painted with long level strokes, a tall trunk with upright ones")
    func strokesRunTheWayTheShapeRuns() throws {
        let band = try Self.paint(##"<rect x="0" y="400" width="960" height="120" fill="#5C8A4A"/>"##)
        let level = band.filter { Self.direction($0) < 0.35 || Self.direction($0) > .pi - 0.35 }
        #expect(Double(level.count) >= Double(band.count) * 0.8, "\(level.count) of \(band.count) level")
        let trunk = try Self.paint(##"<rect x="460" y="200" width="40" height="300" fill="#5A3B22"/>"##)
        #expect(!trunk.isEmpty)
        let upright = trunk.filter { abs(Self.direction($0) - .pi / 2) < 0.4 }
        #expect(Double(upright.count) >= Double(trunk.count) * 0.7, "\(upright.count) of \(trunk.count) upright")
    }

    @Test("Shapes are painted back to front in the sketch's own order, big brush first")
    func backToFront() throws {
        let strokes = try Self.paint("""
            <rect x="0" y="0" width="960" height="640" fill="#7FA6D6"/>
            <circle cx="700" cy="160" r="50" fill="#F2D27A"/>
            """)
        func yellow(_ stroke: BrushSketch.Stroke) -> Bool {
            let c = AgentGroupRecolour.rgb(stroke.colorHex)
            return c.r > c.b + 0.2
        }
        let sun = strokes.indices.filter { yellow(strokes[$0]) }
        let skyRows = strokes.indices.filter { !yellow(strokes[$0]) && strokes[$0].size > 80 }
        #expect(!sun.isEmpty && !skyRows.isEmpty)
        #expect((skyRows.max() ?? 0) < (sun.min() ?? 0), "the sky is painted before the sun")
        #expect(sun.allSatisfy { strokes[$0].size < 80 })
        #expect(sun.allSatisfy { Self.distance(CGPoint(x: 700, y: 160), strokes[$0].points) < 60 })
    }

    @Test("A flat fill is painted in several close shades, never one flat colour")
    func closeShades() throws {
        let strokes = try Self.paint(##"<rect x="0" y="0" width="960" height="640" fill="#7FA6D6"/>"##)
        let hexes = Set(strokes.map(\.colorHex))
        #expect(hexes.count >= 4)
        let base = AgentGroupRecolour.rgb("#7FA6D6")
        for hex in hexes {
            let c = AgentGroupRecolour.rgb(hex)
            #expect(abs(c.r - base.r) + abs(c.g - base.g) + abs(c.b - base.b) < 0.4, "\(hex) strays from the fill")
        }
    }

    @Test("A gradient sky is painted from its top colour at the top to its bottom colour at the bottom")
    func gradient() throws {
        let strokes = try Self.paint("""
            <defs><linearGradient id="s" x1="0" y1="0" x2="0" y2="1">
            <stop offset="0" stop-color="#1F3C88"/><stop offset="1" stop-color="#F6B26B"/></linearGradient></defs>
            <rect x="0" y="0" width="960" height="640" fill="url(#s)"/>
            """)
        let top = try #require(strokes.min { $0.points[0].y < $1.points[0].y })
        let bottom = try #require(strokes.max { $0.points[0].y < $1.points[0].y })
        #expect(AgentGroupRecolour.rgb(top.colorHex).b > AgentGroupRecolour.rgb(top.colorHex).r)
        #expect(AgentGroupRecolour.rgb(bottom.colorHex).r > AgentGroupRecolour.rgb(bottom.colorHex).b)
    }

    @Test("Strokes stay inside their shape, apart from running off the canvas's own edge")
    func staysInside() throws {
        let strokes = try Self.paint(##"<ellipse cx="480" cy="320" rx="200" ry="120" fill="#3E6B35"/>"##)
        #expect(!strokes.isEmpty)
        for stroke in strokes {
            let middle = stroke.points[stroke.points.count / 2]
            let inside = pow((middle.x - 480) / 200, 2) + pow((middle.y - 320) / 120, 2)
            #expect(inside <= 1.15, "a stroke's middle at \(middle) is outside the ellipse")
        }
    }

    @Test("A line in the sketch is painted along its length at its own width")
    func lines() throws {
        let strokes = try Self.paint(##"<path d="M100 500 L800 450" stroke="#222222" stroke-width="6" fill="none"/>"##)
        #expect(!strokes.isEmpty)
        #expect(strokes.allSatisfy { $0.size >= 4 && $0.size <= 9 })
        #expect(strokes.allSatisfy { Self.distance($0.points[0], [CGPoint(x: 100, y: 500), CGPoint(x: 800, y: 450)]) < 8 })
    }

    @Test("A sketch drawn in other units is fitted to the canvas")
    func fitsTheCanvas() throws {
        let strokes = try Self.paint(##"<rect x="0" y="0" width="96" height="64" fill="#7FA6D6"/>"##, viewBox: "0 0 96 64")
        #expect(Self.covered(CGPoint(x: 900, y: 600), by: strokes))
        #expect(Self.covered(CGPoint(x: 30, y: 30), by: strokes))
    }

    @Test("A busy sketch stays under the stroke budget, and the same seed paints the same strokes")
    func budgetAndSeed() throws {
        var body = ##"<rect x="0" y="0" width="960" height="640" fill="#7FA6D6"/>"##
        for index in 0..<60 {
            body += ##"<circle cx="\##(40 + (index % 12) * 80)" cy="\##(80 + (index / 12) * 110)" r="34" fill="#2F5D2A"/>"##
        }
        let strokes = try Self.paint(body)
        #expect(strokes.count <= BrushSketch.mostStrokes)
        #expect(try Self.paint(body) == strokes)
    }

    @Test("Each stroke becomes a paint_stroke call the agent tools take, the first starting its own Paint layer")
    func calls() throws {
        let strokes = try Self.paint("""
            <rect x="0" y="0" width="960" height="640" fill="#7FA6D6"/>
            <rect x="0" y="420" width="960" height="220" fill="#4F7A3A"/>
            """, medium: .watercolour)
        let calls = BrushSketch.calls(strokes, medium: .watercolour)
        #expect(calls.count == strokes.count)
        #expect(calls.first?["newLayer"]?.boolValue == true)
        #expect(calls.dropFirst().allSatisfy { $0["newLayer"] == nil })
        for call in calls {
            guard case .success(.paintStroke(_, let stroke)) = AgentTools.request(tool: "paint_stroke", arguments: call) else {
                Issue.record("\(call.encodedString()) is not a paint_stroke call")
                continue
            }
            #expect(stroke.brush.medium == .watercolour)
            #expect(stroke.seed != nil)
        }
    }

    @Test("The medium a request names is the one painted with, oil when it names none")
    func mediumFromWords() {
        #expect(BrushSketch.medium(in: "paint a small landscape in oil") == .oil)
        #expect(BrushSketch.medium(in: "paint a harbour at dusk in watercolor") == .watercolour)
        #expect(BrushSketch.medium(in: "a watercolour painting of a fox") == .watercolour)
        #expect(BrushSketch.medium(in: "paint a pastel sunset") == .chalk)
        #expect(BrushSketch.medium(in: "paint a cat with crayons") == .crayon)
        #expect(BrushSketch.medium(in: "paint a picture of a harbour at dusk") == .oil)
    }
}
