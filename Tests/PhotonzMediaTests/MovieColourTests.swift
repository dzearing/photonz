import AVFoundation
import CoreGraphics
import CoreMedia
import Foundation
import PhotonzCore
@testable import PhotonzMedia
import Testing

/// **An exported video plays with the colours the editor shows.**
///
/// A file that says nothing about its colours is guessed at by every player,
/// and the guess QuickTime, Safari and the app's own reader make (SMPTE-C, the
/// 601 matrix, the 709 curve) played sRGB 76 as 86 and pure red as an orange
/// red (docs/progress/2026-10-04-export-brightness.md). Every test here writes
/// a real file and reads it back the way a player does, through VideoToolbox.
@Suite("An exported video says what colours it holds", .serialized)
struct MovieColourTests {

    static let folder = TestTone.scratch()

    /// The three tags a written file carries, read off its first video track.
    static func tags(of url: URL) async throws -> (primaries: String?, transfer: String?, matrix: String?) {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first,
              let format = try await track.load(.formatDescriptions).first
        else { throw TestTone.Failure.noBuffer }
        func tag(_ key: CFString) -> String? {
            CMFormatDescriptionGetExtension(format, extensionKey: key) as? String
        }
        return (tag(kCMFormatDescriptionExtension_ColorPrimaries),
                tag(kCMFormatDescriptionExtension_TransferFunction),
                tag(kCMFormatDescriptionExtension_YCbCrMatrix))
    }

    static func expectTagged(_ url: URL) async throws {
        let read = try await tags(of: url)
        #expect(read.primaries == kCMFormatDescriptionColorPrimaries_ITU_R_709_2 as String)
        #expect(read.transfer == kCMFormatDescriptionTransferFunction_sRGB as String)
        #expect(read.matrix == kCMFormatDescriptionYCbCrMatrix_ITU_R_709_2 as String)
    }

    /// Colours a person can tell apart at a glance: the greys where the guess
    /// went wrong the most, and the three primaries.
    static let greys: [Int] = [16, 76, 128, 200]
    static let primaries: [(r: Int, g: Int, b: Int)] = [(255, 0, 0), (0, 255, 0), (0, 0, 255)]

    static func near(_ a: (r: Int, g: Int, b: Int), _ b: (r: Int, g: Int, b: Int), within: Int) -> Bool {
        abs(a.r - b.r) <= within && abs(a.g - b.g) <= within && abs(a.b - b.b) <= within
    }

    /// One flat colour a second, in the order given, as sRGB code values.
    static func steps(_ colours: [(r: Int, g: Int, b: Int)],
                      plan: VideoFramePlan) -> @Sendable (Int) async -> CGImage? {
        let size = plan.size
        let values = colours.map { (Double($0.r) / 255, Double($0.g) / 255, Double($0.b) / 255) }
        return { ms in
            let index = min(values.count - 1, ms / 1000)
            return DocumentMovieWriterTests.solid(values[index], size: size)
        }
    }

    // MARK: - What the encoder is asked for

