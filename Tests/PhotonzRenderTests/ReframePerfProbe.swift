import CoreGraphics
import Foundation
import PhotonzCore
import PhotonzRender
import Testing

/// What a punch-in costs the composite path.
///
/// Not a gate, a MEASUREMENT: the renderer change this feature needed (a photo
/// enlarged past its own pixels gets the good resampler in an ordinary render,
/// not only on a magnified one) only ever fires while something is being blown
/// up, and this says what that costs on a document the size of a screen
/// recording.
@Suite("What a punch-in costs the composite")
struct ReframePerfProbe {

    @Test("A 12 megapixel frame punched in to 200% still composites well inside a frame")
    func punchedInCompositeIsFast() throws {
        let pixels = CGSize(width: 4000, height: 3000)
        let store = ImageStore()
        let ref = ImageRef(id: UUID(), pixelSize: pixels)
        let context = CGContext(data: nil, width: 4000, height: 3000, bitsPerComponent: 8,
                                bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue)
        try #require(context != nil)
        context?.setFillColor(CGColor(red: 0.2, green: 0.3, blue: 0.5, alpha: 1))
        context?.fill(CGRect(origin: .zero, size: pixels))
        let image = try #require(context?.makeImage())
        store.register(image, as: ref)

        var layer = Layer(name: "clip", content: .image(ref),
                          frame: CGRect(x: 0, y: 0, width: 4000, height: 3000))
        layer.movie = MovieRef(id: UUID(), pixelSize: pixels, durationMS: 8000)
        layer.time = LayerTime(inMS: 0, outMS: 8000, sourceInMS: 0, sourceLengthMS: 8000)
        var document = PhotonzDocument(canvasSize: CGSize(width: 4000, height: 3000),
                                       layers: [layer])
        document.durationMS = 8000
        let landed = document.punchIn(layerID: layer.id,
                                      onRegion: CGRect(x: 1000, y: 750, width: 2000, height: 1500),
                                      atTimeMS: 4000)
        #expect(landed)

        let renderer = DocumentRenderer()
        // Warm, so the measurement is the composite and not the first-run cost
        // of building a Core Image context.
        _ = renderer.render(document.drawn(atTimeMS: 4000), store: store)
        var worst = 0.0
        for ms in [3900, 4000, 4400, 5000] {
            let shown = document.drawn(atTimeMS: ms)
            let began = Date()
            _ = renderer.render(shown, store: store)
            worst = max(worst, Date().timeIntervalSince(began) * 1000)
        }
        // Printed rather than only asserted, so the number lands in the log a
        // perf note is written from.
        print("punched-in composite, worst of four frames: \(Int(worst))ms")
        #expect(worst < 200)
    }
}
