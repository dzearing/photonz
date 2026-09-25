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

    /// A cut recording with its sound taken off, a b-roll clip in a group, a
    /// piece of music, a title and a caption: what an edited video is.
    private func editedVideo() -> (PhotonzDocument, MovieRef, MovieRef, SoundRef) {
        let talk = MovieRef(pixelSize: CGSize(width: 640, height: 360), durationMS: 8_000,
                            hasSound: true)
        let broll = MovieRef(pixelSize: CGSize(width: 640, height: 360), durationMS: 4_000)
        let music = SoundRef(durationMS: 14_000)
        var doc = PhotonzDocument.recording(talk, name: "talk")
        doc.rememberMedia(.recording(talk), named: "talk.mov")
        doc.rememberMedia(.sound(music), named: "music.wav")
        var brollClip = Layer(name: "b-roll", content: .image(broll.frameRef(atSourceMS: 0)),
                              frame: CGRect(x: 0, y: 0, width: 320, height: 180))
        brollClip.movie = broll
        brollClip.time = LayerTime(inMS: 2_000, outMS: 5_000, sourceInMS: 500,
                                   sourceLengthMS: broll.durationMS)
        doc.addLayer(Layer(name: "Group", content: .group(GroupContent(children: [brollClip])),
                           frame: CGRect(x: 0, y: 0, width: 320, height: 180)))
        var musicLayer = Layer(name: "music", content: .sound(music), frame: .zero)
        musicLayer.time = LayerTime(inMS: 0, outMS: 8_000, sourceInMS: 0,
                                    sourceLengthMS: music.durationMS)
        musicLayer.soundLevel = AudioLevel(gain: 0.4)
        doc.addLayer(musicLayer)
        var title = Layer(name: "Title", content: .text(TextContent(string: "Hello")),
                          frame: CGRect(x: 20, y: 20, width: 200, height: 40))
        title.time = LayerTime(inMS: 0, outMS: 3_000)
        doc.addLayer(title)
        return (doc, talk, broll, music)
    }

    @Test func aVideoRoundTripsWithoutAnyOfItsFramesInTheStore() throws {
        let (doc, talk, broll, music) = editedVideo()
        let url = tempPackageURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let table = [
            ProjectMediaFile(id: talk.id, kind: .recording, name: "talk.mov",
                             path: "/Users/me/Movies/talk.mov", relativePath: nil),
            ProjectMediaFile(id: broll.id, kind: .recording, name: "b-roll.mov",
                             path: "/Users/me/Movies/b-roll.mov", relativePath: nil),
            ProjectMediaFile(id: music.id, kind: .sound, name: "music.wav",
                             path: "/Users/me/Music/music.wav", relativePath: nil),
        ]
        // A clip's frame is fetched from its recording, never kept in the
        // store, so the write must not ask the store for it.
        try PackageIO.write(doc, store: ImageStore(), media: table, to: url)

        #expect(FileManager.default.fileExists(atPath: url.appendingPathComponent("media.json").path))
        let loaded = try PackageIO.read(from: url, into: ImageStore())
        #expect(loaded == doc)
        #expect(try PackageIO.readMedia(from: url) == table)
        // ...and no frame of any recording was written into the package.
        let images = (try? FileManager.default.contentsOfDirectory(
            atPath: url.appendingPathComponent("images").path)) ?? []
        #expect(images.isEmpty)
    }

    @Test func aPictureWritesNoMediaTable() throws {
        let store = ImageStore()
        let base = store.register(solidImage(width: 20, height: 20, r: 0, g: 0, b: 255))
        let url = tempPackageURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try PackageIO.write(PhotonzDocument.withBaseImage(base), store: store, to: url)
        #expect(!FileManager.default.fileExists(atPath: url.appendingPathComponent("media.json").path))
        #expect(try PackageIO.readMedia(from: url).isEmpty)
    }

    @Test func readOfMissingPackageThrows() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("does-not-exist-\(UUID().uuidString).photonz")
        #expect(throws: (any Error).self) {
            try PackageIO.read(from: url, into: ImageStore())
        }
    }
}
