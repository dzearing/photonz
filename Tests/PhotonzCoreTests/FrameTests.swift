import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// A frame is a group with a size (`docs/design/ui-building.md`, step A2). It
/// holds still at the size it was given, it clips what sticks out, several of
/// them sit on one canvas, and everything else about it — selecting, moving,
/// restacking, saving — is what a group already does.
@Suite("A frame is a group with a size")
struct FrameTests {

    private func leaf(_ name: String, _ frame: CGRect) -> Layer {
        Layer(name: name, content: .text(TextContent(string: name)), frame: frame)
    }

    /// Canvas 2000×1200 holding one 390×844 phone frame at (100, 60) with a
    /// button inside it at local (20, 40), and a loose caption on the canvas.
    private func makeDocument() -> PhotonzDocument {
        let button = leaf("Button", CGRect(x: 20, y: 40, width: 120, height: 44))
        let frame = Layer.frameLayer(name: "Home", origin: CGPoint(x: 100, y: 60),
                                     size: CGSize(width: 390, height: 844),
                                     children: [button])
        return PhotonzDocument(canvasSize: CGSize(width: 2000, height: 1200),
                               layers: [leaf("Caption", CGRect(x: 600, y: 20, width: 200, height: 30)), frame])
    }

    private func frameID(in document: PhotonzDocument) -> UUID {
        document.frames.first!.id
    }

    // MARK: - The box

    @Test("A frame's box is the size it was given, not the size of its contents")
    func boxIsStoredSize() {
        let document = makeDocument()
        let frame = document.frames.first!
        #expect(frame.isFrame)
        #expect(frame.localBounds == CGRect(x: 100, y: 60, width: 390, height: 844))
        #expect(document.canvasBounds(of: frame.id) == CGRect(x: 100, y: 60, width: 390, height: 844))
    }

    @Test("A child hanging off the edge never resizes the frame")
    func childOutsideLeavesBoxAlone() {
        var document = makeDocument()
        let id = frameID(in: document)
        document.updateLayer(id: id) {
            $0.children.append(leaf("Overhang", CGRect(x: -200, y: 900, width: 100, height: 100)))
        }
        #expect(document.layer(id: id)?.localBounds == CGRect(x: 100, y: 60, width: 390, height: 844))
    }

    @Test("An ordinary group still follows its contents")
    func plainGroupUnchanged() {
        let child = leaf("Box", CGRect(x: 0, y: 0, width: 100, height: 40))
        let group = Layer(name: "Group", content: .group(GroupContent(children: [child])),
                          frame: CGRect(x: 10, y: 20, width: 0, height: 0))
        #expect(!group.isFrame)
        #expect(group.localBounds == CGRect(x: 10, y: 20, width: 100, height: 40))
    }

    @Test("A clipping frame's drawing reaches no further than its box")
    func clippedRenderBounds() {
        var document = makeDocument()
        let id = frameID(in: document)
        document.updateLayer(id: id) {
            $0.children.append(leaf("Overhang", CGRect(x: 300, y: 800, width: 400, height: 400)))
        }
        let clipped = document.layer(id: id)!.renderBounds
        #expect(clipped == CGRect(x: 100, y: 60, width: 390, height: 844))

        document.setFrameClips(id: id, false)
        let open = document.layer(id: id)!.renderBounds
        #expect(open.maxX > 490)
        #expect(open.maxY > 904)
    }

    // MARK: - Clicking

    @Test("The empty room inside a frame picks the frame itself")
    func emptyRoomPicksFrame() {
        let document = makeDocument()
        let id = frameID(in: document)
        #expect(document.hitTest(CGPoint(x: 400, y: 700))?.id == id)
    }

    @Test("A click on something inside still picks the frame at the top level, and a double click goes in")
    func clickPicksOutermost() {
        let document = makeDocument()
        let id = frameID(in: document)
        let button = document.layer(id: id)!.children[0]
        let point = CGPoint(x: 100 + 20 + 10, y: 60 + 40 + 10)
        let picked = document.selectionTarget(at: point, inside: nil)
        #expect(picked?.id == id)
        let deeper = document.descendTarget(at: point, inside: nil)
        #expect(deeper?.id == button.id)
        #expect(deeper?.context == id)
    }

    @Test("What hangs outside a clipping frame cannot be clicked")
    func clippedChildIsNotClickable() {
        var document = makeDocument()
        let id = frameID(in: document)
        document.updateLayer(id: id) {
            $0.children.append(leaf("Overhang", CGRect(x: 300, y: 900, width: 200, height: 100)))
        }
        // (450, 1010) in canvas space is inside the overhang but outside the frame.
        #expect(document.hitTest(CGPoint(x: 450, y: 1010)) == nil)
        // With clipping off it is on screen again, so the click reaches it —
        // and a plain click still resolves to the frame it belongs to.
        document.setFrameClips(id: id, false)
        #expect(document.hitTest(CGPoint(x: 450, y: 1010))?.name == "Overhang")
        #expect(document.selectionTarget(at: CGPoint(x: 450, y: 1010), inside: nil)?.id == id)
    }

