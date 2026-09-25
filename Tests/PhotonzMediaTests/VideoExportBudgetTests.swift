import AVFoundation
import CoreGraphics
import Foundation
import PhotonzCore
@testable import PhotonzMedia
import Testing

/// **The file that lands is the file the sheet promised.**
///
/// Every test here writes a real MP4 with `VideoExporter.exportMP4` and then
/// opens it again: how big its picture is, what it weighs against the budget it
/// was given, and whether writing it twice gives the same bytes. Nothing is
/// checked by asking the exporter what it thinks it did.
@Suite("A recording comes out at the size it was promised", .serialized)
struct VideoExportBudgetTests {

    static let folder = TestTone.scratch()

    /// A source recording that is not trivially compressible: a moving square
    /// on a changing background, so an encoder given a budget has something to
    /// spend it on. A flat colour would compress to nothing and the budget
    /// would never bind.
    static func busySource(seconds: Int, size: CGSize) async throws -> URL {
        let plan = DocumentVideoExport.plan(durationMS: seconds * 1000, canvasSize: size,
                                            format: .mp4, quality: .high)
        let url = folder.appendingPathComponent("busy-\(seconds)s.mp4")
        let width = Int(plan.size.width), height = Int(plan.size.height)
        let frames: DocumentMovieWriter.FrameSource = { ms in
            guard let context = CGContext(data: nil, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpace(name: CGColorSpace.sRGB)
                                              ?? CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return nil }
            let t = Double(ms) / 1000
            context.setFillColor(red: 0.1 + 0.4 * abs(sin(t)), green: 0.2, blue: 0.6, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            // Enough moving detail that the picture costs real bits.
            for row in 0..<24 {
                let shift = (t * 90 + Double(row) * 17).truncatingRemainder(dividingBy: Double(width))
                context.setFillColor(red: Double(row) / 24, green: 1 - Double(row) / 24,
                                     blue: 0.9, alpha: 1)
                context.fill(CGRect(x: shift, y: Double(row) * Double(height) / 24,
                                    width: Double(width) / 3, height: Double(height) / 24))
            }
            return context.makeImage()
        }
        try await DocumentMovieWriter.write(plan: plan, mix: [], soundURLs: [:], to: url,
                                            frames: frames)
        return url
    }

    /// A page of small text scrolling up at `pixelsPerSecond`, which is the
    /// hardest thing an ordinary screen recording asks of the encoder: every
    /// frame is new fine detail. Unlike `busySource`, this spends every budget
    /// on the row: at 1280 x 800 Standard lands around 1.1 MB against a
    /// 0.92 MB budget and Small around 0.55 MB against 0.32 MB, where the
    /// busy source lands near 0.13 MB whatever it is given.
    static func scrollingText(seconds: Int, size: CGSize,
                              pixelsPerSecond: Double = 300) async throws -> URL {
        let plan = DocumentVideoExport.plan(durationMS: seconds * 1000, canvasSize: size,
                                            format: .mp4, quality: .high)
        let url = folder.appendingPathComponent("scrolling-\(seconds)s-\(Int(size.width)).mp4")
        let width = Int(plan.size.width), height = Int(plan.size.height)
        let lineHeight = 14.0
        let frames: DocumentMovieWriter.FrameSource = { ms in
            guard let context = CGContext(data: nil, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpace(name: CGColorSpace.sRGB)
                                              ?? CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return nil }
            context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            let scrolled = Double(ms) / 1000 * pixelsPerSecond
            var line = Int(scrolled / lineHeight)
            while Double(line) * lineHeight - scrolled < Double(height) {
                let y = Double(line) * lineHeight - scrolled
                var x = 8.0, word = 0
                while x < Double(width) - 20 {
                    // A word is a run of thin strokes of uneven height, which
                    // is what a line of type looks like to an encoder.
                    let wordWidth = Double(12 + (line * 31 + word * 17) % 50)
                    var stroke = x
                    while stroke < x + wordWidth {
                        let w = Double(1 + (line + word + Int(stroke)) % 3)
                        let h = Double(6 + (line * 7 + Int(stroke)) % 5)
                        context.setFillColor(red: Double((line * 13) % 7) / 10, green: 0.1,
                                             blue: Double((word * 5) % 9) / 12, alpha: 1)
                        context.fill(CGRect(x: stroke, y: y + 10 - h, width: w, height: h))
                        stroke += w + 1.5
                    }
                    x += wordWidth + 7
                    word += 1
                }
                line += 1
            }
            return context.makeImage()
        }
        try await DocumentMovieWriter.write(plan: plan, mix: [], soundURLs: [:], to: url,
                                            frames: frames)
        return url
    }

    /// The same busy picture with a sound track on it, which is what a real
    /// screen recording is. Worth its own source: an export reads the picture
    /// and the sound out of one file and lays them into another, and getting
    /// the two out of step with each other is how an export stops dead.
    static func busySourceWithSound(seconds: Int, size: CGSize) async throws -> URL {
        let silent = try await busySource(seconds: seconds, size: size)
        let tone = folder.appendingPathComponent("tone-\(seconds)s.m4a")
        try TestTone.writeFlat(to: tone, seconds: Double(seconds))
        let url = folder.appendingPathComponent("busy-sound-\(seconds)s.mp4")
        try? FileManager.default.removeItem(at: url)
        let composition = AVMutableComposition()
        let picture = AVURLAsset(url: silent)
        let sound = AVURLAsset(url: tone)
        let length = try await picture.load(.duration)
        if let from = try await picture.loadTracks(withMediaType: .video).first,
           let lane = composition.addMutableTrack(withMediaType: .video,
                                                  preferredTrackID: kCMPersistentTrackID_Invalid) {
            try lane.insertTimeRange(CMTimeRange(start: .zero, duration: length), of: from, at: .zero)
        }
        if let from = try await sound.loadTracks(withMediaType: .audio).first,
           let lane = composition.addMutableTrack(withMediaType: .audio,
                                                  preferredTrackID: kCMPersistentTrackID_Invalid) {
            try lane.insertTimeRange(CMTimeRange(start: .zero, duration: length), of: from, at: .zero)
        }
        let session = try #require(AVAssetExportSession(asset: composition,
                                                        presetName: AVAssetExportPresetPassthrough))
        try await session.export(to: url, as: .mp4)
        return url
    }

    static func bytes(of url: URL) -> Int {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
    }

    static func wholeOf(_ url: URL, seconds: Double) -> VideoCutList {
        VideoCutList(pieces: [VideoPiece(start: 0, end: seconds)], sourceDuration: seconds)
    }

    // MARK: - The choices really are different sizes

    /// A source big enough that the choices really are three different
    /// pictures: 1920 wide comes out untouched at High, capped to 1440 at
    /// Standard and 960 at Small. A clip already smaller than every cap would
    /// make this test a measurement of encoder noise rather than of the row.
    @Test("Each choice writes the picture size it said it would, and a smaller file")
    func eachChoiceLandsAtItsOwnSize() async throws {
        let size = CGSize(width: 1920, height: 1200)
        let source = try await Self.busySource(seconds: 2, size: size)
        let cuts = Self.wholeOf(source, seconds: 2)
        var written: [VideoExportQuality: Int] = [:]
        for quality in VideoExportQuality.allCases {
            let recipe = quality.recipe(format: .mp4, sourceSize: size, sourceFPS: 30)
            let out = Self.folder.appendingPathComponent("choice-\(quality.rawValue).mp4")
            try await VideoExporter.exportMP4(from: source, to: out, cuts: cuts, crop: nil,
                                              recipe: recipe)
            let landed = await VideoExporter.orientedNaturalSize(of: out)
            #expect(landed == recipe.size,
                    "\(quality.rawValue) asked for \(recipe.size) and landed at \(landed)")
            written[quality] = Self.bytes(of: out)
        }
        let high = try #require(written[.high])
        let standard = try #require(written[.standard])
        let small = try #require(written[.small])
        #expect(small < standard, "Small is \(small) bytes and Standard is \(standard)")
        #expect(small < high, "Small is \(small) bytes and High is \(high)")
        // Standard is deliberately NOT asserted smaller than High. On material
        // that spends neither budget, the only difference between them is the
        // picture size, and a smaller picture is not always a smaller file:
        // resampling sharp edges makes the pixels that are left harder to
        // compress. On this clip 1440 x 900 came out 101,244 bytes against
        // 1920 x 1200's 99,740. Standard earns its place on a big or a busy
        // recording, where its cap and its budget both bite; on a small easy
        // one the sheet says what it will weigh and that is the honest answer.
        _ = high
    }

    // MARK: - The number under the format is close to the file

    @Test("What lands on an easy recording is inside the budget it was given")
    func theBudgetIsACeiling() async throws {
        let size = CGSize(width: 1280, height: 800)
        let source = try await Self.busySource(seconds: 3, size: size)
        let recipe = VideoExportQuality.standard.recipe(format: .mp4, sourceSize: size,
                                                        sourceFPS: 30)
        let out = Self.folder.appendingPathComponent("budget.mp4")
        try await VideoExporter.exportMP4(from: source, to: out, cuts: Self.wholeOf(source, seconds: 3),
                                          crop: nil, recipe: recipe)
        let landed = Self.bytes(of: out)
        let promised = recipe.expectedBytes(seconds: 3, hasAudio: false)
        // A budget is a ceiling, so the file must not sail past it. This source
        // lands far UNDER it, around 133 KB of a 922 KB budget: the encoder has
        // reached its own idea of good enough and stopped spending. So nothing
        // here compares two budgets on it. Both Standard and Small land near
        // that floor, 133 KB and 121 KB when the machine is quiet, and with
        // other encodes running beside them Standard came out anywhere from
        // 113 KB to 127 KB, under Small about a third of the time. Which is
        // smaller there is the encoder's mood, not the recipe; the comparison
        // lives in the next test, on a picture that spends its budget.
        #expect(landed <= Int(Double(promised) * 1.25),
                "\(landed) bytes landed against a \(promised) byte budget")
    }

    /// **A smaller budget really does write a smaller file**, which is what the
    /// Quality row promises, checked where the budget is what decides the size.
    ///
    /// Each choice is written three times and the lightest of each is compared.
    /// The system's H.264 encoder does not write the same size twice when other
    /// encodes share the machine, and here it never came out LIGHTER for it:
    /// with six other encodes running beside this, Standard landed anywhere
    /// from 1.1 MB to 3.1 MB and Small from 0.9 MB to 1.8 MB, once heavier than
    /// Standard, where a quiet machine writes 1.1 MB and 0.55 MB every time.
    /// The lightest of three is the one the encoder wrote closest to quiet.
    @Test("On a recording busy enough to spend it, a smaller budget writes a smaller file")
    func aSmallerBudgetWritesASmallerFile() async throws {
        let size = CGSize(width: 1280, height: 800)
        let source = try await Self.scrollingText(seconds: 3, size: size)
        let cuts = Self.wholeOf(source, seconds: 3)
        // Both at the recording's own size, the way the sheet's Size row pins
        // it, so the two files are the same picture at the same frame rate and
        // the ONLY thing between them is the budget. Without that, Small's
        // smaller picture makes it the smaller file even with no budget at all.
        let standard = VideoExportQuality.standard.recipe(format: .mp4, sourceSize: size,
                                                          sourceFPS: 30, size: .full)
        let small = VideoExportQuality.small.recipe(format: .mp4, sourceSize: size,
                                                    sourceFPS: 30, size: .full)
        #expect(standard.size == small.size && standard.fps == small.fps)
        var standardBytes: [Int] = [], smallBytes: [Int] = []
        for pass in 0..<3 {
            for (recipe, name) in [(standard, "standard"), (small, "small")] {
                let out = Self.folder.appendingPathComponent("spent-\(name)-\(pass).mp4")
                try await VideoExporter.exportMP4(from: source, to: out, cuts: cuts, crop: nil,
                                                  recipe: recipe)
                if name == "standard" {
                    standardBytes.append(Self.bytes(of: out))
                } else {
                    smallBytes.append(Self.bytes(of: out))
                }
            }
        }
        let lightestStandard = try #require(standardBytes.min())
        let lightestSmall = try #require(smallBytes.min())
        // The encoder is not sitting on its own floor here: Standard spends at
        // least half of what it was allowed, so the budget is what is deciding
        // the size and comparing two of them means something.
        let allowed = standard.expectedBytes(seconds: 3, hasAudio: false)
        let floor = "Standard wrote \(standardBytes) bytes against \(allowed) allowed: "
            + "this picture no longer spends its budget, so the next line proves nothing"
        #expect(lightestStandard >= allowed / 2, "\(floor)")
        #expect(lightestSmall < lightestStandard,
                "Small wrote \(smallBytes) bytes and Standard \(standardBytes)")
    }

    // MARK: - The same recording twice

    /// **What "the same file" honestly means here, measured rather than hoped.**
    ///
    /// Two exports of one recording come out the same length to within a
    /// fraction of a percent, the same duration, the same picture size, and
    /// showing the same picture to the eye. They are NOT byte for byte the
    /// same, and no setting available here makes them so:
    ///
    /// - The system's H.264 encoder decides differently from run to run under
    ///   different load. Three pairs of exports of one three second clip came
    ///   out 52,390/52,766, then equal, then 54,902/52,390 bytes, with the
    ///   picture a level or two different in eight bit terms. Requiring the
    ///   hardware encoder does not change that: it wanders just as far when
    ///   other encodes share it.
    /// - Turning frame reordering off makes the short case reproducible, and
    ///   more than doubles the file: 130,349 bytes becomes 278,280. That is the
    ///   wrong trade for a feature about sending files, and on the eight second
    ///   sample it did not hold anyway.
    /// - The one path that IS byte for byte identical is the one most exports
    ///   take: an untouched recording at the top choice is a file copy, and the
    ///   walk checks that separately and strictly.
    ///
    /// So this test measures what is true, and the Export sheet says "about".
    @Test("Exporting the same recording twice gives the same file to look at")
    func twiceIsTheSameFile() async throws {
        let size = CGSize(width: 640, height: 400)
        let source = try await Self.busySource(seconds: 2, size: size)
        let recipe = VideoExportQuality.standard.recipe(format: .mp4, sourceSize: size,
                                                        sourceFPS: 30)
        let cuts = Self.wholeOf(source, seconds: 2)
        let first = Self.folder.appendingPathComponent("twice-1.mp4")
        let second = Self.folder.appendingPathComponent("twice-2.mp4")
        try await VideoExporter.exportMP4(from: source, to: first, cuts: cuts, crop: nil,
                                          recipe: recipe)
        try await VideoExporter.exportMP4(from: source, to: second, cuts: cuts, crop: nil,
                                          recipe: recipe)
        let one = Self.bytes(of: first), two = Self.bytes(of: second)
        let drift = abs(Double(one - two)) / Double(max(1, one))
        // A quarter. On a quiet machine the two come out the same size to the
        // byte. With other encodes running beside them they do not, and it is
        // the system encoder's doing rather than anything in the recipe: the
        // whole test suite beside it moved them up to seven per cent apart
        // (0.064 and 0.071 on 2026-09-24 and 25), and six encodes at once moved
        // them nineteen. The size a person is told for an MP4 comes from its
        // budget, not from writing it, so this drift never reaches the sheet,
        // which says "about". What this guards against is a file that changes
        // size by a lot on you, a dropped stretch or a lost budget, not the
        // encoder's own wobble; the length and picture checks below are exact.
        #expect(drift < 0.25,
                "two exports of one recording came out \(one) and \(two) bytes")
        #expect(await VideoExporter.orientedNaturalSize(of: first)
                == VideoExporter.orientedNaturalSize(of: second))
        let ranFirst = try await AVURLAsset(url: first).load(.duration).seconds
        let ranSecond = try await AVURLAsset(url: second).load(.duration).seconds
        #expect(abs(ranFirst - ranSecond) < 0.05)
        // And they show the same picture, to the eye: a couple of levels out of
        // 255 is what the encoder's own decisions move, and nothing a person
        // sees.
        for at in [0.2, 1.0, 1.8] {
            let left = try await Self.colour(of: first, atSeconds: at)
            let right = try await Self.colour(of: second, atSeconds: at)
            let apart = zip(left, right).map { abs(Int($0) - Int($1)) }.max() ?? 0
            #expect(apart <= 6,
                    "the two exports are \(apart) levels apart at \(at)s: \(left) and \(right)")
        }
    }

    /// What colour the written file shows at a moment, squeezed into one pixel.
    static func colour(of url: URL, atSeconds seconds: Double) async throws -> [UInt8] {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let frame = try await generator.image(
            at: CMTime(seconds: seconds, preferredTimescale: 600)).image
        var pixel = [UInt8](repeating: 0, count: 4)
        pixel.withUnsafeMutableBytes { bytes in
            guard let context = CGContext(data: bytes.baseAddress, width: 1, height: 1,
                                          bitsPerComponent: 8, bytesPerRow: 4,
                                          space: CGColorSpace(name: CGColorSpace.sRGB)
                                              ?? CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return }
            context.interpolationQuality = .low
            context.draw(frame, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        return pixel
    }

    // MARK: - A recording with sound on it

    @Test("A recording with sound on it exports all the way through, sound and all")
    func aRecordingWithSoundFinishes() async throws {
        let size = CGSize(width: 1280, height: 800)
        let source = try await Self.busySourceWithSound(seconds: 4, size: size)
        let recipe = VideoExportQuality.standard.recipe(format: .mp4, sourceSize: size,
                                                        sourceFPS: 30)
        let out = Self.folder.appendingPathComponent("with-sound.mp4")
        try await VideoExporter.exportMP4(from: source, to: out,
                                          cuts: Self.wholeOf(source, seconds: 4), crop: nil,
                                          recipe: recipe)
        let asset = AVURLAsset(url: out)
        let ran = try await asset.load(.duration).seconds
        #expect(abs(ran - 4) < 0.3, "the file runs \(ran)s, not 4s: it stopped part way")
        #expect(try await !asset.loadTracks(withMediaType: .audio).isEmpty)
        #expect(await VideoExporter.orientedNaturalSize(of: out) == recipe.size)
    }

    // MARK: - It still plays

    @Test("The file plays: H.264 in an MP4 that the system will decode")
    func theFilePlays() async throws {
        let size = CGSize(width: 960, height: 600)
        let source = try await Self.busySource(seconds: 2, size: size)
        let recipe = VideoExportQuality.small.recipe(format: .mp4, sourceSize: size, sourceFPS: 30)
        let out = Self.folder.appendingPathComponent("plays.mp4")
        try await VideoExporter.exportMP4(from: source, to: out,
                                          cuts: Self.wholeOf(source, seconds: 2), crop: nil,
                                          recipe: recipe)
        let asset = AVURLAsset(url: out)
        #expect(try await asset.load(.isPlayable))
        let track = try #require(try await asset.loadTracks(withMediaType: .video).first)
        let descriptions = try await track.load(.formatDescriptions)
        let codec = try #require(descriptions.first.map { CMFormatDescriptionGetMediaSubType($0) })
        // 'avc1' — H.264, the one format every chat app, browser and phone
        // decodes without being asked twice.
        #expect(codec == kCMVideoCodecType_H264)
        let seconds = try await asset.load(.duration).seconds
        #expect(abs(seconds - 2) < 0.2)
    }
}
