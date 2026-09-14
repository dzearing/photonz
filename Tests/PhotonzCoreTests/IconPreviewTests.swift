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

    @Test("A frame is never shown BIGGER than it is drawn")
    func neverUpscales() {
        // Blowing a 24 point frame up to 64 is not a size it will really be
        // used at, and the softness it would show is the preview's own, not
        // the icon's.
        #expect(IconPreviews.sides(forFrameSide: 24) == [16, 24])
        #expect(IconPreviews.sides(forFrameSide: 32) == [16, 24, 32])
        #expect(IconPreviews.sides(forFrameSide: 64) == [16, 24, 32, 48, 64])
    }

    @Test("The smallest frame still shows itself at true size")
    func smallestFrame() {
        // A 16 point frame drawn at 3200% is never seen at 16 anywhere else in
        // the app, so the one preview it gets is the whole point of the strip.
        #expect(IconPreviews.sides(forFrameSide: 16) == [16])
        // A size nobody offered still gets its own true size, with the
        // interface sizes under it.
        #expect(IconPreviews.sides(forFrameSide: 20) == [16, 20])
        #expect(IconPreviews.sides(forFrameSide: 10) == [10])
        // Each size appears once, however it was arrived at.
        #expect(Set(IconPreviews.sides(forFrameSide: 48)).count
            == IconPreviews.sides(forFrameSide: 48).count)
    }

    @Test("A frame too big or too odd to be an icon is shown at nothing")
    func nonIconFrames() {
        #expect(IconPreviews.sides(forFrameSide: 1000).isEmpty)
        #expect(IconPreviews.sides(forFrameSide: 0).isEmpty)
    }

    // MARK: - The chip each preview sits on

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

    // MARK: - The flag it ships behind

    @Test("The previews are a Next flag, on by default, written up for a person")
    func theFlag() {
        let next = FeatureCatalog.defaultSettings(for: .next)
        let flag = next.flags.first { $0.name == FeatureCatalog.iconPreviewsFlag }
        #expect(flag != nil, "the Experiments window builds its list from this catalogue")
        #expect(flag?.isEnabled == true)
        #expect(flag?.title == "See an icon at the size it will be used")
        // Long enough to say what it does and what off means, like every other
        // flag's write-up.
        #expect((flag?.description.count ?? 0) > 200)
        // Current never grows it: the whole feature is Next's.
        #expect(FeatureCatalog.defaultSettings(for: .current).flags
            .contains { $0.name == FeatureCatalog.iconPreviewsFlag } == false)
    }
}
