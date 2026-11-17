import CoreGraphics
import CoreImage
import CoreVideo
import Foundation
import PhotonzCore
@testable import PhotonzRender
import Testing
import VideoToolbox

/// A video export draws each frame straight into the encoder's buffer, and
/// reads a decoded frame of a recording straight off the surface it was decoded
/// onto, rather than through a CGImage both ways. Both have to draw exactly the
/// picture the CGImage route drew: same pixels, same way up, same colours.
@Suite("A video frame drawn into the encoder's buffer")
struct VideoFrameIntoBufferTests {

    static let size = CGSize(width: 320, height: 200)

    /// A 32BGRA buffer on a surface, the kind an encoder's pool hands out.
    static func buffer(_ width: Int, _ height: Int) throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        let attributes: [String: Any] = [
            kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
            kCVPixelBufferMetalCompatibilityKey as String: true,
        ]
        CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA,
                            attributes as CFDictionary, &buffer)
        return try #require(buffer)
    }

    /// The pixel at (x, y) counted from the TOP left, as B, G, R.
    static func pixel(_ buffer: CVPixelBuffer, _ x: Int, _ y: Int) -> [Int] {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return [] }
        let row = base.advanced(by: y * CVPixelBufferGetBytesPerRow(buffer))
            .assumingMemoryBound(to: UInt8.self)
        return (0..<4).map { Int(row[x * 4 + $0]) }
    }

    /// The largest difference in any colour channel between two buffers.
    static func largestDifference(_ a: CVPixelBuffer, _ b: CVPixelBuffer) -> Int {
        CVPixelBufferLockBaseAddress(a, .readOnly)
        CVPixelBufferLockBaseAddress(b, .readOnly)
        defer {
            CVPixelBufferUnlockBaseAddress(a, .readOnly)
            CVPixelBufferUnlockBaseAddress(b, .readOnly)
        }
        guard let pa = CVPixelBufferGetBaseAddress(a), let pb = CVPixelBufferGetBaseAddress(b) else { return 255 }
        var worst = 0
        for y in 0..<CVPixelBufferGetHeight(a) {
            let ra = pa.advanced(by: y * CVPixelBufferGetBytesPerRow(a)).assumingMemoryBound(to: UInt8.self)
            let rb = pb.advanced(by: y * CVPixelBufferGetBytesPerRow(b)).assumingMemoryBound(to: UInt8.self)
            for x in 0..<CVPixelBufferGetWidth(a) {
                for c in 0..<3 { worst = max(worst, abs(Int(ra[x * 4 + c]) - Int(rb[x * 4 + c]))) }
            }
        }
        return worst
    }

    /// What the export did before: the composite as a CGImage, drawn over
    /// black into the buffer on the CPU.
    static func drawnTheOldWay(_ image: CGImage, into buffer: CVPixelBuffer) {
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer), width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return }
        let whole = CGRect(x: 0, y: 0, width: width, height: height)
        context.setFillColor(gray: 0, alpha: 1)
        context.fill(whole)
        context.interpolationQuality = .high
        context.draw(image, in: whole)
    }

    /// A document whose top half is a red picture and bottom half a half
    /// see-through blue one over nothing, with a soft ramp across the red: so
    /// the way up, the colours and the black under a see-through pixel are
    /// all read.
    static func document() throws -> (PhotonzDocument, ImageStore) {
        let half = CGSize(width: size.width, height: size.height / 2)
        let red = try ImageStoreFlatColourTests.image { context in
            for x in 0..<300 {
                context.setFillColor(red: 0.88, green: CGFloat(x) / 600, blue: 0.12, alpha: 1)
                context.fill(CGRect(x: x, y: 0, width: 1, height: 200))
            }
        }
        let blue = try ImageStoreFlatColourTests.image { context in
            context.setFillColor(red: 0.12, green: 0.31, blue: 0.82, alpha: 0.5)
            context.fill(CGRect(x: 0, y: 0, width: 300, height: 200))
        }
        let store = ImageStore()
        var doc = PhotonzDocument(canvasSize: size)
        doc.layers = [
            Layer(name: "Top", content: .image(store.register(red)), frame: CGRect(origin: .zero, size: half)),
            Layer(name: "Bottom", content: .image(store.register(blue)),
                  frame: CGRect(origin: CGPoint(x: 0, y: half.height), size: half)),
        ]
        return (doc, store)
    }

    @Test func drawsTheSamePictureTheCGImageRouteDid() throws {
        let (doc, store) = try Self.document()
        let renderer = DocumentRenderer()
        let old = try Self.buffer(320, 200)
        let new = try Self.buffer(320, 200)
        Self.drawnTheOldWay(try #require(renderer.render(doc, store: store)), into: old)
        #expect(renderer.render(doc, store: store, scale: 1, into: new))
        // The right way up: red on top, blue (half over black) below.
        let top = Self.pixel(new, 160, 20), bottom = Self.pixel(new, 160, 180)
        #expect(top[2] > 200 && top[0] < 60, "top is red: \(top)")
        #expect(bottom[0] > 80 && bottom[0] < 140 && bottom[2] < 40, "bottom is half blue over black: \(bottom)")
        #expect(Self.largestDifference(old, new) <= 2)
        // A movie has no transparency: what a see-through pixel shows is the
        // black under it, and the buffer says it is solid.
        #expect(bottom[3] == 255)
    }

    @Test func drawsAtTheExportScale() throws {
        let (doc, store) = try Self.document()
        let renderer = DocumentRenderer()
        let old = try Self.buffer(160, 100)
        let new = try Self.buffer(160, 100)
        Self.drawnTheOldWay(try #require(renderer.render(doc, store: store, scale: 0.5)), into: old)
        #expect(renderer.render(doc, store: store, scale: 0.5, into: new))
        #expect(Self.largestDifference(old, new) <= 2)
    }

    @Test func aDecodedFrameReadOffItsSurfaceDrawsAsItsPictureDoes() throws {
        // A frame as a decoder hands it over: a surface with a picture made of it.
        let surface = try Self.buffer(320, 200)
        CVPixelBufferLockBaseAddress(surface, [])
        if let base = CVPixelBufferGetBaseAddress(surface) {
            for y in 0..<200 {
                let row = base.advanced(by: y * CVPixelBufferGetBytesPerRow(surface)).assumingMemoryBound(to: UInt8.self)
                for x in 0..<320 {
                    row[x * 4] = UInt8(x * 255 / 319)          // B rises left to right
                    row[x * 4 + 1] = y < 100 ? 200 : 40       // G: top band light
                    row[x * 4 + 2] = UInt8(y * 255 / 199)     // R rises top to bottom
                    row[x * 4 + 3] = 255
                }
            }
        }
        CVPixelBufferUnlockBaseAddress(surface, [])
        var made: CGImage?
        VTCreateCGImageFromCVPixelBuffer(surface, options: nil, imageOut: &made)
        let picture = try #require(made)

        var doc = PhotonzDocument(canvasSize: Self.size)
        let ref = ImageRef(pixelSize: Self.size)
        doc.layers = [Layer(name: "Clip", content: .image(ref), frame: CGRect(origin: .zero, size: Self.size))]
        let plain = ImageStore()
        plain.register(picture, as: ref)
        let withSurface = ImageStore()
        withSurface.register(picture, as: ref, surface: surface)
        #expect(withSurface.surface(for: ref, standingFor: picture) === surface)

        let old = try Self.buffer(320, 200)
        let new = try Self.buffer(320, 200)
        #expect(DocumentRenderer().render(doc, store: plain, scale: 1, into: old))
        #expect(DocumentRenderer().render(doc, store: withSurface, scale: 1, into: new))
        #expect(Self.largestDifference(old, new) <= 1)
        // Still the right way up: the light green band is on top.
        #expect(Self.pixel(new, 10, 10)[1] > 150 && Self.pixel(new, 10, 190)[1] < 90)
    }

    @Test func everyNewFrameOfARecordingIsTheOneDrawn() throws {
        // A recording's frames come and go under one reference, each a new
        // picture on its own surface. Every one drawn has to be that frame and
        // not one drawn before it, even where a new picture lands where an old
        // one was in memory.
        let ref = ImageRef(pixelSize: CGSize(width: 64, height: 64))
        var doc = PhotonzDocument(canvasSize: CGSize(width: 64, height: 64))
        doc.layers = [Layer(name: "Clip", content: .image(ref), frame: CGRect(x: 0, y: 0, width: 64, height: 64))]
        let store = ImageStore()
        let renderer = DocumentRenderer()
        let out = try Self.buffer(64, 64)
        for frame in 0..<120 {
            let level = UInt8(frame * 2)
            let surface = try Self.buffer(64, 64)
            CVPixelBufferLockBaseAddress(surface, [])
            if let base = CVPixelBufferGetBaseAddress(surface) {
                for y in 0..<64 {
                    let row = base.advanced(by: y * CVPixelBufferGetBytesPerRow(surface)).assumingMemoryBound(to: UInt8.self)
                    for x in 0..<64 { row[x * 4] = level; row[x * 4 + 1] = level; row[x * 4 + 2] = level; row[x * 4 + 3] = 255 }
                }
            }
            CVPixelBufferUnlockBaseAddress(surface, [])
            var made: CGImage?
            VTCreateCGImageFromCVPixelBuffer(surface, options: nil, imageOut: &made)
            store.register(try #require(made), as: ref, surface: surface)
            made = nil
            #expect(renderer.render(doc, store: store, scale: 1, into: out))
            let shown = Self.pixel(out, 32, 32)[1]
            #expect(abs(shown - Int(level)) <= 2, "frame \(frame) showed \(shown), wanted \(level)")
            if abs(shown - Int(level)) > 2 { break }
        }
    }

    @Test func aSurfaceOnlyAnswersForThePictureItCameWith() throws {
        let surface = try Self.buffer(4, 4)
        var made: CGImage?
        VTCreateCGImageFromCVPixelBuffer(surface, options: nil, imageOut: &made)
        let picture = try #require(made)
        let other = try #require(ImageStoreFlatColourTests.image { _ in })
        let store = ImageStore()
        let ref = ImageRef(pixelSize: CGSize(width: 4, height: 4))
        store.register(picture, as: ref, surface: surface)
        #expect(store.surface(for: ref, standingFor: other) == nil)
        store.register(other, as: ref)
        #expect(store.surface(for: ref, standingFor: picture) == nil)
        store.register(picture, as: ref, surface: surface)
        store.remove(ref)
        #expect(store.surface(for: ref, standingFor: picture) == nil)
    }
}
