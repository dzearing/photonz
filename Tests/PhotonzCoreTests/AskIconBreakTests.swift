import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// A break is drawn by a tool on the outline the model drew whole
/// (`AskIconBreak`). Nothing here, or in the tool, knows what the object is.
@Suite("Ask breaks an icon's outline")
struct AskIconBreakTests {

    static let kite = """
        <svg viewBox="0 0 24 24" fill="none" stroke="#1D1D1F" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
          <ellipse id="kite-sail" cx="12" cy="10" rx="7" ry="8"/>
          <path id="kite-tail" d="M12 18 L12 22"/>
        </svg>
        """
    static let curved = """
        <svg viewBox="0 0 24 24" fill="none" stroke="#1D1D1F" stroke-width="2">
          <path id="shell" d="M12 3 C7 3 4 8 4 13 C4 18 7 21 12 21 C17 21 20 18 20 13 C20 8 17 3 12 3 Z"/>
        </svg>
        """

    /// The same drawing off the 24 grid, where the tear stays in the drawing's
    /// own numbers. On the grid it is placed first (`AskIconBreakUnitsTests`).
    static func offGrid(_ svg: String) -> String {
        svg.replacingOccurrences(of: "0 0 24 24", with: "0 0 25 25")
    }

    static func parts(_ svg: String?) -> [SVGArtwork.Part] {
        guard case .success(let art)? = svg.map({ SVGArtwork.parse($0) }) else { return [] }
        return art.parts
    }

    static func reply(_ tool: String, _ arguments: AgentJSON) -> AgentJSON {
        ["message": ["role": "assistant", "content": "",
                     "tool_calls": [["function": ["name": .string(tool), "arguments": arguments]]]]]
    }

    // MARK: The question

    @Test("The question is asked on its own, in few words, and names no subject")
    func question() {
        let body = AskIconBreak.questionBody(model: "m", request: "a kite snapping icon")
        #expect(body["model"]?.stringValue == "m")
        #expect(body["tools"] == nil)
        #expect(body["think"]?.boolValue == false)
        #expect(body["options"]?["temperature"]?.doubleValue == 0)
        #expect(body["options"]?["num_predict"]?.intValue == AskIconBreak.mostAnswerTokens)
        let asked = body["messages"]?.arrayValue?.last?["content"]?.stringValue ?? ""
        #expect(asked.hasSuffix("a kite snapping icon"))
        #expect(asked.contains("For example:"))
    }

    @Test("The answer is the object whole, or nothing when nothing is breaking")
    func answers() {
        #expect(AskIconBreak.object(fromAnswer: "a kite") == "a kite")
        #expect(AskIconBreak.object(fromAnswer: "<think>hm</think>\n A kite.\n") == "A kite")
        #expect(AskIconBreak.object(fromAnswer: "no") == nil)
        #expect(AskIconBreak.object(fromAnswer: "No.") == nil)
        #expect(AskIconBreak.object(fromAnswer: "  ") == nil)
        #expect(AskIconBreak.object(fromAnswer: "<svg viewBox=\"0 0 24 24\"></svg>") == nil)
        let rambling = String(repeating: "a very long answer ", count: 10)
        #expect(AskIconBreak.object(fromAnswer: rambling) == nil)
    }

    // MARK: The tool

    @Test("The biggest outline is torn, and every other part stays as it was")
    func tearsTheBody() throws {
        let broken = try #require(AskIconBreak.applied(to: Self.offGrid(Self.kite)))
        let parts = Self.parts(broken)
        let body = try #require(parts.first { $0.name == "Kite sail" || $0.name == "kite-sail" })
        guard case .path(let outline) = body.shape else { Issue.record("the sail is not a path"); return }
        #expect(outline.closed)
        #expect(outline.rings.count == 1)
        let before = Self.parts(Self.kite)
        #expect(parts.contains { $0.name == before[1].name && $0.shape == before[1].shape })
        #expect(body.stroke == "#1D1D1F")
        #expect(body.strokeWidth == 2)
    }

