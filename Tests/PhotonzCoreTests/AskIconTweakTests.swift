import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// A follow-up on an icon Ask made changes that icon in place, as one undo step
/// (`AgentIconRestyle`): the whole icon's look, line weight or colour.
@Suite("Ask tweaks the icon it made")
struct AskIconTweakTests {

    static let outlined = """
        <svg viewBox="0 0 24 24" fill="none" stroke="#1D1D1F" stroke-width="2" stroke-linecap="round">
        <rect id="body" x="3" y="5" width="18" height="14" rx="2"/>
        <path id="flap" d="M3 7 L12 13 L21 7"/>
        </svg>
        """
    static let solid = """
        <svg viewBox="0 0 24 24" fill="#1D1D1F"><circle id="shell" cx="12" cy="11" r="9"/>
        <circle id="dot" cx="12" cy="22" r="1"/></svg>
        """

    /// A picture holding `svg` as an icon, the way Ask lands one.
    static func document(_ svg: String) throws -> PhotonzDocument {
        let art = try SVGArtwork.parse(svg).get()
        var document = PhotonzDocument(canvasSize: CGSize(width: 512, height: 512), layers: [])
        document.layers.insert(art.iconFrame(named: "Icon", side: 512, origin: .zero), at: 0)
        return document
    }

    static func parts(_ document: PhotonzDocument) -> [Layer] {
        document.layers.first(where: \.isFrame)?.children ?? []
    }

    static func part(_ name: String, in document: PhotonzDocument) -> Layer? {
        parts(document).first { $0.name == name }
    }

    static func weight(_ layer: Layer?) -> CGFloat? { layer?.path?.strokeWidth ?? layer?.style.borderWidth }
    static func fill(_ layer: Layer?) -> String? { (layer?.path?.fill ?? layer?.annotation?.fill)?.hex.uppercased() }
    static func ink(_ layer: Layer?) -> String? {
        guard let layer else { return nil }
        if let path = layer.path { return path.colorHex.uppercased() }
        return (layer.style.borderWidth > 0 ? layer.style.borderColorHex : layer.annotation?.colorHex)?.uppercased()
    }

    // MARK: The tool

    @Test("Made solid, the big shape fills and a line on it stays visible as a cut")
    func filled() throws {
        var document = try Self.document(Self.outlined)
        let done = document.agentRestyleIcon(AgentIconRestyle(look: .filled))
        #expect((try? done.get().layers) == 2)
        #expect(Self.fill(Self.part("Body", in: document)) == "#1D1D1F")
        #expect(Self.weight(Self.part("Body", in: document)) == 0)
        let flap = Self.part("Flap", in: document)
        #expect(flap != nil)
        #expect(Self.ink(flap) == "#FFFFFF")
        #expect((Self.weight(flap) ?? 0) > 0)
    }

    @Test("Made outline, solid shapes become lines of one weight, and a part too small for a line stays solid")
    func outline() throws {
        var document = try Self.document(Self.solid)
        _ = document.agentRestyleIcon(AgentIconRestyle(look: .outline))
        let shell = Self.part("Shell", in: document)
        #expect(Self.fill(shell) == nil)
        #expect(Self.ink(shell) == "#1D1D1F")
        #expect((Self.weight(shell) ?? 0) >= 512 / 24)
        #expect(Self.fill(Self.part("Dot", in: document)) == "#1D1D1F")
    }

    @Test("There and back: a cut made by filling comes back as a line in the icon's ink")
    func thereAndBack() throws {
        var document = try Self.document(Self.outlined)
        _ = document.agentRestyleIcon(AgentIconRestyle(look: .filled))
        _ = document.agentRestyleIcon(AgentIconRestyle(look: .outline))
        #expect(Self.ink(Self.part("Flap", in: document)) == "#1D1D1F")
        #expect(Self.fill(Self.part("Body", in: document)) == nil)
    }

