import CoreGraphics
import Foundation
import ImageIO
import Testing
import PhotonzCore
import UniformTypeIdentifiers
@testable import PhotonzRender

/// The committed demo document (`Scripts/playtest/fixtures/path-demo.photonz`)
/// still opens and still draws paths.
///
/// It is the only picture of a path anybody can look at until the Pen exists,
/// and the `path-demo` walk opens it in the real app, so a change that broke
/// it would take the audit's evidence with it.
///
/// To rebuild the fixture after changing `PathDemoDocument`:
/// `PATH_FIXTURE_OUT=$PWD/Scripts/playtest/fixtures/path-demo.photonz Scripts/test.sh --filter PathDemoFixture`
@Suite("The demo path document")
struct PathDemoFixtureTests {

    private var fixture: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // PhotonzRenderTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("Scripts/playtest/fixtures/path-demo.photonz")
    }

    private func pixel(_ image: CGImage, x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        let width = image.width, height = image.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        let context = CGContext(data: &data, width: width, height: height,
                                bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let offset = (y * width + x) * 4
        return (data[offset], data[offset + 1], data[offset + 2], data[offset + 3])
    }

    @Test func rebuildsTheFixtureWhenAskedTo() throws {
        guard let out = ProcessInfo.processInfo.environment["PATH_FIXTURE_OUT"] else { return }
        let url = URL(fileURLWithPath: out)
        try? FileManager.default.removeItem(at: url)
        try PackageIO.write(PathDemoDocument.make(), store: ImageStore(), to: url)
    }

    @Test func theCommittedFixtureOpensAndDrawsItsPaths() throws {
        let store = ImageStore()
        let document = try PackageIO.read(from: fixture, into: store)
        #expect(document.canvasSize == PathDemoDocument.canvas)
        let paths = document.layers.filter { $0.path != nil }
        #expect(paths.count == 4, "four paths: corners, curves, both, and an open one")
        #expect(paths.contains { $0.path?.isClosed == false }, "one of them is open")
        #expect(paths.contains { $0.path?.anchors.contains { $0.isHalfSmooth } == true },
                "and one of them turns a half-smooth anchor")

        let image = DocumentRenderer().render(document, store: store)!
        if let out = ProcessInfo.processInfo.environment["PATH_DEMO_PNG"] {
            let url = URL(fileURLWithPath: out)
            if let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) {
                CGImageDestinationAddImage(dest, image, nil)
                CGImageDestinationFinalize(dest)
            }
        }
        // The bowed square sits at x 440, y 90, 130 tall, and its top edge is
        // dead straight: every sample along it is orange.
        for x in stride(from: 450, through: 530, by: 10) {
            let p = pixel(image, x: x, y: 96)
            #expect(p.r > 180 && p.g > 100 && p.b < 110, "top edge broken at x = \(x): \(p)")
        }
        // ...and its right-hand side bows out past the 540 its anchors sit on.
        #expect(pixel(image, x: 560, y: 155).a > 200, "the curve bulges past the anchors")
    }
}
