import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// A drawing written as SVG comes in as editable layers (`SVGArtwork.swift`):
/// Ask's drawings, the built-in drawing set, and one day File ▸ Open.
@Suite("SVG drawings become editable layers")
struct SVGArtworkTests {

    static func parse(_ text: String) throws -> SVGArtwork {
        try SVGArtwork.parse(text).get()
    }

    static func near(_ a: CGFloat, _ b: CGFloat, _ slack: CGFloat = 0.01) -> Bool { abs(a - b) <= slack }

    static func near(_ a: CGPoint, _ b: CGPoint, _ slack: CGFloat = 0.01) -> Bool {
        near(a.x, b.x, slack) && near(a.y, b.y, slack)
    }

    // MARK: Reading

    @Test("Circles, ellipses and rectangles come in as ovals and boxes, named by their ids")
    func basicShapes() throws {
        let drawing = try Self.parse("""
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
              <circle id="head" cx="50" cy="50" r="40" fill="#FFCC4D"/>
              <ellipse id="left-eye" cx="35" cy="40" rx="5" ry="8" fill="#664500"/>
              <rect id="hat_band" x="10" y="0" width="80" height="10" rx="2" fill="red"/>
            </svg>
            """)
        #expect(drawing.parts.count == 3)
        #expect(drawing.parts.map(\.name) == ["Head", "Left eye", "Hat band"])
        #expect(drawing.parts[0].shape == .ellipse(CGRect(x: 10, y: 10, width: 80, height: 80)))
        #expect(drawing.parts[1].shape == .ellipse(CGRect(x: 30, y: 32, width: 10, height: 16)))
        #expect(drawing.parts[2].shape == .rect(CGRect(x: 10, y: 0, width: 80, height: 10), radius: 2))
        #expect(drawing.parts[0].fill == "#FFCC4D")
        #expect(drawing.parts[2].fill == "#FF0000")
        #expect(drawing.viewBox == CGRect(x: 0, y: 0, width: 100, height: 100))
    }

