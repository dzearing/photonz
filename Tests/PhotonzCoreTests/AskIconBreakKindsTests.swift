import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// Each way of breaking looks like itself (2026-11-07). A tear at the upper
/// right suits a balloon, but made a broken heart look bitten and a bubble look
/// like a cracked egg. So the model says HOW it breaks, from a general list,
/// and the tool draws that: a crack runs through it, or a burst tears one
/// edge. Nothing here knows what the object is.
@Suite("Ask breaks an icon the way it was asked to break")
struct AskIconBreakKindsTests {

    /// Wider than tall, drawn in a line.
    static let wide = """
        <svg viewBox="0 0 25 25" fill="none" stroke="#1D1D1F" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">\
        <ellipse id="pillow" cx="12" cy="12" rx="9" ry="6"/></svg>
        """
    /// Taller than wide, solid.
    static let tallSolid = """
        <svg viewBox="0 0 25 25"><path id="stone" fill="#1D1D1F" stroke="none" d="M12 3 C16 3 18 8 18 12.5 C18 17 15.5 21 12 21 C8.5 21 6 17 6 12.5 C6 8 8 3 12 3 Z"/></svg>
        """
    /// A round outline with a small part inside it, on the grid.
    static let ring = """
        <svg viewBox="0 0 24 24" fill="none" stroke="#1D1D1F" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">\
        <circle id="ring" cx="12" cy="12" r="7"/><path id="shine" d="M8.5 10.5 C8.5 9.5 9 8.8 10 8.5"/></svg>
        """

    static func parts(_ svg: String?) -> [SVGArtwork.Part] {
        guard case .success(let art)? = svg.map({ SVGArtwork.parse($0) }) else { return [] }
        return art.parts
    }

    static func flattened(_ shape: SVGArtwork.Shape) -> [CGPoint] {
        guard case .path(let outline) = shape else { return [] }
        return outline.rings.flatMap { PathContent(anchors: $0, isClosed: outline.closed).flattened() }
    }

    // MARK: The answer

    @Test("The model says how it breaks and what it is, and an answer with no way still tears")
    func answers() {
        #expect(AskIconBreak.answer(from: "cracked: a plate") == .init(kind: .crack, object: "a plate"))
        #expect(AskIconBreak.answer(from: "Shattered: a vase.") == .init(kind: .crack, object: "a vase"))
        #expect(AskIconBreak.answer(from: "burst: a kite") == .init(kind: .tear, object: "a kite"))
        #expect(AskIconBreak.answer(from: "torn: a kite") == .init(kind: .tear, object: "a kite"))
        #expect(AskIconBreak.answer(from: "<think>x</think> cracked - a plate") == .init(kind: .crack, object: "a plate"))
        #expect(AskIconBreak.answer(from: "a kite") == .init(kind: .tear, object: "a kite"))
        #expect(AskIconBreak.answer(from: "no") == nil)
        #expect(AskIconBreak.answer(from: "cracked:") == nil)
    }

