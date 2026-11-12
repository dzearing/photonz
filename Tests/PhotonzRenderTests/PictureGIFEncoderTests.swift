import CoreGraphics
import Foundation
import ImageIO
import PhotonzCore
import Testing
@testable import PhotonzRender

/// **A moving picture written out as a GIF** (task
/// `an-animated-picture-exports-as-a-gif`). These read the real file back the
/// way Preview and a browser do, through ImageIO, so what is checked is the
/// bytes that would land on disk.
@Suite("A moving picture is written out as a GIF")
struct PictureGIFEncoderTests {

    static let canvas = CGSize(width: 200, height: 160)

    /// A blue triangle on a white canvas, swinging there and back for ever.
    static func swinging(_ repeats: MotionRepeat = .foreverThereAndBack,
                         keyed: Bool? = nil) throws -> (document: PhotonzDocument, store: ImageStore) {
        var (document, store) = try PictureExportBackgroundTests.iconOnABlankCanvas()
        let index = document.layers.count - 1
        document.layers[index].motions = [
            LayerMotion(property: .rotation, from: .number(-30), to: .number(30),
                        timing: MotionTiming(startMS: 0, durationMS: 1000),
                        curve: .linear, repeats: repeats, pivot: .centre)
        ]
        if let keyed {
            document.keyLap = KeyLap(repeats: keyed)
            document.motionCycleMS = 1000
        }
        return (document, store)
    }

    static func encode(_ document: PhotonzDocument, store: ImageStore, scale: CGFloat = 1,
                       background: SVGExport.Background = .keep) -> Data? {
        PictureGIFEncoder.data(of: document, frameID: nil, scale: scale, background: background,
                               renderer: DocumentRenderer(), store: store)
    }

    static func source(_ data: Data) throws -> CGImageSource {
        try #require(CGImageSourceCreateWithData(data as CFData, nil))
    }

    static func gifProperties(_ source: CGImageSource, frame: Int? = nil) -> [CFString: Any] {
        let all = frame.map { CGImageSourceCopyPropertiesAtIndex(source, $0, nil) }
            ?? CGImageSourceCopyProperties(source, nil)
        return (all as? [CFString: Any])?[kCGImagePropertyGIFDictionary] as? [CFString: Any] ?? [:]
    }

    @Test func aStillPictureWritesNoGIF() throws {
        let (document, store) = try PictureExportBackgroundTests.iconOnABlankCanvas()
        #expect(Self.encode(document, store: store) == nil)
    }

    @Test func aSwingingPictureIsAGIFWithAFramePerMomentOfTheLoop() throws {
        let (document, store) = try Self.swinging()
        let plan = try #require(PictureGIF.plan(for: document))
        let data = try #require(Self.encode(document, store: store))
        let source = try Self.source(data)
        #expect(CGImageSourceGetType(source) as String? == "com.compuserve.gif")
        #expect(CGImageSourceGetCount(source) == plan.timesMS.count)
        // Goes round for ever, as the timeline does.
        #expect(Self.gifProperties(source)[kCGImagePropertyGIFLoopCount] as? Int == 0)
        // Each frame is held as long as the plan says, so one play of the file
        // is one lap of the timeline.
        var total = 0.0
        for index in 0..<CGImageSourceGetCount(source) {
            let delay = Self.gifProperties(source, frame: index)[kCGImagePropertyGIFUnclampedDelayTime]
                as? Double ?? 0
            #expect(abs(delay - Double(plan.delaysInHundredths[index]) / 100) < 0.005)
            total += delay
        }
        #expect(abs(total - 1.0) < 0.011)
        // It is the canvas's size.
        let first = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(first.width == Int(Self.canvas.width))
        #expect(first.height == Int(Self.canvas.height))
    }

    @Test func theFramesActuallyMove() throws {
        let (document, store) = try Self.swinging()
        let data = try #require(Self.encode(document, store: store))
        let source = try Self.source(data)
        let first = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let quarter = try #require(CGImageSourceCreateImageAtIndex(source, CGImageSourceGetCount(source) / 4, nil))
        #expect(try Self.pixels(first) != Self.pixels(quarter))
    }

    @Test func aLapPlayedOnceWritesAFileThatStops() throws {
        let (document, store) = try Self.swinging(.once, keyed: false)
        let data = try #require(Self.encode(document, store: store))
        // No loop block at all: every reader plays a GIF without one once and
        // holds the last picture.
        #expect(data.range(of: Data("NETSCAPE2.0".utf8)) == nil)
        let looping = try Self.swinging(.once, keyed: true)
        let loopingData = try #require(Self.encode(looping.document, store: looping.store))
        #expect(loopingData.range(of: Data("NETSCAPE2.0".utf8)) != nil)
    }

    @Test func twoTimesTheScaleIsTwiceTheSize() throws {
        let (document, store) = try Self.swinging()
        let data = try #require(Self.encode(document, store: store, scale: 2))
        let first = try #require(CGImageSourceCreateImageAtIndex(try Self.source(data), 0, nil))
        #expect(first.width == Int(Self.canvas.width) * 2)
    }

    @Test func leavingTheCanvasOutLeavesTheCornersEmpty() throws {
        let (document, store) = try Self.swinging()
        let data = try #require(Self.encode(document, store: store, background: .drop))
        let first = try #require(CGImageSourceCreateImageAtIndex(try Self.source(data), 0, nil))
        let pixels = try Self.pixels(first)
        #expect(pixels[3] == 0)
        let kept = try #require(Self.encode(document, store: store, background: .keep))
        let keptFirst = try #require(CGImageSourceCreateImageAtIndex(try Self.source(kept), 0, nil))
        #expect(try Self.pixels(keptFirst)[3] == 255)
    }

    @Test func theSizerHandsBackTheVeryFileItWeighed() async throws {
        let (document, store) = try Self.swinging()
        let sizer = ExportSizer(renderer: DocumentRenderer(), store: store)
        let weighed = try #require(await sizer.gifData(of: document, frameID: nil, scale: 1,
                                                      background: .keep))
        let renders = await sizer.rendersMade
        let again = try #require(await sizer.gifData(of: document, frameID: nil, scale: 1,
                                                    background: .keep))
        #expect(weighed == again)
        #expect(await sizer.rendersMade == renders)
    }

    /// RGBA bytes of a picture, top row first.
    static func pixels(_ image: CGImage) throws -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = try #require(CGContext(data: &bytes, width: image.width, height: image.height,
                                             bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                             space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return bytes
    }
}
