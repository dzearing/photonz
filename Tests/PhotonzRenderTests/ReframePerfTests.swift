import CoreGraphics
import Foundation
import PhotonzCore
import PhotonzRender
import Testing

/// What a punch-in costs the composite path.
///
/// A MEASUREMENT first, with a loose gate under it: the renderer change this feature needed (a photo
/// enlarged past its own pixels gets the good resampler in an ordinary render,
/// not only on a magnified one) only ever fires while something is being blown
/// up, and this says what that costs on a document the size of a screen
/// recording.
@Suite("What a punch-in costs the composite", .serialized)
struct ReframePerfTests {

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

        // A renderer on a context of its own, each frame beside the 1080p
        // frame yardstick in the same round: a stopwatch against a flat 200ms
        // read 292ms on GitHub's VM (2026-10-28), where timings are only ever
        // reported, and it was the one budget there that did not ask.
        let renderer = MachineSpeed.timedRenderer()
        // Warm, so the measurement is the composite and not the first-run cost
        // of building a Core Image context.
        _ = renderer.render(document.drawn(atTimeMS: 4000), store: store)
        let moments = [3900, 4000, 4400, 5000]
        var round = 0
        let reading = MachineSpeed.measureInterleaved(yardstick: .frame, rounds: 32) {
            _ = renderer.render(document.drawn(atTimeMS: moments[round % moments.count]), store: store)
            round += 1
        }
        // Printed rather than only asserted, so the number lands in the log a
        // perf note is written from.
        print(String(format: "punched-in composite, typical of 32 frames: %.1fms", reading.rawMS))
        // Alone on the calibration machine, 3.2 to 3.4ms beside a frame ruler
        // reading 1.9 to 2.6 against its own 3.3 (2026-10-30), and 3.3 to 3.9
        // in the stopwatch run: twice the composite fails 1.5 times that. The
        // frame ruler, not the filter graph: beside the other stopwatch
        // suites' 12 megapixel exports the filter graph read 9 to 13ms against
        // its own 8 while the composite read what it reads alone.
        MachineSpeed.judgeScaled("a 12 megapixel frame punched in to 200%", reading,
                                 baselineMS: 3.4, tolerance: 1.5,
                                 sourceLocation: SourceLocation(fileID: #fileID, filePath: #filePath,
                                                                line: #line, column: #column))
    }
}
