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

    // MARK: - What the dark chip draws

    @Test("A light chip is painted the frame's own flat surface, under the exported picture")
    func lightChipIsTheSurface() throws {
        // icon-draw-wt.html draws the glyph straight on a light chip. The
        // frame sat as a white square inside a grey chip; painting the chip in
        // the artboard's colour gives the mock's chip, while the picture on it
        // stays exactly what Export writes. Left out of the picture, a soft
        // edge blended on screen reads up to a fifth darker than in the file,
        // which would flatter the very hairlines the strip is there to catch.
        var document = PhotonzDocument(canvasSize: CGSize(width: 200, height: 200))
        let frame = document.addFrame(origin: CGPoint(x: 10, y: 10),
                                      size: CGSize(width: 24, height: 24))
        #expect(document.iconPreviewGroundHex(id: frame.id) == "#FFFFFF")
        let light = try #require(document.iconPreviewDocument(id: frame.id, onDarkGround: false))
        #expect(light == document.frameDocument(id: frame.id))
        #expect(document.iconPreviewDocument(id: UUID(), onDarkGround: false) == nil)
    }

    @Test("On the dark chip an icon frame is drawn without its own surface")
    func darkChipDropsTheSurface() throws {
        // The frame's white is the artboard, not the icon: left in, the dark
        // chip would be a white square with a dark rim, and the glyph would
        // never be seen against the dark at all.
        var document = PhotonzDocument(canvasSize: CGSize(width: 200, height: 200))
        let frame = document.addFrame(origin: CGPoint(x: 10, y: 10),
                                      size: CGSize(width: 24, height: 24))
        let dark = try #require(document.iconPreviewDocument(id: frame.id, onDarkGround: true))
        #expect(dark.layers.first?.group?.background == nil)
        #expect(document.iconPreviewDocument(id: UUID(), onDarkGround: true) == nil)
    }

    @Test("A surface the chip cannot paint stays in the picture")
    func gradientOrClearSurfaceStays() throws {
        var document = PhotonzDocument(canvasSize: CGSize(width: 200, height: 200))
        let clear = document.addFrame(origin: .zero, size: CGSize(width: 24, height: 24),
                                      backgroundHex: nil)
        #expect(document.iconPreviewGroundHex(id: clear.id) == nil)
        let shaded = document.addFrame(origin: CGPoint(x: 50, y: 0),
                                       size: CGSize(width: 24, height: 24))
        document.updateLayer(id: shaded.id) { frame in
            guard var group = frame.group else { return }
            group.background = Paint(hex: "#2050C0", kind: .linear)
            frame.content = .group(group)
        }
        // A gradient is not one colour a chip can be, so it sits on the plain
        // chip, still exactly as Export draws it.
        #expect(document.iconPreviewGroundHex(id: shaded.id) == nil)
        let light = try #require(document.iconPreviewDocument(id: shaded.id, onDarkGround: false))
        #expect(light == document.frameDocument(id: shaded.id))
    }

    // MARK: - The chip each preview sits on

    @Test("One chip is dark: the one before the biggest, as the mock puts 32 on dark under a 24")
    func oneDarkChip() {
        // icon-draw-wt.html step 11 draws 16, 24, 48 on light and 32 on dark,
        // so a glyph is checked on both grounds. The biggest stays light, where
        // the detail is read; the size beside it shows the dark ground.
        #expect(IconPreviews.darkSide(among: IconPreviews.sides(forFrameSide: 24)) == 32)
        #expect(IconPreviews.darkSide(among: IconPreviews.sides(forFrameSide: 16)) == 24)
        #expect(IconPreviews.darkSide(among: IconPreviews.sides(forFrameSide: 512)) == 48)
        #expect(IconPreviews.darkSide(among: [10, 16]) == 10)
        // A lone chip stays light: with one picture there is no second ground
        // to compare against, and the light one is the one people draw on.
        #expect(IconPreviews.darkSide(among: [16]) == nil)
        #expect(IconPreviews.darkSide(among: []) == nil)
    }

    @Test("Every preview sits on a chip with the same margin round it")
    func chipSides() {
        // The chip is the icon plus one even margin, so five chips of five
        // sizes read as one row of squares rather than five arbitrary boxes.
        #expect(IconPreviews.chipSide(for: 16) == 26)
        #expect(IconPreviews.chipSide(for: 64) == 74)
        #expect(IconPreviews.chipSide(for: 16) - 16 == IconPreviews.chipSide(for: 48) - 48)
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
