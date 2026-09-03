import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

@Suite("Layer clipboard")
struct ClipboardTests {

    @Test func transferRoundTripsThroughJSON() throws {
        var layer = Layer(name: "Note", content: .text(TextContent(string: "hi")),
                          frame: CGRect(x: 5, y: 5, width: 80, height: 20))
        layer.style.shadow = ShadowStyle()
        let transfer = LayerTransfer(layer: layer, imageData: Data([1, 2, 3]))
        let data = try JSONEncoder().encode(transfer)
        let decoded = try JSONDecoder().decode(LayerTransfer.self, from: data)
        #expect(decoded.layer == layer)
        #expect(decoded.imageData == Data([1, 2, 3]))
    }

    @Test func smallPastedImageLandsCenteredAtFullSize() {
        let frame = PastePlacement.frame(forImageOf: CGSize(width: 200, height: 100),
                                         canvas: CGSize(width: 800, height: 600))
        #expect(frame == CGRect(x: 300, y: 250, width: 200, height: 100))
    }

    @Test func oversizedPastedImageAspectFitsTheCanvas() {
        let frame = PastePlacement.frame(forImageOf: CGSize(width: 1600, height: 600),
                                         canvas: CGSize(width: 800, height: 600))
        // Scale 0.5 → 800×300, centered vertically.
        #expect(frame == CGRect(x: 0, y: 150, width: 800, height: 300))
    }

    @Test func degenerateImageSizeFallsBackToCanvasCenter() {
        let frame = PastePlacement.frame(forImageOf: .zero,
                                         canvas: CGSize(width: 800, height: 600))
        #expect(frame.isEmpty)
        #expect(frame.origin == CGPoint(x: 400, y: 300))
    }
}

/// Copying, pasting and dropping when the document is built out of frames.
/// A layer that arrives over a screen should join that screen, land where it
/// looks like it landed, and fit inside it.
@Suite("Paste and drop onto a frame")
struct PasteOntoFrameTests {

    private func leaf(_ name: String, _ frame: CGRect) -> Layer {
        Layer(name: name, content: .text(TextContent(string: name)), frame: frame)
    }

    /// Canvas 2000×1200 holding one 390×844 phone frame at (100, 60) with a
    /// button inside it at local (20, 40).
    private func makeDocument() -> PhotonzDocument {
        let button = leaf("Button", CGRect(x: 20, y: 40, width: 120, height: 44))
        let frame = Layer.frameLayer(name: "Home", origin: CGPoint(x: 100, y: 60),
                                     size: CGSize(width: 390, height: 844),
                                     children: [button])
        return PhotonzDocument(canvasSize: CGSize(width: 2000, height: 1200), layers: [frame])
    }

    private var insideTheFrame: CGPoint { CGPoint(x: 200, y: 300) }
    private var bareCanvas: CGPoint { CGPoint(x: 1500, y: 1000) }

    // MARK: - What ⌘C puts on the pasteboard

    @Test("A layer copied out of a frame carries its position on the canvas")
    func copiedLayerCarriesItsCanvasPosition() {
        let document = makeDocument()
        let button = document.frames.first!.children.first!
        let copied = document.detachedLayer(id: button.id)
        #expect(copied?.frame == CGRect(x: 120, y: 100, width: 120, height: 44))
    }

    @Test("Copying a loose layer changes nothing about it")
    func copyingALooseLayerIsTheLayer() {
        var document = makeDocument()
        let note = leaf("Note", CGRect(x: 900, y: 900, width: 100, height: 40))
        document.addLayer(note)
        #expect(document.detachedLayer(id: note.id) == note)
    }

    @Test("Copying a group keeps the pieces inside it where they are")
    func copyingAGroupKeepsItsContents() {
        var document = makeDocument()
        let frameID = document.frames.first!.id
        // A group whose anchor is not the top left of its contents, which is
        // what happens as soon as anything inside it is moved.
        let group = Layer(name: "Row",
                          content: .group(GroupContent(children: [
                              leaf("A", CGRect(x: 30, y: 10, width: 40, height: 20)),
                          ])),
                          frame: CGRect(origin: CGPoint(x: 10, y: 10), size: .zero))
        document.updateLayer(id: frameID) { $0.children.append(group) }
        let copied = document.detachedLayer(id: group.id)
        #expect(copied?.frame.origin == CGPoint(x: 110, y: 70))
        #expect(copied?.children == group.children)
    }

