import CoreGraphics
import Foundation
import PhotonzCore
@testable import PhotonzRender
import Testing

/// The one test that can say the extracted shadow is RIGHT rather than
/// plausible: put the screenshot back together out of what the command produced
/// — the repaired page, every piece cut out of it, and the shadow read off the
/// cards — and compare that against the screenshot it came from, pixel by
/// pixel, through the app's own renderer.
///
/// Everything else about this feature is a number in a struct. This is the only
/// check that closes the loop, so it is also what pins the MEANING of the
/// numbers: that `radius` is a gaussian sigma in image pixels, and that a
/// positive `offset` height throws the shadow down the page.
///
/// Full design: `docs/design/separate-into-layers.md`.
@Suite("A separated card and its shadow put the picture back")
struct SeparatedShadowRoundTripTests {

    private static let capture: CGImage? = {
        guard let url = Bundle.module.url(forResource: "Fixtures/settings-pane-2x",
                                          withExtension: "png"),
              let data = try? Data(contentsOf: url) else { return nil }
        return ImageCodec.decode(data)
    }()

    /// Every piece the command produced, laid back over the repaired page the
    /// way the app lays them: boxes under the words that sat on them, each
    /// piece a child of whatever held it, shadows on the bodies.
    private func rebuild(_ result: LayerSeparator.Result, size: CGSize,
                         store: ImageStore) -> PhotonzDocument {
        let flat = result.pieces.map { piece -> PhotonzDocument.SeparatedPiece in
            let content: PhotonzDocument.SeparatedPiece.Content
            switch piece.body {
            case .picture(let image): content = .picture(store.register(image))
            case .shape(let shape):
                content = .shape(fill: shape.fill, radii: shape.radii,
                                 borderWidth: shape.borderWidth, borderColor: shape.borderColor)
            }
            return PhotonzDocument.SeparatedPiece(frame: piece.rect, content: content,
                                                  name: "Piece", shadow: piece.shadow)
        }
        func assemble(_ node: LayerNesting.Node) -> PhotonzDocument.SeparatedPiece {
            let piece = flat[node.index]
            guard !node.children.isEmpty else { return piece }
            return PhotonzDocument.SeparatedPiece(
                frame: piece.frame, content: piece.content, name: piece.name,
                bodyName: "Body", children: node.children.map(assemble), shadow: piece.shadow)
        }
        let page = store.register(result.background)
        var doc = PhotonzDocument(canvasSize: size, layers: [
            Layer(name: "Page", content: .image(page),
                  frame: CGRect(origin: .zero, size: size), isLocked: true)
        ])
        let id = doc.layers[0].id
        doc.separateIntoLayers(id: id, patched: page, pieces: result.nested.map(assemble))
        return doc
    }

    @Test func rebuildingTheCaptureFromItsPiecesPutsTheShadowsBack() throws {
        let capture = try #require(Self.capture)
        let analysis = EdgeMapAnalyzer.analyzeFully(capture)
        let result = try #require(LayerSeparator.separate(capture, luma: analysis.luma))
        let card = try #require(result.boxes.first { $0.rect.width > 1000 })
        let shadow = try #require(card.shadow)

        let store = ImageStore()
        let size = CGSize(width: capture.width, height: capture.height)
        let rebuilt = try #require(DocumentRenderer().render(rebuild(result, size: size,
                                                                    store: store),
                                                            store: store))
        let want = try #require(LayerSeparator.read(capture))
        let have = try #require(LayerSeparator.read(rebuilt))
        let w = capture.width

        func compare(_ include: (Int, Int) -> Bool) -> (worst: Int, at: (Int, Int), mean: Double) {
            var worst = 0, at = (0, 0), total = 0.0, count = 0
            for y in 0..<capture.height {
                for x in 0..<w where include(x, y) {
                    let i = (y * w + x) * 4
                    let d = max(abs(Int(want[i]) - Int(have[i])),
                                max(abs(Int(want[i + 1]) - Int(have[i + 1])),
                                    abs(Int(want[i + 2]) - Int(have[i + 2]))))
                    if d > worst { worst = d; at = (x, y) }
                    total += Double(d)
                    count += 1
                }
            }
            return (worst, at, count > 0 ? total / Double(count) : 0)
        }

        // The shadow on its own: everything the cards' shadows reached, and
        // none of the pieces themselves, so nothing but the shadow is being
        // judged. This is the number that says the reading is right.
        let cards = result.boxes.filter { $0.rect.width > 1000 }.map(\.rect)
        let band = compare { x, y in
            let p = CGPoint(x: Double(x) + 0.5, y: Double(y) + 0.5)
            return cards.contains { $0.insetBy(dx: -16, dy: -16).contains(p) && !$0.contains(p) }
        }
        // And the whole picture, which also carries every run of text that was
        // cut out and laid back — a wider claim, kept as the honest headline.
        let all = compare { _, _ in true }
        print("ROUND TRIP the capture rebuilt from its own pieces: in the cards' shadow "
            + "bands, worst channel difference \(band.worst)/255 at \(band.at), mean "
            + "\(String(format: "%.3f", band.mean))/255. Over the whole picture, worst "
            + "\(all.worst)/255 at \(all.at), mean \(String(format: "%.3f", all.mean))/255. "
            + "Shadow \(shadow.colorHex) at \(Int((shadow.opacity * 100).rounded()))%, blur "
            + "\(shadow.radius) px, offset (\(shadow.offset.width), \(shadow.offset.height))")

        // Two levels out of 255 at the very worst pixel, and three hundredths
        // of a level on average, which is the picture's own rounding plus the
        // corners, where the real shadow is cast by a rounded rectangle and the
        // reading was taken off the straight runs. A shadow read with the wrong
        // softness or thrown the wrong way misses by ten times this along the
        // edge it is wrong about: reading it in the wrong colour space, which
        // is the mistake this test caught, missed by eleven.
        #expect(band.worst <= 2)
        #expect(band.mean <= 0.05)
    }
}
