// A recording whose file is replaced on disk under its own name, for the walks
// that check nothing of the old file is ever shown again
// (`a-recording-replaced-on-disk-shows-its-new-frames-walk`). Probe-only, like
// the rest of the harness.
#if PHOTONZ_PLAYTEST
import AVFoundation
import CoreText
import Foundation
import PhotonzCore
import PhotonzMedia

@MainActor
enum PlaytestChangingRecording {

    /// The two files that take turns at one path. They differ in everything a
    /// window reads off a file: picture, size, length, sound and clicks.
    enum Version: Sendable {
        case first, changed

        var colour: String { self == .first ? "red" : "blue" }
        var size: CGSize { self == .first ? CGSize(width: 1280, height: 800) : CGSize(width: 1440, height: 810) }
        var seconds: Int { self == .first ? 6 : 9 }
        var hasSound: Bool { self == .changed }
        var clicks: Int { self == .first ? 0 : 1 }
        var words: String { self == .first ? "OLD FILE" : "NEW FILE" }
    }

    enum Way { case inPlace, replaced }

    static let fileName = "Changes on disk.mp4"

    static func makeFirst(in folder: URL) async throws -> URL {
        let url = folder.appendingPathComponent(fileName)
        for leftover in [url, VideoOriginals.url(for: url), VideoEditsSidecar.url(for: url)] {
            try? FileManager.default.removeItem(at: leftover)
        }
        return try await change(to: .first, way: .replaced, in: folder)
    }

