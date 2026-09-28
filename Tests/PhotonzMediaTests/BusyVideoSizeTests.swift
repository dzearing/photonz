import AVFoundation
import CoreGraphics
import Foundation
import PhotonzCore
@testable import PhotonzMedia
import Testing

/// **A busy MP4 lands at the size the Export sheet said.**
///
/// A page of fine text scrolling past is the hardest thing a screen recording
/// asks of the encoder, and until 2026-09-28 it landed at up to two and a half
/// times the size the sheet quoted: Small of a three second 1280 x 800 page at
/// 900 pixels a second came to 830,895 bytes against 324,000, so somebody who
/// picked Small to get under a chat limit found their file did not fit. Two
/// things now stand between them and that:
///
/// - **The encoder is held to its budget** by a one second cap on what it may
///   spend (`MovieCompression`), wherever the picture would otherwise land
///   over it. Busy but ordinary scrolling lands within a
///   quarter of the quote at every choice, and an easy recording is written
///   exactly as it was, since a cap takes bits from it that it never needed.
/// - **Where it cannot, the sheet measures.** The system's H.264 encoder has a
///   floor it will not go under on a picture that is new detail every frame:
///   at 900 pixels a second nothing it was asked for got Small under 1.3 times
///   its budget. So the sheet writes a few stretches at the chosen setting and
///   says what they come to (`VideoExportSample`), and that is within a quarter
///   of the file that lands at every choice, busy or easy.
///
/// Every file here is written for real and weighed off the disk.
@Suite("A busy MP4 lands at the size the sheet said", .serialized)
struct BusyVideoSizeTests {

    static let size = CGSize(width: 1280, height: 800)
    static let folder = VideoExportBudgetTests.folder

    static func bytes(_ url: URL) -> Int { VideoExportBudgetTests.bytes(of: url) }

    /// How far a file may land from the number it was measured against.
    static let tolerance = 0.25

    static func near(_ landed: Int, _ said: Int) -> Bool {
        let ratio = Double(landed) / Double(max(1, said))
        return ratio >= 1 - tolerance && ratio <= 1 + tolerance
    }

    /// The lightest of three, for a size or a weigh. The system's H.264
    /// encoder writes heavier, and never lighter, while other encodes share
    /// the machine, as they do when the whole suite runs: one run beside
    /// eleven other export suites wrote Standard of the 300 px/s page at 1.59
    /// times its budget where a quiet machine writes 1.20 every time
    /// (`VideoExportBudgetTests.aSmallerBudgetWritesASmallerFile` found the
    /// same). The lightest of three is the one written closest to quiet.
    static func lightest(_ write: () async throws -> Int) async throws -> Int {
        var best = Int.max
        for _ in 0..<3 { best = min(best, try await write()) }
        return best
    }

    // MARK: - A recording (the recording's own Export sheet)

