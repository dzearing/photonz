import CoreGraphics
import Foundation
import Testing
import PhotonzCore
@testable import PhotonzRender

/// A filled oval with a border round it, drawn at every magnification.
///
/// The canvas draws the picture twice: one document-sized composite stretched
/// over the zoom, and — past 1:1 in screen pixels — a sharp tile drawn at the
/// zoom's own resolution. Export takes a third path, the whole document drawn
/// at the export's scale. All three go through the same renderer, so all three
/// have to agree about what the document says.
///
/// They did not. A red circle inside a frame came out as a red RING with
/// nothing inside it on the canvas at 75%, and as a solid red disc in the
/// picture Export wrote and in the layers panel thumbnail beside it, so what
/// you were looking at while you worked was not what you were going to get
/// (reported 2026-09-14). The fill was being rubbed out by the border's own
/// ring: an inside border shares the pixels on the shape's edge with the paint
/// underneath (`laid`), which needs the shape's silhouette to work out who owns
/// what, and that silhouette came back BLANK at about half of all sizes. A
/// blank silhouette says the shape covers nothing, so the ring took every pixel
/// and the fill was left with none.
@Suite("A filled oval keeps its fill at every size")
struct FilledOvalRenderTests {

    // MARK: - The scene

    /// The reported scene: a 512 frame with a 360 circle in it, filled red,
    /// with a 4 point red border on the inside of its edge — exactly what the
    /// Ellipse tool draws (`AnnotationStyles.content(for:)` gives the shape no
    /// stroke of its own and `arrivingStyle(forShape:)` puts its edge in the
    /// Effects list).
    private func document(ovalSide: CGFloat = 360, borderWidth: CGFloat = 4) -> PhotonzDocument {
        var document = PhotonzDocument(canvasSize: CGSize(width: 1600, height: 1100))
        let frame = document.addFrame(origin: CGPoint(x: 100, y: 100),
                                      size: CGSize(width: 512, height: 512))
        var oval = AnnotationContent(shape: .ellipse, strokeWidth: 0, colorHex: fillHex,
                                     start: .zero, end: CGPoint(x: ovalSide, y: ovalSide),
                                     fillColorHex: fillHex)
        oval.strokePosition = .inside
        var layer = Layer(name: "Ellipse", content: .annotation(oval),
                          frame: CGRect(x: 76, y: 76, width: ovalSide, height: ovalSide))
        let border = BorderEffect(width: borderWidth, colorHex: fillHex,
                                  position: .inside, follows: .box)
        layer.style.effects.append(.border(border))
        document.updateLayer(id: frame.id) { $0.children.append(layer) }
        return document
    }

    private let fillHex = "#FF3B30"
    private var fillRGB: (Int, Int, Int) { (255, 59, 48) }

    /// The oval's own box on the canvas, in document points.
    private let ovalBox = CGRect(x: 176, y: 176, width: 360, height: 360)

    // MARK: - Reading pixels

    private func bytes(_ image: CGImage) -> [UInt8] {
        var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = CGContext(data: &data, width: image.width, height: image.height,
                                bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return data
    }

    private func pixel(_ image: CGImage, _ data: [UInt8], x: Int, y: Int) -> (Int, Int, Int) {
        let offset = (y * image.width + x) * 4
        return (Int(data[offset]), Int(data[offset + 1]), Int(data[offset + 2]))
    }

    /// How much of the middle of the picture is the fill's colour: the centre
    /// and eight points a quarter of the way out from it, so a ring with a hole
    /// in it cannot pass by having one lucky pixel.
    private func fillCoverage(_ image: CGImage) -> Int {
        let data = bytes(image)
        let cx = image.width / 2, cy = image.height / 2
        let reach = max(1, min(image.width, image.height) / 8)
        var found = 0
        var offsets: [(Int, Int)] = []
        for dx in [-reach, 0, reach] {
            for dy in [-reach, 0, reach] { offsets.append((dx, dy)) }
        }
        for (dx, dy) in offsets {
            let read = pixel(image, data, x: cx + dx, y: cy + dy)
            if abs(read.0 - fillRGB.0) <= 8, abs(read.1 - fillRGB.1) <= 8,
               abs(read.2 - fillRGB.2) <= 8 { found += 1 }
        }
        return found
    }

    /// Every scale worth asking about: the ones the canvas uses at ordinary
    /// zooms (a 2x screen doubles them), the ones the icon previews strip asks
    /// for, and a couple of export scales. The fractional ones matter most: the
    /// size in whole pixels rounds UP at about half of them, which is exactly
    /// when the silhouette used to come back blank.
    private let scales: [CGFloat] = [
        16.0 / 512, 24.0 / 512, 32.0 / 512, 48.0 / 512, 64.0 / 512, 128.0 / 512,
        0.2, 0.25, 0.3, 0.35, 0.4, 0.43, 0.45, 0.5, 0.6, 0.66, 0.7, 0.75,
        0.8, 0.9, 1.5, 2, 2.5, 3
    ]

    // MARK: - The tests

    @Test("Exported at any scale, the oval is filled")
    func exportsFilled() {
        let renderer = DocumentRenderer()
        let store = ImageStore()
        let document = document()
        for scale in scales {
            let image = renderer.render(document, store: store, scale: scale)
            #expect(image != nil, "no picture at \(scale)")
            guard let image else { continue }
            #expect(fillCoverage(cropToOval(image, scale: scale)) == 9,
                    "the oval came out hollow at scale \(scale)")
        }
    }

