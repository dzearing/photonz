import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// A torn icon reads in 24 whole units like every other icon in a 512 picture.
///
/// The tear is worked out at the size it will land, on whole units, so nothing
/// after it has to round what it cut. These drawings are the model's own, read
/// back from the eval's logs on 2026-11-06: they hang, stand off centre and sit
/// on half units, which is what made a tear land in fractions.
@Suite("A torn icon writes whole units")
struct AskIconBreakUnitsTests {

    static let drawings: [(name: String, svg: String)] = [
        ("hangs below the live area", """
        <svg viewBox="0 0 24 24" fill="none" stroke="#1D1D1F" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path id="body" d="M12 2 C15.5 2 18 5 18 9 C18 12.5 15.5 15.5 13 16.5 L13 17.5 L11 17.5 L11 16.5 C8.5 15.5 6 12.5 6 9 C6 5 8.5 2 12 2 Z"/><path id="knot" d="M11 17.5 L10 19 L14 19 L13 17.5 Z" fill="#1D1D1F" stroke="none"/><path id="string" d="M12 19 C12 20.5 11 21.5 12 23"/></svg>
        """),
        ("hangs, with a narrower neck", """
        <svg viewBox="0 0 24 24" fill="none" stroke="#1D1D1F" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path id="body" d="M12 2 C15.5 2 18 5 18 9 C18 12.5 15 15.5 12 15.5 C9 15.5 6 12.5 6 9 C6 5 8.5 2 12 2 Z"/><path id="knot" d="M11 15.5 L10 17.5 L14 17.5 L13 15.5 Z" fill="#1D1D1F" stroke="none"/><path id="string" d="M12 17.5 C12 19.5 10.5 20.5 12 22"/></svg>
        """),
        ("drawn on half units", """
        <svg viewBox="0 0 24 24"><path id="heart" d="M12 20.5 C 7.5 17 3.5 13.5 3.5 9.5 C 3.5 6.5 5.5 4.5 8 4.5 C 9.8 4.5 11.2 5.5 12 7 C 12.8 5.5 14.2 4.5 16 4.5 C 18.5 4.5 20.5 6.5 20.5 9.5 C 20.5 13.5 16.5 17 12 20.5 Z" fill="none" stroke="#1D1D1F" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg>
        """),
        ("solid with no line", """
        <svg viewBox="0 0 24 24"><path id="egg" fill="#1D1D1F" stroke="none" d="M12 2.5 C15.5 2.5 18 7.5 18 12 C18 16.5 15.5 20.5 12 20.5 C8.5 20.5 6 16.5 6 12 C6 7.5 8.5 2.5 12 2.5 Z"/></svg>
        """),
        ("a circle with a small part inside", """
        <svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg"><circle id="bubble" cx="12" cy="10.5" r="7.5" fill="none" stroke="#1D1D1F" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/><path id="highlight" d="M 7.5 8.5 A 4.5 4.5 0 0 1 10 5.5" fill="none" stroke="#1D1D1F" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg>
        """),
        ("a circle with a part below it", """
        <svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg"><circle id="bubble" cx="12" cy="10.5" r="7.5" fill="none" stroke="#1D1D1F" stroke-width="2"/><circle id="droplet" cx="12" cy="20" r="1.5" fill="#1D1D1F" stroke="none"/></svg>
        """),
        ("small on its grid", """
        <svg viewBox="0 0 24 24"><circle id="dot" cx="12" cy="12" r="4" fill="none" stroke="#000000" stroke-width="2"/></svg>
        """),
        ("a heavy line", """
        <svg viewBox="0 0 24 24"><rect id="box" x="4" y="4" width="16" height="16" rx="2" fill="none" stroke="#000000" stroke-width="3"/></svg>
        """)
    ]

    /// The drawings whose outline tears: a round line opens instead
    /// (`AskIconBreakOpensTests`).
    static let round: Set<String> = ["a circle with a small part inside", "a circle with a part below it", "small on its grid"]
    static let tearing = drawings.filter { !round.contains($0.name) }