    @discardableResult
    static func change(to version: Version, way: Way, in folder: URL) async throws -> URL {
        let url = folder.appendingPathComponent(fileName)
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("changing-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let made = scratch.appendingPathComponent(fileName)
        try await write(version, to: made, scratch: scratch)

        let pointer = PointerTrackSidecar.url(for: url)
        try? FileManager.default.removeItem(at: pointer)
        if version.clicks > 0 {
            let click = PointerClick(downMS: 1000, upMS: 1100, point: CGPoint(x: 200, y: 200), button: .left)
            try PointerTrackSidecar.save(
                PointerTrack(pixelSize: version.size, samples: [PointerSample(ms: 0, x: 200, y: 200)],
                             clicks: [click]), for: url)
        }
        switch way {
        case .inPlace:
            let data = try Data(contentsOf: made)
            let handle = try FileHandle(forWritingTo: url)
            try handle.truncate(atOffset: 0)
            try handle.write(contentsOf: data)
            try handle.close()
        case .replaced:
            if FileManager.default.fileExists(atPath: url.path) {
                _ = try FileManager.default.replaceItemAt(url, withItemAt: made)
            } else {
                try FileManager.default.moveItem(at: made, to: url)
            }
        }
        return url
    }

    private static func write(_ version: Version, to url: URL, scratch: URL) async throws {
        let plan = DocumentVideoExport.plan(durationMS: version.seconds * 1000, canvasSize: version.size,
                                            format: .mp4, quality: .high)
        var mix: [AudioMixSegment] = []
        var sounds: [UUID: URL] = [:]
        if version.hasSound {
            let tone = scratch.appendingPathComponent("tone.caf")
            try writeTone(seconds: version.seconds, to: tone)
            let ref = SoundRef(durationMS: version.seconds * 1000)
            sounds[ref.id] = tone
            mix = [AudioMixSegment(layerID: UUID(), sound: ref, startMS: 0, lengthMS: ref.durationMS,
                                   sourceInMS: 0, sourceLengthMS: ref.durationMS, speedPercent: 100,
                                   ramps: [AudioGainRamp(fromMS: 0, toMS: ref.durationMS, fromGain: 1, toGain: 1)])]
        }
        let size = plan.size
        try await DocumentMovieWriter.write(plan: plan, mix: mix, soundURLs: sounds, to: url) { ms in
            picture(of: version, atMS: ms, size: size)
        }
    }

    private nonisolated static func picture(of version: Version, atMS ms: Int, size: CGSize) -> CGImage? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height),
                                      bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.setFillColor(version == .first ? CGColor(srgbRed: 0.75, green: 0.1, blue: 0.1, alpha: 1)
                             : CGColor(srgbRed: 0.1, green: 0.2, blue: 0.8, alpha: 1))
        context.fill(CGRect(origin: .zero, size: size))
        let font = CTFontCreateWithName("Helvetica-Bold" as CFString, size.height / 8, nil)
        let words = "\(version.words)  \(ms / 1000).\(ms % 1000 / 100)s"
        let line = CTLineCreateWithAttributedString(NSAttributedString(
            string: words, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font,
                                        NSAttributedString.Key(kCTForegroundColorAttributeName as String):
                                            CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)]))
        context.textPosition = CGPoint(x: size.width * 0.08, y: size.height * 0.45)
        CTLineDraw(line, context)
        // A bar crossing the picture, so a still frame says when it is from.
        context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        let along = CGFloat(ms) / CGFloat(version.seconds * 1000)
        context.fill(CGRect(x: along * size.width, y: 0, width: 12, height: size.height * 0.2))
        return context.makeImage()
    }

    private static func writeTone(seconds: Int, to url: URL) throws {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(44100 * seconds)),
              let samples = buffer.floatChannelData?[0] else { throw CocoaError(.fileWriteUnknown) }
        buffer.frameLength = buffer.frameCapacity
        for index in 0..<Int(buffer.frameLength) {
            samples[index] = 0.4 * sinf(Float(index) * 2 * .pi * 440 / 44100)
        }
        try AVAudioFile(forWriting: url, settings: format.settings).write(from: buffer)
    }

    // MARK: Looking

    /// Which file a picture came from, nil where it is neither (black).
    static func version(of image: CGImage) -> Version? {
        var pixel = [UInt8](repeating: 0, count: 4)
        pixel.withUnsafeMutableBytes { raw in
            let context = CGContext(data: raw.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                    space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            context?.interpolationQuality = .medium
            context?.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        let (red, blue) = (Int(pixel[0]), Int(pixel[2]))
        if red > blue + 40 { return .first }
        return blue > red + 40 ? .changed : nil
    }

    struct Reading { var right: [String] = []; var wrong: [String] = [] }

    static func read(_ editor: EditorState, store: CaptureStore, against version: Version) async -> Reading {
        var reading = Reading()
        func say(_ ok: Bool, _ words: String) {
            if ok { reading.right.append(words) } else { reading.wrong.append(words) }
        }
        guard let movie = editor.document?.allLayers.compactMap(\.movie).first else {
            return Reading(wrong: ["the window holds no recording"])
        }
        // Before anything has played: where the window opened, then back, then
        // forward, a step a refresh, as a hand does.
        let opened = editor.renderedImage.flatMap { Self.version(of: $0) }
        say(opened == version, "opened on a \(opened?.colour ?? "blank") picture")
        let length = editor.documentLengthMS
        editor.pauseDocument()
        let start = length * 9 / 10
        editor.scrubDocument(toMS: start)
        try? await Task.sleep(for: .seconds(0.6))
        for (name, places) in [("backwards", (0...90).map { start - $0 * start / 90 }),
                               ("forwards", (0...90).map { $0 * start / 90 })] {
            editor.beginPlayheadDrag()
            var seen: [String: Int] = [:]
            var inHand: [String: Int] = [:]
            var known: [ObjectIdentifier: Version?] = [:]
            for ms in places {
                editor.dragPlayhead(toMS: ms)
                try? await Task.sleep(for: .milliseconds(16))
                if let drawn = editor.renderedImage {
                    seen[Self.version(of: drawn)?.colour ?? "blank", default: 0] += 1
                }
                for frame in 0...movie.frameIndex(atSourceMS: movie.durationMS) {
                    guard let image = editor.store.image(for: movie.frameRef(atFrame: frame)) else { continue }
                    let key = ObjectIdentifier(image)
                    if known[key] == nil {
                        let from = Self.version(of: image)
                        known[key] = from
                        inHand[from?.colour ?? "blank", default: 0] += 1
                    }
                }
            }
            editor.endPlayheadDrag()
            let only: ([String: Int]) -> Bool = { counts in
                counts.keys.allSatisfy { $0 == version.colour } && !counts.isEmpty
            }
            say(only(seen), "scrubbing \(name) the canvas showed \(describe(seen)) pictures")
            say(only(inHand), "\(describe(inHand)) frames decoded")
        }
        // Where the hand stopped, once the sharp frame is in.
        try? await Task.sleep(for: .seconds(0.8))
        let settled = editor.renderedImage.flatMap { Self.version(of: $0) }
        say(settled == version, "at rest a \(settled?.colour ?? "blank") picture")

        var strip: [String: Int] = [:]
        for ms in stride(from: 0, to: movie.durationMS, by: 1000) {
            let picture = await ClipFilmstripFrames.shared.picture(of: movie, atSourceMS: ms)
            strip[picture.flatMap { Self.version(of: $0) }?.colour ?? "blank", default: 0] += 1
        }
        say(strip.keys.allSatisfy { $0 == version.colour }, "timeline pictures \(describe(strip))")

        let ms = movie.durationMS
        say(abs(ms - version.seconds * 1000) <= 40, "length \(ms) ms")
        say(movie.pixelSize == version.size, "size \(Int(movie.pixelSize.width)) by \(Int(movie.pixelSize.height))")
        say(movie.hasSound == version.hasSound, movie.hasSound ? "with sound" : "no sound")
        if version.hasSound, let sound = movie.soundRef {
            SoundLibrary.shared.loadWaveform(for: sound)
            for _ in 0..<30 where SoundLibrary.shared.waveform(for: sound) == nil {
                try? await Task.sleep(for: .milliseconds(100))
            }
            say(SoundLibrary.shared.waveform(for: sound) != nil, "a waveform")
        }
        let clicks = MovieLibrary.shared.pointerTrack(for: movie)?.clicks.count ?? 0
        say(clicks == version.clicks, "\(clicks) clicks")

        if PlaytestGeneratedHistory.folder != nil {
            // What bringing History up does, then its tile as it is drawn.
            store.noticeChangedRecordings()
            try? await Task.sleep(for: .seconds(0.6))
            if let entry = store.entries.first(where: { $0.fileName == fileName }) {
                var thumbnail = store.thumbnail(for: entry)
                for _ in 0..<30 where thumbnail.image == nil {
                    try? await Task.sleep(for: .milliseconds(100))
                    thumbnail = store.thumbnail(for: entry)
                }
                let from = thumbnail.image.flatMap { Self.version(of: $0) }
                say(from == version, "History thumbnail \(from?.colour ?? "blank"), "
                    + "\(Int((thumbnail.duration ?? 0).rounded())) s")
            } else {
                say(false, "no tile in History")
            }
        }
        return reading
    }

    private static func describe(_ counts: [String: Int]) -> String {
        counts.isEmpty ? "no" : counts.sorted { $0.key < $1.key }.map { "\($0.value) \($0.key)" }.joined(separator: " and ")
    }
}
#endif
