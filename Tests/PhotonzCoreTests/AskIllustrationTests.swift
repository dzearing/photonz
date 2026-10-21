import CoreGraphics
import Foundation
@testable import PhotonzCore
import Testing

/// Ask asking for an illustration (`docs/design/ask.md`, "Drawing an
/// illustration"): the scene goes to the illustrator with the look the person
/// named, never to the model's own SVG, and the change row says which look.
@Suite("Ask sends a scene to the illustrator in the style asked for")
struct AskIllustrationTests {

    static func conversation(_ request: String) -> AskConversation {
        AskConversation(request: request, documentRead: #"{"canvas":{"width":1440,"height":1024}}"#,
                        drawings: AskDrawingTests.library)
    }

    @Test("A scene is planned with no svg, and the look the person typed is added to its style")
    func sceneNeedsNoSVG() {
        var talk = Self.conversation("draw an svg illustration of a sun over mountains as line art")
        _ = talk.take(AskDrawingTests.reply("add_drawing", ["subject": "sun over mountains"]))
        #expect(talk.steps.count == 1)
        #expect(talk.steps.first?.arguments["style"]?.stringValue?.contains("line art") == true)
    }

    @Test("A lone animal asked for as an illustration is the illustrator's too")
    func foxIllustration() {
        var talk = Self.conversation("draw an illustration of a fox")
        _ = talk.take(AskDrawingTests.reply("add_drawing", ["subject": "fox"]))
        #expect(talk.steps.count == 1)
        #expect(AskDrawingCheck.drawings(in: AskPlan(steps: talk.steps, summary: "", names: [:])).isEmpty)
    }

    @Test("A style the model guessed for a thing the person did not ask to illustrate is dropped")
    func guessedStyleDropped() {
        var talk = Self.conversation("draw a picture of a bird")
        _ = talk.take(AskDrawingTests.reply("add_drawing", ["subject": "dog", "style": "illustration"]))
        #expect(talk.steps.first?.arguments["style"] == nil)
        #expect(IllustrationBrief.make(subject: "bird", style: "illustration") == nil)
        #expect(IllustrationBrief.make(subject: "sun", style: "illustration") == nil)
    }

    @Test("A badge the model sent as an icon is drawn as an illustration unless the person said icon")
    func badgeIsNotAnIcon() {
        var talk = Self.conversation("draw the sun over mountains as a black silhouette badge with pines")
        _ = talk.take(AskDrawingTests.reply("add_drawing", ["subject": "sun over mountains", "style": "silhouette", "icon": true]))
        #expect(talk.steps.first?.arguments["icon"] == nil)
        let icon = AskConversation.withStyleWords(["subject": "sun over mountains", "icon": true],
                                                   from: "make an app icon of the sun over mountains")
        #expect(icon["icon"]?.boolValue == true)
    }

    @Test("A drawing from the built-in set is not looked at, so a misreading cannot swap it for the model's svg")
    func builtInNotTakenBack() {
        let plan = AskPlan(steps: [AskStep(tool: "add_drawing", arguments: ["subject": "dog"]),
                                   AskStep(tool: "add_drawing", arguments: ["subject": "bicycle", "svg": "<svg/>", "builtIn": false])],
                           summary: "")
        #expect(AskDrawingCheck.drawings(in: plan, library: AskDrawingTests.library).map(\.subject) == ["bicycle"])
    }

    @Test("A picture of a thing still goes to the built-in set and its look")
    func thingStaysAThing() {
        var talk = Self.conversation("draw a picture of a dog.")
        _ = talk.take(AskDrawingTests.reply("add_drawing", ["subject": "dog"]))
        #expect(talk.steps.first?.arguments["style"] == nil)
        #expect(AskDrawingCheck.drawings(in: AskPlan(steps: talk.steps, summary: "", names: [:])).count == 1)
    }

    @Test("The instructions send a scene to add_drawing with a style and no svg")
    func instructionsSayStyle() {
        let text = AskConversation.instructions(documentRead: "{}")
        #expect(text.contains("illustration or a scene"))
        #expect(text.contains("style"))
    }