    static func drawing(_ name: String) -> String {
        drawings.first { $0.name == name }?.svg ?? ""
    }

    static func landed(_ svg: String) throws -> (art: SVGArtwork, frame: Layer, file: String) {
        let torn = try #require(AskIconBreak.applied(to: svg))
        guard case .success(let art) = SVGArtwork.parse(torn) else { throw Unreadable() }
        let frame = art.iconFrame(named: "Icon", side: 512, origin: .zero)
        var document = PhotonzDocument(canvasSize: CGSize(width: 512, height: 512), layers: [frame])
        document.madeAsIcon = true
        return (art, frame, SVGExport.write(document).text)
    }

    struct Unreadable: Error {}

    /// The numbers in the file that say where something IS: every end of every
    /// run, not a curve's handles, which is the one fraction allowed.
    static func placesOffTheGrid(in file: String) -> [String] {
        var off: [String] = []
        func check(_ label: String, _ value: Double) {
            if abs(value - value.rounded()) > 1e-9 { off.append("\(label)=\(value)") }
        }
        for match in file.matches(of: /\sd="([^"]*)"/) {
            var command: Character = "M"
            var numbers: [Double] = []
            func flush() {
                let keep = command == "C" ? Array(numbers.suffix(2)) : numbers
                for value in keep { check("d \(command)", value) }
                numbers = []
            }
            for token in String(match.output.1).matches(of: /[A-Za-z]|-?(?:\d+\.?\d*|\.\d+)/) {
                let text = String(token.output)
                if let value = Double(text) {
                    numbers.append(value)
                } else {
                    flush()
                    command = Character(text)
                }
            }
            flush()
        }
        for match in file.matches(of: /translate\(([^)]*)\)/) {
            for value in String(match.output.1).split(whereSeparator: { " ,".contains($0) }) {
                check("translate", Double(value) ?? .nan)
            }
        }
        for match in file.matches(of: /stroke-width="([^"]*)"/) {
            check("stroke-width", (Double(String(match.output.1)) ?? .nan) * 2)
        }
        return off
    }

    static let unit: CGFloat = 512.0 / 24

    /// The marks, as landed, in units.
    static func marks(_ frame: Layer) -> [(start: CGPoint, end: CGPoint)] {
        frame.children.filter { $0.name.lowercased().hasPrefix("burst") }.sorted { $0.name < $1.name }.compactMap { layer in
            guard let path = layer.path, path.anchors.count == 2 else { return nil }
            func place(_ point: CGPoint) -> CGPoint {
                CGPoint(x: (point.x + layer.frame.minX) / unit, y: (point.y + layer.frame.minY) / unit)
            }
            return (place(path.anchors[0].point), place(path.anchors[1].point))
        }
    }

    @Test("Every end of every run and every place is whole, and a line is whole or a half", arguments: drawings)
    func wholeThroughout(_ drawing: (name: String, svg: String)) throws {
        let file = try Self.landed(drawing.svg).file
        #expect(file.contains("viewBox=\"0 0 24 24\""))
        #expect(Self.placesOffTheGrid(in: file) == [], "\(drawing.name): \(file)")
    }

    @Test("It lands inside the live area, the way the rest of the set does", arguments: drawings)
    func inTheLiveArea(_ drawing: (name: String, svg: String)) throws {
        let frame = try Self.landed(drawing.svg).frame
        let box = frame.children.reduce(CGRect.null) { $0.union($1.frame) }
        let side = IconKeylines.liveAreaSide * Self.unit
        #expect(box.width <= side + 1e-6 && box.height <= side + 1e-6, "\(drawing.name): \(box)")
        #expect(box.minX >= 0 && box.minY >= 0 && box.maxX <= 512 && box.maxY <= 512, "\(drawing.name): \(box)")
        #expect(abs(box.midX - 256) <= Self.unit && abs(box.midY - 256) <= Self.unit, "\(drawing.name): \(box)")
    }

    @Test("Every line in a torn icon is one weight", arguments: drawings)
    func oneWeight(_ drawing: (name: String, svg: String)) throws {
        let frame = try Self.landed(drawing.svg).frame
        let weights = Set(frame.children.compactMap { $0.path?.strokeWidth }.filter { $0 > 0 }
            .map { ($0 / Self.unit * 1000).rounded() })
        #expect(weights.count == 1, "\(drawing.name): \(weights)")
    }

    @Test("The marks fan out, turning one way, each one a real stroke", arguments: tearing)
    func theMarksFan(_ drawing: (name: String, svg: String)) throws {
        let marks = Self.marks(try Self.landed(drawing.svg).frame)
        #expect(marks.count == AskIconBreak.markCount, "\(drawing.name)")
        let angles = marks.map { atan2($0.end.y - $0.start.y, $0.end.x - $0.start.x) }
        for (one, next) in zip(angles, angles.dropFirst()) {
            #expect(next - one > 0.3, "\(drawing.name): \(angles)")
        }
        for mark in marks {
            #expect(hypot(mark.end.x - mark.start.x, mark.end.y - mark.start.y) >= 1.4, "\(drawing.name)")
        }
    }

    @Test("No mark touches what is left of the outline", arguments: tearing)
    func theMarksStandClear(_ drawing: (name: String, svg: String)) throws {
        let frame = try Self.landed(drawing.svg).frame
        let layer = try #require(frame.children.filter { $0.path?.isClosed == true }
            .max { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height })
        let body = try #require(layer.path)
        let outline = body.flattened().map {
            CGPoint(x: ($0.x + layer.frame.minX) / Self.unit, y: ($0.y + layer.frame.minY) / Self.unit)
        }
        let weight = (frame.children.compactMap { $0.path?.strokeWidth }.max() ?? 0) / Self.unit
        let line = body.strokeWidth > 0 ? weight / 2 : 0
        for mark in Self.marks(frame) {
            for step in 0...8 {
                let t = CGFloat(step) / 8
                let along = CGPoint(x: mark.start.x + (mark.end.x - mark.start.x) * t,
                                    y: mark.start.y + (mark.end.y - mark.start.y) * t)
                let nearest = outline.map { hypot($0.x - along.x, $0.y - along.y) }.min() ?? .infinity
                #expect(nearest >= line + weight / 2 + 0.2, "\(drawing.name): \(along) is \(nearest) from the outline")
            }
        }
    }

    @Test("A shape that is not round keeps its size: only a circle's middle needs an even size")
    func anEggKeepsItsSize() throws {
        let frame = try Self.landed(Self.drawing("solid with no line")).frame
        let body = try #require(frame.children.first { $0.name == "Egg" })
        #expect(body.frame.height / Self.unit >= 14 - 1e-6, "\(body.frame.height / Self.unit)")
    }

    @Test("The tear still goes in and comes back: rounding has not flattened it", arguments: tearing)
    func theTeethSurvive(_ drawing: (name: String, svg: String)) throws {
        let frame = try Self.landed(drawing.svg).frame
        let body = try #require(frame.children.filter { $0.path?.isClosed == true }
            .max { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }?.path)
        // The outline ends at the tear, crosses its three teeth and closes.
        let points = body.anchors.suffix(4).map(\.point) + body.anchors.prefix(1).map(\.point)
        #expect(points.count == 5)
        let (from, to) = (points[0], points[4])
        let across = CGPoint(x: to.x - from.x, y: to.y - from.y)
        let length = hypot(across.x, across.y)
        // How far in from the line across the tear, toward the middle of the
        // outline: the middle tooth may stand out past that line.
        let middle = CGPoint(x: body.flattened().map(\.x).reduce(0, +) / CGFloat(body.flattened().count),
                             y: body.flattened().map(\.y).reduce(0, +) / CGFloat(body.flattened().count))
        let inward: CGFloat = ((middle.x - from.x) * across.y - (middle.y - from.y) * across.x) < 0 ? -1 : 1
        func depth(_ point: CGPoint) -> CGFloat {
            inward * ((point.x - from.x) * across.y - (point.y - from.y) * across.x) / length / Self.unit
        }
        #expect(depth(points[1]) >= 1, "\(drawing.name)")
        #expect(depth(points[3]) >= 1, "\(drawing.name)")
        // A whole unit back: any less and it rounds to a staircase, which is a
        // step and not a tear.
        #expect(depth(points[2]) <= min(depth(points[1]), depth(points[3])) - 0.9, "\(drawing.name): \(points)")
    }

    @Test("The tear has a real corner in it: it never goes flat", arguments: tearing)
    func aTearHasCorners(_ drawing: (name: String, svg: String)) throws {
        let frame = try Self.landed(drawing.svg).frame
        let body = try #require(frame.children.filter { $0.path?.isClosed == true }
            .max { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }?.path)
        let points = body.anchors.suffix(4).map(\.point) + body.anchors.prefix(1).map(\.point)
        let runs = zip(points, points.dropFirst()).map { CGPoint(x: $1.x - $0.x, y: $1.y - $0.y) }
        // On a square grid a zigzag along a diagonal is right angles, so a
        // right angle counts.
        let turns = zip(runs, runs.dropFirst()).filter { $0.x * $1.x + $0.y * $1.y <= 1e-6 }
        #expect(turns.count >= 1, "\(drawing.name): \(points.map { "\($0.x / Self.unit),\($0.y / Self.unit)" })")
    }

    @Test("A drawing placed exactly across the live area is kept, not fitted and rounded again")
    func exactlyTheLiveArea() throws {
        for drawing in Self.drawings {
            let torn = try #require(AskIconBreak.applied(to: drawing.svg))
            guard case .success(let art) = SVGArtwork.parse(torn) else { throw Unreadable() }
            let points = art.parts.reduce(CGRect.null) { $0.union(SVGArtwork.shapeBounds($1.shape)) }
            let frame = art.iconFrame(named: "Icon", side: 512, origin: .zero)
            let landed = frame.children.reduce(CGRect.null) { $0.union($1.frame) }
            let side = max(landed.width, landed.height) / Self.unit
            #expect(abs(side - max(points.width, points.height)) < 0.51, "\(drawing.name): \(side) from \(points)")
        }
    }

    @Test("No stub of curve is left at either end of the tear", arguments: tearing)
    func noStubs(_ drawing: (name: String, svg: String)) throws {
        let frame = try Self.landed(drawing.svg).frame
        let body = try #require(frame.children.filter { $0.path?.isClosed == true }
            .max { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }?.path)
        let points = body.anchors.map(\.point)
        let keptEnd = points.count - 4
        let first = hypot(points[1].x - points[0].x, points[1].y - points[0].y) / Self.unit
        let last = hypot(points[keptEnd].x - points[keptEnd - 1].x, points[keptEnd].y - points[keptEnd - 1].y) / Self.unit
        #expect(first >= AskIconBreak.shortestRun - 0.75, "\(drawing.name): \(first)")
        #expect(last >= AskIconBreak.shortestRun - 0.75, "\(drawing.name): \(last)")
    }

    @Test("It sits in the middle: at most a unit between its two sides", arguments: drawings)
    func centred(_ drawing: (name: String, svg: String)) throws {
        let frame = try Self.landed(drawing.svg).frame
        let box = frame.children.reduce(CGRect.null) { $0.union($1.frame) }
        // An odd span cannot sit dead centre on 24 units, and an outer mark
        // stepping a unit evens most of them, not all.
        #expect(abs(box.minX - (512 - box.maxX)) / Self.unit <= 1 + 1e-6, "\(drawing.name): \(box)")
        #expect(abs(box.minY - (512 - box.maxY)) / Self.unit <= 1 + 1e-6, "\(drawing.name): \(box)")
    }

    @Test("A drawing with room for its marks stays about the size it was drawn, on an even number of units")
    func keepsItsSize() throws {
        let frame = try Self.landed(Self.drawing("a circle with a small part inside")).frame
        let body = try #require(frame.children.first { $0.name == "Bubble" })
        // Drawn 15 across, so 16: the even size nearest. Torn away at its upper
        // right, the bottom and left of it are what is left to measure.
        let path = try #require(body.path)
        let bottom = try #require(path.anchors.map(\.point.y).max())
        let left = try #require(path.anchors.map(\.point.x).min())
        #expect(abs(bottom / Self.unit - 16) < 1e-6, "\(bottom / Self.unit)")
        #expect(abs(left) < 1e-6, "\(left / Self.unit)")
    }

    @Test("A circle drawn on a half stays a circle: its four ends are the same way from its middle")
    func aCircleStaysRound() throws {
        let frame = try Self.landed(Self.drawing("a circle with a small part inside")).frame
        let body = try #require(frame.children.first { $0.name == "Bubble" }?.path)
        let points = body.anchors.map(\.point)
        let middle = 8 * Self.unit
        // The ends the tear left: the bottom and the left.
        #expect(points.contains { abs($0.x - middle) < 1e-6 && abs($0.y - 2 * middle) < 1e-6 })
        #expect(points.contains { abs($0.x) < 1e-6 && abs($0.y - middle) < 1e-6 })
    }

    @Test("A line weight lands on a half unit at the finest, and one drawn lighter stays lighter")
    func lineWeights() throws {
        func weights(_ svg: String) throws -> Set<CGFloat> {
            Set(try Self.landed(svg).frame.children.compactMap { $0.path?.strokeWidth }.filter { $0 > 0 }
                .map { ($0 / Self.unit * 1000).rounded() / 1000 })
        }
        // Brought down to fit its marks, its line comes down with it.
        #expect(try weights(Self.drawing("hangs below the live area")) == [1.5])
        // Brought up to fill the live area, it lands no heavier than 1.5.
        #expect(try weights(Self.drawing("a circle with a small part inside")) == [AskIconBreak.heaviestTornLine])
        let light = Self.drawing("a circle with a small part inside").replacingOccurrences(of: "stroke-width=\"2\"", with: "stroke-width=\"1\"")
        #expect(try weights(light) == [1])
    }

    @Test("A part that is not torn moves with the rest: the drawing is still the drawing")
    func everythingMovesTogether() throws {
        let svg = Self.drawing("hangs below the live area")
        let torn = try #require(AskIconBreak.applied(to: svg))
        guard case .success(let before) = SVGArtwork.parse(svg), case .success(let after) = SVGArtwork.parse(torn) else {
            throw Unreadable()
        }
        func box(_ art: SVGArtwork, _ name: String) throws -> CGRect {
            SVGArtwork.shapeBounds(try #require(art.parts.first { $0.name == name }).shape)
        }
        let scale = try box(after, "String").height / box(before, "String").height
        #expect(abs(try box(after, "Knot").width / box(before, "Knot").width - scale) < 1e-3)
        let gapBefore = try box(before, "String").minY - box(before, "Knot").minY
        let gapAfter = try box(after, "String").minY - box(after, "Knot").minY
        #expect(abs(gapAfter - gapBefore * scale) < 1e-3)
    }

    @Test("Asked for twice, it tears the same way")
    func settled() throws {
        let svg = Self.drawing("hangs below the live area")
        #expect(AskIconBreak.applied(to: svg) == AskIconBreak.applied(to: svg))
    }

    @Test("A drawing on some other grid still lands whole")
    func anotherGrid() throws {
        let file = try Self.landed("""
        <svg viewBox="0 0 48 48"><circle id="dot" cx="24" cy="24" r="15" fill="none" stroke="#000000" stroke-width="4"/></svg>
        """).file
        #expect(Self.placesOffTheGrid(in: file) == [], "\(file)")
    }

    @Test("An app icon's tile is left its full size: only an icon on the grid is placed")
    func aTileStays() throws {
        let torn = try #require(AskIconBreak.applied(to: """
        <svg viewBox="0 0 24 24"><rect id="tile" x="0" y="0" width="24" height="24" rx="5" fill="#2255EE"/><circle id="ball" cx="12" cy="12" r="7" fill="none" stroke="#FFFFFF" stroke-width="2"/></svg>
        """))
        #expect(!torn.contains("transform"))
        #expect(torn.contains("width=\"24\""))
    }
}