    @Test("The question offers every way to break, in words that name no subject")
    func question() {
        let asked = AskIconBreak.questionBody(model: "m", request: "r")["messages"]?.arrayValue?.last?["content"]?.stringValue ?? ""
        for kind in AskIconBreak.Kind.allCases { #expect(asked.contains("\(kind.word):")) }
    }

    // MARK: A crack

    @Test("A crack in a line drawing runs right through it the short way, as one jagged line, and the outline stays whole")
    func crackInALine() throws {
        let parts = Self.parts(AskIconBreak.applied(to: Self.wide, kind: .crack))
        let body = try #require(parts.first)
        #expect(body.shape == Self.parts(Self.wide)[0].shape)
        let crack = try #require(parts.first { $0.name?.lowercased().contains("crack") == true })
        #expect(parts.count == 2)
        #expect(crack.stroke == "#1D1D1F")
        #expect(crack.strokeWidth == 2)
        #expect(crack.fill == nil)
        guard case .path(let outline) = crack.shape else { Issue.record("not a path"); return }
        #expect(!outline.closed)
        let points = try #require(outline.rings.first).map(\.point)
        // Jagged: at least four turns, each a real corner.
        #expect(points.count >= 5)
        // The short way of a wide thing is down: it starts at the top edge,
        // inside the outline.
        let box = SVGArtwork.shapeBounds(body.shape)
        let own = SVGArtwork.shapeBounds(crack.shape)
        #expect(own.height > own.width)
        // It starts in the outline's own line, its round end never past it.
        let start = points.first?.y ?? 0
        #expect(start - crack.strokeWidth / 2 >= box.minY && start < box.minY + crack.strokeWidth)
        // It runs right through, ending in the line on the far side.
        let end = points.last?.y ?? 0
        #expect(end + crack.strokeWidth / 2 <= box.maxY && end > box.maxY - crack.strokeWidth)
        #expect(own.minX > box.minX && own.maxX < box.maxX)
    }

    @Test("A crack in a solid thing splits it in two along a jagged line, the halves a little apart")
    func crackInASolid() throws {
        let parts = Self.parts(AskIconBreak.applied(to: Self.tallSolid, kind: .crack))
        #expect(parts.count == 2)
        let halves = parts.filter { $0.fill == "#1D1D1F" }
        #expect(halves.count == 2)
        #expect(Set(halves.compactMap(\.name)).count == 2)
        for half in halves {
            guard case .path(let outline) = half.shape else { Issue.record("not a path"); continue }
            #expect(outline.closed)
        }
        // The short way of a tall thing is across: one half above the other.
        let boxes = halves.map { SVGArtwork.shapeBounds($0.shape) }
        let upper = try #require(boxes.min { $0.midY < $1.midY }), lower = try #require(boxes.max { $0.midY < $1.midY })
        #expect(upper.midY < lower.midY - 4)
        #expect(abs(upper.width - lower.width) < 4)
        // Apart everywhere: no two points of the two halves touch.
        let a = Self.flattened(halves[0].shape), b = Self.flattened(halves[1].shape)
        let nearest = a.map { p in b.map { hypot(p.x - $0.x, p.y - $0.y) }.min() ?? .infinity }.min() ?? 0
        #expect(nearest >= 1)
        // Together they still are the whole thing, give or take the gap.
        let whole = SVGArtwork.shapeBounds(Self.parts(Self.tallSolid)[0].shape)
        let both = upper.union(lower)
        #expect(abs(both.width - whole.width) < 1.5)
        #expect(both.height >= whole.height && both.height < whole.height + 3)
    }

    @Test("A cracked icon on the grid lands on whole units, inside the live area")
    func crackOnTheGrid() throws {
        for svg in [Self.ring, Self.tallSolid.replacingOccurrences(of: "0 0 25 25", with: "0 0 24 24")] {
            let torn = try #require(AskIconBreak.applied(to: svg, kind: .crack))
            guard case .success(let art) = SVGArtwork.parse(torn) else { Issue.record("unreadable"); continue }
            let frame = art.iconFrame(named: "Icon", side: 512, origin: .zero)
            var document = PhotonzDocument(canvasSize: CGSize(width: 512, height: 512), layers: [frame])
            document.madeAsIcon = true
            let file = SVGExport.write(document).text
            #expect(AskIconBreakUnitsTests.placesOffTheGrid(in: file).isEmpty, "\(file)")
        }
    }

    // MARK: A tear

    @Test("A part lying in the torn stretch goes with it; a part elsewhere stays")
    func tearTakesWhatIsInTheGap() throws {
        let svg = """
            <svg viewBox="0 0 25 25" fill="none" stroke="#1D1D1F" stroke-width="2" stroke-linecap="round">\
            <circle id="ring" cx="12" cy="12" r="8"/><path id="shine" d="M15 7.5 C16 8 16.5 8.5 17 9.5"/>\
            <path id="shadow" d="M7 15 C7.5 16 8 16.5 9 17"/></svg>
            """
        let parts = Self.parts(AskIconBreak.applied(to: svg, kind: .tear))
        #expect(!parts.contains { $0.name == "Shine" || $0.name == "shine" })
        #expect(parts.contains { $0.name == "Shadow" || $0.name == "shadow" })
    }

    // MARK: In the talk

    @Test("The way it breaks reaches the tool: a crack lands as a crack")
    func talkCracks() throws {
        var talk = AskConversation(request: "a cracked pillow icon", documentRead: AskIconBreakTests.read,
                                   iconBreak: .init(kind: .crack, object: "a pillow"))
        _ = talk.take(AskIconBreakTests.reply("add_drawing", ["subject": "pillow", "svg": .string(Self.wide)]))
        let svg = try #require(talk.steps.first?.arguments["svg"]?.stringValue)
        #expect(svg.contains("crack"))
        #expect(!svg.contains("burst"))
    }
}