    @Test("The change row says which look an illustration was drawn in")
    func rowSaysTheLook() {
        func row(_ args: AgentJSON) -> String { AskChangeWords.sentence([AskStep(tool: "add_drawing", arguments: args)]) }
        #expect(row(["subject": "sun over mountains", "style": "line art"]) == "Drew a line art illustration")
        #expect(row(["subject": "sun over mountains", "style": "silhouette badge"]) == "Drew a silhouette badge")
        #expect(row(["subject": "sun over mountains"]) == "Drew a sunset illustration")
        #expect(row(["subject": "dog"]) == "Drew a drawing")
        for words in [row(["subject": "sun over mountains", "style": "line art"]), row(["subject": "lighthouse on a cliff"])] {
            #expect(words.count <= AskChangeWords.budget)
        }
    }

    @Test("add_drawing takes a style")
    func toolTakesStyle() throws {
        let request = AgentTools.request(tool: "add_drawing", arguments: ["subject": "sun over mountains", "style": "flat"])
        guard case .success(.addDrawing(_, let call)) = request else {
            Issue.record("not an add_drawing request")
            return
        }
        #expect(call.style == "flat")
        #expect(call.illustration?.style == .flat)
    }

    @Test("An illustration is fitted whole, centred, at four fifths of the canvas")
    func illustrationBox() {
        let box = AgentDrawingPlacement.box(nil, fitting: CGSize(width: 1200, height: 800), on: CGSize(width: 1440, height: 1024))
        #expect(box.width == 1152)
        #expect(box.height == 768)
        #expect(abs(box.midX - 720) <= 1 && abs(box.midY - 512) <= 1)
    }

    // MARK: Reading gradients

    @Test("An SVG gradient fill becomes the app's own gradient, stops and direction kept")
    func svgGradient() throws {
        let svg = """
        <svg viewBox="0 0 100 100"><defs>
        <linearGradient id="g" x1="0" y1="0" x2="0" y2="1"><stop offset="0%" stop-color="#112233"/><stop offset="100%" stop-color="#AABBCC" stop-opacity="0.5"/></linearGradient>
        <radialGradient id="r" cx="0.5" cy="0.5" r="0.71"><stop offset="0" stop-color="#FFFFFF"/><stop offset="0.7" stop-color="#FFFFFF" stop-opacity="0"/></radialGradient>
        </defs><rect width="100" height="60" fill="url(#g)"/><circle cx="50" cy="50" r="20" fill="url(#r)"/></svg>
        """
        guard case .success(let art) = SVGArtwork.parse(svg) else {
            Issue.record("did not read")
            return
        }
        let linear = try #require(art.parts.first?.fillPaint)
        #expect(linear.kind == .linear)
        #expect(abs(linear.angle - 180) < 0.5)
        #expect(linear.orderedStops.map(\.hex) == ["#112233", "#AABBCC80"])
        #expect(art.parts.first?.fill == "#112233")
        let radial = try #require(art.parts.last?.fillPaint)
        #expect(radial.kind == .radial)
        #expect(abs((radial.orderedStops.last?.position ?? 0) - 0.7) < 0.02)
        // As layers, the rectangle and the oval carry the gradients.
        let layers = art.layers(named: "Test", fitting: CGRect(x: 0, y: 0, width: 100, height: 100))
        let fills = layers.compactMap { $0.annotation?.fill }
        #expect(fills.filter(\.isGradient).count == 2)
    }

    @Test("Groups are kept only when asked, so a drawing of a thing is unchanged")
    func groupsOnlyWhenAsked() {
        let svg = ##"<svg viewBox="0 0 10 10"><g id="sky"><rect width="10" height="5" fill="#00F"/></g><g id="land"><rect y="5" width="10" height="5" fill="#0F0"/></g></svg>"##
        guard case .success(let flat) = SVGArtwork.parse(svg), case .success(let kept) = SVGArtwork.parse(svg, keepingGroups: true) else {
            Issue.record("did not read")
            return
        }
        #expect(flat.parts.allSatisfy { $0.groups.isEmpty })
        #expect(kept.parts.map(\.groups) == [["Sky"], ["Land"]])
        let group = kept.group(named: "Scene", fitting: CGRect(x: 0, y: 0, width: 100, height: 100))
        guard case .group(let inside) = group.content else {
            Issue.record("not a group")
            return
        }
        #expect(inside.children.map(\.name) == ["Sky", "Land"])
    }
}