    @Test("Both writers ask the encoder for 709 primaries, the sRGB curve and the 709 matrix")
    func settingsCarryTheColourProperties() {
        let expected: [String: String] = [
            AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
            AVVideoTransferFunctionKey: AVVideoTransferFunction_IEC_sRGB,
            AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
        ]
        #expect(MovieColour.properties == expected)

        // Every size and quality the sheet offers, held or not.
        for quality in VideoExportQuality.allCases {
            for size in [nil] + VideoExportSize.allCases.map(Optional.some) {
                let plan = DocumentVideoExport.plan(durationMS: 1000,
                                                    canvasSize: CGSize(width: 2560, height: 1600),
                                                    format: .mp4, quality: quality, size: size)
                for holds in [false, true] {
                    let document = DocumentMovieWriter.videoSettings(plan: plan, holdsToBudget: holds)
                    #expect(document[AVVideoColorPropertiesKey] as? [String: String] == expected,
                            "document at \(quality) \(String(describing: size))")
                }
            }
            for size in [nil] + VideoExportSize.allCases.map(Optional.some) {
                let recipe = quality.recipe(format: .mp4, sourceSize: CGSize(width: 2560, height: 1600),
                                            sourceFPS: 30, size: size)
                for holds in [false, true] {
                    let recording = VideoExporter.movieSettings(recipe, holdsToBudget: holds)
                    #expect(recording[AVVideoColorPropertiesKey] as? [String: String] == expected,
                            "recording at \(quality) \(String(describing: size))")
                }
            }
        }
    }

    // MARK: - The document's file

    @Test("A document's file is tagged and plays its greys and primaries as the editor shows them")
    func documentFilePlaysTheEditorsColours() async throws {
        let colours = Self.greys.map { (r: $0, g: $0, b: $0) } + Self.primaries
        let plan = DocumentVideoExport.plan(durationMS: colours.count * 1000,
                                            canvasSize: CGSize(width: 320, height: 240),
                                            format: .mp4, quality: .high)
        let out = Self.folder.appendingPathComponent("document-colours.mp4")
        try await DocumentMovieWriter.write(plan: plan, mix: [], soundURLs: [:], to: out,
                                            frames: Self.steps(colours, plan: plan))
        try await Self.expectTagged(out)

        for (index, written) in colours.enumerated() {
            let played = try await DocumentMovieWriterTests.colour(of: out, atSeconds: Double(index) + 0.5)
            let allowance = written.r == written.g && written.g == written.b ? 1 : 2
            #expect(Self.near(played, written, within: allowance),
                    "wrote \(written), plays as \(played)")
        }
    }

    // MARK: - The recording's file

    /// A recording as the Mac's own screen recorder writes one, tagged
    /// 709 / 709 / 709, one flat colour a second.
    static func appleStyleRecording(_ colours: [(r: Int, g: Int, b: Int)], to url: URL) async throws {
        try? FileManager.default.removeItem(at: url)
        let size = CGSize(width: 320, height: 240)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height),
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
            ],
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
                kCVPixelBufferWidthKey as String: Int(size.width),
                kCVPixelBufferHeightKey as String: Int(size.height),
            ])
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        let fps = 10
        for index in 0..<(colours.count * fps) {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)) }
            let colour = colours[index / fps]
            guard let pool = adaptor.pixelBufferPool else { break }
            var made: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &made)
            guard let buffer = made else { break }
            CVPixelBufferLockBaseAddress(buffer, [])
            let base = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
            let stride = CVPixelBufferGetBytesPerRow(buffer)
            for row in 0..<Int(size.height) {
                for column in 0..<Int(size.width) {
                    let at = row * stride + column * 4
                    base[at] = UInt8(colour.b); base[at + 1] = UInt8(colour.g)
                    base[at + 2] = UInt8(colour.r); base[at + 3] = 255
                }
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(index),
                                                               timescale: CMTimeScale(fps)))
        }
        input.markAsFinished()
        writer.endSession(atSourceTime: CMTime(value: CMTimeValue(colours.count * fps),
                                               timescale: CMTimeScale(fps)))
        await writer.finishWriting()
        if writer.status == .failed, let error = writer.error { throw error }
    }

    @Test("A recording's export is tagged and plays as the recording itself plays")
    func recordingExportPlaysLikeTheRecording() async throws {
        let colours = Self.greys.map { (r: $0, g: $0, b: $0) } + Self.primaries
        let source = Self.folder.appendingPathComponent("recording.mp4")
        try await Self.appleStyleRecording(colours, to: source)
        let out = Self.folder.appendingPathComponent("recording-export.mp4")
        let recipe = VideoExportQuality.high.recipe(format: .mp4,
                                                    sourceSize: CGSize(width: 320, height: 240),
                                                    sourceFPS: 10)
        try await VideoExporter.exportMP4(
            from: source, to: out,
            cuts: VideoCutList(pieces: [VideoPiece(start: 0, end: Double(colours.count))],
                               sourceDuration: Double(colours.count)),
            crop: nil, recipe: recipe)
        try await Self.expectTagged(out)

        for (index, written) in colours.enumerated() {
            let original = try await DocumentMovieWriterTests.colour(of: source, atSeconds: Double(index) + 0.5)
            let played = try await DocumentMovieWriterTests.colour(of: out, atSeconds: Double(index) + 0.5)
            let allowance = written.r == written.g && written.g == written.b ? 1 : 2
            #expect(Self.near(played, original, within: allowance),
                    "the recording plays \(original), its export \(played)")
        }
    }
}