    @Test("A path's straight runs, absolute and relative, land on the right points")
    func straightRuns() throws {
        let drawing = try Self.parse(#"<svg viewBox="0 0 50 50"><path d="M10 10 H30 v10 l-10 5 L10 20z"/></svg>"#)
        guard case .path(let path) = drawing.parts.first?.shape else { Issue.record("not a path"); return }
        #expect(path.closed)
        #expect(path.rings.count == 1)
        let points = path.rings[0].map(\.point)
        #expect(points == [CGPoint(x: 10, y: 10), CGPoint(x: 30, y: 10), CGPoint(x: 30, y: 20),
                           CGPoint(x: 20, y: 25), CGPoint(x: 10, y: 20)])
        // An SVG with no fill said is filled black, as a browser draws it.
        #expect(drawing.parts[0].fill == "#000000")
        #expect(drawing.parts[0].stroke == nil)
    }

    @Test("Curves keep their handles, and smooth and quadratic curves are worked out")
    func curves() throws {
        let drawing = try Self.parse(#"<svg viewBox="0 0 100 100"><path d="M0 0C10 0 20 10 20 20S30 40 40 40Q50 40 50 50T60 60"/></svg>"#)
        guard case .path(let path) = drawing.parts.first?.shape else { Issue.record("not a path"); return }
        let ring = path.rings[0]
        #expect(ring.count == 5)
        #expect(ring[0].handleOut == CGPoint(x: 10, y: 0))
        #expect(ring[1].point == CGPoint(x: 20, y: 20))
        #expect(ring[1].handleIn == CGPoint(x: 0, y: -10))
        // S reflects the last control point through the current point.
        #expect(ring[1].handleOut == CGPoint(x: 0, y: 10))
        #expect(ring[1].kind == .smooth)
        // A quadratic's control at (50,40) from (40,40) to (50,50) is a cubic
        // with handles two thirds of the way to it.
        #expect(Self.near(ring[2].handleOut ?? .zero, CGPoint(x: 20.0 / 3, y: 0)))
        #expect(Self.near(ring[3].handleIn ?? .zero, CGPoint(x: 0, y: -20.0 / 3)))
        #expect(ring[4].point == CGPoint(x: 60, y: 60))
    }

    @Test("Numbers written tight together, and arc flags with no spaces, are read the way a browser reads them")
    func tightNumbers() throws {
        let drawing = try Self.parse(#"<svg viewBox="0 0 36 36"><path d="M1.5.5l2-1e1L.5.5a2 2 0 012 2z"/></svg>"#)
        guard case .path(let path) = drawing.parts.first?.shape else { Issue.record("not a path"); return }
        let points = path.rings[0].map(\.point)
        #expect(Self.near(points[0], CGPoint(x: 1.5, y: 0.5)))
        #expect(Self.near(points[1], CGPoint(x: 3.5, y: -9.5)))
        #expect(Self.near(points[2], CGPoint(x: 0.5, y: 0.5)))
        #expect(Self.near(points.last ?? .zero, CGPoint(x: 2.5, y: 2.5)))
    }

    @Test("A circle drawn with two arcs comes back round, with its closing point joined to its first")
    func arcCircle() throws {
        let drawing = try Self.parse(#"<svg viewBox="0 0 20 20"><path d="M0 10a10 10 0 1 1 20 0a10 10 0 1 1-20 0z"/></svg>"#)
        guard case .path(let path) = drawing.parts.first?.shape else { Issue.record("not a path"); return }
        let ring = path.rings[0]
        // Two half circles, each two quarter curves; the last point is the
        // first again and is folded into it.
        #expect(ring.count == 4)
        #expect(ring.allSatisfy { $0.handleIn != nil && $0.handleOut != nil })
        let bounds = drawing.bounds
        #expect(Self.near(bounds.minX, 0, 0.05) && Self.near(bounds.maxX, 20, 0.05))
        #expect(Self.near(bounds.minY, 0, 0.05) && Self.near(bounds.maxY, 20, 0.05))
    }

    @Test("A group's paint and transform reach what it holds, and its id names the unnamed")
    func groups() throws {
        let drawing = try Self.parse("""
            <svg viewBox="0 0 100 100">
              <g id="ears" fill="#C1694F" transform="translate(10 20) scale(2)">
                <circle cx="5" cy="5" r="5"/>
                <circle cx="20" cy="5" r="5" fill="#00F"/>
              </g>
            </svg>
            """)
        #expect(drawing.parts.map(\.name) == ["Ears 1", "Ears 2"])
        #expect(drawing.parts[0].fill == "#C1694F")
        #expect(drawing.parts[1].fill == "#0000FF")
        #expect(drawing.parts[0].shape == .ellipse(CGRect(x: 10, y: 20, width: 20, height: 20)))
        #expect(drawing.parts[1].shape == .ellipse(CGRect(x: 40, y: 20, width: 20, height: 20)))
    }

    @Test("A turned ellipse becomes a path, since an oval layer cannot turn on its own")
    func rotatedEllipse() throws {
        let drawing = try Self.parse(#"<svg viewBox="0 0 100 100"><ellipse cx="50" cy="50" rx="20" ry="10" transform="rotate(45 50 50)"/></svg>"#)
        guard case .path(let path) = drawing.parts.first?.shape else { Issue.record("not a path"); return }
        #expect(path.closed)
        #expect(path.rings[0].count == 4)
    }

    @Test("Styles in a style attribute count, and a gradient paints with its first colour")
    func styleAndGradients() throws {
        let drawing = try Self.parse("""
            <svg viewBox="0 0 10 10">
              <defs><linearGradient id="sky"><stop offset="0" stop-color="#87CEEB"/><stop offset="1" stop-color="#fff"/></linearGradient>
                <circle id="hidden" cx="1" cy="1" r="1"/></defs>
              <rect width="10" height="10" fill="url(#sky)"/>
              <path d="M0 0L10 10" style="fill:none;stroke:#333;stroke-width:2"/>
              <rect width="1" height="1" fill="#fff" display="none"/>
            </svg>
            """)
        #expect(drawing.parts.count == 2)
        #expect(drawing.parts[0].fill == "#87CEEB")
        #expect(drawing.parts[1].fill == nil)
        #expect(drawing.parts[1].stroke == "#333333")
        #expect(drawing.parts[1].strokeWidth == 2)
        guard case .path(let line) = drawing.parts[1].shape else { Issue.record("not a path"); return }
        #expect(!line.closed)
    }

    @Test("Several pieces in one filled path stay one shape, with holes kept by its fill rule")
    func rings() throws {
        let drawing = try Self.parse(#"<svg viewBox="0 0 30 30"><path fill-rule="evenodd" d="M0 0h30v30H0zM10 10h10v10H10z"/></svg>"#)
        guard case .path(let path) = drawing.parts.first?.shape else { Issue.record("not a path"); return }
        #expect(path.rings.count == 2)
        #expect(path.evenOdd)
    }

    @Test("Polygons, polylines and lines are read")
    func polygons() throws {
        let drawing = try Self.parse("""
            <svg viewBox="0 0 10 10"><polygon id="roof" points="0,5 5,0 10,5"/>
            <polyline points="0 9 5 8 10 9" fill="none" stroke="black"/>
            <line x1="0" y1="0" x2="10" y2="10" stroke="#000" stroke-width="3"/></svg>
            """)
        #expect(drawing.parts.count == 3)
        guard case .path(let roof) = drawing.parts[0].shape else { Issue.record("not a path"); return }
        #expect(roof.closed && roof.rings[0].count == 3)
        guard case .path(let line) = drawing.parts[2].shape else { Issue.record("not a path"); return }
        #expect(!line.closed && drawing.parts[2].strokeWidth == 3)
    }

    @Test("Something that is not an SVG, or draws nothing, is refused with a sentence")
    func refusals() {
        if case .success = SVGArtwork.parse("a dog") { Issue.record("words were read as a drawing") }
        if case .success = SVGArtwork.parse("<svg viewBox=\"0 0 10 10\"><text>Dog</text></svg>") {
            Issue.record("a drawing with nothing to draw was accepted")
        }
        if case .failure(let error) = SVGArtwork.parse("<svg><circle r=\"5\"") {
            #expect(!error.message.isEmpty)
        } else {
            Issue.record("broken XML was accepted")
        }
    }

    // MARK: Becoming layers

    static let smiley = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 36 36"><circle cx="18" cy="18" r="18" fill="#FFCC4D"/><path fill="#664500" d="M10.515 23.621C10.56 23.8 11.683 28 18 28c6.318 0 7.44-4.2 7.485-4.379a.499.499 0 0 0-.237-.554.505.505 0 0 0-.6.077C24.629 23.163 22.694 25 18 25s-6.63-1.837-6.648-1.855a.502.502 0 0 0-.598-.081.5.5 0 0 0-.239.557z"/><ellipse cx="12" cy="13.5" fill="#664500" rx="2.5" ry="3.5"/><ellipse cx="24" cy="13.5" fill="#664500" rx="2.5" ry="3.5"/></svg>
        """

    @Test("A drawing fills the box it is given, centred, keeping its shape, as one named group")
    func fitsTheBox() throws {
        let drawing = try Self.parse(Self.smiley)
        let box = CGRect(x: 100, y: 50, width: 400, height: 200)
        let group = drawing.group(named: "Smiley", fitting: box)
        #expect(group.name == "Smiley")
        #expect(group.isGroup)
        #expect(group.children.count == 4)
        let bounds = group.localBounds
        // 200 tall, so 200 wide, in the middle of the 400.
        #expect(Self.near(bounds.height, 200, 0.5))
        #expect(Self.near(bounds.width, 200, 0.5))
        #expect(Self.near(bounds.midX, 300, 0.5))
        #expect(Self.near(bounds.minY, 50, 0.5))
        // The face is an oval layer a person can pick and resize; the mouth a path.
        #expect(group.children[0].annotation?.shape == .ellipse)
        #expect(group.children[1].path != nil)
        #expect(group.children[1].path?.fill != nil)
        #expect(group.children[1].path?.strokeWidth == 0)
    }

    @Test("Unnamed parts are named after the drawing, numbered from the bottom")
    func partNames() throws {
        let drawing = try Self.parse(Self.smiley)
        let group = drawing.group(named: "Smiley", fitting: CGRect(x: 0, y: 0, width: 36, height: 36))
        #expect(group.children.map(\.name) == ["Smiley 1", "Smiley 2", "Smiley 3", "Smiley 4"])
    }

    @Test("Given part names win over the ids")
    func givenNames() throws {
        let drawing = try Self.parse(Self.smiley).named(["Face", "Mouth", "Left eye", "Right eye"])
        let group = drawing.group(named: "Smiley", fitting: CGRect(x: 0, y: 0, width: 72, height: 72))
        #expect(group.children.map(\.name) == ["Face", "Mouth", "Left eye", "Right eye"])
    }

    @Test("Lines scale with the drawing")
    func strokeScales() throws {
        let drawing = try Self.parse(##"<svg viewBox="0 0 10 10"><path d="M0 0L10 10" fill="none" stroke="#000" stroke-width="1"/></svg>"##)
        let group = drawing.group(named: "Line", fitting: CGRect(x: 0, y: 0, width: 100, height: 100))
        // The line's own width counts in the box it fits, so 11 units become 100 points.
        #expect(Self.near(group.children[0].path?.strokeWidth ?? 0, 100.0 / 11, 0.05))
    }

    @Test("As an icon, the drawing sits on the frame's live area, inside its margin, in a frame of its own")
    func iconFrame() throws {
        let drawing = try Self.parse(Self.smiley)
        let frame = drawing.iconFrame(named: "Smiley", side: 512, origin: .zero)
        #expect(frame.isFrame)
        #expect(frame.frame.size == CGSize(width: 512, height: 512))
        let margin = IconKeylines.margin(forSide: 512)
        let inside = frame.children.reduce(CGRect.null) { $0.union($1.localBounds) }
        #expect(inside.minX >= margin - 0.5 && inside.maxX <= 512 - margin + 0.5)
        #expect(inside.minY >= margin - 0.5 && inside.maxY <= 512 - margin + 0.5)
        // Filling it: a round drawing reaches the live area's edges.
        #expect(Self.near(inside.width, 512 - 2 * margin, 1))
    }
}