    @Test("A layer outside every frame is picked as it always was")
    func looseLayerUnaffected() {
        let document = makeDocument()
        #expect(document.hitTest(CGPoint(x: 700, y: 30))?.name == "Caption")
        #expect(document.hitTest(CGPoint(x: 1500, y: 1100)) == nil)
    }

    // MARK: - Several frames on one canvas

    @Test("Several frames coexist, and moving one carries only its own contents")
    func severalFrames() {
        var document = makeDocument()
        let first = frameID(in: document)
        let second = document.addFrame(name: "Settings", origin: CGPoint(x: 600, y: 60),
                                       size: CGSize(width: 390, height: 844)).id
        #expect(document.frames.count == 2)
        let buttonID = document.layer(id: first)!.children[0].id
        let before = document.canvasFrame(of: buttonID)

        document.moveLayer(id: second, toCanvasOrigin: CGPoint(x: 700, y: 60))
        #expect(document.canvasBounds(of: second)?.origin == CGPoint(x: 700, y: 60))
        #expect(document.canvasFrame(of: buttonID) == before)

        document.moveLayer(id: first, toCanvasOrigin: CGPoint(x: 0, y: 0))
        #expect(document.canvasFrame(of: buttonID) == CGRect(x: 20, y: 40, width: 120, height: 44))
    }

    @Test("A frame restacks like any other layer")
    func restacks() {
        var document = makeDocument()
        let id = frameID(in: document)
        #expect(document.layers.last?.id == id)
        document.restackLayers(ids: [id], .toBack)
        #expect(document.layers.first?.id == id)
    }

    @Test("A marquee grabs a frame whole")
    func marqueeGrabsWhole() {
        let document = makeDocument()
        let id = frameID(in: document)
        #expect(document.layerIDs(fullyInside: CGRect(x: 90, y: 50, width: 420, height: 880)).contains(id))
        #expect(!document.layerIDs(fullyInside: CGRect(x: 90, y: 50, width: 200, height: 200)).contains(id))
    }

    // MARK: - Sizes

    @Test("The preset list offers real screen sizes and recognises a custom one")
    func presets() {
        #expect(FramePreset.all.count >= 4)
        #expect(FramePreset.matching(CGSize(width: 390, height: 844))?.title == "Phone")
        #expect(FramePreset.matching(CGSize(width: 391, height: 844)) == nil)
        #expect(FramePreset.normalized(CGSize(width: 390.4, height: 843.6)) == CGSize(width: 390, height: 844))
        #expect(FramePreset.normalized(CGSize(width: 0, height: -5)) == CGSize(width: 1, height: 1))
        #expect(FramePreset.normalized(CGSize(width: CGFloat.nan, height: 100)).width == 1)
        #expect(!FramePreset.isValid(CGSize(width: 0, height: 100)))
    }

    @Test("Resizing a frame moves where it clips and leaves the contents alone")
    func resizeDoesNotScaleContents() {
        var document = makeDocument()
        let id = frameID(in: document)
        let buttonID = document.layer(id: id)!.children[0].id
        let before = document.canvasFrame(of: buttonID)
        document.setFrameSize(id: id, size: CGSize(width: 1024, height: 768))
        #expect(document.canvasBounds(of: id)?.size == CGSize(width: 1024, height: 768))
        #expect(document.canvasFrame(of: buttonID) == before)
    }

    @Test("A frame's width and height are typeable, an ordinary group's are not")
    func typedSize() {
        let document = makeDocument()
        let frame = document.frames.first!
        let editing = LayerGeometryEditing(layer: frame)
        #expect(editing.canSetWidth)
        #expect(editing.canSetHeight)
        let resized = frame.resized(to: CGRect(x: 10, y: 20, width: 500, height: 900))
        #expect(resized.localBounds == CGRect(x: 10, y: 20, width: 500, height: 900))
        #expect(resized.children.count == frame.children.count)

        let group = Layer(name: "Group", content: .group(GroupContent(children: [leaf("A", .zero)])),
                          frame: CGRect(x: 0, y: 0, width: 0, height: 0))
        #expect(!LayerGeometryEditing(layer: group).canSetWidth)
    }

    // MARK: - Making one out of what is already there

