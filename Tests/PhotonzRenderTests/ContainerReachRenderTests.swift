import CoreGraphics
import Foundation
import Testing
import PhotonzCore
@testable import PhotonzRender

/// Pulling Corner Radius on a group rounds what is INSIDE it, in pixels.
///
/// The report this comes from is about a pull that changed nothing: pick a
/// group with room around its contents, pull the row, and the only thing that
/// moved was the dashed selection marquee, which is gone the moment you click
/// away. A group paints nothing of its own, so masking its corners cut empty
/// air. The user settled it on 2026-09-13: the row rounds what is inside the
/// group (`PhotonzCore/ContainerRounding.swift`).
///
/// A walk photographs the window and needs the screen unlocked to do it. This
/// renders the canvas itself, so it can say what the picture does in the one
/// place a person would look — the button's own corner — whatever the screen is
/// doing.
@Suite("Rounding a group rounds what is inside it")
struct ContainerReachRenderTests {

    private func pixel(_ image: CGImage, x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = CGContext(data: &data, width: image.width, height: image.height,
                                bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let offset = (y * image.width + x) * 4
        return (data[offset], data[offset + 1], data[offset + 2], data[offset + 3])
    }

    private func isBlue(_ p: (r: UInt8, g: UInt8, b: UInt8, a: UInt8)) -> Bool {
        p.b > 180 && p.r < 90
    }

    private let canvas = CGSize(width: 200, height: 200)

    /// A blue button in a group with 20 points of room round it, which is the
    /// case the report came from: the group's own corners are empty air on
    /// every side, so a mask cut there takes nothing away.
    private func buttonInAPaddedGroup() -> Layer {
        var box = AnnotationContent(shape: .rectangle, strokeWidth: 0,
                                    start: .zero, end: CGPoint(x: 100, y: 60))
        box.fillColorHex = "#2F6FED"
        let button = Layer(name: "Button", content: .annotation(box),
                           frame: CGRect(x: 20, y: 20, width: 100, height: 60))
        var content = GroupContent(children: [button])
        content.layout = .free(padding: GroupPadding(20))
        return Layer(name: "Save button", content: .group(content),
                     frame: CGRect(x: 40, y: 40, width: 140, height: 100))
    }

    private func document() -> PhotonzDocument {
        PhotonzDocument(canvasSize: canvas, layers: [buttonInAPaddedGroup()])
    }

    /// The button's own top-left corner, three points in from it, which is the
    /// first bit of blue a 24pt curve takes away. The button starts at (60, 60)
    /// on the canvas: the group at (40, 40) plus its 20 points of room.
    private let insideTheCorner = (x: 63, y: 63)

    @Test func theButtonInsideTheGroupLosesItsCorner() {
        var doc = document()
        let groupID = doc.layers[0].id

        let before = DocumentRenderer().render(doc, store: ImageStore())!
        #expect(isBlue(pixel(before, x: insideTheCorner.x, y: insideTheCorner.y)))

        // Exactly what the panel does: read the row, pull it, write what it
        // reaches.
        let row = doc.cornerRadiusSelection(layerIDs: [groupID], readingWhatShows: true)
        #expect(row.reachesContents)
        doc.setCornerRadii(layerIDs: row.layerIDs, to: CornerRadii(24), onlyWhatShows: true)

        let after = DocumentRenderer().render(doc, store: ImageStore())!
        #expect(!isBlue(pixel(after, x: insideTheCorner.x, y: insideTheCorner.y)))
        // ...and the middle of the button is untouched, so this is a corner
        // being rounded rather than the button disappearing.
        #expect(isBlue(pixel(after, x: 110, y: 90)))
    }

    @Test func theOldPullChangedNothingAtAll() {
        // What the report saw. Masking the GROUP at 24 cuts the group's own
        // corners, which are empty air, so every pixel of the button is
        // exactly where it was.
        var doc = document()
        let groupID = doc.layers[0].id

        let before = DocumentRenderer().render(doc, store: ImageStore())!
        doc.setCornerRadii(layerIDs: [groupID], to: CornerRadii(24))
        let after = DocumentRenderer().render(doc, store: ImageStore())!

        #expect(isBlue(pixel(before, x: insideTheCorner.x, y: insideTheCorner.y)))
        #expect(isBlue(pixel(after, x: insideTheCorner.x, y: insideTheCorner.y)))
    }

    @Test func pullingItBackDownSquaresTheButtonAgain() {
        var doc = document()
        let groupID = doc.layers[0].id
        var row = doc.cornerRadiusSelection(layerIDs: [groupID], readingWhatShows: true)
        doc.setCornerRadii(layerIDs: row.layerIDs, to: CornerRadii(24), onlyWhatShows: true)

        row = doc.cornerRadiusSelection(layerIDs: [groupID], readingWhatShows: true)
        #expect(row.reading.value == 24)
        doc.setCornerRadii(layerIDs: row.layerIDs, to: .none, onlyWhatShows: true)

        let squared = DocumentRenderer().render(doc, store: ImageStore())!
        #expect(isBlue(pixel(squared, x: insideTheCorner.x, y: insideTheCorner.y)))
    }
}