    @Test("Thicker and thinner change every line alike, and leave the shapes where they are")
    func weights() throws {
        var document = try Self.document(Self.outlined)
        let before = try #require(Self.weight(Self.part("Body", in: document)))
        let frames = Self.parts(document).map(\.frame)
        _ = document.agentRestyleIcon(AgentIconRestyle(weight: .thicker))
        let thicker = try #require(Self.weight(Self.part("Body", in: document)))
        #expect(thicker > before * 1.25)
        #expect(Self.weight(Self.part("Flap", in: document)) == thicker)
        #expect(Self.parts(document).map(\.frame) == frames)
        _ = document.agentRestyleIcon(AgentIconRestyle(weight: .thinner))
        _ = document.agentRestyleIcon(AgentIconRestyle(weight: .thinner))
        #expect((Self.weight(Self.part("Body", in: document)) ?? 0) < before * 0.8)
    }

    @Test("A line never gets too thin to see at 16 px, however often it is thinned")
    func thinnest() throws {
        var document = try Self.document(Self.outlined)
        for _ in 0..<12 { _ = document.agentRestyleIcon(AgentIconRestyle(weight: .thinner)) }
        #expect((Self.weight(Self.part("Body", in: document)) ?? 0) >= 512 * AgentIconRestyle.thinnest)
    }

    @Test("A colour reaches lines and fills alike, and a cut stays white")
    func colour() throws {
        var document = try Self.document(Self.outlined)
        _ = document.agentRestyleIcon(AgentIconRestyle(look: .filled))
        _ = document.agentRestyleIcon(AgentIconRestyle(colorHex: "#D0021B"))
        let body = try #require(Self.fill(Self.part("Body", in: document)))
        #expect(body != "#1D1D1F")
        let colour = AgentGroupRecolour.rgb(body)
        #expect(colour.r > colour.g && colour.r > colour.b)
        #expect(Self.ink(Self.part("Flap", in: document)) == "#FFFFFF")
    }

    @Test("A picture with no icon says so")
    func noIcon() {
        var document = PhotonzDocument(canvasSize: CGSize(width: 1440, height: 1024), layers: [])
        if case .success = document.agentRestyleIcon(AgentIconRestyle(look: .filled)) { Issue.record("it found an icon") }
    }

    @Test("The tool takes a look, a weight or a colour, and refuses nothing to do")
    func toolRequest() {
        if case .success(.restyleIcon(_, let change)) = AgentTools.request(tool: "restyle_icon", arguments: ["look": "outline", "weight": "thicker", "color": "#D0021B"]) {
            #expect(change.look == .outline)
            #expect(change.weight == .thicker)
            #expect(change.colorHex == "#D0021B")
        } else { Issue.record("no request") }
        if case .success = AgentTools.request(tool: "restyle_icon", arguments: [:]) { Issue.record("nothing to do") }
        if case .success = AgentTools.request(tool: "restyle_icon", arguments: ["look": "wobbly"]) { Issue.record("no such look") }
    }

    // MARK: What the model is offered

    static let iconRead = #"{"kind":"picture","canvas":{"width":512,"height":512},"layers":[{"kind":"frame","name":"Icon","frame":{"x":0,"y":0,"width":512,"height":512},"children":[{"kind":"path","name":"Body","frame":{"x":70,"y":90,"width":370,"height":330}}]}]}"#
    static let plainRead = #"{"kind":"picture","canvas":{"width":1440,"height":1024}}"#

    static func toolNames(_ talk: AskConversation) -> [String] {
        (talk.chatBody(model: "m")["tools"]?.arrayValue ?? []).compactMap { $0["function"]?["name"]?.stringValue }
    }

