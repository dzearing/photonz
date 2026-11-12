import CoreGraphics
import Foundation
@testable import PhotonzCore
import Testing

/// An icon request takes the icon route (`docs/design/ask.md`, "An icon"):
/// chosen from the general words for an icon, drawn by the model as clean
/// shapes, never painted and traced, and held to what an icon is.
@Suite("Ask makes icons that are icons")
struct AskIconTests {

    static let bell = ##"""
    <svg viewBox="0 0 24 24" fill="none" stroke="#1D1D1F" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
    <path id="bell-body" d="M6 8a6 6 0 0 1 12 0c0 7 3 9 3 9H3s3-2 3-9"/>
    <path id="clapper" d="M10 21a2 2 0 0 0 4 0"/></svg>
    """##

    static func conversation(_ request: String, paints: Bool = true) -> AskConversation {
        AskConversation(request: request, documentRead: #"{"kind":"picture","canvas":{"width":1440,"height":1024}}"#, paints: paints)
    }

    static func reply(_ name: String, _ args: AgentJSON) -> AgentJSON {
        ["message": ["role": "assistant", "content": "", "tool_calls": .array([["function": ["name": .string(name), "arguments": args]]])]]
    }

    // MARK: Which requests

    @Test("The general words for an icon take the icon route, whatever the subject")
    func iconWords() {
        for asked in ["make an icon of a balloon popping", "a trash can icon", "a settings gear icon, outline",
                      "a rocket app icon", "a home glyph", "a favicon for a bakery", "Icons for a toolbar"] {
            #expect(AskIcon.asked(in: asked), "\(asked)")
        }
        for asked in ["draw a dog", "a logo for a coffee shop", "a badge with a mountain", "an iconic lighthouse"] {
            #expect(!AskIcon.asked(in: asked), "\(asked)")
        }
    }

    // MARK: Designed in words first

    @Test("The design is asked for on its own: the icon rules and the request, no tools, short and plain")
    func designBody() {
        let body = AskIcon.designBody(model: "m", request: "a kite tangling icon")
        let messages = body["messages"]?.arrayValue ?? []
        #expect(body["model"]?.stringValue == "m")
        #expect(body["tools"] == nil)
        #expect(body["think"]?.boolValue == false)
        #expect(body["options"]?["num_predict"]?.intValue == AskIcon.mostDesignTokens)
        #expect(messages.first?["content"]?.stringValue?.contains("24 24") == true)
        let asked = messages.last?["content"]?.stringValue ?? ""
        #expect(asked.hasPrefix("a kite tangling icon"))
        #expect(asked.contains("no SVG yet"))
    }

    @Test("A design is the model's words; nothing to go on gives no design")
    func designAnswer() {
        #expect(AskIcon.design(fromAnswer: "<think>hm</think>\n A kite, its tail knotted. \n") == "A kite, its tail knotted.")
        #expect(AskIcon.design(fromAnswer: "   ") == nil)
        #expect(AskIcon.design(fromAnswer: "<svg viewBox=\"0 0 24 24\"></svg>") == nil)
    }

    @Test("An object simply at rest takes no design: coordinates made a rocket out of stiff triangles")
    func atRestTakesNoDesign() {
        for answer in ["at rest", "At rest.", "<think>hm</think>\nAT REST", " at rest\n"] {
            #expect(AskIcon.design(fromAnswer: answer) == nil, "\(answer)")
        }
        #expect(AskIcon.design(fromAnswer: "The kite is at rest no longer: its tail is knotted.") != nil)
        #expect(AskIcon.designAsk.contains("reply only: at rest"))
    }

    @Test("Small parts are ruled on only where a design is drawn, so an icon at rest plans as it did")
    func smallPartsRule() {
        #expect(AskIcon.drawTheDesign.contains("under 4 across"))
        #expect(!AskConversation.iconRules.contains("under 4 across"))
    }

    @Test("The design follows the request, and drawing it is left to the plan")
    func designInTheTalk() {
        let talk = AskConversation(request: "a kite tangling icon", documentRead: #"{"kind":"picture","canvas":{"width":1440,"height":1024}}"#,
                                   iconDesign: "A kite, its tail knotted.")
        let messages = talk.chatBody(model: "m")["messages"]?.arrayValue ?? []
        let said = messages.compactMap { $0["content"]?.stringValue }
        #expect(messages.dropFirst().first?["content"]?.stringValue == "a kite tangling icon")
        #expect(said.contains("A kite, its tail knotted."))
        #expect(messages.last?["role"]?.stringValue == "user")
        #expect(messages.last?["content"]?.stringValue == AskIcon.drawTheDesign)
    }

    @Test("Only the icon route takes a design")
    func designOnlyOnTheIconRoute() {
        #expect(AskConversation.takesIconRoute("a kite icon", brushes: true, web: false))
        #expect(!AskConversation.takesIconRoute("draw a kite", brushes: true, web: false))
        #expect(!AskConversation.takesIconRoute("a kite icon", brushes: false, web: true))
        let talk = AskConversation(request: "draw a kite", documentRead: #"{"kind":"picture","canvas":{"width":1440,"height":1024}}"#,
                                   iconDesign: "A kite.")
        let said = (talk.chatBody(model: "m")["messages"]?.arrayValue ?? []).compactMap { $0["content"]?.stringValue }
        #expect(!said.contains("A kite."))
    }

    @Test("A designed icon lands as drawn: every redraw of a torn balloon lost the tear or the balloon")
    func designedLandsAsDrawn() {
        let read = #"{"kind":"picture","canvas":{"width":1440,"height":1024}}"#
        #expect(AskConversation(request: "a kite tangling icon", documentRead: read, iconDesign: "A kite, its tail knotted.").landsAsDrawn)
        #expect(!AskConversation(request: "a kite icon", documentRead: read).landsAsDrawn)
        #expect(!AskConversation(request: "draw a kite", documentRead: read, iconDesign: "A kite.").landsAsDrawn)
    }

    @Test("The built-in model is held to what a call says it may write")
    func mostTokens() {
        let held = AskServerChat.body(fromOllama: ["options": ["num_predict": 300]])
        #expect(held["max_tokens"]?.intValue == 300)
        #expect(AskServerChat.body(fromOllama: [:])["max_tokens"]?.intValue == AskServerChat.mostTokensATurn)
    }

    @Test("An app icon is drawn at 1024, any other icon at 512")
    func sides() {
        #expect(AskIcon.side(for: "a rocket app icon") == 1024)
        #expect(AskIcon.side(for: "an app icon for a music player") == 1024)
        #expect(AskIcon.side(for: "a trash can icon") == 512)
    }

    @Test("The look comes from the person's words")
    func looks() {
        #expect(AskIcon.look(in: "a settings gear icon, outline") == .outline)
        #expect(AskIcon.look(in: "an outlined bell icon") == .outline)
        #expect(AskIcon.look(in: "a filled bell icon") == .filled)
        #expect(AskIcon.look(in: "a solid camera icon") == .filled)
        #expect(AskIcon.look(in: "a duotone heart icon") == .duotone)
        #expect(AskIcon.look(in: "a two tone heart icon") == .duotone)
        #expect(AskIcon.look(in: "a trash can icon") == nil)
    }

    // MARK: The plan

    @Test("An icon is never painted: with the picture model ready it still needs the model's own svg")
    func neverPainted() {
        var talk = Self.conversation("a trash can icon")
        _ = talk.take(Self.reply("add_drawing", ["subject": "trash can", "icon": true]))
        #expect(talk.steps.isEmpty)
        #expect(talk.messages.last?["content"]?.stringValue?.contains("svg") == true)
    }

    @Test("A model that forgot to say icon still makes an icon, sized and styled from the words")
    func forgotIcon() {
        var talk = Self.conversation("a settings gear icon, outline")
        _ = talk.take(Self.reply("add_drawing", ["subject": "gear", "svg": .string(Self.bell)]))
        #expect(talk.steps.first?.arguments["icon"]?.boolValue == true)
        #expect(talk.steps.first?.arguments["side"]?.intValue == 512)
        #expect(talk.steps.first?.arguments["style"]?.stringValue == "outline")
    }

    @Test("A photo the model planned for an icon comes back as a drawing it must write itself")
    func photoPlanned() {
        var talk = Self.conversation("a camera icon")
        _ = talk.take(Self.reply("add_photo", ["subject": "camera"]))
        #expect(talk.steps.isEmpty)
    }

    @Test("Icon instructions replace the painting ones, and name no subject")
    func instructions() {
        let told = AskConversation.instructions(documentRead: "{}", paints: false, icon: true)
        #expect(told.contains("viewBox=\"0 0 24 24\""))
        #expect(!told.contains("send no svg"))
        let plain = AskConversation.instructions(documentRead: "{}", paints: true)
        #expect(!plain.contains("viewBox=\"0 0 24 24\""))
    }

    @Test("A drawing that is not an icon request plans exactly as before")
    func otherDrawingsUntouched() {
        var talk = Self.conversation("draw a dog")
        _ = talk.take(Self.reply("add_drawing", ["subject": "dog"]))
        #expect(talk.steps.count == 1)
        #expect(talk.steps.first?.arguments["icon"] == nil)
    }

    @Test("An icon stands for an idea, so the look asks whether what was seen could stand for it")
    func judgedAsAnIcon() {
        // "search" seen as "magnifying glass" and "envelope" seen as "Email"
        // were both thrown away as misses (the eval, 2026-11-04).
        let body = AskDrawingCheck.judgeBody(model: "m", subject: "search", seen: "Magnifying glass", icon: true)
        let asked = body["messages"]?.arrayValue?.first?["content"]?.stringValue ?? ""
        #expect(asked.contains("stand for"))
        #expect(asked.contains("search") && asked.contains("Magnifying glass"))
        let plain = AskDrawingCheck.judgeBody(model: "m", subject: "dog", seen: "Mouse")
        #expect(plain["messages"]?.arrayValue?.first?["content"]?.stringValue?.contains("stand for") == false)
    }

    @Test("An icon carries no plan to be checked against: a plain gear was sent back as not showing it is a gear")
    func noPlan() {
        var talk = Self.conversation("a settings gear icon")
        _ = talk.take(Self.reply("add_drawing", ["subject": "gear", "svg": .string(Self.bell), "plan": .array(["It is a gear"])]))
        #expect(talk.steps.first?.arguments["plan"] == nil)
        #expect(AskIcon.isIn(AskPlan(steps: talk.steps, summary: "")))
        #expect(!AskIcon.isIn(AskPlan(steps: [AskStep(tool: "add_drawing", arguments: ["subject": "dog"])], summary: "")))
    }

    @Test("An icon drawn again is told to change its outline, not to reach for real colours")
    func revisedAsAnIcon() {
        let note = AskDrawingCheck.revisionNote(subject: "the thing", seen: "something else", icon: true)
        #expect(note.contains("something else"))
        #expect(note.contains("silhouette"))
        #expect(!note.contains("colours it really has"))
        #expect(AskDrawingCheck.revisionNote(subject: "dog", seen: "cat").contains("colours it really has"))
    }

    @Test("The icon rules say how an action shows: on the object, with marks kept clear of it")
    func actionRule() {
        #expect(AskConversation.iconRules.contains("break its outline"))
        #expect(AskConversation.iconRules.contains("never touching"))
    }

    // MARK: The craft check

    @Test("A clean icon passes")
    func cleanPasses() throws {
        let art = try SVGArtwork.parse(Self.bell).get()
        #expect(AskIconCheck.problems(art, look: .outline, appIcon: false).isEmpty)
    }

    @Test("Too many parts, unnamed parts, two line weights and hairlines are each sent back")
    func problems() throws {
        let many = (0..<20).map { ##"<circle id="dot-\##($0)" cx="\##($0 + 2)" cy="12" r="1" fill="#000000"/>"## }.joined()
        let crowded = try SVGArtwork.parse(##"<svg viewBox="0 0 24 24">\##(many)</svg>"##).get()
        #expect(AskIconCheck.problems(crowded, look: nil, appIcon: false).contains { $0.contains("parts") })

        let unnamed = try SVGArtwork.parse(##"<svg viewBox="0 0 24 24"><rect x="2" y="2" width="20" height="20" fill="#000000"/></svg>"##).get()
        #expect(AskIconCheck.problems(unnamed, look: nil, appIcon: false).contains { $0.contains("id") })

        let weights = try SVGArtwork.parse(##"""
        <svg viewBox="0 0 24 24" fill="none" stroke="#000000"><circle id="rim" cx="12" cy="12" r="9" stroke-width="2"/>
        <path id="hand" d="M12 7v5" stroke-width="3.5"/></svg>
        """##).get()
        #expect(AskIconCheck.problems(weights, look: nil, appIcon: false).contains { $0.contains("line weight") })

        let hairline = try SVGArtwork.parse(##"""
        <svg viewBox="0 0 24 24" fill="none" stroke="#000000" stroke-width="0.5"><circle id="rim" cx="12" cy="12" r="10"/></svg>
        """##).get()
        #expect(AskIconCheck.problems(hairline, look: nil, appIcon: false).contains { $0.contains("16") })
    }

    /// The user's trash story, every run from 2026-11-08 to 11-11: a line
    /// can and lid, and the trash a solid filled shape. Every look of the
    /// judge read it as "a block", never rubbish, and marked it down.
    @Test("In a line icon, a part drawn solid is sent back to be drawn in lines; a dot is not")
    func solidAmongLines() throws {
        let trash = try SVGArtwork.parse(AskMotionTuckedInTests.bin).get()
        let said = AskIconCheck.problems(trash, look: nil, appIcon: false)
        #expect(said.contains { $0.lowercased().contains("trash") && $0.contains("lines") }, "\(said)")
        // A dot (no wider than a line is thick) is part of the line style.
        let dot = try SVGArtwork.parse(##"""
        <svg viewBox="0 0 24 24" fill="none" stroke="#1D1D1F" stroke-width="2" stroke-linecap="round">
        <circle id="rim" cx="12" cy="12" r="9"/><line id="stem" x1="12" y1="11" x2="12" y2="16"/>
        <circle id="dot" cx="12" cy="8" r="1" fill="#1D1D1F" stroke="none"/></svg>
        """##).get()
        #expect(AskIconCheck.problems(dot, look: nil, appIcon: false).isEmpty)
        // Drawn in lines but too small for them, it fills in all the same
        // (the model's answer to the send-back on 2026-11-11: the same 3 by 3
        // shape with a stroke of 2), and is sent back with a size to draw it.
        let small = try SVGArtwork.parse(AskMotionTuckedInTests.stroked).get()
        let smallSaid = AskIconCheck.problems(small, look: nil, appIcon: false)
        #expect(smallSaid.contains { $0.lowercased().contains("trash") && $0.contains("4 across") }, "\(smallSaid)")
        // A filled icon asked for keeps its fills.
        #expect(!AskIconCheck.problems(trash, look: .filled, appIcon: false).contains { $0.lowercased().contains("trash") })
        // And the clean line icon still passes.
        #expect(AskIconCheck.problems(try SVGArtwork.parse(Self.bell).get(), look: nil, appIcon: false).isEmpty)
    }

    @Test("A look asked for is held to: outline has no big fills, filled has fills, duotone has two tones")
    func looksHeld() throws {
        let filled = try SVGArtwork.parse(##"<svg viewBox="0 0 24 24"><circle id="disc" cx="12" cy="12" r="10" fill="#000000"/></svg>"##).get()
        #expect(AskIconCheck.problems(filled, look: .outline, appIcon: false).contains { $0.contains("outline") })
        #expect(AskIconCheck.problems(filled, look: .filled, appIcon: false).isEmpty)
        #expect(AskIconCheck.problems(filled, look: .duotone, appIcon: false).contains { $0.contains("two") })
        let outline = try SVGArtwork.parse(Self.bell).get()
        #expect(AskIconCheck.problems(outline, look: .filled, appIcon: false).contains { $0.contains("filled") })
        let two = try SVGArtwork.parse(##"""
        <svg viewBox="0 0 24 24"><circle id="back" cx="12" cy="12" r="10" fill="#B9C4FF"/><circle id="front" cx="12" cy="12" r="5" fill="#2F49D1"/></svg>
        """##).get()
        #expect(AskIconCheck.problems(two, look: .duotone, appIcon: false).isEmpty)
    }

    @Test("A drawing that is sent back is sent back with what to change, and lands in the end")
    func sentBackThenLands() {
        let thin = ##"<svg viewBox="0 0 24 24" fill="none" stroke="#000000" stroke-width="0.5"><circle id="rim" cx="12" cy="12" r="10"/></svg>"##
        var talk = Self.conversation("a clock icon")
        for _ in 0..<AskIconCheck.mostSendBacks {
            _ = talk.take(Self.reply("add_drawing", ["subject": "clock", "svg": .string(thin)]))
            #expect(talk.steps.isEmpty)
        }
        _ = talk.take(Self.reply("add_drawing", ["subject": "clock", "svg": .string(thin)]))
        #expect(talk.steps.count == 1)
    }

    // MARK: The document's own icons

    @Test("An icon frame already in the document sets the look a new one matches")
    func documentLook() {
        let read = ##"{"canvas":{"width":1200,"height":800},"layers":[{"kind":"frame","name":"Bell","frame":{"x":0,"y":0,"width":512,"height":512},"children":[{"kind":"path","name":"Body","frame":{"x":0,"y":0,"width":10,"height":10},"path":{"stroke":"#1D1D1F","strokeWidth":42.6}}]}]}"##
        let line = AskIcon.documentLook(read)
        #expect(line?.contains("#1D1D1F") == true)
        #expect(line?.contains("2") == true)
        #expect(AskIcon.documentLook(#"{"canvas":{"width":1200,"height":800},"layers":[]}"#) == nil)
    }

    // MARK: Where it goes

    @Test("An icon on a blank picture is the picture: a square canvas and a clear frame, no surface of its own")
    func blankBecomesTheIcon() throws {
        var document = PhotonzDocument(canvasSize: CGSize(width: 1440, height: 1024))
        let drawing = try SVGArtwork.parse(Self.bell).get()
        let id = document.addDrawing(drawing, named: "Bell", icon: true, side: 1024, box: nil, blank: true)
        #expect(document.canvasSize == CGSize(width: 1024, height: 1024))
        #expect(document.layer(id: id)?.group?.background == nil)
    }

    @Test("A box and an oval Ask draws on an icon's grid land where the model's SVG put them, line on the edge")
    func outlinesLandWhereWritten() throws {
        // The SVG the model wrote for the eval's ticked box (run
        // 20261108-235558-ask): before 2026-11-09 its box landed at 4,4 16x16,
        // corner 3, half a line small all round, because a box's line starts
        // inside its edge (task find-out-whether-boxes-and-ovals-ask-draws-land).
        let svg = ##"<svg viewBox="0 0 24 24" fill="none" stroke="#1D1D1F" stroke-width="2"><rect id="box" x="3" y="3" width="18" height="18" rx="4"/><circle id="dot" cx="12" cy="12" r="4"/></svg>"##
        let drawing = try SVGArtwork.parse(svg).get()
        for onGrid in [false, true] {
            var document = PhotonzDocument(canvasSize: CGSize(width: 1440, height: 1024))
            document.addDrawing(drawing, named: "Ticked", icon: true, side: 24, box: nil, blank: true, onGrid: onGrid)
            let box = try #require(document.allLayers.first { $0.name == "Box" })
            let dot = try #require(document.allLayers.first { $0.name == "Dot" })
            #expect(document.canvasFrame(of: box.id) == CGRect(x: 3, y: 3, width: 18, height: 18), "onGrid \(onGrid)")
            #expect(document.canvasFrame(of: dot.id) == CGRect(x: 8, y: 8, width: 8, height: 8), "onGrid \(onGrid)")
            #expect(box.outlinePosition == .center && dot.outlinePosition == .center, "onGrid \(onGrid)")
            #expect(box.annotation?.cornerRadius == 4, "onGrid \(onGrid)")
        }
    }

    @Test("An icon with a box given is drawn in that box, and the canvas never grows")
    func boxKeepsTheCanvas() throws {
        var document = PhotonzDocument(canvasSize: CGSize(width: 800, height: 600))
        document.addLayer(Layer(name: "Work", content: .group(GroupContent(children: [])), frame: CGRect(x: 0, y: 0, width: 10, height: 10)))
        let drawing = try SVGArtwork.parse(Self.bell).get()
        let id = document.addDrawing(drawing, named: "Bell", icon: true, box: CGRect(x: 700, y: 500, width: 64, height: 64))
        #expect(document.canvasSize == CGSize(width: 800, height: 600))
        #expect(document.layer(id: id)?.isFrame == false)
    }

    @Test("With work on the canvas and no box, the document still never grows and gains no frame")
    func neverGrows() throws {
        var document = PhotonzDocument(canvasSize: CGSize(width: 800, height: 600))
        document.addLayer(Layer(name: "Work", content: .group(GroupContent(children: [])), frame: CGRect(x: 0, y: 0, width: 10, height: 10)))
        let drawing = try SVGArtwork.parse(Self.bell).get()
        let id = document.addDrawing(drawing, named: "Bell", icon: true, box: nil)
        #expect(document.canvasSize == CGSize(width: 800, height: 600))
        #expect(document.layer(id: id)?.isFrame == false)
    }

    @Test("Where an icon goes, from whether the picture is blank and whether a box was given")
    func placementChoice() {
        #expect(AgentDrawingPlacement.iconPlace(blank: true, box: nil) == .thisPicture)
        #expect(AgentDrawingPlacement.iconPlace(blank: true, box: CGRect(x: 0, y: 0, width: 9, height: 9)) == .inBox)
        #expect(AgentDrawingPlacement.iconPlace(blank: false, box: nil) == .newPicture)
        #expect(AgentDrawingPlacement.iconPlace(blank: false, box: CGRect(x: 0, y: 0, width: 9, height: 9)) == .inBox)
    }

    @Test("The tool takes an icon's side, up to an app icon")
    func toolSide() throws {
        let request = AgentTools.request(tool: "add_drawing", arguments: ["subject": "rocket", "icon": true, "side": 1024, "svg": .string(Self.bell)])
        guard case .success(.addDrawing(_, let call)) = request else { Issue.record("\(request)"); return }
        #expect(call.side == 1024)
    }

    @Test("A 1024 app icon counts as an icon, so it gets its grid and its previews")
    func appIconIsAnIcon() {
        #expect(IconPreviews.isIconSize(CGSize(width: 1024, height: 1024)))
        #expect(!IconPreviews.isIconSize(CGSize(width: 1000, height: 1000)))
        #expect(IconPreviews.sides(forFrameSide: 1024) == IconPreviews.interfaceSides)
    }

    // MARK: Its row

    @Test("The row of an icon made in a new picture says so, within the row's budget")
    func newIconRow() {
        #expect(AskChangeWords.madeNewIcon("Balloon") == "Made a new icon: Balloon")
        let long = AskChangeWords.madeNewIcon("A rather long balloon popping over a very long subject name")
        #expect(long.count <= AskChangeWords.budget)
        #expect(long.hasPrefix("Made a new icon: "))
    }

    @Test("A row for work in another picture stays on, whatever happens to this one")
    func rowElsewhere() {
        let document = PhotonzDocument(canvasSize: CGSize(width: 800, height: 600))
        var list = AskChangeList()
        let id = list.recordElsewhere(asked: "a trash can icon", sentence: "Made a new icon: Trash can", document: document)
        #expect(list.row(id)?.sentence == "Made a new icon: Trash can")
        list.follow(document)
        #expect(list.row(id)?.isOn == true)
    }

    // MARK: New Image

    @Test("New Image offers the icon sizes only where they are asked for")
    func presets() {
        #expect(BlankCanvas.presets(withIcons: false) == BlankCanvas.presets)
        let sizes = BlankCanvas.presets(withIcons: true).map(\.size)
        #expect(sizes.contains(CGSize(width: 512, height: 512)))
        #expect(sizes.contains(CGSize(width: 1024, height: 1024)))
    }

    // MARK: SVG

    @Test("An SVG's line ends and corners are kept")
    func lineStyle() throws {
        let square = ##"<svg viewBox="0 0 24 24" fill="none" stroke="#000000" stroke-width="2" stroke-linecap="square" stroke-linejoin="bevel"><path id="tick" d="M4 12l5 5L20 6"/></svg>"##
        let art = try SVGArtwork.parse(square).get()
        let layer = try #require(art.layers(named: "Tick", fitting: CGRect(x: 0, y: 0, width: 24, height: 24)).first)
        #expect(layer.path?.lineEnd == .square)
        #expect(layer.path?.lineCorner == .flat)
    }
}
