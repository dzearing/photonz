import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// The Size row on the Export sheet: Full, 1080p and 720p, which is what
/// Premiere and every share tool offer and what people post. The size owns the
/// picture's pixels; the Quality row beside it keeps the frame rate and the
/// budget.
@Suite("Video export size")
struct VideoExportSizeTests {

    private let retina = CGSize(width: 2880, height: 1800)
    private let portrait = CGSize(width: 1800, height: 2880)
    private let sample = CGSize(width: 1280, height: 800)
    private let hd = CGSize(width: 1920, height: 1080)

    // MARK: - What each size means

    @Test("1080p and 720p cap the short side and keep the shape")
    func capsTheShortSide() {
        #expect(VideoExportSize.full.outputSize(for: retina) == retina)
        #expect(VideoExportSize.p1080.outputSize(for: retina) == CGSize(width: 1728, height: 1080))
        #expect(VideoExportSize.p720.outputSize(for: retina) == CGSize(width: 1152, height: 720))
    }

    @Test("A portrait recording caps its width, which is its short side")
    func portraitCapsTheWidth() {
        #expect(VideoExportSize.p1080.outputSize(for: portrait)
            == CGSize(width: 1080, height: 1728))
    }

    @Test("A recording already smaller than a size is never blown up")
    func neverUpscales() {
        #expect(VideoExportSize.p1080.outputSize(for: sample) == sample)
        #expect(VideoExportSize.p720.outputSize(for: CGSize(width: 640, height: 400))
            == CGSize(width: 640, height: 400))
    }

    @Test("Only the sizes that make the picture smaller are offered")
    func offersOnlyWhatShrinks() {
        #expect(VideoExportSize.offered(for: retina) == [.full, .p1080, .p720])
        #expect(VideoExportSize.offered(for: sample) == [.full, .p720])
        #expect(VideoExportSize.offered(for: hd) == [.full, .p720])
        #expect(VideoExportSize.offered(for: CGSize(width: 640, height: 400)) == [.full])
    }

    @Test("A GIF steps down one: Full, 720p and 480p")
    func animatedStepsDown() {
        #expect(VideoExportSize.offered(for: retina, format: .gif) == [.full, .p720, .p480])
        #expect(VideoExportSize.offered(for: retina, format: .heic) == [.full, .p720, .p480])
        #expect(VideoExportSize.offered(for: sample, format: .gif) == [.full, .p720, .p480])
        #expect(VideoExportSize.p480.outputSize(for: sample) == CGSize(width: 768, height: 480))
        #expect(VideoExportSize.firstChoice(for: .gif) == .p480)
        #expect(VideoExportSize.firstChoice(for: .mp4) == .full)
    }

    @Test("A size that is not on offer for this recording falls back to Full")
    func fallsBackToFull() {
        #expect(VideoExportSize.p1080.offeredOrFull(for: sample) == .full)
        #expect(VideoExportSize.p720.offeredOrFull(for: sample) == .p720)
        #expect(VideoExportSize.p480.offeredOrFull(for: retina, format: .mp4) == .full)
        #expect(VideoExportSize.p1080.offeredOrFull(for: retina, format: .gif) == .full)
    }

    @Test("Full names the pixels it keeps; the others are the names people post at")
    func labels() {
        #expect(VideoExportSize.full.label(for: retina) == "Full · 2880 × 1800")
        #expect(VideoExportSize.p1080.label(for: retina) == "1080p")
        #expect(VideoExportSize.p720.label(for: retina) == "720p")
        #expect(!VideoExportSize.full.label(for: retina).contains("—"))
    }

    // MARK: - The size owns the pixels, the quality the rest

    @Test("An MP4 at 1080p is 1728 by 1080 whatever the quality, with even sides")
    func movieAt1080p() {
        for quality in VideoExportQuality.allCases {
            let recipe = quality.recipe(format: .mp4, sourceSize: retina, sourceFPS: 30,
                                        size: .p1080)
            #expect(recipe.size == CGSize(width: 1728, height: 1080))
        }
        let odd = VideoExportQuality.high.recipe(format: .mp4, sourceSize: CGSize(width: 1281, height: 801),
                                                 sourceFPS: 30, size: .p720)
        #expect(Int(odd.size.width) % 2 == 0)
        #expect(Int(odd.size.height) % 2 == 0)
    }

    @Test("With a size chosen, the quality no longer shrinks the picture")
    func qualityKeepsItsHandsOffThePixels() {
        let recipe = VideoExportQuality.small.recipe(format: .mp4, sourceSize: retina,
                                                     sourceFPS: 60, size: .full)
        #expect(recipe.size == retina)
        #expect(recipe.fps == 30)
    }

    @Test("A smaller size asks for a smaller budget")
    func smallerSizeSmallerBudget() {
        let full = VideoExportQuality.high.recipe(format: .mp4, sourceSize: retina,
                                                  sourceFPS: 30, size: .full)
        let small = VideoExportQuality.high.recipe(format: .mp4, sourceSize: retina,
                                                   sourceFPS: 30, size: .p720)
        #expect(small.videoBitsPerSecond < full.videoBitsPerSecond / 3)
    }

    @Test("A GIF at a size is that size, at the quality's frame rate")
    func gifAtASize() {
        let recipe = VideoExportQuality.small.recipe(format: .gif, sourceSize: retina,
                                                     sourceFPS: 30, size: .p720)
        #expect(recipe.size == CGSize(width: 1152, height: 720))
        #expect(recipe.fps == 10)
    }

    @Test("With no size chosen, every quality means what it always did")
    func noSizeIsUnchanged() {
        for format in RecordingFormat.allCases {
            for quality in VideoExportQuality.allCases {
                #expect(quality.recipe(format: format, sourceSize: retina, sourceFPS: 60)
                    == quality.recipe(format: format, sourceSize: retina, sourceFPS: 60, size: nil))
            }
        }
    }

    // MARK: - The sheet

    private func untouched(bytes: Int = 600_000_000) -> RecordingExport.Source {
        RecordingExport.Source(sourceDuration: 300, keptDuration: 300, sourceSize: retina,
                               fileBytes: bytes, isEdited: false, sourceFPS: 30, hasAudio: true)
    }

    @Test("An untouched recording is copied only at Full")
    func copiesOnlyAtFull() {
        let source = untouched()
        #expect(RecordingExport.copiesVerbatim(format: .mp4, quality: .high, source: source,
                                               size: .full))
        #expect(!RecordingExport.copiesVerbatim(format: .mp4, quality: .high, source: source,
                                                size: .p1080))
    }

    @Test("The shape line says the pixels the size lands on")
    func shapeLineSaysThePixels() {
        let line = RecordingExport.shapeLine(choice: .video(.mp4), quality: .high,
                                             source: untouched(), size: .p1080)
        #expect(line.hasPrefix("1728 × 1080 px"))
    }

    @Test("Picking a smaller size makes the weight smaller")
    func smallerSizeWeighsLess() {
        let source = untouched()
        func bytes(_ size: VideoExportSize) -> Int {
            switch RecordingExport.weight(format: .mp4, quality: .high, source: source, size: size) {
            case .exact(let b), .about(let b): return b
            default: return 0
            }
        }
        #expect(bytes(.full) == 600_000_000)
        #expect(bytes(.p1080) < bytes(.full))
        #expect(bytes(.p720) < bytes(.p1080))
        #expect(bytes(.p720) > 0)
    }

    @Test("A GIF weighed at one size is not the answer for another")
    func weighingBelongsToItsSize() {
        let weighing = RecordingExport.Weighing(format: .gif, quality: .standard,
                                                size: .p720, fraction: 1, bytes: 1000)
        #expect(weighing.answers(format: .gif, quality: .standard, size: .p720))
        #expect(!weighing.answers(format: .gif, quality: .standard, size: .full))
    }

    // MARK: - The estimate for an edited video

    @Test("What the footage costs per second is measured per pixel across every file")
    func footageRate() {
        let one = RecordingExport.Footage(bytes: 151_020, seconds: 8, pixelSize: sample)
        #expect(abs((RecordingExport.footageBytesPerSecond([one], at: sample) ?? 0) - 18_877.5) < 0.01)
        // A second file at a quarter of the pixels, costing a quarter as much
        // per second, is the same cost per pixel: the rate does not move.
        let quarter = RecordingExport.Footage(bytes: 151_020 / 4, seconds: 8,
                                              pixelSize: CGSize(width: 640, height: 400))
        #expect(abs((RecordingExport.footageBytesPerSecond([one, quarter], at: sample) ?? 0)
            - 18_877.5) < 1)
        #expect(RecordingExport.footageBytesPerSecond([], at: sample) == nil)
    }

    /// Measured 2026-09-24 in an-edited-recording-comes-out-as-a-video-walk:
    /// the eight second sample weighs 151,020 bytes; cut to four seconds and
    /// written, 74,557 bytes landed while the sheet said "about 1.8 MB".
    @Test("An edited video is estimated from what its footage costs, not the budget")
    func editedVideoFromItsFootage() {
        let rate = 151_020.0 / 8
        let source = RecordingExport.Source(sourceDuration: 4, keptDuration: 4, sourceSize: sample,
                                            fileBytes: 0, isEdited: true, sourceFPS: 30,
                                            hasAudio: true, footageBytesPerSecond: rate)
        guard case .about(let bytes) = RecordingExport.weight(format: .mp4, quality: .high,
                                                              source: source, size: .full)
        else { Issue.record("an edited video should be an estimate"); return }
        let landed = 74_557.0
        #expect(Double(bytes) < landed * 2)
        #expect(Double(bytes) > landed / 2)
    }

    @Test("Without any footage to measure, the budget is still the answer")
    func noFootageFallsBackToTheBudget() {
        let source = RecordingExport.Source(sourceDuration: 4, keptDuration: 4, sourceSize: sample,
                                            fileBytes: 0, isEdited: true, sourceFPS: 30)
        guard case .about(let bytes) = RecordingExport.weight(format: .mp4, quality: .high,
                                                              source: source, size: .full)
        else { Issue.record("expected an estimate"); return }
        let budget = VideoExportQuality.high.recipe(format: .mp4, sourceSize: sample, sourceFPS: 30,
                                                    size: .full)
            .expectedBytes(seconds: 4, hasAudio: false)
        #expect(bytes == budget)
    }

    /// Measured 2026-09-24 in export-a-video-at-1080p-walk: five minutes of
    /// the sample at 2880 × 1800 (14,130,625 bytes, 319.24 s) with its
    /// captions burned in, written at 1080p, landed at 17,881,424 bytes. The
    /// same picture without captions encodes at about half that rate: a word
    /// lighting up three times a second is a lot of picture changing.
    @Test("Captions burned into the picture are counted in the estimate")
    func captionsAreCounted() {
        func estimate(captioned: TimeInterval) -> Int {
            let source = RecordingExport.Source(sourceDuration: 319.24, keptDuration: 319.24,
                                                sourceSize: retina, fileBytes: 14_130_625,
                                                isEdited: true, sourceFPS: 30, hasAudio: true,
                                                captionedSeconds: captioned)
            guard case .about(let bytes) = RecordingExport.weight(format: .mp4, quality: .high,
                                                                  source: source, size: .p1080)
            else { return 0 }
            return bytes
        }
        let landed = 17_881_424.0
        let with = Double(estimate(captioned: 300))
        #expect(with < landed * 2)
        #expect(with > landed / 2)
        #expect(estimate(captioned: 0) < estimate(captioned: 300))
    }

    @Test("A document counts the seconds its captions are on screen")
    func captionedSecondsOfADocument() {
        var document = PhotonzDocument(canvasSize: sample)
        var clip = Layer(name: "Clip", content: .text(TextContent(string: "picture")),
                         frame: CGRect(origin: .zero, size: sample))
        clip.time = LayerTime(inMS: 0, outMS: 6_000)
        document.addLayer(clip)
        #expect(document.captionedSeconds == 0)
        document.landCaptions([
            CaptionCue(words: [TranscribedWord("One", startMS: 0, endMS: 2_000)],
                       inMS: 0, outMS: 2_000),
            CaptionCue(words: [TranscribedWord("Two", startMS: 3_000, endMS: 4_500)],
                       inMS: 3_000, outMS: 4_500),
        ], look: nil)
        #expect(abs(document.captionedSeconds - 3.5) < 0.001)
    }

    // MARK: - A document's plan

    @Test("A document written at 1080p is photographed at 1080p")
    func documentPlan() {
        let movie = DocumentVideoExport.plan(durationMS: 2000, canvasSize: retina, format: .mp4,
                                             quality: .high, size: .p1080)
        #expect(movie.size == CGSize(width: 1728, height: 1080))
        let gif = DocumentVideoExport.plan(durationMS: 2000, canvasSize: retina, format: .gif,
                                           quality: .standard, size: .p720)
        #expect(gif.size == CGSize(width: 1152, height: 720))
        #expect(gif.fps == 15)
    }
}
