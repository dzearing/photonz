import CoreGraphics
import Foundation
import ImageIO
import PhotonzCore
import PhotonzRender
import Testing

/// The older title set, toned down (task
/// `the-existing-title-pages-are-toned-down-to-calm`): measured on the real
/// renderer, each one's background moves at most half as much while it holds
/// as it did before.
///
/// The user, 2026-10-18: "The existing title pages are far too busy." The
/// number is the mean difference of two frames half a second apart while the
/// title holds, 0 to 255 per channel, with nothing of the title showing but its
/// background, over a dark recording. A name card is measured over the corner
/// it sits in, not the whole frame it barely covers. `before` is what each one
/// measured on 2026-10-18 before it was toned down.
@Suite("The older title set holds on a background that barely moves")
struct TitleMoreStylesCalmFramesTests {

    static let canvas = CGSize(width: 1280, height: 720)
    static let hold = (2000, 2500)

    /// Measured on the designs before this task, the same way.
    static let before: [BuiltInTitle: Double] = [
        .keynote: 8.284, .softGlass: 6.501, .kinetic: 3.097, .editorial: 3.376, .terminal: 6.014, .glass: 0.108,
        .lightLeak: 12.794, .gradientGlow: 3.917, .stacked: 10.312, .splitWipe: 0.193, .underline: 0, .pill: 0.358,
    ]

    static var fixtures: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Scripts/playtest/fixtures")
    }

    static func picture(_ name: String) throws -> CGImage {
        let url = fixtures.appendingPathComponent(name)
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil), "\(name)")
        return try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    }

    /// `preset` at the start of a ten second dark recording, with nothing of
    /// it showing but its background.
    static func background(_ preset: BuiltInTitle, store: ImageStore) throws -> PhotonzDocument {
        var doc = PhotonzDocument(canvasSize: canvas)
        var clip = Layer(name: "Recording",
                         content: .image(store.register(try picture("Dark artboard with glow 800x500.png"))),
                         frame: CGRect(origin: .zero, size: canvas))
        clip.time = LayerTime(inMS: 0, outMS: 10_000, sourceInMS: 0, sourceLengthMS: 10_000)
        doc.layers = [clip]
        doc.durationMS = 10_000
        let landed = doc.insertTitle(preset, atTimeMS: 0, motionBlur: true)
        let id = try #require(landed, "\(preset.name)").layerID
        let group = try #require(doc.layer(id: id))
        for piece in group.children where !["Background", "Shade"].contains(piece.name) {
            doc.updateLayer(id: piece.id) { $0.isVisible = false }
        }
        return doc
    }

    /// RGBA at 640 by 360; for a card, only the lower left corner it sits in.
    static func pixels(_ image: CGImage, card: Bool) -> [UInt8] {
        let width = 640, height = 360
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        bytes.withUnsafeMutableBytes { raw in
            guard let context = CGContext(data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        guard card else { return bytes }
        // Rows from the top: the bottom three tenths, the left half.
        var corner: [UInt8] = []
        for row in (height * 7 / 10)..<height {
            let start = row * width * 4
            corner += bytes[start..<(start + width / 2 * 4)]
        }
        return corner
    }

    static func difference(_ a: [UInt8], _ b: [UInt8]) -> Double {
        var total = 0
        var index = 0
        while index < a.count {
            total += abs(Int(a[index]) - Int(b[index])) + abs(Int(a[index + 1]) - Int(b[index + 1]))
                + abs(Int(a[index + 2]) - Int(b[index + 2]))
            index += 4
        }
        return Double(total) / Double(max(1, a.count / 4 * 3))
    }

    static func motion(_ preset: BuiltInTitle) throws -> Double {
        let store = ImageStore()
        let doc = try background(preset, store: store)
        let card = preset.kind == .nameCard
        let a = try #require(DocumentRenderer().render(doc.drawn(atTimeMS: hold.0), store: store))
        let b = try #require(DocumentRenderer().render(doc.drawn(atTimeMS: hold.1), store: store))
        return difference(pixels(a, card: card), pixels(b, card: card))
    }

    @Test("Each one's background moves at most half as much while it holds as it did before",
          arguments: BuiltInTitle.shelved.filter { !$0.isCalm })
    func backgroundBarelyMoves(_ preset: BuiltInTitle) throws {
        let now = try Self.motion(preset)
        let then = try #require(Self.before[preset], "\(preset.name) was never measured")
        print("[calm-bar] \(preset.rawValue): \(String(format: "%.3f", now)) (before \(then))")
        #expect(now <= then / 2 + 0.02, "\(preset.name) moves \(now), before \(then)")
    }
}