    @Test("The sharp tile the canvas draws is filled too")
    func tilesFilled() {
        let renderer = DocumentRenderer()
        let store = ImageStore()
        let document = document()
        for scale in scales {
            let tile = renderer.renderTile(document, store: store, region: ovalBox, scale: scale)
            #expect(tile != nil, "no tile at \(scale)")
            guard let tile else { continue }
            #expect(fillCoverage(tile.image) == 9,
                    "the canvas drew the oval hollow at scale \(scale)")
        }
    }

    @Test("An icon preview of the oval is filled at every size")
    func previewsFilled() {
        let renderer = DocumentRenderer()
        let store = ImageStore()
        let document = document()
        let id = document.frames.first!.id
        for side in IconPreviews.interfaceSides {
            let preview = renderer.iconPreview(for: id, in: document, store: store, side: side)
            #expect(preview != nil, "no preview at \(side)")
            guard let preview else { continue }
            #expect(fillCoverage(preview) == 9,
                    "the \(Int(side)) preview drew the oval hollow")
        }
    }

    /// The acceptance the reported bug was really about: the canvas and the
    /// exported picture are two drawings of one document, so a difference
    /// between them is the app lying about what you are making.
    @Test("The canvas tile and the exported picture say the same thing")
    func tileAndExportAgree() {
        let renderer = DocumentRenderer()
        let store = ImageStore()
        let document = document()
        for scale in scales {
            guard let tile = renderer.renderTile(document, store: store,
                                                 region: ovalBox, scale: scale) else { continue }
            guard let exported = renderer.render(document, store: store, scale: scale) else { continue }
            #expect(fillCoverage(tile.image) == fillCoverage(cropToOval(exported, scale: scale)),
                    "canvas and export disagree about the oval at scale \(scale)")
        }
    }

    /// The other half of the same arithmetic: a border thick enough to swallow
    /// the shape leaves a solid disc, never a disc with a hole punched in the
    /// middle of it.
    @Test("A border too thick to leave a hole fills the oval solid")
    func fatBorderFillsSolid() {
        let renderer = DocumentRenderer()
        let store = ImageStore()
        // 200 points of border on a 360 point circle: the inside edge of the
        // ring would be past the centre, so there is no hole left to draw.
        let document = document(borderWidth: 200)
        for scale in [CGFloat(0.43), 0.5, 1, 1.5] {
            guard let image = renderer.render(document, store: store, scale: scale) else {
                Issue.record("no picture at \(scale)")
                continue
            }
            #expect(fillCoverage(cropToOval(image, scale: scale)) == 9,
                    "a fat border left a hole at scale \(scale)")
        }
    }

    // MARK: -

    /// The oval's own square out of a whole-document picture, so the pixels
    /// read are the middle of the SHAPE rather than the middle of the canvas.
    private func cropToOval(_ image: CGImage, scale: CGFloat) -> CGImage {
        let box = ovalBox.magnified(by: scale).integral
        let clamped = box.intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard clamped.width >= 3, clamped.height >= 3,
              let cropped = image.cropping(to: clamped) else { return image }
        return cropped
    }
}
