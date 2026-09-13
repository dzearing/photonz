import AVFoundation
import AppKit
import CoreGraphics
import PhotonzCore

// The recording a video guide brings with it.
//
// Every other sample in the catalogue is a drawing: a few layers put into a
// window. A recording cannot be, so this writes a real MP4 to disk before the
// window opens. Without it the video guides would depend on the person happening
// to have recorded something, which is the one thing a sample exists to avoid.
//
// It is deliberately BORING AT BOTH ENDS. Two seconds of a window sitting there,
// four of something actually happening, two more of it sitting there again. That
// is what makes trimming it worth doing: a clip where every second matters
// teaches the gesture and none of the judgement.
@MainActor
enum TutorialSampleRecording {
    /// 1280 by 800 at 20 frames a second. Small enough to write quickly, and
    /// the shape of a real screen recording, so the window it opens fills out
    /// the way a capture of somebody's screen would.
    static let size = CGSize(width: 1280, height: 800)
    static let framesPerSecond = 20
    static let seconds = 8.0
    /// Where the interesting part is, in seconds. The guide's copy says "the
    /// first and last few seconds are nothing happening", and this is that.
    static let deadAir = 2.0

    /// The name in the title bar, so it is obvious this is not your work.
    static let fileName = "Tutorial Sample.mp4"

