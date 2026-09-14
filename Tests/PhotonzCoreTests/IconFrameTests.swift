import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// A frame can be the size of an ICON (`next-icon-frames`).
///
/// Before this the smallest thing New Frame offered was a 1000 point square, so
/// somebody sitting down to draw a 24 pixel glyph had nowhere to draw it. Two
/// halves: the sizes themselves, kept in a group of their own so the list does
/// not turn into a wall of numbers, and the camera, because a 16 pixel canvas
/// dropped at 100% is a speck you cannot draw in.
struct IconFrameTests {

    // MARK: - The sizes

    @Test("The icon sizes are there, square, and in a group of their own")
    func iconSizes() {
        #expect(FramePreset.icons.map { Int($0.size.width) } == [16, 24, 32, 48, 64, 512])
        #expect(FramePreset.icons.allSatisfy { $0.size.width == $0.size.height })
        #expect(FramePreset.icons.allSatisfy { $0.group == .icons })
        #expect(FramePreset.screens.allSatisfy { $0.group == .screens })
        // Screens first, so nothing that walks the whole list reorders itself.
        #expect(FramePreset.all.prefix(FramePreset.screens.count).map(\.id)
            == FramePreset.screens.map(\.id))
    }

    @Test("A surface with the flag off sees exactly the list it always saw")
    func iconsAreOptional() {
        #expect(FramePreset.all(includingIcons: false).map(\.id) == FramePreset.screens.map(\.id))
        #expect(FramePreset.all(includingIcons: true).map(\.id) == FramePreset.all.map(\.id))
        // The size the dialog opens on is still the phone, wherever the icons
        // sit in the list.
        #expect(FramePreset.default.title == "Phone")
    }

    @Test("An icon size is recognised, and a menu names it by its size")
    func matchingAnIconSize() {
        let icon = FramePreset.matching(CGSize(width: 24, height: 24))
        #expect(icon?.group == .icons)
        // A screen is known by its name, an icon by how big it is: "Icon 24"
        // beside "24 × 24" would be the same sentence twice.
        #expect(icon?.menuTitle == "24 × 24")
        #expect(FramePreset.matching(CGSize(width: 390, height: 844))?.menuTitle == "Phone")
        #expect(FramePreset.sizeText(CGSize(width: 1440, height: 1024)) == "1440 × 1024")
    }

    @Test("An icon frame is an ordinary frame in every other way")
    func iconFrameIsAnOrdinaryFrame() {
        var document = PhotonzDocument(canvasSize: CGSize(width: 1600, height: 1100))
        let made = document.addFrame(origin: CGPoint(x: 100, y: 100),
                                     size: CGSize(width: 24, height: 24))
        #expect(made.isFrame)
        #expect(made.frame.size == CGSize(width: 24, height: 24))
        #expect(document.frames.count == 1)
        // A shape drawn on it joins it, exactly as it would on a desktop screen.
        let dot = Layer(name: "Dot", content: .text(TextContent(string: "Dot")),
                        frame: CGRect(x: 106, y: 106, width: 12, height: 12))
        document.addLayerDrawnOnFrame(dot)
        #expect(document.layer(id: made.id)?.children.count == 1)
        #expect(document.layer(id: made.id)?.children.first?.frame.origin == CGPoint(x: 6, y: 6))
    }

    // MARK: - Arriving somewhere you can draw

    /// A 1600x1100 canvas in a 1000x800 view at 1:1.
    private func viewport(zoom: CGFloat = 1) -> Viewport {
        Viewport(documentSize: CGSize(width: 1600, height: 1100),
                 viewSize: CGSize(width: 1000, height: 800),
                 zoom: zoom, origin: .zero).clamped()
    }

    @Test("A 16 pixel frame opens big enough to draw in, on a whole multiple")
    func aSpeckIsZoomedUp() {
        let start = viewport()
        let frame = CGRect(x: 792, y: 542, width: 16, height: 16)
        let arrived = start.framing(frame, padding: 48, minimumSide: 240)
        // Room is 904 x 704, so 44x would fit, but the camera stops at 32x.
        #expect(arrived.zoom == Viewport.maxZoom)
        #expect(16 * arrived.zoom >= 240)
        // ...and it is in the middle of the view, not somewhere off the edge.
        let box = CGRect(origin: arrived.viewPoint(fromDocument: frame.origin),
                         size: CGSize(width: frame.width * arrived.zoom,
                                      height: frame.height * arrived.zoom))
        #expect(abs(box.midX - 500) < 1)
        #expect(abs(box.midY - 400) < 1)
    }

    @Test("A 64 pixel frame lands on a whole multiple rather than a fractional one")
    func zoomIsAWholeMultiple() {
        let arrived = viewport().framing(CGRect(x: 768, y: 518, width: 64, height: 64))
        // 704 / 64 = 11, exactly; anything fractional would shimmer the pixels.
        #expect(arrived.zoom == 11)
        #expect(arrived.zoom == arrived.zoom.rounded())
    }

    @Test("A screen-sized frame the camera can already see is left alone")
    func aFrameYouCanAlreadySeeDoesNotMoveTheCamera() {
        let start = viewport()
        let onScreen = CGRect(x: 100, y: 100, width: 390, height: 600)
        #expect(start.framing(onScreen) == start)
    }

    @Test("A frame off the edge is fetched without being magnified")
    func aBigFrameOffScreenIsRevealedNotZoomed() {
        let start = viewport()
        let away = CGRect(x: 1100, y: 100, width: 400, height: 600)
        let arrived = start.framing(away)
        #expect(arrived.zoom == start.zoom)
        #expect(arrived != start)
        #expect(arrived == start.revealing(away))
    }

    @Test("Already zoomed in past what the frame needs, the camera stays put")
    func zoomedInAlreadyIsNotPulledBack() {
        let start = viewport(zoom: 20)
        let icon = CGRect(x: 792, y: 542, width: 24, height: 24)
        let arrived = start.framing(icon)
        // 24 at 20x is 480 points across, which is plenty; only the reveal runs.
        #expect(arrived.zoom == 20)
    }

    @Test("A frame with no size at all leaves the camera exactly as it was")
    func nonsenseIsIgnored() {
        let start = viewport()
        #expect(start.framing(.null) == start)
        #expect(start.framing(CGRect(x: 10, y: 10, width: 0, height: 40)) == start)
    }
}
