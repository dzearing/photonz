import CoreGraphics
import Foundation
import Testing
@testable import PhotonzRender

/// What a file dragged over the canvas is allowed to become. The pointer a
/// drag shows is decided from here, so a file that can do nothing has to read
/// as refused rather than as an accepted copy that quietly does nothing.
@Suite("A file dragged over the canvas")
struct CanvasFileDropTests {

    private func write(_ name: String, _ contents: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("photonz-drop-\(UUID().uuidString)-\(name)")
        try contents.write(to: url)
        return url
    }

    private func picture(width: Int, height: Int) throws -> Data {
        let context = CGContext(data: nil, width: width, height: height,
                                bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(srgbRed: 0.2, green: 0.4, blue: 0.9, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try #require(ImageCodec.encode(context.makeImage()!, format: .png))
    }

    @Test func aPictureLandsAsALayerAtItsOwnSize() throws {
        let url = try write("shot.png", try picture(width: 320, height: 200))
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(CanvasFileDrop.of(url) == .picture(CGSize(width: 320, height: 200)))
    }

    @Test func aPackageOpensInAWindowRatherThanLanding() throws {
        // Nothing reads the contents at drag time: the extension is the whole
        // promise, and opening it is what answers for it.
        let url = try write("board.photonz", Data("not really a package".utf8))
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(CanvasFileDrop.of(url) == .package)
    }

    @Test func thePackageExtensionIsReadWithoutCaringAboutCase() throws {
        let url = try write("board.PhotonZ", Data("not really a package".utf8))
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(CanvasFileDrop.of(url) == .package)
    }

    @Test(arguments: ["notes.txt", "archive.zip", "sheet.csv"])
    func aFileThatIsNotAPictureIsRefused(name: String) throws {
        let url = try write(name, Data("plain words, no pixels".utf8))
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(CanvasFileDrop.of(url) == .unsupported)
    }

    @Test func aPictureNameOnSomethingThatIsNotOneIsStillRefused() throws {
        // The extension lies; the header does not. A .png full of text has no
        // size to land at, so the drag must say no.
        let url = try write("liar.png", Data("plain words, no pixels".utf8))
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(CanvasFileDrop.of(url) == .unsupported)
    }

    @Test func aFolderIsRefused() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("photonz-drop-folder-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(CanvasFileDrop.of(url) == .unsupported)
    }

    @Test func aFileThatIsNotThereIsRefused() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("photonz-drop-missing-\(UUID().uuidString).png")
        #expect(CanvasFileDrop.of(url) == .unsupported)
    }

    @Test func onlyTheRefusedCaseShowsTheNoEntryPointer() throws {
        let png = try write("shot.png", try picture(width: 40, height: 40))
        let package = try write("board.photonz", Data("x".utf8))
        let text = try write("notes.txt", Data("x".utf8))
        defer { for url in [png, package, text] { try? FileManager.default.removeItem(at: url) } }
        #expect(CanvasFileDrop.of(png).isAccepted)
        #expect(CanvasFileDrop.of(package).isAccepted)
        #expect(!CanvasFileDrop.of(text).isAccepted)
    }

    @Test func onlyAPictureCarriesASizeToDrawALandingBoxFrom() throws {
        let png = try write("shot.png", try picture(width: 64, height: 48))
        let package = try write("board.photonz", Data("x".utf8))
        let text = try write("notes.txt", Data("x".utf8))
        defer { for url in [png, package, text] { try? FileManager.default.removeItem(at: url) } }
        #expect(CanvasFileDrop.of(png).pictureSize == CGSize(width: 64, height: 48))
        #expect(CanvasFileDrop.of(package).pictureSize == nil)
        #expect(CanvasFileDrop.of(text).pictureSize == nil)
    }
}
