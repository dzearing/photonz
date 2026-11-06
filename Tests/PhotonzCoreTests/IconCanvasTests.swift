import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// A picture made as an icon works like an icon: its canvas answers every
/// question an icon frame answers, without a frame anybody has to make.
struct IconCanvasTests {

    private static let ref = ImageRef(id: UUID(), pixelSize: CGSize(width: 512, height: 512))

    /// What File, New, Image, Icon makes: a locked Background, marked.
    private func iconPicture(side: CGFloat = 512) -> PhotonzDocument {
        var document = PhotonzDocument.withBaseImage(
            ImageRef(id: UUID(), pixelSize: CGSize(width: side, height: side)))
        document.madeAsIcon = true
        return document
    }

    private func oval(at box: CGRect = CGRect(x: 100, y: 100, width: 200, height: 200)) -> Layer {
        Layer(name: "Oval",
              content: .annotation(AnnotationContent(shape: .ellipse, start: .zero,
                                                     end: CGPoint(x: box.width, y: box.height))),
              frame: box)
    }

    // MARK: What makes one

    @Test("Icon and App Icon are the rows that make an icon, and no other row is")
    func iconRows() {
        #expect(BlankCanvas.makesAnIcon(presetID: "icon"))
        #expect(BlankCanvas.makesAnIcon(presetID: "app-icon"))
        for preset in BlankCanvas.presets { #expect(!BlankCanvas.makesAnIcon(presetID: preset.id)) }
        #expect(!BlankCanvas.makesAnIcon(presetID: "custom"))
    }

    @Test("A square picture that was not made as an icon gets none of this")
    func squareIsNotAnIcon() {
        let document = PhotonzDocument.withBaseImage(Self.ref)
        #expect(!document.isIconCanvas)
        #expect(!document.opensAsIcon)
        #expect(!document.hasIconFrames)
        #expect(document.iconFrameID(under: CGPoint(x: 50, y: 50)) == nil)
        #expect(document.iconSnap(at: CGPoint(x: 50.4, y: 50.4), keylines: true) == nil)
    }

    @Test("A marked picture cut to a size no icon is drawn at stops being one")
    func cutOffAnIconSize() {
        var document = iconPicture()
        #expect(document.isIconCanvas)
        document.canvasSize = CGSize(width: 512, height: 300)
        #expect(!document.isIconCanvas)
        #expect(!document.opensAsIcon)
    }

    @Test("The mark survives a save, and a file from before it reads as no icon")
    func saved() throws {
        let data = try JSONEncoder().encode(iconPicture())
        #expect(try JSONDecoder().decode(PhotonzDocument.self, from: data).isIconCanvas)

        let plain = try JSONEncoder().encode(PhotonzDocument.withBaseImage(Self.ref))
        #expect(!String(decoding: plain, as: UTF8.self).contains("madeAsIcon"))
        #expect(try !JSONDecoder().decode(PhotonzDocument.self, from: plain).madeAsIcon)
    }

    // MARK: It answers as a frame does

    @Test("Points land on whole units counted from the picture's corner")
    func snapsToUnits() throws {
        let document = iconPicture()
        let snap = try #require(document.iconSnap(at: CGPoint(x: 100.4, y: 200.3), keylines: false))
        #expect(snap.frame == CGRect(x: 0, y: 0, width: 512, height: 512))
        #expect(snap.point(nearest: CGPoint(x: 100.4, y: 200.3), zoom: 8) == CGPoint(x: 100, y: 200))
    }

    @Test("Off the picture there is nothing to snap to")
    func offThePicture() {
        #expect(iconPicture().iconSnap(at: CGPoint(x: -40, y: 20), keylines: true) == nil)
    }

    @Test("A shape already drawn pulls the next point, as it does in a frame")
    func shapesPull() throws {
        var document = iconPicture()
        document.addLayerDrawnOnFrame(oval())
        let snap = try #require(document.iconSnap(at: CGPoint(x: 200.4, y: 100.4), keylines: false))
        #expect(snap.centers.contains(CGPoint(x: 200, y: 200)))
        #expect(snap.anchors.contains(CGPoint(x: 200, y: 100)))
    }

    @Test("A line starts at the weight an icon of this size starts it at")
    func startingWeight() {
        let document = iconPicture()
        var framed = PhotonzDocument(canvasSize: CGSize(width: 512, height: 512))
        framed.addFrame(origin: .zero, size: CGSize(width: 512, height: 512))
        let point = CGPoint(x: 30, y: 30)
        #expect(document.iconFrameSize(under: point) == CGSize(width: 512, height: 512))
        #expect(document.startingStrokeWidth(armed: 40, chosen: false, drawnAt: point)
                == framed.startingStrokeWidth(armed: 40, chosen: false, drawnAt: point))
    }