    /// Where the encoder can be held to its budget, the budget is the number:
    /// text scrolling at an ordinary pace at every choice, and fast scrolling at
    /// High. The cases it cannot hold are named in the next test.
    @Test("Scrolling text lands near its budget wherever the encoder can be held to it",
          arguments: [(300.0, VideoExportQuality.high), (300, .standard), (300, .small),
                      (900, .high)])
    func aRecordingLandsNearItsBudget(speed: Double, quality: VideoExportQuality) async throws {
        let source = try await VideoExportBudgetTests.scrollingText(seconds: 3, size: Self.size,
                                                                    pixelsPerSecond: speed)
        let recipe = quality.recipe(format: .mp4, sourceSize: Self.size, sourceFPS: 30)
        let out = Self.folder.appendingPathComponent("busy-\(Int(speed))-\(quality.rawValue).mp4")
        let landed = try await Self.lightest {
            try await VideoExporter.exportMP4(from: source, to: out,
                                              cuts: VideoExportBudgetTests.wholeOf(source, seconds: 3),
                                              crop: nil, recipe: recipe)
            return Self.bytes(out)
        }
        let budget = recipe.expectedBytes(seconds: 3, hasAudio: false)
        #expect(Self.near(landed, budget),
                "\(quality.rawValue) at \(Int(speed)) px/s landed \(landed) against \(budget)")
    }

    /// **Which ones the encoder cannot be held to, and what answers them.**
    /// Standard and Small of text at 900 pixels a second land over their
    /// budget whatever the encoder is asked; the sheet's weigh says what they
    /// really come to. The weigh is checked at every choice, so it can never
    /// be the thing that is wrong where the budget is right.
    @Test("Where the budget cannot hold, what the sheet weighs is what lands",
          arguments: [300.0, 900.0])
    func aRecordingsWeighIsWhatLands(speed: Double) async throws {
        let source = try await VideoExportBudgetTests.scrollingText(seconds: 3, size: Self.size,
                                                                    pixelsPerSecond: speed)
        let cuts = VideoExportBudgetTests.wholeOf(source, seconds: 3)
        var beyondTheBudget: [String] = []
        for quality in VideoExportQuality.allCases {
            let recipe = quality.recipe(format: .mp4, sourceSize: Self.size, sourceFPS: 30)
            let weighed = try await Self.lightest {
                try await VideoExporter.weighMP4(from: source, cuts: cuts, crop: nil,
                                                 recipe: recipe)
            }
            let out = Self.folder.appendingPathComponent("weighed-\(Int(speed))-\(quality.rawValue).mp4")
            let landed = try await Self.lightest {
                try await VideoExporter.exportMP4(from: source, to: out, cuts: cuts, crop: nil,
                                                  recipe: recipe)
                return Self.bytes(out)
            }
            #expect(Self.near(landed, weighed),
                    "\(quality.rawValue) at \(Int(speed)) px/s: the sheet weighed \(weighed), \(landed) landed")
            if !Self.near(landed, recipe.expectedBytes(seconds: 3, hasAudio: false)) {
                beyondTheBudget.append(quality.rawValue)
            }
        }
        // Which the encoder cannot be held to, said rather than hidden: none
        // of an ordinary pace of scrolling, and Small of the fast one, where
        // its floor is 1.3 times the budget. High is never among them. If the
        // system's encoder ever gets under its floor, this is the line that
        // says so, and the sheet's weigh goes on being right either way.
        if speed < 600 {
            #expect(beyondTheBudget.isEmpty, "at \(Int(speed)) px/s: \(beyondTheBudget)")
        } else {
            #expect(beyondTheBudget.contains("small") && !beyondTheBudget.contains("high"),
                    "at \(Int(speed)) px/s the budget could not hold \(beyondTheBudget)")
        }
    }

    /// An easy recording is not pushed under its number either: it lands far
    /// under its budget, because the encoder stops when the picture is good
    /// enough, and the weigh says what it really comes to.
    @Test("An easy recording's weigh is what lands")
    func anEasyRecordingsWeighIsWhatLands() async throws {
        let source = try await VideoExportBudgetTests.busySource(seconds: 3, size: Self.size)
        let cuts = VideoExportBudgetTests.wholeOf(source, seconds: 3)
        for quality in VideoExportQuality.allCases {
            let recipe = quality.recipe(format: .mp4, sourceSize: Self.size, sourceFPS: 30)
            let weighed = try await Self.lightest {
                try await VideoExporter.weighMP4(from: source, cuts: cuts, crop: nil,
                                                 recipe: recipe)
            }
            let out = Self.folder.appendingPathComponent("easy-weighed-\(quality.rawValue).mp4")
            let landed = try await Self.lightest {
                try await VideoExporter.exportMP4(from: source, to: out, cuts: cuts, crop: nil,
                                                  recipe: recipe)
                return Self.bytes(out)
            }
            #expect(Self.near(landed, weighed),
                    "\(quality.rawValue): the sheet weighed \(weighed), \(landed) landed")
        }
    }

    /// The sound is counted as it lands rather than at a flat rate: a flat
    /// 128 kbps said 117 KB for a four second recording that landed at 63 KB.
    @Test("A recording with sound on it is weighed with its sound")
    func aRecordingWithSoundIsWeighedWithIt() async throws {
        let source = try await VideoExportBudgetTests.busySourceWithSound(seconds: 4,
                                                                          size: Self.size)
        let cuts = VideoCutList(pieces: [VideoPiece(start: 0.5, end: 1.5),
                                         VideoPiece(start: 2, end: 4)], sourceDuration: 4)
        for quality in VideoExportQuality.allCases {
            let recipe = quality.recipe(format: .mp4, sourceSize: Self.size, sourceFPS: 30)
            let weighed = try await Self.lightest {
                try await VideoExporter.weighMP4(from: source, cuts: cuts, crop: nil,
                                                 recipe: recipe)
            }
            let out = Self.folder.appendingPathComponent("sound-weighed-\(quality.rawValue).mp4")
            let landed = try await Self.lightest {
                try await VideoExporter.exportMP4(from: source, to: out, cuts: cuts, crop: nil,
                                                  recipe: recipe)
                return Self.bytes(out)
            }
            #expect(Self.near(landed, weighed),
                    "\(quality.rawValue): the sheet weighed \(weighed), \(landed) landed")
        }
    }

    /// A long recording is weighed from stretches of it rather than written
    /// whole, and a quiet page that starts to scroll half way is still weighed
    /// right: the stretches reach into both halves.
    @Test("A long recording that is quiet and then busy is weighed from stretches of it")
    func aLongRecordingIsWeighedFromStretches() async throws {
        let seconds = 24
        let plan = DocumentVideoExport.plan(durationMS: seconds * 1000, canvasSize: Self.size,
                                            format: .mp4, quality: .high)
        let source = Self.folder.appendingPathComponent("quiet-then-busy.mp4")
        try await DocumentMovieWriter.write(
            plan: plan, mix: [], soundURLs: [:], to: source,
            frames: VideoExportBudgetTests.scrollingFrames(size: plan.size, pixelsPerSecond: 600,
                                                           stillUntilMS: 12_000))
        let cuts = VideoExportBudgetTests.wholeOf(source, seconds: Double(seconds))
        for quality in [VideoExportQuality.standard, .small] {
            let recipe = quality.recipe(format: .mp4, sourceSize: Self.size, sourceFPS: 30)
            let weighed = try await Self.lightest {
                try await VideoExporter.weighMP4(from: source, cuts: cuts, crop: nil,
                                                 recipe: recipe)
            }
            let out = Self.folder.appendingPathComponent("quiet-then-busy-\(quality.rawValue).mp4")
            let landed = try await Self.lightest {
                try await VideoExporter.exportMP4(from: source, to: out, cuts: cuts, crop: nil,
                                                  recipe: recipe)
                return Self.bytes(out)
            }
            #expect(Self.near(landed, weighed),
                    "\(quality.rawValue): the sheet weighed \(weighed), \(landed) landed")
        }
    }

    // MARK: - A document (the document's Export sheet)

    /// The same page written as a document, which is how a recording leaves
    /// once it has been edited on the timeline: the pictures are drawn and
    /// encoded by the document's own writer, which is held the same way.
    @Test("A document of scrolling text lands near its budget where it can be held",
          arguments: [(300.0, VideoExportQuality.high), (300, .standard), (300, .small),
                      (900, .high)])
    func aDocumentLandsNearItsBudget(speed: Double, quality: VideoExportQuality) async throws {
        let plan = DocumentVideoExport.plan(durationMS: 3000, canvasSize: Self.size,
                                            format: .mp4, quality: quality)
        let out = Self.folder.appendingPathComponent("doc-\(Int(speed))-\(quality.rawValue).mp4")
        let landed = try await Self.lightest {
            try await DocumentMovieWriter.write(
                plan: plan, mix: [], soundURLs: [:], to: out,
                frames: VideoExportBudgetTests.scrollingFrames(size: plan.size,
                                                               pixelsPerSecond: speed))
            return Self.bytes(out)
        }
        let budget = quality.recipe(format: .mp4, sourceSize: Self.size,
                                    sourceFPS: DocumentVideoExport.movieFPS)
            .expectedBytes(seconds: 3, hasAudio: false)
        #expect(Self.near(landed, budget),
                "\(quality.rawValue) at \(Int(speed)) px/s landed \(landed) against \(budget)")
    }

    @Test("A document's weigh is what lands, busy or quiet", arguments: [0.0, 300.0, 900.0])
    func aDocumentsWeighIsWhatLands(speed: Double) async throws {
        let seconds = speed == 0 ? 20 : 3
        let span = 0..<(seconds * 1000)
        for quality in VideoExportQuality.allCases {
            let plan = DocumentVideoExport.plan(range: span, canvasSize: Self.size,
                                                format: .mp4, quality: quality)
            // Quiet for half of it, so a long one is a still page then a busy one.
            let frames = VideoExportBudgetTests.scrollingFrames(
                size: plan.size, pixelsPerSecond: speed == 0 ? 600 : speed,
                stillUntilMS: speed == 0 ? 10_000 : 0)
            let weighed = try await Self.lightest {
                try await DocumentMovieWriter.weigh(span: span, canvasSize: Self.size,
                                                    quality: quality, frames: frames)
            }
            let out = Self.folder.appendingPathComponent("doc-weighed-\(Int(speed))-\(quality.rawValue).mp4")
            let landed = try await Self.lightest {
                try await DocumentMovieWriter.write(plan: plan, mix: [], soundURLs: [:], to: out,
                                                    frames: frames)
                return Self.bytes(out)
            }
            #expect(Self.near(landed, weighed),
                    "\(quality.rawValue) at \(Int(speed)) px/s: the sheet weighed \(weighed), \(landed) landed")
        }
    }
}
