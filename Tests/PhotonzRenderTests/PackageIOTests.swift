import CoreGraphics
import Foundation
import Testing
import PhotonzCore
@testable import PhotonzRender

@Suite("Package IO")
struct PackageIOTests {

    private func solidImage(width: Int, height: Int, r: UInt8, g: UInt8, b: UInt8) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height,
                                bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255,
                                     blue: CGFloat(b) / 255, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    private func tempPackageURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("photonz-tests-\(UUID().uuidString)")
            .appendingPathComponent("Test.photonz")
    }

    @Test func documentRoundTripsThroughPackage() throws {
        let store = ImageStore()
        let base = store.register(solidImage(width: 120, height: 80, r: 255, g: 0, b: 0))
        var doc = PhotonzDocument.withBaseImage(base)
        doc.addLayer(Layer(name: "Note", content: .text(TextContent(string: "hello")),
                           frame: CGRect(x: 10, y: 10, width: 100, height: 24),
                           style: LayerStyle(opacity: 0.9, blurRadius: 2, shadow: ShadowStyle())))

        let url = tempPackageURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try PackageIO.write(doc, store: store, to: url)

        // The package is a directory holding document.json + images/<ref>.heic.
        #expect(FileManager.default.fileExists(atPath: url.appendingPathComponent("document.json").path))
        #expect(FileManager.default.fileExists(
            atPath: url.appendingPathComponent("images/\(base.id.uuidString).heic").path))

        let freshStore = ImageStore()
        let loaded = try PackageIO.read(from: url, into: freshStore)
        #expect(loaded == doc)
        // The bitmap is registered under the document's original ref.
        let image = freshStore.image(for: base)
        #expect(image?.width == 120)
        #expect(image?.height == 80)
    }

    @Test func saveOverAnExistingPackageReplacesIt() throws {
        let store = ImageStore()
        let base = store.register(solidImage(width: 40, height: 40, r: 0, g: 255, b: 0))
        var doc = PhotonzDocument.withBaseImage(base)

        let url = tempPackageURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try PackageIO.write(doc, store: store, to: url)

        doc.addLayer(Layer(name: "Late", content: .text(TextContent(string: "x")),
                           frame: CGRect(x: 0, y: 0, width: 20, height: 10)))
        try PackageIO.write(doc, store: store, to: url)

        let loaded = try PackageIO.read(from: url, into: ImageStore())
        #expect(loaded == doc)
        #expect(loaded.layers.count == 2)
    }

    @Test func readOfMissingPackageThrows() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("does-not-exist-\(UUID().uuidString).photonz")
        #expect(throws: (any Error).self) {
            try PackageIO.read(from: url, into: ImageStore())
        }
    }
}
