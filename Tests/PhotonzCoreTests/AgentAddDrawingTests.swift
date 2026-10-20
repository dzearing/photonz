import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// add_drawing: an agent asks for a thing by name and gets a clean drawing of
/// it as layers, from the built-in set or from an SVG it wrote.
@Suite("add_drawing draws a thing as editable layers")
struct AgentAddDrawingTests {

    static func args(_ json: String) throws -> AgentJSON { try AgentJSON.parse(Data(json.utf8)) }

    static let svg = ##"<svg viewBox="0 0 36 36"><circle id="head" cx="18" cy="18" r="18" fill="#FFCC4D"/></svg>"##

    @Test("The call carries what to draw, the agent's own SVG, and whether it is an icon")
    func theCall() throws {
        let request = try AgentTools.request(tool: "add_drawing", arguments: Self.args("""
            {"subject": "dog", "icon": true, "name": "Rex", "builtIn": false,
             "frame": {"x": 10, "y": 20, "width": 300, "height": 200}, "svg": "<svg/>"}
            """)).get()
        guard case .addDrawing(nil, let call) = request else { Issue.record("\(request)"); return }
        #expect(call.subject == "dog")
        #expect(call.icon)
        #expect(call.name == "Rex")
        #expect(!call.builtIn)
        #expect(call.svg == "<svg/>")
        #expect(call.frame == CGRect(x: 10, y: 20, width: 300, height: 200))
    }

    @Test("A drawing with no subject is refused")
    func needsASubject() throws {
        guard case .failure(let error) = AgentTools.request(tool: "add_drawing", arguments: try Self.args(#"{"subject": "  "}"#))
        else { Issue.record("an empty subject was accepted"); return }
        #expect(error.message.contains("subject"))
    }

    @Test("A drawing lands centred on the canvas, a sensible size, as one group named for the thing")
    func centred() throws {
        var document = PhotonzDocument(canvasSize: CGSize(width: 1440, height: 1024))
        let drawing = try SVGArtwork.parse(Self.svg).get()
        let id = document.addDrawing(drawing, named: "Smiley face", icon: false, box: nil)
        let group = try #require(document.layer(id: id))
        #expect(group.name == "Smiley face")
        let box = group.localBounds
        #expect(abs(box.midX - 720) < 1 && abs(box.midY - 512) < 1)
        #expect(abs(box.height - 1024 * AgentDrawingPlacement.share) < 1)
        #expect(document.canvasSize == CGSize(width: 1440, height: 1024))
    }

    @Test("A drawing asked for in a box fills that box")
    func inABox() throws {
        var document = PhotonzDocument(canvasSize: CGSize(width: 1440, height: 1024))
        let drawing = try SVGArtwork.parse(Self.svg).get()
        let id = document.addDrawing(drawing, named: "Sun", icon: false,
                                     box: CGRect(x: 100, y: 100, width: 200, height: 200))
        let box = try #require(document.layer(id: id)).localBounds
        #expect(abs(box.minX - 100) < 0.5 && abs(box.width - 200) < 0.5)
    }

    @Test("A box hanging off the canvas is kept on it, and one wholly off it is the middle")
    func boxKeptOnCanvas() {
        let canvas = CGSize(width: 1440, height: 1024)
        #expect(AgentDrawingPlacement.box(CGRect(x: 720, y: 512, width: 600, height: 600), on: canvas)
                == CGRect(x: 720, y: 512, width: 600, height: 512))
        #expect(AgentDrawingPlacement.box(CGRect(x: 5000, y: 0, width: 100, height: 100), on: canvas)
                == AgentDrawingPlacement.box(on: canvas))
    }

    @Test("An icon on a blank picture makes the picture a square icon frame, the drawing on its keylines")
    func iconOnBlank() throws {
        var document = PhotonzDocument(canvasSize: CGSize(width: 1440, height: 1024))
        let drawing = try SVGArtwork.parse(Self.svg).get()
        let id = document.addDrawing(drawing, named: "Smiley face", icon: true, box: nil)
        #expect(document.canvasSize == CGSize(width: 512, height: 512))
        let frame = try #require(document.layer(id: id))
        #expect(frame.isFrame)
        #expect(frame.frame == CGRect(x: 0, y: 0, width: 512, height: 512))
        #expect(document.isIconFrame(id: id))
        let margin = IconKeylines.margin(forSide: 512)
        let inside = frame.children.reduce(CGRect.null) { $0.union($1.localBounds) }
        #expect(abs(inside.minX - margin) < 0.5 && abs(inside.maxX - (512 - margin)) < 0.5)
    }

    @Test("An icon on a blank picture's flat background squeezes the background to the square with it")
    func iconOnBlankBackground() throws {
        var document = PhotonzDocument(canvasSize: CGSize(width: 1440, height: 1024))
        var background = Layer(name: "Background", content: .image(ImageRef(pixelSize: CGSize(width: 1440, height: 1024))), frame: CGRect(x: 0, y: 0, width: 1440, height: 1024))
        background.isLocked = true
        document.addLayer(background)
        let drawing = try SVGArtwork.parse(Self.svg).get()
        let id = document.addDrawing(drawing, named: "Smiley face", icon: true, box: nil, blank: true)
        #expect(document.canvasSize == CGSize(width: 512, height: 512))
        #expect(document.layers.first?.frame == CGRect(x: 0, y: 0, width: 512, height: 512))
        #expect(document.layer(id: id)?.frame == CGRect(x: 0, y: 0, width: 512, height: 512))
    }

    @Test("An icon beside other work is a new icon frame next to it, nothing moved")
    func iconBesideWork() throws {
        var document = PhotonzDocument(canvasSize: CGSize(width: 800, height: 600))
        let drawing = try SVGArtwork.parse(Self.svg).get()
        let first = document.addDrawing(drawing, named: "Sun", icon: false, box: nil)
        let before = document.layer(id: first)?.frame
        let id = document.addDrawing(drawing, named: "Smiley face", icon: true, box: nil)
        #expect(document.layer(id: first)?.frame == before)
        let frame = try #require(document.layer(id: id))
        #expect(frame.isFrame && frame.frame.size == CGSize(width: 512, height: 512))
        #expect(document.canvasSize.width >= frame.frame.maxX && document.canvasSize.height >= frame.frame.maxY)
    }
}