    @Test("A weight somebody chose is theirs, on the canvas as in a frame")
    func chosenWeight() {
        #expect(iconPicture().startingStrokeWidth(armed: 90, chosen: true,
                                                  drawnAt: CGPoint(x: 30, y: 30)) == 90)
    }

    @Test("Mirror Across Center and Center on the Artboard use the middle of the picture")
    func middleOfThePicture() throws {
        var document = iconPicture()
        let shape = oval(at: CGRect(x: 40, y: 60, width: 100, height: 100))
        document.addLayerDrawnOnFrame(shape)
        #expect(document.mirrorAxis(of: shape.id) == 256)
        let copies = document.mirrorAcrossCenter(ids: [shape.id])
        let copy = try #require(copies.first.flatMap { document.layer(id: $0) })
        #expect(copy.frame.minX == 372)
        let moved = document.centerOnArtboard(ids: [shape.id])
        #expect(moved)
        #expect(document.layer(id: shape.id)?.frame == CGRect(x: 206, y: 206, width: 100, height: 100))
    }

    @Test("The Artboard pivot of a shape on the picture is the picture's middle")
    func pivot() throws {
        var document = iconPicture()
        let shape = oval(at: CGRect(x: 40, y: 60, width: 100, height: 100))
        document.addLayerDrawnOnFrame(shape)
        let plain = shape
        var framed = PhotonzDocument(canvasSize: CGSize(width: 512, height: 512))
        framed.addFrame(origin: .zero, size: CGSize(width: 512, height: 512))
        framed.addLayerDrawnOnFrame(plain)
        #expect(document.artboardPivot(for: shape.id) != nil)
        #expect(document.artboardPivot(for: shape.id) == framed.artboardPivot(for: shape.id))
    }

    // MARK: The previews

    @Test("Nothing to preview until something is drawn, then the picture is what they show")
    func previewsWaitForADrawing() {
        var document = iconPicture()
        let inside = PhotonzDocument.iconCanvasID
        let background = document.layers[0].id
        #expect(document.iconPreviewFrameID(picked: nil, pointerIn: inside, remembered: nil) == nil)
        #expect(document.iconPreviewFrameID(picked: background, pointerIn: nil, remembered: nil) == nil)
        let shape = oval()
        document.addLayerDrawnOnFrame(shape)
        #expect(document.iconPreviewFrameID(picked: shape.id, pointerIn: nil, remembered: nil) == inside)
        #expect(document.iconPreviewFrameID(picked: nil, pointerIn: inside, remembered: nil) == inside)
        // Standing back to look keeps them up, as it does for a frame.
        #expect(document.iconPreviewFrameID(picked: nil, pointerIn: nil, remembered: inside) == inside)
        // ...and a picture opened from a file has one icon to show before
        // anybody has picked or pointed at anything.
        #expect(document.iconPreviewFrameID(picked: nil, pointerIn: nil, remembered: nil) == inside)
    }

    @Test("A remembered canvas is dropped once there is nothing left to show")
    func rememberedCanvasIsChecked() {
        let document = iconPicture()
        #expect(document.iconPreviewFrameID(picked: nil, pointerIn: nil,
                                            remembered: PhotonzDocument.iconCanvasID) == nil)
        let plain = PhotonzDocument.withBaseImage(Self.ref)
        #expect(plain.iconPreviewFrameID(picked: nil, pointerIn: nil,
                                         remembered: PhotonzDocument.iconCanvasID) == nil)
    }

    @Test("The previews are drawn at the picture's size, and the sizes are an icon's")
    func previewSizes() {
        #expect(iconPicture().iconSize(of: PhotonzDocument.iconCanvasID) == CGSize(width: 512, height: 512))
        #expect(iconPicture().iconBox(of: PhotonzDocument.iconCanvasID)
                == CGRect(x: 0, y: 0, width: 512, height: 512))
        #expect(PhotonzDocument(canvasSize: CGSize(width: 512, height: 512))
                    .iconBox(of: PhotonzDocument.iconCanvasID) == nil)
    }

    @Test("On the Dark ground the white Background is left out, as a frame's surface is")
    func darkGround() throws {
        var document = iconPicture()
        let shape = oval()
        document.addLayerDrawnOnFrame(shape)
        let id = PhotonzDocument.iconCanvasID
        let light = try #require(document.iconPreviewDocument(id: id, onDarkGround: false))
        let dark = try #require(document.iconPreviewDocument(id: id, onDarkGround: true))
        #expect(light.layers.count == 2)
        #expect(dark.layers.map(\.id) == [shape.id])
        #expect(dark.canvasSize == document.canvasSize)
    }

    @Test("What the card keeps clear of is what is drawn, never the Background")
    func ink() {
        var document = iconPicture()
        #expect(document.iconPreviewInk(id: PhotonzDocument.iconCanvasID).isEmpty)
        document.addLayerDrawnOnFrame(oval())
        #expect(document.iconPreviewInk(id: PhotonzDocument.iconCanvasID).count == 1)
    }

    // MARK: Frames keep their say

    @Test("A screen on an icon picture stays a screen")
    func screenOnTheCanvas() {
        var document = iconPicture(side: 1024)
        let screen = document.addFrame(origin: CGPoint(x: 100, y: 100),
                                       size: CGSize(width: 390, height: 844))
        let inside = CGPoint(x: 200, y: 200)
        #expect(document.iconFrameID(under: inside) == nil)
        #expect(document.iconFrameID(containing: screen.id) == nil)
        #expect(document.iconSnap(at: inside, keylines: true) == nil)
        // ...and beside it the canvas is still the icon.
        #expect(document.iconFrameID(under: CGPoint(x: 900, y: 40)) == PhotonzDocument.iconCanvasID)
    }

    @Test("An icon frame on an icon picture speaks for itself")
    func iconFrameOnTheCanvas() {
        var document = iconPicture()
        let frame = document.addFrame(origin: CGPoint(x: 40, y: 40), size: CGSize(width: 24, height: 24))
        #expect(document.iconFrameID(under: CGPoint(x: 50, y: 50)) == frame.id)
        #expect(document.iconFrameID(under: CGPoint(x: 300, y: 300)) == PhotonzDocument.iconCanvasID)
    }

    // MARK: Ask's icon

    @Test("Ask's icon fills the picture with a frame, so the guides are the frame's alone")
    func askFillsTheCanvas() {
        var document = iconPicture()
        let frame = document.addFrame(origin: .zero, size: CGSize(width: 512, height: 512))
        #expect(!document.isIconCanvas)
        #expect(document.opensAsIcon)
        #expect(document.iconFrameID(under: CGPoint(x: 50, y: 50)) == frame.id)
    }

    @Test("A picture that is one icon frame opens as an icon, marked or not")
    func frameFillingThePicture() {
        var document = PhotonzDocument(canvasSize: CGSize(width: 512, height: 512))
        document.addFrame(origin: .zero, size: CGSize(width: 512, height: 512))
        #expect(document.opensAsIcon)
    }

    @Test("A small icon frame on a big picture does not make it open as an icon")
    func smallFrameOnABigPicture() {
        var document = PhotonzDocument(canvasSize: CGSize(width: 1440, height: 1024))
        document.addFrame(origin: CGPoint(x: 80, y: 80), size: CGSize(width: 24, height: 24))
        #expect(!document.opensAsIcon)
    }

    @Test("A screen that fills a square picture is no icon")
    func squareScreen() {
        var document = PhotonzDocument(canvasSize: CGSize(width: 1000, height: 1000))
        document.addFrame(origin: .zero, size: CGSize(width: 1000, height: 1000))
        #expect(!document.opensAsIcon)
    }
}
