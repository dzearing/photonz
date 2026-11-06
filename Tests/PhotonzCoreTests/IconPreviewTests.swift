import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// Seeing an icon at the size it will really be used (`next-icon-previews`).
///
/// An icon is the only thing in this app drawn at one size and looked at at
/// another, so while you draw in an icon frame the same drawing is shown small
/// beside you. This is the pure half: WHICH sizes a given frame is shown at,
/// and which frames get shown at all.
struct IconPreviewTests {

    // MARK: - Which frames are icons

    @Test("A small square frame is an icon; a screen is not")
    func iconFrameSizes() {
        #expect(IconPreviews.isIconSize(CGSize(width: 24, height: 24)))
        #expect(IconPreviews.isIconSize(CGSize(width: 512, height: 512)))
        // Every size the Icons group offers is one, or the strip would be
        // missing from the frames it was built for.
        #expect(FramePreset.icons.allSatisfy { IconPreviews.isIconSize($0.size) })
        // A screen is not, whatever its shape: the Square preset is a
        // thousand points across and nobody draws a glyph on it.
        #expect(FramePreset.screens.allSatisfy { !IconPreviews.isIconSize($0.size) })
        // Not square, not an icon: an icon is square everywhere it is used,
        // and a 512 x 64 banner shown at 16 would be a smear.
        #expect(!IconPreviews.isIconSize(CGSize(width: 64, height: 32)))
        #expect(!IconPreviews.isIconSize(.zero))
    }

    // MARK: - Which sizes one frame is shown at

    @Test("An app icon frame is shown at every interface size")
    func appIconSides() {
        #expect(IconPreviews.sides(forFrameSide: 512) == [16, 24, 32, 48, 64])
    }

    @Test("A 24 point icon is shown at 16, 24, 32 and 48, as the icon mock draws it")
    func twentyFourShowsTheMocksFour() {
        // icon-draw-wt.html, step 11: the strip under a 24 unit glyph reads
        // 16, 24, 32, 48. A 24 grid glyph is used at 32 and 48 as well, and
        // those are the sizes a designer checks it at before it joins a set.
        #expect(IconPreviews.sides(forFrameSide: 24) == [16, 24, 32, 48])
    }

    @Test("A frame is shown at every interface size up to twice its own")
    func upToTwiceItsOwnSide() {
        // The picture is drawn AT each size from the shapes, never a small
        // picture blown up, so a bigger chip is the icon's own pixels at that
        // size. Twice is where it stops: a 16 shown at 64 is a different icon.
        #expect(IconPreviews.sides(forFrameSide: 16) == [16, 24, 32])
        #expect(IconPreviews.sides(forFrameSide: 32) == [16, 24, 32, 48, 64])
        #expect(IconPreviews.sides(forFrameSide: 48) == [16, 24, 32, 48, 64])
        #expect(IconPreviews.sides(forFrameSide: 64) == [16, 24, 32, 48, 64])
    }