    @Test("Frame Selection wraps what is selected without moving it")
    func frameSelection() {
        var document = PhotonzDocument(canvasSize: CGSize(width: 800, height: 600),
                                       layers: [leaf("A", CGRect(x: 100, y: 100, width: 50, height: 50)),
                                                leaf("B", CGRect(x: 200, y: 180, width: 60, height: 40))])
        let ids = Set(document.layers.map(\.id))
        #expect(document.canFrameSelection(ids: [document.layers[0].id]))
        let made = document.frameSelection(ids: ids)
        #expect(made?.isFrame == true)
        #expect(made?.localBounds == CGRect(x: 100, y: 100, width: 160, height: 120))
        // A frame drawn around existing work paints no surface behind it.
        #expect(made?.group?.backgroundHex == nil)
        let a = document.allLayers.first { $0.name == "A" }!
        #expect(document.canvasFrame(of: a.id) == CGRect(x: 100, y: 100, width: 50, height: 50))
    }

    @Test("A frame can become an ordinary group and back")
    func toggleFrame() {
        var document = makeDocument()
        let id = frameID(in: document)
        document.setFrame(id: id, isFrame: false)
        #expect(document.layer(id: id)?.isFrame == false)
        // As a plain group it follows its contents again.
        #expect(document.canvasBounds(of: id) == CGRect(x: 120, y: 100, width: 120, height: 44))
        document.setFrame(id: id, isFrame: true)
        #expect(document.canvasBounds(of: id) == CGRect(x: 120, y: 100, width: 120, height: 44))
    }

    @Test("A fresh name never repeats")
    func names() {
        var document = makeDocument()
        #expect(document.freshFrameName() == "Frame")
        document.addFrame(origin: .zero, size: CGSize(width: 100, height: 100))
        #expect(document.freshFrameName() == "Frame 2")
    }

    @Test("Every layer knows the frame it belongs to")
    func frameMembership() {
        let document = makeDocument()
        let id = frameID(in: document)
        let button = document.layer(id: id)!.children[0]
        let caption = document.layers[0]
        #expect(document.frameID(containing: button.id) == id)
        #expect(document.frameID(containing: id) == id)
        #expect(document.frameID(containing: caption.id) == nil)
    }

    @Test("The first frame lands in view; the next lines up beside it")
    func placement() {
        var document = PhotonzDocument(canvasSize: CGSize(width: 2000, height: 1200))
        let size = CGSize(width: 390, height: 844)
        let visible = CGRect(x: 400, y: 100, width: 800, height: 900)
        let first = document.placementForNewFrame(size: size, visible: visible)
        #expect(first == CGPoint(x: 800 - 195, y: 550 - 422))

        document.addFrame(name: "One", origin: first, size: size)
        let second = document.placementForNewFrame(size: size, visible: visible)
        #expect(second == CGPoint(x: first.x + 390 + PhotonzDocument.frameGutter, y: first.y))

        // The row keeps its top edge even when the frames are different heights.
        document.addFrame(name: "Two", origin: second, size: CGSize(width: 300, height: 400))
        let third = document.placementForNewFrame(size: size, visible: visible)
        #expect(third.y == first.y)
        #expect(third.x == second.x + 300 + PhotonzDocument.frameGutter)
    }

    // MARK: - Drawing on a frame

    @Test("A layer drawn on a frame lands on that frame, without moving")
    func drawingLandsOnTheFrame() {
        var document = makeDocument()
        let id = frameID(in: document)
        // Drawn in canvas space, over the middle of the frame.
        let drawn = leaf("Card", CGRect(x: 140, y: 200, width: 200, height: 120))
        let landed = document.addLayerOnFrame(drawn)
        #expect(landed == id)
        #expect(document.layer(id: id)?.children.count == 2)
        #expect(document.canvasFrame(of: drawn.id) == CGRect(x: 140, y: 200, width: 200, height: 120))
        // It is not a top-level layer any more.
        #expect(document.layers.contains { $0.id == drawn.id } == false)
    }

    @Test("A layer drawn on bare canvas is added exactly as it always was")
    func drawingOffAFrameIsUnchanged() {
        var document = makeDocument()
        let drawn = leaf("Note", CGRect(x: 900, y: 900, width: 100, height: 40))
        #expect(document.addLayerOnFrame(drawn) == nil)
        #expect(document.layers.last?.id == drawn.id)
        #expect(document.canvasFrame(of: drawn.id) == CGRect(x: 900, y: 900, width: 100, height: 40))
    }