    @Test("Pasting a layer copied from a frame puts it back on that frame, where it looks")
    func pasteLandsOnTheFrameInPlace() {
        var document = makeDocument()
        let frameID = document.frames.first!.id
        let button = document.frames.first!.children.first!
        let copy = document.detachedLayer(id: button.id)!.duplicated(offsetBy: CGPoint(x: 16, y: 16))
        document.addLayerDrawnOnFrame(copy)
        #expect(document.frameID(containing: copy.id) == frameID)
        #expect(document.canvasFrame(of: copy.id) == CGRect(x: 136, y: 116, width: 120, height: 44))
    }

    @Test("A copied screen pasted back does not land inside the screen it came from")
    func aPastedFrameStaysATopLevelScreen() {
        var document = makeDocument()
        let original = document.frames.first!
        let copy = document.detachedLayer(id: original.id)!
            .duplicated(offsetBy: CGPoint(x: 16, y: 16))
        document.addLayerDrawnOnFrame(copy)
        #expect(document.layers.last?.id == copy.id)
        #expect(document.frameID(containing: copy.id) == copy.id)
        #expect(document.canvasBounds(of: copy.id)
                == CGRect(x: 116, y: 76, width: 390, height: 844))
    }

    // MARK: - Where an arriving image lands

    @Test("An image dropped on a frame lands under the pointer, inside that frame")
    func imageDroppedOnAFrameLandsUnderThePointer() {
        let document = makeDocument()
        let placed = document.placementForIncomingImage(size: CGSize(width: 200, height: 100),
                                                        at: CGPoint(x: 300, y: 400))
        #expect(placed == CGRect(x: 200, y: 350, width: 200, height: 100))
    }

    @Test("An image dropped over a frame's edge is nudged wholly onto it, never half off")
    func imageDroppedNearAnEdgeIsNudgedIn() {
        let document = makeDocument()
        // Frame box (100, 60) 390×844; let go 10 points inside its top left.
        let placed = document.placementForIncomingImage(size: CGSize(width: 200, height: 100),
                                                        at: CGPoint(x: 110, y: 70))
        #expect(placed == CGRect(x: 100, y: 60, width: 200, height: 100))
    }

    @Test("An image too big for the frame it lands on is fitted to it, not clipped away")
    func oversizedImageFitsTheFrame() {
        let document = makeDocument()
        let placed = document.placementForIncomingImage(size: CGSize(width: 780, height: 1688),
                                                        at: insideTheFrame)
        // Fitted edge to edge, so where the pointer was makes no difference.
        #expect(placed == CGRect(x: 100, y: 60, width: 390, height: 844))
    }

    @Test("An image dropped on bare canvas lands exactly where it always did")
    func imageOnBareCanvasIsUnchanged() {
        let document = makeDocument()
        let placed = document.placementForIncomingImage(size: CGSize(width: 200, height: 100),
                                                        at: bareCanvas)
        #expect(placed == PastePlacement.frame(forImageOf: CGSize(width: 200, height: 100),
                                               canvas: document.canvasSize))
    }

    @Test("A paste with no pointer uses the canvas centre, and joins a frame sitting there")
    func pasteWithNoPointerUsesTheCanvasCentre() {
        var document = makeDocument()
        // Nothing at the canvas centre yet: the old placement stands.
        let size = CGSize(width: 200, height: 100)
        #expect(document.placementForIncomingImage(size: size, at: nil)
                == PastePlacement.frame(forImageOf: size, canvas: document.canvasSize))
        // A frame over the canvas centre takes it.
        document.addFrame(name: "Wide", origin: CGPoint(x: 800, y: 400),
                          size: CGSize(width: 500, height: 400))
        #expect(document.placementForIncomingImage(size: size, at: nil)
                == CGRect(x: 950, y: 550, width: 200, height: 100))
    }

    @Test("A document with no frames places an arriving image exactly as before")
    func noFramesNoChange() {
        let document = PhotonzDocument(canvasSize: CGSize(width: 800, height: 600),
                                       layers: [leaf("Shot", CGRect(x: 0, y: 0, width: 800, height: 600))])
        let size = CGSize(width: 200, height: 100)
        let expected = PastePlacement.frame(forImageOf: size, canvas: document.canvasSize)
        #expect(document.placementForIncomingImage(size: size, at: CGPoint(x: 10, y: 10)) == expected)
        #expect(document.placementForIncomingImage(size: size, at: nil) == expected)
    }
}