    @Test("The tool and its rule are there only when the picture holds an icon")
    func offered() {
        let onIcon = AskConversation(request: "thicker lines", documentRead: Self.iconRead)
        #expect(Self.toolNames(onIcon).contains("restyle_icon"))
        let said = onIcon.chatBody(model: "m")["messages"]?.arrayValue?.first?["content"]?.stringValue ?? ""
        #expect(said.contains("restyle_icon"))
        let elsewhere = AskConversation(request: "thicker lines", documentRead: Self.plainRead)
        #expect(!Self.toolNames(elsewhere).contains("restyle_icon"))
        #expect(elsewhere.chatBody(model: "m")["messages"]?.arrayValue?.first?["content"]?.stringValue?.contains("restyle_icon") == false)
    }

    @Test("A planned restyle is one step of the plan")
    func planned() {
        var talk = AskConversation(request: "thicker lines", documentRead: Self.iconRead)
        _ = talk.take(["message": ["role": "assistant", "content": "",
                                   "tool_calls": .array([["function": ["name": "restyle_icon", "arguments": ["weight": "thicker"]]]])]])
        #expect(talk.steps.map(\.tool) == ["restyle_icon"])
    }

    @Test("Its row says what it did")
    func row() {
        let step = AskStep(tool: "restyle_icon", arguments: ["weight": "thicker"])
        let read = PhotonzDocument(canvasSize: CGSize(width: 512, height: 512), layers: [])
        let said = AskChangeWords.sentence([step], asked: "thicker lines", before: read, after: read, madeAll: true)
        #expect(said.lowercased().contains("icon"))
    }

    // MARK: Which requests are tweaks

    @Test("A look said on its own after an icon is a tweak, not the icon made again")
    func lookIsNotARemake() {
        #expect(AgentPictureKind.remade("make it outline", after: "a bell icon, filled") == nil)
        #expect(AgentPictureKind.remade("as an outline", after: "a bell icon") == nil)
        #expect(AgentPictureKind.remade("make it a silhouette", after: "a kite icon") == nil)
    }

    @Test("Another kind of picture after an icon, and any look after a drawing, are still made again")
    func remakesStay() {
        #expect(AgentPictureKind.remade("as a photo", after: "a bell icon") == "a bell icon, as a photo")
        #expect(AgentPictureKind.remade("as vector art", after: "a dog on a beach") == "a dog on a beach, as vector art")
    }

    @Test("Asking about the icon that is there changes it; asking for another draws one")
    func theIconHere() {
        #expect(!AskConversation.takesIconRoute("make the icon thinner", brushes: false, web: false, holdsIcon: true))
        #expect(!AskConversation.takesIconRoute("make this icon outline", brushes: false, web: false, holdsIcon: true))
        #expect(AskConversation.takesIconRoute("make the icon thinner", brushes: false, web: false))
        #expect(AskConversation.takesIconRoute("a trash can icon", brushes: false, web: false, holdsIcon: true))
        #expect(AskConversation.takesIconRoute("make an icon of the sun", brushes: false, web: false, holdsIcon: true))
    }

    // MARK: change_part on a line

    @Test("A part drawn only in line takes the colour asked for: a heart was left black when told to go red")
    func changePartRecoloursALine() throws {
        var document = try Self.document(Self.outlined)
        var change = AgentPartChange(part: "Flap", layer: nil)
        change.colorHex = "#D0021B"
        _ = document.agentChangePart(change)
        let colour = AgentGroupRecolour.rgb(try #require(Self.ink(Self.part("Flap", in: document))))
        #expect(colour.r > colour.g && colour.r > colour.b)
    }

    @Test("A box drawn only in line takes it too, on its edge")
    func changePartRecoloursABoxEdge() throws {
        var document = try Self.document(Self.outlined)
        var change = AgentPartChange(part: "Body", layer: nil)
        change.colorHex = "#D0021B"
        _ = document.agentChangePart(change)
        let colour = AgentGroupRecolour.rgb(try #require(Self.ink(Self.part("Body", in: document))))
        #expect(colour.r > colour.g && colour.r > colour.b)
    }
}