    @Test("A size nobody offered still shows itself at true size")
    func offSizeFrames() {
        // A size nobody offered still gets its own true size, with the
        // interface sizes round it.
        #expect(IconPreviews.sides(forFrameSide: 20) == [16, 20, 24, 32])
        #expect(IconPreviews.sides(forFrameSide: 10) == [10, 16])
        // Each size appears once, however it was arrived at.
        #expect(Set(IconPreviews.sides(forFrameSide: 48)).count
            == IconPreviews.sides(forFrameSide: 48).count)
    }

    @Test("A frame too big or too odd to be an icon is shown at nothing")
    func nonIconFrames() {
        #expect(IconPreviews.sides(forFrameSide: 1000).isEmpty)
        #expect(IconPreviews.sides(forFrameSide: 0).isEmpty)
    }

    // MARK: - What each ground draws

    @Test("The light ground is the frame's own flat surface, under the exported picture")
    func lightGroundIsTheSurface() throws {
        // The glyph sits straight on the ground rather than on a white square
        // inside a grey one, while the picture on it stays exactly what Export
        // writes. Left out of the picture, a soft edge blended on screen reads
        // up to a fifth darker than in the file, which would flatter the very
        // hairlines the strip is there to catch.
        var document = PhotonzDocument(canvasSize: CGSize(width: 200, height: 200))
        let frame = document.addFrame(origin: CGPoint(x: 10, y: 10),
                                      size: CGSize(width: 24, height: 24))
        #expect(document.iconPreviewGroundHex(id: frame.id) == "#FFFFFF")
        let light = try #require(document.iconPreviewDocument(id: frame.id, onDarkGround: false))
        #expect(light == document.frameDocument(id: frame.id))
        #expect(document.iconPreviewDocument(id: UUID(), onDarkGround: false) == nil)
    }

    @Test("The ground labelled Light is light whatever the frame is painted")
    func lightGroundIsAlwaysLight() {
        // It says Light on it, so it has to be. A dark or a mid surface stays
        // in the picture as the square it really is, on the plain light ground.
        var document = PhotonzDocument(canvasSize: CGSize(width: 200, height: 200))
        let cream = document.addFrame(origin: .zero, size: CGSize(width: 24, height: 24),
                                      backgroundHex: "#FFF6E0")
        let black = document.addFrame(origin: CGPoint(x: 30, y: 0),
                                      size: CGSize(width: 24, height: 24),
                                      backgroundHex: "#101010")
        let blue = document.addFrame(origin: CGPoint(x: 60, y: 0),
                                     size: CGSize(width: 24, height: 24),
                                     backgroundHex: "#2050C0")
        #expect(document.iconPreviewGroundHex(id: cream.id) == "#FFF6E0")
        #expect(document.iconPreviewGroundHex(id: black.id) == IconPreviews.lightGroundHex)
        #expect(document.iconPreviewGroundHex(id: blue.id) == IconPreviews.lightGroundHex)
    }

    @Test("On the dark ground an icon frame is drawn without its own surface")
    func darkGroundDropsTheSurface() throws {
        // The frame's white is the artboard, not the icon: left in, the dark
        // ground would hold a white square, and the glyph would never be seen
        // against the dark at all.
        var document = PhotonzDocument(canvasSize: CGSize(width: 200, height: 200))
        let frame = document.addFrame(origin: CGPoint(x: 10, y: 10),
                                      size: CGSize(width: 24, height: 24))
        let dark = try #require(document.iconPreviewDocument(id: frame.id, onDarkGround: true))
        #expect(dark.layers.first?.group?.background == nil)
        #expect(document.iconPreviewDocument(id: UUID(), onDarkGround: true) == nil)
    }

    @Test("A surface the ground cannot be stays in the picture")
    func gradientOrClearSurfaceStays() throws {
        var document = PhotonzDocument(canvasSize: CGSize(width: 200, height: 200))
        let clear = document.addFrame(origin: .zero, size: CGSize(width: 24, height: 24),
                                      backgroundHex: nil)
        #expect(document.iconPreviewGroundHex(id: clear.id) == IconPreviews.lightGroundHex)
        let shaded = document.addFrame(origin: CGPoint(x: 50, y: 0),
                                       size: CGSize(width: 24, height: 24))
        document.updateLayer(id: shaded.id) { frame in
            guard var group = frame.group else { return }
            group.background = Paint(hex: "#2050C0", kind: .linear)
            frame.content = .group(group)
        }
        // A gradient is not one colour a ground can be, so it sits on the plain
        // light ground, still exactly as Export draws it.
        #expect(document.iconPreviewGroundHex(id: shaded.id) == IconPreviews.lightGroundHex)
        let light = try #require(document.iconPreviewDocument(id: shaded.id, onDarkGround: false))
        #expect(light == document.frameDocument(id: shaded.id))
    }

    // MARK: - The card

    @Test("The card is sized from its sizes, so where it fits can be worked out")
    func cardSizes() {
        let all = IconPreviews.interfaceSides
        // 184 points of icons, four gaps of ten, eight either side of them on
        // the ground, ten either side of that on the glass.
        #expect(IconPreviews.cardSize(sides: all, hasTransport: false).width == 260)
        // Two grounds of 64 and six each above and below, then the title, the
        // numbers and the card's own padding.
        #expect(IconPreviews.groundHeight(sides: all) == 76)
        #expect(IconPreviews.cardSize(sides: all, hasTransport: false).height == 216)
        // The title row is always there, so a transport arriving never moves it.
        #expect(IconPreviews.cardSize(sides: all, hasTransport: true)
            == IconPreviews.cardSize(sides: all, hasTransport: false))
    }

    @Test("A narrow card still holds its title and the words on each ground")
    func narrowCard() {
        // Light sits above the smallest icon, so a ground is never shorter than
        // the word and that icon together, however small the sizes are.
        #expect(IconPreviews.groundHeight(sides: [16]) == 38)
        let lone = IconPreviews.cardSize(sides: [16], hasTransport: false)
        #expect(lone.width == IconPreviews.minimumGroundWidth + 20)
        // Play and the speed menu need more room than the title alone.
        #expect(IconPreviews.cardSize(sides: [16], hasTransport: true).width > lone.width)
    }

    @Test("The sizes down a ground step by their own width and one gap")
    func columnsLineUp() {
        #expect(IconPreviews.columnLeadings(sides: [16, 24, 32]) == [8, 34, 68])
    }

    // MARK: - Where the card goes

    private let room = CGSize(width: 1200, height: 900)
    private let toolBar = CGRect(x: 400, y: 840, width: 400, height: 48)

    private func place(_ bounds: CGSize? = nil, icon: CGRect, ink: [CGRect] = [],
                       chrome: [CGRect]? = nil) -> IconPreviews.Placement? {
        IconPreviews.placement(sides: IconPreviews.interfaceSides, hasTransport: false,
                               in: bounds ?? room, inset: 12, icon: icon, ink: ink,
                               chrome: chrome ?? [toolBar])
    }

    @Test("With room to spare the card is top left and shows every size")
    func topLeftByDefault() throws {
        let placed = try #require(place(icon: CGRect(x: 500, y: 300, width: 200, height: 200)))
        #expect(placed.anchor == .topLeading)
        #expect(placed.sides == IconPreviews.interfaceSides)
        #expect(placed.frame.origin == CGPoint(x: 12, y: 12))
    }

    @Test("An icon under the top left corner sends the card to the next corner")
    func stepsAsideFromTheIcon() throws {
        let icon = CGRect(x: 40, y: 40, width: 300, height: 300)
        let placed = try #require(place(icon: icon))
        #expect(placed.anchor == .topTrailing)
        #expect(!placed.frame.intersects(icon))
    }

    @Test("A frame with no corner free lets the card lie on its empty margin, never on the ink")
    func liesOnTheEmptyArtboard() throws {
        // A frame fitted to the view reaches past every corner the card could
        // take, but what is drawn in it does not: the blank artboard is no loss.
        let icon = CGRect(x: 120, y: 10, width: 880, height: 880)
        let ink = [CGRect(x: 420, y: 300, width: 300, height: 300)]
        let placed = try #require(place(icon: icon, ink: ink))
        #expect(placed.sides == IconPreviews.interfaceSides)
        #expect(placed.anchor == .topLeading)
        #expect(!placed.frame.intersects(ink[0]))
    }

    @Test("Where the whole card cannot fit it drops its biggest sizes, not the small ones")
    func dropsTheBiggestFirst() throws {
        // A gutter of 200 beside a drawing that fills its frame: the 16 is the
        // size that matters most, because it is the one a hairline dies at.
        let icon = CGRect(x: 212, y: 0, width: 900, height: 900)
        let placed = try #require(place(icon: icon, ink: [icon]))
        #expect(placed.sides == [16, 24, 32, 48])
        #expect(!placed.frame.intersects(icon))
    }

    @Test("With nowhere left that does not cover the drawing, the card goes")
    func goesRatherThanCovers() {
        let everywhere = CGRect(origin: .zero, size: room)
        #expect(place(icon: everywhere, ink: [everywhere]) == nil)
    }

    @Test("It is never parked on other chrome")
    func keepsOffTheChrome() {
        // The top two corners are taken by the icon, and a tool bar as wide as
        // the view takes the bottom two.
        let icon = CGRect(x: 0, y: 0, width: 1200, height: 300)
        let bar = CGRect(x: 0, y: 700, width: 1200, height: 200)
        #expect(place(icon: icon, ink: [icon], chrome: [bar]) == nil)
    }

    // MARK: - What the card keeps clear of

    @Test("The drawing is what is in the frame and can be seen, in canvas space")
    func inkIsVisibleChildren() throws {
        var document = PhotonzDocument(canvasSize: CGSize(width: 200, height: 200))
        let frame = document.addFrame(origin: CGPoint(x: 50, y: 50),
                                      size: CGSize(width: 24, height: 24))
        #expect(document.iconPreviewInk(id: frame.id).isEmpty)
        func box(_ rect: CGRect) -> Layer {
            Layer(name: "Box", content: .annotation(AnnotationContent(shape: .rectangle)),
                  frame: rect)
        }
        let shown = box(CGRect(x: 2, y: 3, width: 10, height: 10))
        var hidden = box(CGRect(x: 0, y: 0, width: 20, height: 20))
        hidden.isVisible = false
        let spilling = box(CGRect(x: 20, y: 20, width: 40, height: 40))
        document.updateLayer(id: frame.id) { layer in
            guard var group = layer.group else { return }
            group.children = [shown, hidden, spilling]
            layer.content = .group(group)
        }
        // A frame clips, so what spills past its edge is not on screen to cover.
        #expect(document.iconPreviewInk(id: frame.id)
            == [CGRect(x: 52, y: 53, width: 10, height: 10),
                CGRect(x: 70, y: 70, width: 4, height: 4)])
        #expect(document.iconPreviewInk(id: UUID()).isEmpty)
    }

    // MARK: - Finding the frame in a document

    @Test("The frame a drawing is inside is the one previewed")
    func previewedFrameInDocument() {
        var document = PhotonzDocument(canvasSize: CGSize(width: 1600, height: 1100))
        let icon = document.addFrame(origin: CGPoint(x: 100, y: 100),
                                     size: CGSize(width: 512, height: 512))
        let screen = document.addFrame(origin: CGPoint(x: 800, y: 100),
                                       size: CGSize(width: 1440, height: 1024))
        #expect(document.isIconFrame(id: icon.id))
        #expect(!document.isIconFrame(id: screen.id))

        // Drawing inside the icon frame keeps the strip up: what you have
        // selected while you draw is the shape, not the frame around it.
        let dot = Layer(name: "Dot", content: .annotation(AnnotationContent(shape: .ellipse)),
                        frame: CGRect(x: 300, y: 300, width: 40, height: 40))
        document.addLayerDrawnOnFrame(dot)
        let drawnID = document.layer(id: icon.id)?.children.first?.id
        #expect(drawnID != nil)
        #expect(document.iconFrameID(containing: drawnID ?? icon.id) == icon.id)
        // A layer on the screen next door is not in an icon frame at all.
        #expect(document.iconFrameID(containing: screen.id) == nil)
    }

    // MARK: - Which icon the strip keeps showing

    /// A document with one icon frame, one shape drawn in it, and a screen
    /// next door with a shape of its own.
    private func iconAndScreen() -> (document: PhotonzDocument, icon: UUID, second: UUID,
                                     drawn: UUID, screen: UUID, onScreen: UUID) {
        var document = PhotonzDocument(canvasSize: CGSize(width: 2400, height: 1400))
        let icon = document.addFrame(origin: CGPoint(x: 100, y: 100),
                                     size: CGSize(width: 24, height: 24))
        let second = document.addFrame(origin: CGPoint(x: 300, y: 100),
                                       size: CGSize(width: 48, height: 48))
        let screen = document.addFrame(origin: CGPoint(x: 800, y: 100),
                                       size: CGSize(width: 1440, height: 1024))
        let dot = Layer(name: "Dot", content: .annotation(AnnotationContent(shape: .ellipse)),
                        frame: CGRect(x: 104, y: 104, width: 8, height: 8))
        document.addLayerDrawnOnFrame(dot)
        let drawn = document.layer(id: icon.id)?.children.first?.id ?? icon.id
        let box = Layer(name: "Box", content: .annotation(AnnotationContent(shape: .rectangle)),
                        frame: CGRect(x: 900, y: 200, width: 120, height: 80))
        document.addLayerDrawnOnFrame(box)
        let onScreen = document.layer(id: screen.id)?.children.first?.id ?? screen.id
        return (document, icon.id, second.id, drawn, screen.id, onScreen)
    }

    @Test("What is picked says which icon, as it always did")
    func previewFrameFromSelection() {
        let d = iconAndScreen()
        #expect(d.document.iconPreviewFrameID(picked: d.drawn, pointerIn: nil,
                                              remembered: nil) == d.icon)
        #expect(d.document.iconPreviewFrameID(picked: d.icon, pointerIn: nil,
                                              remembered: nil) == d.icon)
        // What is picked answers even when the answer is "no icon": picking
        // something on a screen and sweeping the pointer over an icon does not
        // make the strip speak for the icon.
        #expect(d.document.iconPreviewFrameID(picked: d.onScreen, pointerIn: d.icon,
                                              remembered: d.icon) == nil)
    }

    @Test("With nothing picked the pointer says which icon")
    func previewFrameFromPointer() {
        let d = iconAndScreen()
        #expect(d.document.iconPreviewFrameID(picked: nil, pointerIn: d.second,
                                              remembered: d.icon) == d.second)
    }

    @Test("With nothing picked and the pointer over neither, the strip stays on the last icon")
    func previewFrameRemembered() {
        // THE POINT OF THE ROW. Clicking bare canvas or pressing Escape is how
        // you stand back and look at what you have drawn, and it is exactly
        // the moment the previews are worth most, so neither may take them
        // away: nothing is picked, and the pointer is out on bare canvas.
        let d = iconAndScreen()
        #expect(d.document.iconPreviewFrameID(picked: nil, pointerIn: nil,
                                              remembered: d.icon) == d.icon)
    }

    @Test("An icon it can no longer show is forgotten rather than kept")
    func previewFrameForgetsWhatIsGone() {
        var d = iconAndScreen()
        // A screen was never an icon, whatever was remembered.
        #expect(d.document.iconPreviewFrameID(picked: nil, pointerIn: nil,
                                              remembered: d.screen) == nil)
        // ...and a frame that has been deleted is not one either, which is the
        // case no change of selection or pointer would ever announce.
        _ = d.document.removeLayer(id: d.icon)
        #expect(d.document.iconPreviewFrameID(picked: nil, pointerIn: nil,
                                              remembered: d.icon) == nil)
    }

    @Test("A document with nothing to preview still previews nothing")
    func previewFrameOnBareCanvas() {
        let document = PhotonzDocument(canvasSize: CGSize(width: 1600, height: 1100))
        #expect(document.iconPreviewFrameID(picked: nil, pointerIn: nil, remembered: nil) == nil)
        #expect(document.iconPreviewFrameID(picked: UUID(), pointerIn: UUID(),
                                            remembered: UUID()) == nil)
    }

    // MARK: - The flag it ships behind

    @Test("The previews are a Next flag, on by default, written up for a person")
    func theFlag() {
        let next = FeatureCatalog.defaultSettings(for: .next)
        let flag = next.flags.first { $0.name == FeatureCatalog.iconPreviewsFlag }
        #expect(flag != nil, "the Experiments window builds its list from this catalogue")
        #expect(flag?.isEnabled == true)
        #expect(flag?.title == "See an icon at the size it will be used")
        // Says what it does and what off means, inside every switch's budget.
        #expect(flag?.description.contains("Off means") == true)
        #expect(CopyBudget.words(in: flag?.description ?? "") <= CopyBudget.flagDescriptionWords)
        // Current never grows it: the whole feature is Next's.
        #expect(FeatureCatalog.defaultSettings(for: .current).flags
            .contains { $0.name == FeatureCatalog.iconPreviewsFlag } == false)
    }
}
