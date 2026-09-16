import CoreGraphics
import Foundation
import PhotonzCore
@testable import PhotonzRender
import Testing

/// Separate into Layers on a capture of a WHOLE APP WINDOW, which is the case
/// the feature was worst at and the case people actually reach for.
///
/// The fixture is `Fixtures/app-window-2x.png`: this app's own editor window at
/// 2x, with a dark canvas carrying a white artboard and a red rectangle, a
/// floating toolbar across the bottom, and a panel down the right side holding
/// layer rows, checkboxes, colour swatches and dropdowns.
///
/// Every part of that is painted a different dark, and NONE of them covers half
/// the picture's outer border. The sweep used to insist on one page behind
/// everything, so on this capture it claimed nothing at all: forty runs of text
/// came out and not one button, and a person who had just watched a label lift
/// off a button was left looking at the button still baked into the picture.
/// This file is the guard on that never coming back.
///
/// Full design: `docs/design/separate-into-layers.md`.
@Suite("Separate into Layers on a whole app window")
struct AppWindowSeparateFixtureTests {

    /// The numbers the app itself reads a 2x screenshot with.
    private static let gap = Double(AlignmentScan.visibleGap * 2)
    private static let minElement: Double = 20

    private static let capture: CGImage? = {
        guard let url = Bundle.module.url(forResource: "Fixtures/app-window-2x",
                                          withExtension: "png"),
              let data = try? Data(contentsOf: url) else { return nil }
        return ImageCodec.decode(data)
    }()

    private static let separated: LayerSeparator.Result? = {
        guard let capture else { return nil }
        return LayerSeparator.separate(capture, luma: EdgeMapAnalyzer.analyzeFully(capture).luma,
                                       gap: gap, minElement: minElement)
    }()

    private func boxes() throws -> [LayerSeparator.Piece] {
        try #require(Self.separated).boxes
    }

    /// Whether anything that came out is that rectangle, give or take a pixel
    /// of antialiasing on each side.
    private func found(_ boxes: [LayerSeparator.Piece], _ rect: CGRect) -> Bool {
        boxes.contains { $0.rect.insetBy(dx: -2, dy: -2).contains(rect)
            && rect.insetBy(dx: -4, dy: -4).contains($0.rect) }
    }

    // MARK: - The thing the whole task was about

    @Test func aWholeWindowGivesUpItsBoxesAndNotJustItsWords() throws {
        let boxes = try boxes()
        // It used to be none. The exact number moves with the heuristic; that
        // it is a real handful is the claim.
        #expect(boxes.count >= 8)
        #expect(try #require(Self.separated).runs.count >= 30)
    }

    @Test func theControlsOnThePanelComeOut() throws {
        let boxes = try boxes()
        // The selected layer's row, the swatch on it, and two dropdowns further
        // down the panel: the things a person points at when they say "that
        // button".
        #expect(found(boxes, CGRect(x: 2019, y: 141, width: 496, height: 76)))
        #expect(found(boxes, CGRect(x: 2031, y: 149, width: 80, height: 60)))
        #expect(found(boxes, CGRect(x: 2231, y: 991, width: 161, height: 40)))
        #expect(found(boxes, CGRect(x: 2231, y: 1351, width: 161, height: 40)))
    }

    @Test func theShapeOnTheCanvasComesOutToo() throws {
        // The red rectangle sitting on the white artboard, which is a different
        // background again from the panel and the canvas around it.
        #expect(found(try boxes(), CGRect(x: 767, y: 886, width: 478, height: 366)))
    }

    @Test func aControlThatIsOneFlatColourComesOutAsARealRectangle() throws {
        let shapes = try boxes().filter { if case .shape = $0.body { return true }; return false }
        #expect(!shapes.isEmpty)
    }

    // MARK: - And nothing that is not a box

    @Test func theWindowItselfIsNeverHandedBackAsALayer() throws {
        let capture = try #require(Self.capture)
        let area = Double(capture.width * capture.height)
        // The chrome, the canvas and the panel are what everything else is
        // sitting ON. Reading them as backgrounds is the fix; claiming one of
        // them as a piece would be a window-shaped hole in the picture.
        for box in try boxes() {
            #expect(Double(box.rect.width * box.rect.height) < 0.4 * area)
        }
    }

    @Test func noTwoPiecesClaimTheSamePixels() throws {
        let boxes = try boxes()
        for (i, a) in boxes.enumerated() {
            for b in boxes[(i + 1)...] {
                // Holding one is fine, that is what a row does to its label.
                // Overlapping it is not: the pixels would come out twice.
                #expect(!a.rect.intersects(b.rect) || a.rect.contains(b.rect)
                        || b.rect.contains(a.rect))
            }
        }
    }

    @Test func everySpaceAPieceCameFromIsFilledInExactlyOnce() throws {
        let result = try #require(Self.separated)
        for (i, a) in result.patched.enumerated() {
            for b in result.patched[(i + 1)...] { #expect(!a.intersects(b)) }
        }
    }
}
