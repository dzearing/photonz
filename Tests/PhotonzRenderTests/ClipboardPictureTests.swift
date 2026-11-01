import CoreGraphics
import Foundation
import Testing
import PhotonzCore
@testable import PhotonzRender

/// A copied picture goes on the clipboard the moment Copy is pressed and its
/// PNG is made off the main thread; a paste that arrives first waits for it
/// (`ClipboardPicture`). These hold the waiting half: never the old bytes,
/// never none, the same bytes for every reader, and the encode made once.
@Suite("Clipboard picture")
struct ClipboardPictureTests {

    private func picture(width: Int = 96, height: Int = 64) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height,
                                bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        for y in 0..<height {
            context.setFillColor(CGColor(srgbRed: CGFloat(y) / CGFloat(height), green: 0.4,
                                         blue: 0.8, alpha: 1))
            context.fill(CGRect(x: 0, y: y, width: width, height: 1))
        }
        return context.makeImage()!
    }

    private func firstPixel(_ image: CGImage) -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: 4)
        let context = CGContext(data: &pixels, width: 1, height: 1, bitsPerComponent: 8,
                                bytesPerRow: 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return pixels
    }

    /// Counts how often the slow source was asked, from any thread.
    private final class Calls: @unchecked Sendable {
        private let lock = NSLock()
        private var n = 0
        func bump() { lock.lock(); n += 1; lock.unlock() }
        var count: Int { lock.lock(); defer { lock.unlock() }; return n }
    }

    @Test func thePNGIsTheSameBytesACopyWroteBefore() throws {
        let image = picture()
        let expected = try #require(ImageCodec.encode(image, format: .png))
        #expect(ClipboardPicture(image).png == expected)
    }

    @Test func makingOneReturnsAtOnceWhileThePictureIsStillBeingMade() {
        let image = picture()
        let started = Date()
        let pending = ClipboardPicture(making: {
            Thread.sleep(forTimeInterval: 0.3)
            return image
        })
        #expect(Date().timeIntervalSince(started) < 0.05)
        #expect(!pending.isReady)
    }

    @Test func aReaderWhoAsksFirstWaitsAndGetsTheNewPicture() throws {
        let image = picture()
        let expected = try #require(ImageCodec.encode(image, format: .png))
        let pending = ClipboardPicture(making: {
            Thread.sleep(forTimeInterval: 0.2)
            return image
        })
        #expect(!pending.isReady)
        #expect(pending.png == expected)
        #expect(pending.isReady)
    }

    @Test func everyReaderGetsTheSameBytesAndThePictureIsMadeOnce() async throws {
        let image = picture()
        let calls = Calls()
        let pending = ClipboardPicture(making: {
            calls.bump()
            Thread.sleep(forTimeInterval: 0.1)
            return image
        })
        let all = await withTaskGroup(of: Data?.self) { group in
            for _ in 0..<8 { group.addTask { pending.png } }
            var found: [Data?] = []
            for await data in group { found.append(data) }
            return found
        }
        let first = try #require(all.first ?? nil)
        #expect(all.allSatisfy { $0 == first })
        #expect(calls.count == 1)
    }

    @Test func theTIFFHoldsTheSamePicture() throws {
        let image = picture()
        let tiff = try #require(ClipboardPicture(image).tiff())
        let decoded = try #require(ImageCodec.decode(tiff))
        #expect(decoded.width == image.width && decoded.height == image.height)
        #expect(firstPixel(decoded) == firstPixel(image))
        // A TIFF is the picture's own type, not a PNG under another name.
        #expect(tiff.starts(with: [0x4D, 0x4D]) || tiff.starts(with: [0x49, 0x49]))
    }

    @Test func aPictureThatCouldNotBeMadeAnswersNothingAndNeverHangs() {
        let pending = ClipboardPicture(making: { nil })
        #expect(pending.png == nil)
        #expect(pending.tiff() == nil)
        #expect(pending.isReady)
    }
}

/// One promised clipboard type: made once, whoever asks first, and let go of
/// as soon as it is handed over, so a copy holds nothing in Photonz once the
/// system clipboard has it (`PromisedData`).
@Suite("Promised clipboard data")
struct PromisedDataTests {

    private final class Calls: @unchecked Sendable {
        private let lock = NSLock()
        private var n = 0
        func bump() { lock.lock(); n += 1; lock.unlock() }
        var count: Int { lock.lock(); defer { lock.unlock() }; return n }
    }

    private final class Token: Sendable {}

    @Test func readyAheadThenTakenIsMadeOnce() {
        let calls = Calls()
        let promise = PromisedData { calls.bump(); return Data([1, 2, 3]) }
        promise.prepare()
        promise.prepare()
        #expect(promise.take() == Data([1, 2, 3]))
        #expect(calls.count == 1)
    }

    @Test func takenWithoutPreparingIsMadeThere() {
        let promise = PromisedData { Data([7]) }
        #expect(promise.take() == Data([7]))
    }

    @Test func aTakeWhileItIsBeingMadeWaitsForIt() async {
        let calls = Calls()
        let promise = PromisedData {
            calls.bump()
            Thread.sleep(forTimeInterval: 0.15)
            return Data([9])
        }
        let preparing = Task.detached { promise.prepare() }
        try? await Task.sleep(for: .milliseconds(20))
        #expect(promise.take() == Data([9]))
        await preparing.value
        #expect(calls.count == 1)
    }

    @Test func onceHandedOverNothingIsHeld() {
        weak var held: Token?
        let promise: PromisedData = {
            let token = Token()
            held = token
            return PromisedData { _ = token; return Data(count: 1024) }
        }()
        #expect(held != nil)
        #expect(promise.take() != nil)
        // The maker, and everything it held on to, is gone, and so is the data.
        #expect(held == nil)
        #expect(promise.take() == nil)
    }
}