    static var url: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return caches.appendingPathComponent("Photonz", isDirectory: true)
            .appendingPathComponent("Tutorials", isDirectory: true)
            .appendingPathComponent(fileName)
            .standardizedFileURL
    }

    /// A clean copy of the sample, every time a guide is started.
    ///
    /// The trim guide teaches that saving writes the edit into the file, so the
    /// sample has to be rewritten rather than reused: a person who saved last
    /// time would otherwise open the guide on a clip somebody had already cut,
    /// and the step asking them to bring the start in would be asking them to
    /// do it twice. Anything a save left beside it goes with it.
    static func fresh() -> URL? {
        let url = Self.url
        let manager = FileManager.default
        try? manager.createDirectory(at: url.deletingLastPathComponent(),
                                     withIntermediateDirectories: true)
        try? manager.removeItem(at: url)
        try? manager.removeItem(at: VideoOriginals.url(for: url))
        try? manager.removeItem(at: VideoEditsSidecar.url(for: url))
        return write(to: url) ? url : nil
    }

    // MARK: - Writing it

    private static func write(to url: URL) -> Bool {
        guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mp4) else { return false }
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height),
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32ARGB),
                kCVPixelBufferWidthKey as String: Int(size.width),
                kCVPixelBufferHeightKey as String: Int(size.height),
            ])
        guard writer.canAdd(input) else { return false }
        writer.add(input)
        guard writer.startWriting() else { return false }
        writer.startSession(atSourceTime: .zero)

        let total = Int(seconds * Double(framesPerSecond))
        for frame in 0..<total {
            // Driven by hand rather than by `requestMediaDataWhenReady`: this
            // is 160 small frames written once, and a callback would mean the
            // window opening on a file that is not finished yet.
            while !input.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.005) }
            guard let pool = adaptor.pixelBufferPool,
                  let buffer = makeBuffer(pool: pool,
                                          at: Double(frame) / Double(framesPerSecond))
            else { continue }
            adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame),
                                                                timescale: CMTimeScale(framesPerSecond)))
        }
        input.markAsFinished()

        // Finishing is asynchronous and the window is about to be told to open
        // this file, so the wait is real rather than polite.
        let done = DispatchSemaphore(value: 0)
        writer.finishWriting { done.signal() }
        _ = done.wait(timeout: .now() + 10)
        return writer.status == .completed
    }

    private static func makeBuffer(pool: CVPixelBufferPool, at time: Double) -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess,
              let buffer else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: CVPixelBufferGetWidth(buffer),
            height: CVPixelBufferGetHeight(buffer),
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue)
        else { return nil }
        draw(in: context, at: time)
        return buffer
    }

    // MARK: - What is in it

    /// A made up app copying a folder of files: a bar filling along the very
    /// top, and a tile in the top left corner counting up. Nothing for two
    /// seconds, then four of it happening, then nothing again.
    ///
    /// WHERE things are drawn is not decoration. A guide's card is a fixed
    /// width in the middle of the window, and in a window this shape it covers
    /// the middle third from top to bottom: a clip whose only moving part was
    /// in the centre would be a clip you could not watch while the card told
    /// you to watch it. So the bar runs along the top edge, above the highest
    /// a card ever reaches, and the tile sits in the left column, clear of the
    /// widest one.
    private static func draw(in context: CGContext, at time: Double) {
        let full = CGRect(origin: .zero, size: size)
        fill(context, full, "#20242E")

        // The progress of the thing happening, 0 before it starts and 1 after
        // it finishes, so both ends of the clip are a still picture.
        let action = max(0, min(1, (time - deadAir) / (seconds - deadAir * 2)))
        let done = Int((action * 240).rounded())

        // The bar along the very top, the one thing no callout can cover.
        let strip = CGRect(x: 0, y: size.height - 16, width: size.width, height: 16)
        fill(context, strip, "#2C3240")
        if action > 0 {
            fill(context, CGRect(x: 0, y: strip.minY, width: size.width * action,
                                 height: strip.height), "#3B7CFF")
        }

        // The tile, in the left column.
        let tile = CGRect(x: 56, y: 300, width: 300, height: 380)
        fill(context, tile, "#F4F6FA", radius: 16)

        let heading = action <= 0 ? "Ready" : (action >= 1 ? "Finished" : "Copying")
        text(context, heading, at: CGPoint(x: 88, y: 620), size: 26, hex: "#1F2430", bold: true)
        text(context, "\(done)", at: CGPoint(x: 88, y: 500), size: 72, hex: "#3B7CFF", bold: true)
        text(context, "of 240 files", at: CGPoint(x: 88, y: 450), size: 20, hex: "#6B7280")

        let track = CGRect(x: 88, y: 400, width: 236, height: 10)
        fill(context, track, "#DCE0E8", radius: 5)
        if action > 0 {
            fill(context, CGRect(x: track.minX, y: track.minY,
                                 width: max(10, track.width * action), height: track.height),
                 "#3B7CFF", radius: 5)
        }

        // The rows tick in one at a time, so there is something changing to
        // watch as well as something filling.
        // Four rows, and they stay INSIDE the tile: a fifth ran off the bottom
        // of it and read as words loose on the page.
        let names = ["report-1.png", "report-2.png", "notes.pdf", "screens.zip"]
        let arrived = Int(action * Double(names.count))
        for row in 0..<min(arrived, names.count) {
            text(context, names[row], at: CGPoint(x: 88, y: 372 - CGFloat(row) * 24),
                 size: 15, hex: "#6B7280")
        }
    }

    // MARK: - Drawing helpers

    private static func fill(_ context: CGContext, _ rect: CGRect, _ hex: String,
                             radius: CGFloat = 0) {
        context.setFillColor(color(hex))
        if radius > 0 {
            let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius,
                              transform: nil)
            context.addPath(path)
            context.fillPath()
        } else {
            context.fill(rect)
        }
    }

    private static func text(_ context: CGContext, _ string: String, at point: CGPoint,
                             size: CGFloat, hex: String, bold: Bool = false) {
        let font = NSFont.systemFont(ofSize: size, weight: bold ? .semibold : .regular)
        let attributed = NSAttributedString(string: string, attributes: [
            .font: font,
            .foregroundColor: NSColor(cgColor: color(hex)) ?? .black,
        ])
        let line = CTLineCreateWithAttributedString(attributed)
        context.textPosition = point
        CTLineDraw(line, context)
    }

    private static func color(_ hex: String) -> CGColor {
        let scanner = Scanner(string: hex.replacingOccurrences(of: "#", with: ""))
        var value: UInt64 = 0
        scanner.scanHexInt64(&value)
        return CGColor(red: CGFloat((value >> 16) & 0xFF) / 255,
                       green: CGFloat((value >> 8) & 0xFF) / 255,
                       blue: CGFloat(value & 0xFF) / 255, alpha: 1)
    }
}