    @Test("The outline goes in where it is torn: its top right is no longer there")
    func theTearIsATear() throws {
        let broken = try #require(AskIconBreak.applied(to: Self.kite))
        let body = try #require(Self.parts(broken).first)
        guard case .path(let outline) = body.shape else { Issue.record("not a path"); return }
        let points = try #require(outline.rings.first).map(\.point)
        // The sail's own edge at 45 degrees up and right: nothing of the
        // outline is left near it, and something now lies well inside it.
        let edge = CGPoint(x: 12 + 7 * cos(CGFloat.pi / 4), y: 10 - 8 * sin(CGFloat.pi / 4))
        #expect(points.allSatisfy { hypot($0.x - edge.x, $0.y - edge.y) > 1 })
        #expect(points.contains { hypot($0.x - 12, $0.y - 10) < 6 })
        // A clean icon: a handful of corners and the curve left, not a trace.
        #expect(points.count <= 12)
    }

    @Test("An outline of long and short runs tears in the same place: the shape the model really drew")
    func tearsAcrossUnevenRuns() throws {
        let svg = ##"<svg viewBox="0 0 24 24" fill="none" stroke="#1D1D1F" stroke-width="2"><path id="sail" d="M12 2.5 C8.5 2.5 5.5 5.5 5.5 9.5 C5.5 13.5 8.5 16.5 11 17.5 L11 18.5 L13 18.5 L13 17.5 C15.5 16.5 18.5 13.5 18.5 9.5 C18.5 5.5 15.5 2.5 12 2.5 Z"/></svg>"##
        let body = try #require(Self.parts(AskIconBreak.applied(to: Self.offGrid(svg))).first)
        guard case .path(let outline) = body.shape else { Issue.record("not a path"); return }
        let content = PathContent(anchors: outline.rings[0], isClosed: true)
        let drawn = content.flattened()
        // Nothing of the outline is left near its upper right.
        #expect(drawn.allSatisfy { hypot($0.x - 17, $0.y - 5) > 1.5 })
        // The far side is all still there.
        #expect(drawn.contains { abs($0.x - 5.5) < 0.2 && abs($0.y - 9.5) < 1 })
    }

    @Test("What is kept of a curve is still a curve, not a run of little lines")
    func keepsCurves() throws {
        let broken = try #require(AskIconBreak.applied(to: Self.curved))
        let body = try #require(Self.parts(broken).first)
        guard case .path(let outline) = body.shape else { Issue.record("not a path"); return }
        let anchors = try #require(outline.rings.first)
        #expect(anchors.contains { $0.handleOut != nil || $0.handleIn != nil })
        #expect(anchors.count <= 12)
    }