    @Test("A shape drawn mostly on a frame joins it; one drawn mostly off it does not")
    func theCentreDecides() {
        var document = makeDocument()
        let id = frameID(in: document)
        // Centre at (480, 400): inside the frame, which ends at x = 490.
        let mostlyOn = leaf("On", CGRect(x: 380, y: 380, width: 200, height: 40))
        #expect(document.addLayerOnFrame(mostlyOn) == id)
        // Centre at (540, 400): past the frame's right edge.
        let mostlyOff = leaf("Off", CGRect(x: 440, y: 380, width: 200, height: 40))
        #expect(document.addLayerOnFrame(mostlyOff) == nil)
    }

    @Test("A document with no frames adds layers exactly as it did")
    func noFramesNoChange() {
        var document = PhotonzDocument(canvasSize: CGSize(width: 400, height: 400),
                                       layers: [leaf("A", CGRect(x: 0, y: 0, width: 400, height: 400))])
        let before = document
        var after = document
        document.addLayer(leaf("B", CGRect(x: 10, y: 10, width: 20, height: 20)))
        after.addLayerOnFrame(leaf("B", CGRect(x: 10, y: 10, width: 20, height: 20)))
        #expect(after.layers.count == document.layers.count)
        #expect(after.layers.last?.name == "B")
        #expect(before.layers.count == 1)
    }

    @Test("The frame under a point is the innermost one")
    func frameUnderAPoint() {
        var document = makeDocument()
        let outer = frameID(in: document)
        let inner = Layer.frameLayer(name: "Card", origin: CGPoint(x: 40, y: 100),
                                     size: CGSize(width: 200, height: 200))
        document.updateLayer(id: outer) { $0.children.append(inner) }
        #expect(document.frameID(under: CGPoint(x: 200, y: 220)) == inner.id)
        #expect(document.frameID(under: CGPoint(x: 200, y: 700)) == outer)
        #expect(document.frameID(under: CGPoint(x: 1500, y: 700)) == nil)
    }

    // MARK: - Export

    @Test("A frame exports as a picture of its own contents only")
    func frameDocument() {
        let document = makeDocument()
        let id = frameID(in: document)
        let export = document.frameDocument(id: id)
        #expect(export?.canvasSize == CGSize(width: 390, height: 844))
        #expect(export?.layers.count == 1)
        #expect(export?.layers.first?.frame.origin == .zero)
        // The caption sitting outside the frame is not in the picture.
        #expect(export?.allLayers.contains { $0.name == "Caption" } == false)
        #expect(export?.allLayers.contains { $0.name == "Button" } == true)
        // Only a frame answers.
        #expect(document.frameDocument(id: document.layers[0].id) == nil)
    }

    @Test("A hidden frame still exports")
    func hiddenFrameExports() {
        var document = makeDocument()
        let id = frameID(in: document)
        document.updateLayer(id: id) { $0.isVisible = false }
        #expect(document.frameDocument(id: id)?.layers.first?.isVisible == true)
    }

    // MARK: - On disk

    @Test("A frame round-trips, and a group saved before frames existed decodes unchanged")
    func coding() throws {
        let document = makeDocument()
        let data = try JSONEncoder().encode(document)
        let back = try JSONDecoder().decode(PhotonzDocument.self, from: data)
        #expect(back == document)
        let frame = back.frames.first!
        #expect(frame.group?.clipsContents == true)
        #expect(frame.group?.backgroundHex == Layer.defaultFrameBackgroundHex)

        // An ordinary group writes none of the frame keys, so a document from
        // before frames existed is byte for byte what it was.
        let group = GroupContent(children: [leaf("A", .zero)])
        let json = String(data: try JSONEncoder().encode(group), encoding: .utf8) ?? ""
        #expect(!json.contains("isFrame"))
        #expect(!json.contains("clipsContents"))
        #expect(!json.contains("backgroundHex"))

        // …and a payload with only `children` in it comes back as a plain group.
        let legacy = try JSONDecoder().decode(GroupContent.self, from: Data(json.utf8))
        #expect(legacy.isFrame == false)
        #expect(legacy.clipsContents == true)
    }

    @Test("A document with no frames says so")
    func documentWithoutFrames() {
        let document = PhotonzDocument(canvasSize: CGSize(width: 100, height: 100),
                                       layers: [leaf("A", CGRect(x: 0, y: 0, width: 10, height: 10))])
        #expect(!document.hasFrames)
        #expect(document.frames.isEmpty)
        #expect(makeDocument().hasFrames)
    }

    @Test("Duplicating a frame copies the box and everything in it")
    func duplicate() {
        var document = makeDocument()
        let id = frameID(in: document)
        let copy = document.duplicateLayer(id: id)!
        #expect(copy.isFrame)
        #expect(copy.frame.size == CGSize(width: 390, height: 844))
        #expect(copy.children.count == 1)
        #expect(copy.children[0].id != document.layer(id: id)!.children[0].id)
    }
}
