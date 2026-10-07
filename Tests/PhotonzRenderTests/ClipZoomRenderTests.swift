import CoreGraphics
import Foundation
import PhotonzCore
import Testing
@testable import PhotonzRender

/// A zoom region reaches the pixels: the clip's box shows only the part of the
/// picture the zoom is on, filling the box edge to edge (`ClipZoom.swift`).
@Suite("A zoom region in the picture")
struct ClipZoomRenderTests {

    /// Four quarters: red top-left, green top-right, blue bottom-left, white
    /// bottom-right.
    private func quarters(width: Int, height: Int) -> CGImage {
        var data = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                let right = x >= width / 2
                let bottom = y >= height / 2
                switch (right, bottom) {
                case (false, false): data[i] = 255
                case (true, false): data[i + 1] = 255
                case (false, true): data[i + 2] = 255
                case (true, true): data[i] = 255; data[i + 1] = 255; data[i + 2] = 255
                }
                data[i + 3] = 255
            }
        }
        let context = CGContext(data: &data, width: width, height: height,
                                bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return context.makeImage()!
    }

    /// The colour at a point counted from the TOP-left.
    private func ink(_ image: CGImage, at point: CGPoint) -> (r: Int, g: Int, b: Int, a: Int) {
        let width = image.width, height = image.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        let context = CGContext(data: &data, width: width, height: height,
                                bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let index = (Int(point.y) * width + Int(point.x)) * 4
        return (Int(data[index]), Int(data[index + 1]), Int(data[index + 2]), Int(data[index + 3]))
    }

    private func document(store: ImageStore, picture: CGImage) -> (PhotonzDocument, UUID) {
        let canvas = CGSize(width: 200, height: 100)
        let ref = store.register(picture)
        var clip = Layer(name: "Clip", content: .image(ref), frame: CGRect(origin: .zero, size: canvas))
        clip.time = LayerTime(inMS: 0, outMS: 4000)
        var document = PhotonzDocument(canvasSize: canvas, layers: [clip])
        document.durationMS = 4000
        return (document, clip.id)
    }

    @Test func theWindowFillsTheBoxEdgeToEdge() throws {
        let store = ImageStore()
        var (document, id) = document(store: store, picture: quarters(width: 200, height: 100))
        // The top-right quarter.
        document.updateLayer(id: id) { $0.zoomWindow = CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5) }
        let image = try #require(DocumentRenderer().render(document, store: store, scale: 1))
        for point in [CGPoint(x: 1, y: 1), CGPoint(x: 100, y: 50), CGPoint(x: 198, y: 98),
                      CGPoint(x: 1, y: 98), CGPoint(x: 198, y: 1)] {
            let seen = ink(image, at: point)
            #expect(seen.g > 230 && seen.r < 25 && seen.b < 25 && seen.a > 250,
                    "at \(point) the picture read \(seen)")
        }
    }

    @Test func aFrameReadSmallerThanTheRecordingShowsTheSameSpot() throws {
        // A frame decoded at half size for a small window: the window is in
        // fractions of the picture, so it still lands on the same quarter.
        let store = ImageStore()
        var (document, id) = document(store: store, picture: quarters(width: 100, height: 50))
        document.updateLayer(id: id) { $0.zoomWindow = CGRect(x: 0, y: 0.5, width: 0.5, height: 0.5) }
        let image = try #require(DocumentRenderer().render(document, store: store, scale: 1))
        let seen = ink(image, at: CGPoint(x: 100, y: 50))
        #expect(seen.b > 230 && seen.r < 25 && seen.g < 25, "the middle read \(seen)")
    }

    @Test func aZoomDrawnThroughTheTimelineLandsOnItsSpot() throws {
        let store = ImageStore()
        var (document, id) = document(store: store, picture: quarters(width: 200, height: 100))
        // Easing in from 0 to 1s, held on the bottom-right quarter to 3s.
        document.updateLayer(id: id) {
            $0.zooms = [ClipZoom(startMS: 0, endMS: 3000, easeInMS: 1000, easeOutMS: 0,
                                 scale: 2, center: CGPoint(x: 0.75, y: 0.75))]
        }
        // The layer has no recording, so the zoom is not one this clip takes:
        // only a clip that plays a recording zooms.
        let unzoomed = try #require(DocumentRenderer().render(document.drawn(atTimeMS: 2000),
                                                              store: store, scale: 1))
        #expect(ink(unzoomed, at: CGPoint(x: 10, y: 10)).r > 230)
        // Every frame of the recording is the four quarters.
        let movie = MovieRef(pixelSize: CGSize(width: 200, height: 100), durationMS: 4000)
        let picture = quarters(width: 200, height: 100)
        for ms in stride(from: 0, through: 4000, by: MovieRef.frameStepMS) {
            store.register(picture, as: movie.frameRef(atSourceMS: ms))
        }
        document.updateLayer(id: id) { $0.movie = movie }
        let zoomed = try #require(DocumentRenderer().render(document.drawn(atTimeMS: 2000),
                                                            store: store, scale: 1))
        let seen = ink(zoomed, at: CGPoint(x: 10, y: 10))
        #expect(seen.r > 230 && seen.g > 230 && seen.b > 230, "the corner read \(seen)")
    }

    // MARK: - A cropped clip

    /// The recording's frames, read at `readWidth` of its 200 pixels across.
    private func croppedClip(store: ImageStore, readWidth: Int) -> (PhotonzDocument, UUID) {
        let movie = MovieRef(pixelSize: CGSize(width: 200, height: 100), durationMS: 4000)
        let picture = quarters(width: readWidth, height: readWidth / 2)
        for ms in stride(from: 0, through: 4000, by: MovieRef.frameStepMS) {
            store.register(picture, as: movie.frameRef(atSourceMS: ms))
        }
        var document = PhotonzDocument.recording(movie, name: "Clip")
        let id = document.layers[0].id
        // Keep the right half: green over white.
        document.updateLayer(id: id) { $0.cropContent(to: CGRect(x: 100, y: 0, width: 100, height: 100)) }
        return (document, id)
    }

    @Test(arguments: [200, 150, 100])
    func aCroppedClipReadSmallStillShowsWhatItKept(readWidth: Int) throws {
        // A window shows a recording's frames read at the size it shows them,
        // well under the recording's own for a small window. The crop is in
        // the recording's pixels, so it has to be read against the frame's.
        let store = ImageStore()
        let (document, _) = croppedClip(store: store, readWidth: readWidth)
        let image = try #require(DocumentRenderer().render(document.drawn(atTimeMS: 1000), store: store, scale: 1))
        let top = ink(image, at: CGPoint(x: 150, y: 20))
        let bottom = ink(image, at: CGPoint(x: 150, y: 80))
        #expect(top.g > 230 && top.r < 25 && top.b < 25 && top.a > 250, "read \(readWidth): top \(top)")
        #expect(bottom.r > 230 && bottom.g > 230 && bottom.b > 230, "read \(readWidth): bottom \(bottom)")
    }

    @Test func aCroppedPictureDrawnAtTwiceShowsWhatItKept() throws {
        // An export at 2x, and a canvas zoomed in, draw the document magnified.
        let store = ImageStore()
        let ref = store.register(quarters(width: 200, height: 100))
        var layer = Layer(name: "Picture", content: .image(ref), frame: CGRect(x: 0, y: 0, width: 200, height: 100))
        layer.cropContent(to: CGRect(x: 100, y: 0, width: 100, height: 100))
        let document = PhotonzDocument(canvasSize: CGSize(width: 200, height: 100), layers: [layer])
        let image = try #require(DocumentRenderer().render(document, store: store, scale: 2))
        let top = ink(image, at: CGPoint(x: 300, y: 40))
        let bottom = ink(image, at: CGPoint(x: 300, y: 160))
        #expect(top.g > 230 && top.r < 25 && top.b < 25 && top.a > 250, "top \(top)")
        #expect(bottom.r > 230 && bottom.g > 230 && bottom.b > 230, "bottom \(bottom)")
    }

    @Test func aZoomOnACroppedClipReadSmallLandsOnItsSpot() throws {
        // The zoom on the kept right half's bottom half: white.
        let store = ImageStore()
        var (document, id) = croppedClip(store: store, readWidth: 100)
        document.updateLayer(id: id) {
            $0.zooms = [ClipZoom(startMS: 0, endMS: 4000, easeInMS: 0, easeOutMS: 0,
                                 scale: 2, center: CGPoint(x: 0.75, y: 0.75))]
        }
        let image = try #require(DocumentRenderer().render(document.drawn(atTimeMS: 2000), store: store, scale: 1))
        for point in [CGPoint(x: 105, y: 5), CGPoint(x: 195, y: 95), CGPoint(x: 150, y: 50)] {
            let seen = ink(image, at: point)
            #expect(seen.r > 230 && seen.g > 230 && seen.b > 230, "at \(point): \(seen)")
        }
    }
}