    @Test("Three short marks fly out from the tear, clear of the object and of each other")
    func marks() throws {
        let broken = try #require(AskIconBreak.applied(to: Self.offGrid(Self.kite)))
        let parts = Self.parts(broken)
        let marks = parts.filter { $0.name?.lowercased().contains("burst") == true }
        #expect(marks.count == AskIconBreak.markCount)
        let box = SVGArtwork.shapeBounds(Self.parts(Self.kite)[0].shape)
        for mark in marks {
            let own = SVGArtwork.shapeBounds(mark.shape)
            #expect(mark.stroke == "#1D1D1F")
            #expect(mark.strokeWidth == 2)
            #expect(own.midX > box.midX)
            #expect(own.midY < box.midY)
        }
        let ends = marks.map { CGPoint(x: SVGArtwork.shapeBounds($0.shape).midX, y: SVGArtwork.shapeBounds($0.shape).midY) }
        for (index, end) in ends.enumerated() {
            for other in ends[(index + 1)...] { #expect(hypot(end.x - other.x, end.y - other.y) > 2.5) }
        }
    }

    @Test("A small object's lines thin to keep the tear open at 16 px, every line alike")
    func thinsItsLines() throws {
        let svg = """
            <svg viewBox="0 0 24 24" fill="none" stroke="#1D1D1F" stroke-width="2" stroke-linecap="round">\
            <circle id="drum" cx="12" cy="9" r="6"/><path id="cord" stroke-width="2" d="M12 15 V21"/></svg>
            """
        let parts = Self.parts(AskIconBreak.applied(to: Self.offGrid(svg)))
        #expect(parts.count == 2 + AskIconBreak.markCount)
        let weights = Set(parts.map(\.strokeWidth))
        #expect(weights.count == 1)
        let weight = try #require(weights.first)
        #expect(abs(weight - 12 * AskIconBreak.lineShare) < 0.02)
    }

    @Test("A small closed outline clots at this weight, so it lands solid in the same ink")
    func smallPartsGoSolid() throws {
        let svg = """
            <svg viewBox="0 0 24 24" fill="none" stroke="#1D1D1F" stroke-width="2" stroke-linecap="round">\
            <circle id="drum" cx="12" cy="10" r="7"/><path id="clasp" d="M10.5 17.5 L13.5 17.5 L12.5 19.5 Z"/>\
            <path id="cord" d="M12 19.5 L12 22.5"/></svg>
            """
        let parts = Self.parts(AskIconBreak.applied(to: svg))
        let clasp = try #require(parts.first { $0.name == "Clasp" })
        #expect(clasp.fill == "#1D1D1F")
        #expect(clasp.stroke == nil)
        let cord = try #require(parts.first { $0.name == "Cord" })
        #expect(cord.stroke == "#1D1D1F")
        #expect(cord.fill == nil)
    }

    @Test("A line is never made heavier than the model drew it")
    func neverHeavier() throws {
        let parts = Self.parts(AskIconBreak.applied(to: Self.offGrid(Self.kite)))
        #expect(parts.allSatisfy { $0.strokeWidth == 2 })
    }

    @Test("A solid icon is notched, and its marks take its ink")
    func filled() throws {
        let svg = ##"<svg viewBox="0 0 24 24"><circle id="drum" cx="12" cy="12" r="9" fill="#1D1D1F"/></svg>"##
        let parts = Self.parts(AskIconBreak.applied(to: svg))
        let body = try #require(parts.first)
        #expect(body.fill == "#1D1D1F")
        #expect(body.stroke == nil)
        let mark = try #require(parts.last)
        #expect(mark.stroke == "#1D1D1F")
        #expect(mark.fill == nil)
        #expect(mark.strokeWidth >= 1.5)
    }

    @Test("A box tears as well as a round thing")
    func rect() throws {
        let svg = ##"<svg viewBox="0 0 24 24" fill="none" stroke="#000000" stroke-width="2"><rect id="crate" x="4" y="4" width="16" height="16" rx="2"/></svg>"##
        let body = try #require(Self.parts(AskIconBreak.applied(to: svg)).first)
        guard case .path(let outline) = body.shape else { Issue.record("not a path"); return }
        #expect(outline.closed)
    }

    @Test("An app icon's tile is never what tears: the subject on it is")
    func tile() throws {
        let svg = """
            <svg viewBox="0 0 1024 1024"><rect id="tile" width="1024" height="1024" rx="228" fill="#2F49D1"/>\
            <circle id="drum" cx="512" cy="512" r="300" fill="#FFFFFF"/></svg>
            """
        let parts = Self.parts(AskIconBreak.applied(to: svg))
        let first = try #require(parts.first)
        if case .rect = first.shape {} else { Issue.record("the tile changed") }
        let body = try #require(parts.dropFirst().first)
        guard case .path = body.shape else { Issue.record("the drum did not tear"); return }
        // The marks are sized for the drawing, not for a 24 grid.
        let mark = try #require(parts.last)
        #expect(SVGArtwork.shapeBounds(mark.shape).width + SVGArtwork.shapeBounds(mark.shape).height > 20)
        #expect(mark.strokeWidth > 20)
    }

    @Test("An outline with no end to it, a moved shape or no name cannot be torn")
    func cannot() {
        #expect(AskIconBreak.applied(to: ##"<svg viewBox="0 0 24 24"><path id="arc" d="M4 12 C4 4 20 4 20 12" stroke="#000000" fill="none"/></svg>"##) == nil)
        #expect(AskIconBreak.applied(to: ##"<svg viewBox="0 0 24 24"><g transform="rotate(20)"><circle id="drum" cx="12" cy="12" r="9" fill="#000000"/></g></svg>"##) == nil)
        #expect(AskIconBreak.applied(to: ##"<svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="9" fill="#000000"/></svg>"##) == nil)
        #expect(AskIconBreak.applied(to: "not an svg") == nil)
    }

    // MARK: In the talk

    static let read = #"{"kind":"picture","canvas":{"width":1440,"height":1024}}"#

    @Test("The model is asked for the object whole, in the look the person named, and that lands as drawn")
    func talkAsksForTheWholeObject() {
        let talk = AskConversation(request: "a kite snapping icon, outline", documentRead: Self.read, iconBreak: "a kite")
        let asked = talk.chatBody(model: "m")["messages"]?.arrayValue?.dropFirst().first?["content"]?.stringValue ?? ""
        #expect(asked.contains("a kite"))
        #expect(asked.contains("whole"))
        #expect(asked.contains("every part that makes it recognisable"))
        #expect(asked.contains("outline"))
        #expect(!asked.contains("snapping"))
        #expect(talk.landsAsDrawn)
    }

    @Test("An app icon keeps its words, so it is still drawn on its tile")
    func talkKeepsTheAppIcon() {
        let talk = AskConversation(request: "a kite snapping app icon", documentRead: Self.read, iconBreak: "a kite")
        let asked = talk.chatBody(model: "m")["messages"]?.arrayValue?.dropFirst().first?["content"]?.stringValue ?? ""
        #expect(asked.contains("app icon"))
    }

    @Test("What the model draws whole lands torn, as one step")
    func talkTears() throws {
        var talk = AskConversation(request: "a kite snapping icon", documentRead: Self.read, iconBreak: "a kite")
        _ = talk.take(Self.reply("add_drawing", ["subject": "kite", "svg": .string(Self.kite)]))
        #expect(talk.steps.count == 1)
        let svg = try #require(talk.steps.first?.arguments["svg"]?.stringValue)
        #expect(svg.contains("burst"))
        #expect(!svg.contains("<ellipse"))
    }

    @Test("An outline that cannot be torn goes back once to be closed, and an icon lands in the end")
    func talkSendsBack() {
        let open = ##"<svg viewBox="0 0 24 24" fill="none" stroke="#000000" stroke-width="2"><path id="arc" d="M4 12 C4 4 20 4 20 12"/></svg>"##
        var talk = AskConversation(request: "a kite snapping icon", documentRead: Self.read, iconBreak: "a kite")
        _ = talk.take(Self.reply("add_drawing", ["subject": "kite", "svg": .string(open)]))
        #expect(talk.steps.isEmpty)
        #expect(talk.messages.last?["content"]?.stringValue?.contains("closed") == true)
        for _ in 0..<AskIconCheck.mostSendBacks {
            _ = talk.take(Self.reply("add_drawing", ["subject": "kite", "svg": .string(open)]))
        }
        #expect(talk.steps.count == 1)
    }

    @Test("With nothing breaking, an icon plans exactly as it did")
    func nothingBreaking() {
        var talk = AskConversation(request: "a kite icon", documentRead: Self.read)
        _ = talk.take(Self.reply("add_drawing", ["subject": "kite", "svg": .string(Self.kite)]))
        #expect(talk.steps.first?.arguments["svg"]?.stringValue == Self.kite)
        #expect(!talk.landsAsDrawn)
    }
}
