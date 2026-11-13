import AVFoundation
import CoreGraphics
import CoreText
import Foundation
import PhotonzCore

// The recordings the reference edit is cut from (`ReferenceEdit.swift`, task
// `a-long-reference-edit-opens-in-the-probe-in-one`).
//
// Video files are never committed, so the footage is drawn and encoded here,
// once per machine, and kept: a minute each of four screen recordings at
// 3456 x 2234 and 60 frames a second, each with the moving content a real one
// has (a page scrolling, code being typed, windows sliding, a dashboard being
// clicked through, the pointer travelling over all of it) and a voice-like
// sound under it, plus two minutes of music. A recipe version in the folder's
// name (`ReferenceEdit.footageFolderName`) makes a new recipe write new files.
//
// The drawing is plain shapes and text, not a likeness of any app: it only has
// to give the decoder what a screen recording gives it, large flat areas, sharp
// text, and a few things moving.

public enum ReferenceFootage {

    /// What to write: the size, rate and lengths. `full` is the reference
    /// edit's own; a test writes something small and short.
    public struct Spec: Hashable, Sendable {
        public var size: CGSize
        public var framesPerSecond: Int
        public var recordingMS: Int
        public var musicMS: Int

        public init(size: CGSize, framesPerSecond: Int, recordingMS: Int, musicMS: Int) {
            self.size = size
            self.framesPerSecond = framesPerSecond
            self.recordingMS = recordingMS
            self.musicMS = musicMS
        }

        public static let full = Spec(size: ReferenceEdit.pixelSize,
                                      framesPerSecond: ReferenceEdit.framesPerSecond,
                                      recordingMS: ReferenceEdit.footageLengthMS,
                                      musicMS: ReferenceEdit.musicLengthMS)
    }

    public enum Failure: Error, CustomStringConvertible {
        case wouldNotWrite(String)
        public var description: String {
            switch self {
            case .wouldNotWrite(let why): "The reference footage could not be written: \(why)"
            }
        }
    }

    /// Every recording and the music the edit names, in `folder`'s footage
    /// folder, written first where missing. The answer says where each file
    /// is, by the id the document plays it under.
    public static func ensure(in folder: URL, spec: Spec = .full,
                              progress: (@Sendable (String) -> Void)? = nil) async throws -> [UUID: URL] {
        let home = folder.appendingPathComponent(ReferenceEdit.footageFolderName, isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        var files: [UUID: URL] = [:]
        try await withThrowingTaskGroup(of: Void.self) { group in
            for footage in ReferenceEdit.footage {
                let url = home.appendingPathComponent(footage.fileName)
                files[footage.movie.id] = url
                guard !FileManager.default.fileExists(atPath: url.path) else { continue }
                group.addTask {
                    progress?("writing \(footage.fileName)")
                    try await writeRecording(footage, spec: spec, to: url)
                    progress?("wrote \(footage.fileName)")
                }
            }
            let music = home.appendingPathComponent(ReferenceEdit.music.fileName)
            files[ReferenceEdit.music.sound.id] = music
            if !FileManager.default.fileExists(atPath: music.path) {
                group.addTask {
                    try writeMusic(lengthMS: spec.musicMS, to: music)
                    progress?("wrote \(ReferenceEdit.music.fileName)")
                }
            }
            try await group.waitForAll()
        }
        return files
    }

    // MARK: - A recording

    /// One recording: its picture encoded, its voice written beside it, and
    /// the two put into one file. Written under a temporary name and moved
    /// into place, so a run stopped half way leaves nothing that looks done.
    public static func writeRecording(_ footage: ReferenceEdit.Footage, spec: Spec, to url: URL) async throws {
        let folder = url.deletingLastPathComponent()
        let stem = ".\(url.deletingPathExtension().lastPathComponent)-\(UUID().uuidString)"
        let picture = folder.appendingPathComponent(stem + "-picture.mov")
        let voice = folder.appendingPathComponent(stem + "-voice.m4a")
        let merged = folder.appendingPathComponent(stem + ".mov")
        defer {
            for leftover in [picture, voice, merged] { try? FileManager.default.removeItem(at: leftover) }
        }
        try await writePicture(footage, spec: spec, to: picture)
        try writeVoice(seed: UInt64(footage.index + 1), lengthMS: spec.recordingMS, to: voice)
        try await merge(picture: picture, voice: voice, into: merged)
        try? FileManager.default.removeItem(at: url)
        try FileManager.default.moveItem(at: merged, to: url)
    }

    /// One frame of a recording, drawn the way it is encoded.
    public static func frame(_ footage: ReferenceEdit.Footage, spec: Spec, atMS ms: Int) -> CGImage? {
        let scene = SceneDrawing(footage: footage, size: spec.size)
        guard let context = CGContext(data: nil, width: Int(spec.size.width), height: Int(spec.size.height),
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                                          | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return nil }
        scene.draw(in: context, atSeconds: Double(ms) / 1000)
        return context.makeImage()
    }

    static func writePicture(_ footage: ReferenceEdit.Footage, spec: Spec, to url: URL) async throws {
        let width = Int(spec.size.width), height = Int(spec.size.height)
        let (writer, made) = try await HardwareEncoder.start(
            at: url,
            wouldNotStart: { Failure.wouldNotWrite($0?.localizedDescription ?? "the encoder would not start") }
        ) { hardware -> (AVAssetWriter, (AVAssetWriterInput, AVAssetWriterInputPixelBufferAdaptor)) in
            let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
            var settings: [String: Any] = [
                // What the Mac's own screen recorder writes.
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: width,
                AVVideoHeightKey: height,
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: max(2_000_000, width * height * 3),
                    AVVideoExpectedSourceFrameRateKey: spec.framesPerSecond,
                    AVVideoMaxKeyFrameIntervalKey: spec.framesPerSecond * 2,
                    AVVideoAllowFrameReorderingKey: true,
                    AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                ] as [String: Any],
            ]
            if hardware { settings[AVVideoEncoderSpecificationKey] = HardwareEncoder.required }
            let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
            input.expectsMediaDataInRealTime = false
            let adaptor = AVAssetWriterInputPixelBufferAdaptor(
                assetWriterInput: input,
                sourcePixelBufferAttributes: [
                    kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
                    kCVPixelBufferWidthKey as String: width,
                    kCVPixelBufferHeightKey as String: height,
                    kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
                ])
            writer.add(input)
            return (writer, (input, adaptor))
        }
        let (input, adaptor) = made
        writer.startSession(atSourceTime: .zero)
        let scene = SceneDrawing(footage: footage, size: spec.size)
        let frames = spec.recordingMS * spec.framesPerSecond / 1000
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        for n in 0..<frames {
            while !input.isReadyForMoreMediaData {
                if writer.status == .failed { throw Failure.wouldNotWrite(writer.error?.localizedDescription ?? "failed") }
                try await Task.sleep(for: .milliseconds(2))
            }
            guard let pool = adaptor.pixelBufferPool else { throw Failure.wouldNotWrite("no picture buffers") }
            var made: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &made)
            guard let buffer = made else { throw Failure.wouldNotWrite("no picture buffer") }
            CVPixelBufferLockBaseAddress(buffer, [])
            if let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: width, height: height,
                                       bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                                       space: space,
                                       bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                                           | CGBitmapInfo.byteOrder32Little.rawValue) {
                scene.draw(in: context, atSeconds: Double(n) / Double(spec.framesPerSecond))
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            let time = CMTime(value: CMTimeValue(n), timescale: CMTimeScale(spec.framesPerSecond))
            guard adaptor.append(buffer, withPresentationTime: time) else {
                throw Failure.wouldNotWrite(writer.error?.localizedDescription ?? "a frame was refused")
            }
        }
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else {
            throw Failure.wouldNotWrite(writer.error?.localizedDescription ?? "the picture did not finish")
        }
    }

    static func merge(picture: URL, voice: URL, into url: URL) async throws {
        let pictureAsset = AVURLAsset(url: picture)
        let voiceAsset = AVURLAsset(url: voice)
        guard let videoTrack = try await pictureAsset.loadTracks(withMediaType: .video).first,
              let voiceTrack = try await voiceAsset.loadTracks(withMediaType: .audio).first
        else { throw Failure.wouldNotWrite("a track was missing") }
        let length = try await pictureAsset.load(.duration)
        let heard = try await voiceAsset.load(.duration)
        let composition = AVMutableComposition()
        guard let video = composition.addMutableTrack(withMediaType: .video,
                                                      preferredTrackID: kCMPersistentTrackID_Invalid),
              let audio = composition.addMutableTrack(withMediaType: .audio,
                                                      preferredTrackID: kCMPersistentTrackID_Invalid)
        else { throw Failure.wouldNotWrite("no composition tracks") }
        try video.insertTimeRange(CMTimeRange(start: .zero, duration: length), of: videoTrack, at: .zero)
        try audio.insertTimeRange(CMTimeRange(start: .zero, duration: CMTimeMinimum(length, heard)),
                                  of: voiceTrack, at: .zero)
        guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough)
        else { throw Failure.wouldNotWrite("no export session") }
        try await session.export(to: url, as: .mov)
    }

    // MARK: - Sound

    static let sampleRate = 48_000.0

    /// Something that sounds like a person talking from across a room:
    /// syllables of a voiced buzz with a vowel's resonances, words of a few
    /// syllables, pauses between sentences. Its rhythm and loudness are what
    /// a mix, a meter and a waveform see; nobody has to understand it.
    static func writeVoice(seed: UInt64, lengthMS: Int, to url: URL) throws {
        var random = Pseudo(seed: seed &* 0x2545_F491_4F6C_DD1D)
        let total = Int(sampleRate * Double(lengthMS) / 1000)
        var samples = [Float](repeating: 0, count: total)
        var at = Int(sampleRate * 0.3)
        let pitchBase = 105 + Double(seed % 4) * 25
        while at < total {
            let words = 4 + random.below(8)
            for _ in 0..<words {
                let syllables = 1 + random.below(3)
                for _ in 0..<syllables {
                    let length = Int(sampleRate * (0.09 + Double(random.below(120)) / 1000))
                    let pitch = pitchBase * (0.85 + Double(random.below(30)) / 100)
                    let formants = [(300.0 + Double(random.below(500)), 0.6),
                                    (900.0 + Double(random.below(1400)), 0.35)]
                    for i in 0..<length where at + i < total {
                        let t = Double(i) / sampleRate
                        let envelope = sin(Double.pi * Double(i) / Double(length))
                        var value = 0.0
                        var harmonic = 1.0
                        while harmonic * pitch < 3200 {
                            let f = harmonic * pitch
                            var gain = 0.0
                            for (centre, weight) in formants {
                                let d = (f - centre) / 180
                                gain += weight * exp(-d * d)
                            }
                            value += gain * sin(2 * .pi * f * t) / harmonic.squareRoot()
                            harmonic += 1
                        }
                        samples[at + i] += Float(0.22 * envelope * value)
                    }
                    at += length
                }
                at += Int(sampleRate * (0.04 + Double(random.below(90)) / 1000))
            }
            at += Int(sampleRate * (0.3 + Double(random.below(600)) / 1000))
        }
        try writeAAC(samples, channels: 1, to: url)
    }

    /// Two minutes of quiet music: a slow progression of chords on a soft
    /// pad, a bass under it, a light tick on the beat.
    static func writeMusic(lengthMS: Int, to url: URL) throws {
        let total = Int(sampleRate * Double(lengthMS) / 1000)
        var samples = [Float](repeating: 0, count: total)
        // A minor, F, C, G, two seconds each.
        let chords: [[Double]] = [[220, 261.63, 329.63], [174.61, 220, 261.63],
                                  [130.81, 164.81, 196], [196, 246.94, 293.66]]
        let beat = 0.5
        var random = Pseudo(seed: 0x00C0_FFEE)
        for i in 0..<total {
            let t = Double(i) / sampleRate
            let chord = chords[Int(t / 2) % chords.count]
            let within = t.truncatingRemainder(dividingBy: 2)
            let swell = min(1, within / 0.3) * (0.75 + 0.25 * cos(.pi * within))
            var value = 0.0
            for f in chord {
                value += 0.12 * sin(2 * .pi * f * t) + 0.04 * sin(2 * .pi * f * 2.003 * t)
            }
            value *= swell
            value += 0.18 * sin(2 * .pi * chord[0] / 2 * t) * exp(-within.truncatingRemainder(dividingBy: 1) * 3)
            let sinceBeat = t.truncatingRemainder(dividingBy: beat)
            if sinceBeat < 0.03 {
                value += 0.08 * (Double(random.below(2000)) / 1000 - 1) * (1 - sinceBeat / 0.03)
            }
            samples[i] = Float(value * 0.8)
        }
        try writeAAC(samples, channels: 1, to: url)
    }

    static func writeAAC(_ samples: [Float], channels: Int, to url: URL) throws {
        try? FileManager.default.removeItem(at: url)
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: AVAudioChannelCount(channels))
        else { throw Failure.wouldNotWrite("no audio format") }
        let file = try AVAudioFile(forWriting: url, settings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channels,
            AVEncoderBitRateKey: 96_000,
        ], commonFormat: .pcmFormatFloat32, interleaved: false)
        let chunk = 48_000
        var at = 0
        while at < samples.count {
            let count = min(chunk, samples.count - at)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count)),
                  let channel = buffer.floatChannelData?[0] else { throw Failure.wouldNotWrite("no audio buffer") }
            buffer.frameLength = AVAudioFrameCount(count)
            samples.withUnsafeBufferPointer { source in
                if let base = source.baseAddress { channel.update(from: base + at, count: count) }
            }
            try file.write(from: buffer)
            at += count
        }
    }
}

// MARK: - Drawing a screen

/// A small seeded generator, the same numbers on every machine.
struct Pseudo {
    private var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 0x9E37_79B9 : seed }
    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
    mutating func below(_ n: Int) -> Int { n <= 1 ? 0 : Int(next() % UInt64(n)) }
}

/// What one recording looks like at a moment. Everything is laid out in the
/// screen's points (half its pixels), top-left origin, and the parts that do
/// not move are drawn once into pictures and reused every frame.
final class SceneDrawing: @unchecked Sendable {
    let footage: ReferenceEdit.Footage
    let size: CGSize
    /// Pixels per point.
    let scale: CGFloat
    /// The screen in points.
    let points: CGSize
    let desktop: CGImage?
    let page: CGImage?
    let pageHeight: CGFloat
    let window: CGRect
    let accent: CGColor

    init(footage: ReferenceEdit.Footage, size: CGSize) {
        self.footage = footage
        self.size = size
        scale = size.width / (ReferenceEdit.pixelSize.width / 2)
        points = CGSize(width: size.width / scale, height: size.height / scale)
        let hues: [CGFloat] = [0.58, 0.08, 0.33, 0.78]
        let hue = hues[footage.index % hues.count]
        accent = Self.color(hue: hue, saturation: 0.65, brightness: 0.85)
        window = CGRect(x: points.width * 0.12, y: points.height * 0.1,
                        width: points.width * 0.7, height: points.height * 0.78)
        desktop = Self.drawDesktop(size: size, scale: scale, hue: hue, seed: UInt64(footage.index + 7))
        let content = CGSize(width: window.width - 32, height: window.height * 4)
        pageHeight = content.height
        page = Self.drawPage(footage.scene, size: content, scale: scale, accent: accent,
                             seed: UInt64(footage.index + 11))
    }

    static func color(hue: CGFloat, saturation: CGFloat, brightness: CGFloat, alpha: CGFloat = 1) -> CGColor {
        let h = (hue.truncatingRemainder(dividingBy: 1) + 1).truncatingRemainder(dividingBy: 1) * 6
        let c = brightness * saturation
        let x = c * (1 - abs(h.truncatingRemainder(dividingBy: 2) - 1))
        let m = brightness - c
        let (r, g, b): (CGFloat, CGFloat, CGFloat)
        switch Int(h) {
        case 0: (r, g, b) = (c, x, 0)
        case 1: (r, g, b) = (x, c, 0)
        case 2: (r, g, b) = (0, c, x)
        case 3: (r, g, b) = (0, x, c)
        case 4: (r, g, b) = (x, 0, c)
        default: (r, g, b) = (c, 0, x)
        }
        return CGColor(srgbRed: r + m, green: g + m, blue: b + m, alpha: alpha)
    }

    static func context(_ size: CGSize) -> CGContext? {
        CGContext(data: nil, width: max(1, Int(size.width)), height: max(1, Int(size.height)),
                  bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
    }

    /// Points, top-left origin.
    static func flip(_ context: CGContext, height: CGFloat, scale: CGFloat) {
        context.translateBy(x: 0, y: height)
        context.scaleBy(x: scale, y: -scale)
    }

    static func drawDesktop(size: CGSize, scale: CGFloat, hue: CGFloat, seed: UInt64) -> CGImage? {
        guard let context = context(size) else { return nil }
        let points = CGSize(width: size.width / scale, height: size.height / scale)
        flip(context, height: size.height, scale: scale)
        let colours = [color(hue: hue, saturation: 0.55, brightness: 0.35),
                       color(hue: hue + 0.12, saturation: 0.6, brightness: 0.6)]
        if let gradient = CGGradient(colorsSpace: nil, colors: colours as CFArray, locations: [0, 1]) {
            context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: points.width, y: points.height), options: [])
        }
        var random = Pseudo(seed: seed)
        for _ in 0..<6 {
            let r = CGFloat(120 + random.below(260))
            let centre = CGPoint(x: CGFloat(random.below(Int(points.width))), y: CGFloat(random.below(Int(points.height))))
            context.setFillColor(color(hue: hue + CGFloat(random.below(30)) / 100, saturation: 0.5, brightness: 0.8, alpha: 0.12))
            context.fillEllipse(in: CGRect(x: centre.x - r, y: centre.y - r, width: 2 * r, height: 2 * r))
        }
        // A menu bar and a dock, as every Mac screen has.
        context.setFillColor(CGColor(gray: 0.1, alpha: 0.55))
        context.fill(CGRect(x: 0, y: 0, width: points.width, height: 24))
        drawWords(context, ["File", "Edit", "View", "Window", "Help"], at: CGPoint(x: 44, y: 17), size: 13,
                  colour: CGColor(gray: 1, alpha: 0.9), gap: 22)
        let dock = CGRect(x: points.width * 0.3, y: points.height - 70, width: points.width * 0.4, height: 62)
        context.setFillColor(CGColor(gray: 1, alpha: 0.18))
        context.addPath(CGPath(roundedRect: dock, cornerWidth: 18, cornerHeight: 18, transform: nil))
        context.fillPath()
        for i in 0..<12 {
            context.setFillColor(color(hue: CGFloat(i) / 12, saturation: 0.6, brightness: 0.9))
            let tile = CGRect(x: dock.minX + 12 + CGFloat(i) * (dock.width - 24) / 12, y: dock.minY + 8, width: 44, height: 44)
            context.addPath(CGPath(roundedRect: tile, cornerWidth: 10, cornerHeight: 10, transform: nil))
            context.fillPath()
        }
        return context.makeImage()
    }

    static func words(_ random: inout Pseudo, count: Int) -> [String] {
        let syllables = ["ta", "ri", "mo", "len", "sa", "vo", "ki", "ner", "pa", "lu", "dor", "e", "an", "ste", "qui", "ra"]
        return (0..<count).map { _ in
            (0..<(1 + random.below(3))).map { _ in syllables[random.below(syllables.count)] }.joined()
        }
    }

    static func drawWords(_ context: CGContext, _ words: [String], at origin: CGPoint, size: CGFloat,
                          colour: CGColor, gap: CGFloat = 7, mono: Bool = false) {
        let font = CTFontCreateWithName((mono ? "Menlo" : "Helvetica Neue") as CFString, size, nil)
        var x = origin.x
        for word in words {
            let attributed = NSAttributedString(string: word, attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): colour,
            ])
            let line = CTLineCreateWithAttributedString(attributed)
            context.saveGState()
            context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
            context.textPosition = CGPoint(x: x, y: origin.y)
            CTLineDraw(line, context)
            context.restoreGState()
            x += CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil)) + gap
        }
    }

    /// The tall content inside the window, which a scene scrolls or reveals.
    static func drawPage(_ scene: ReferenceEdit.Scene, size: CGSize, scale: CGFloat, accent: CGColor,
                         seed: UInt64) -> CGImage? {
        guard let context = context(CGSize(width: size.width * scale, height: size.height * scale)) else { return nil }
        flip(context, height: size.height * scale, scale: scale)
        var random = Pseudo(seed: seed)
        let dark = scene == .typingCode
        context.setFillColor(dark ? CGColor(srgbRed: 0.11, green: 0.12, blue: 0.15, alpha: 1) : CGColor(gray: 0.98, alpha: 1))
        context.fill(CGRect(origin: .zero, size: size))
        var y: CGFloat = 40
        var lineNumber = 1
        while y < size.height - 40 {
            switch scene {
            case .typingCode:
                let indent = CGFloat(random.below(4)) * 28
                drawWords(context, ["\(lineNumber)"], at: CGPoint(x: 14, y: y), size: 15,
                          colour: CGColor(gray: 0.45, alpha: 1), mono: true)
                let tokens = words(&random, count: 2 + random.below(6))
                let colours = [CGColor(srgbRed: 0.98, green: 0.47, blue: 0.62, alpha: 1),
                               CGColor(srgbRed: 0.55, green: 0.85, blue: 0.98, alpha: 1),
                               CGColor(gray: 0.9, alpha: 1),
                               CGColor(srgbRed: 0.85, green: 0.8, blue: 0.5, alpha: 1)]
                var x = 70 + indent
                for token in tokens {
                    drawWords(context, [token], at: CGPoint(x: x, y: y), size: 15,
                              colour: colours[random.below(colours.count)], mono: true)
                    x += CGFloat(token.count) * 9 + 9
                }
                y += 24
                lineNumber += 1
            case .dashboard:
                // Rows of cards with numbers and little bars.
                let cards = 3
                let width = (size.width - 40 * CGFloat(cards + 1)) / CGFloat(cards)
                for c in 0..<cards {
                    let card = CGRect(x: 40 + CGFloat(c) * (width + 40), y: y, width: width, height: 180)
                    context.setFillColor(CGColor(gray: 1, alpha: 1))
                    context.addPath(CGPath(roundedRect: card, cornerWidth: 14, cornerHeight: 14, transform: nil))
                    context.fillPath()
                    context.setStrokeColor(CGColor(gray: 0.85, alpha: 1))
                    context.addPath(CGPath(roundedRect: card, cornerWidth: 14, cornerHeight: 14, transform: nil))
                    context.strokePath()
                    drawWords(context, words(&random, count: 2), at: CGPoint(x: card.minX + 20, y: card.minY + 34),
                              size: 15, colour: CGColor(gray: 0.4, alpha: 1))
                    drawWords(context, ["\(random.below(90_000) + 1000)"], at: CGPoint(x: card.minX + 20, y: card.minY + 84),
                              size: 34, colour: CGColor(gray: 0.1, alpha: 1))
                    for b in 0..<10 {
                        let h = CGFloat(10 + random.below(60))
                        context.setFillColor(accent)
                        context.fill(CGRect(x: card.minX + 20 + CGFloat(b) * 22, y: card.maxY - 16 - h, width: 14, height: h))
                    }
                }
                y += 220
            case .scrollingPage, .slidingWindows:
                if random.below(7) == 0 {
                    drawWords(context, words(&random, count: 3 + random.below(4)), at: CGPoint(x: 48, y: y + 10),
                              size: 30, colour: CGColor(gray: 0.08, alpha: 1), gap: 10)
                    y += 56
                } else if random.below(9) == 0 {
                    context.setFillColor(accent.copy(alpha: 0.25) ?? accent)
                    context.fill(CGRect(x: 48, y: y, width: size.width - 96, height: 220))
                    y += 250
                } else {
                    drawWords(context, words(&random, count: 9 + random.below(6)), at: CGPoint(x: 48, y: y),
                              size: 17, colour: CGColor(gray: 0.2, alpha: 1))
                    y += 28
                }
            }
        }
        return context.makeImage()
    }

    /// The screen at `seconds` into the recording.
    func draw(in context: CGContext, atSeconds t: Double) {
        let pixels = CGRect(origin: .zero, size: size)
        context.saveGState()
        if let desktop { context.draw(desktop, in: pixels) }
        Self.flip(context, height: size.height, scale: scale)
        context.interpolationQuality = .low

        var frame = window
        var scroll: CGFloat = 0
        var revealed: CGFloat = .infinity
        switch footage.scene {
        case .scrollingPage:
            // Reading down a page: a scroll, a pause, another scroll.
            let step = floor(t / 3)
            let within = min(1, (t - step * 3) / 0.8)
            let eased = 0.5 - 0.5 * cos(.pi * within)
            scroll = CGFloat((step + eased) * 260)
        case .typingCode:
            // A line typed every 0.6 seconds, the view following the caret.
            revealed = CGFloat(t / 0.6) * 24 + 60
            scroll = max(0, revealed - frame.height * 0.7)
        case .slidingWindows:
            // The window sliding across and back while the page drifts.
            frame.origin.x += CGFloat(sin(t * 0.7)) * points.width * 0.12
            frame.origin.y += CGFloat(cos(t * 0.45)) * points.height * 0.05
            scroll = CGFloat(t * 40)
        case .dashboard:
            // A new tab every four seconds, the cards jumping to it.
            scroll = CGFloat(Int(t / 4) % 6) * 220
        }
        scroll = scroll.truncatingRemainder(dividingBy: max(1, pageHeight - frame.height))

        // The window: shadow, body, title bar.
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: 18), blur: 40, color: CGColor(gray: 0, alpha: 0.45))
        context.setFillColor(CGColor(gray: 0.96, alpha: 1))
        context.addPath(CGPath(roundedRect: frame, cornerWidth: 12, cornerHeight: 12, transform: nil))
        context.fillPath()
        context.restoreGState()
        let bar = CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: 30)
        context.setFillColor(CGColor(gray: 0.9, alpha: 1))
        context.fill(bar.insetBy(dx: 12, dy: 0))
        for (i, light) in [CGColor(srgbRed: 1, green: 0.37, blue: 0.34, alpha: 1),
                           CGColor(srgbRed: 1, green: 0.74, blue: 0.18, alpha: 1),
                           CGColor(srgbRed: 0.16, green: 0.79, blue: 0.25, alpha: 1)].enumerated() {
            context.setFillColor(light)
            context.fillEllipse(in: CGRect(x: frame.minX + 14 + CGFloat(i) * 20, y: frame.minY + 9, width: 12, height: 12))
        }
        // The content, scrolled, typed up to the caret.
        let content = CGRect(x: frame.minX + 16, y: frame.minY + 30, width: frame.width - 32, height: frame.height - 42)
        if let page {
            context.saveGState()
            var visible = content
            if revealed.isFinite { visible.size.height = min(content.height, max(0, revealed - scroll)) }
            context.clip(to: visible)
            // Drawn upside down into the flipped space, so flip it back.
            context.translateBy(x: content.minX, y: content.minY - scroll + pageHeight)
            context.scaleBy(x: 1, y: -1)
            context.draw(page, in: CGRect(x: 0, y: 0, width: content.width, height: pageHeight))
            context.restoreGState()
            if revealed.isFinite, revealed - scroll < content.height {
                // The caret, blinking.
                if Int(t * 2) % 2 == 0 {
                    context.setFillColor(CGColor(gray: 0.95, alpha: 1))
                    context.fill(CGRect(x: content.minX + 70 + CGFloat(Int(t * 9) % 30) * 9,
                                        y: content.minY + revealed - scroll - 20, width: 2, height: 20))
                }
            }
        }
        if footage.scene == .dashboard {
            // The tab strip, the picked tab in the accent.
            for tab in 0..<6 {
                let picked = Int(t / 4) % 6 == tab
                context.setFillColor(picked ? accent : CGColor(gray: 0.85, alpha: 1))
                context.fill(CGRect(x: content.minX + 20 + CGFloat(tab) * 120, y: content.minY + 6, width: 100, height: 6))
            }
            // A live chart along the bottom, every bar moving.
            let strip = CGRect(x: content.minX + 20, y: content.maxY - 170, width: content.width - 40, height: 150)
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(strip)
            let bars = 40
            let width = strip.width / CGFloat(bars)
            context.setFillColor(accent)
            for b in 0..<bars {
                let level = 0.55 + 0.4 * sin(t * 2.1 + Double(b) * 0.45) * cos(t * 0.7 + Double(b) * 0.13)
                let h = strip.height * CGFloat(level) * 0.9
                context.fill(CGRect(x: strip.minX + CGFloat(b) * width + 2, y: strip.maxY - h, width: width - 4, height: h))
            }
        }

        // The pointer, travelling a loop over the window and stopping to click.
        let px = frame.midX + CGFloat(sin(t * 0.9) * 0.35 + sin(t * 2.3) * 0.08) * frame.width
        let py = frame.midY + CGFloat(cos(t * 0.6) * 0.32 + sin(t * 1.7) * 0.06) * frame.height
        let arrow = CGMutablePath()
        arrow.move(to: CGPoint(x: px, y: py))
        arrow.addLine(to: CGPoint(x: px, y: py + 22))
        arrow.addLine(to: CGPoint(x: px + 6, y: py + 17))
        arrow.addLine(to: CGPoint(x: px + 11, y: py + 27))
        arrow.addLine(to: CGPoint(x: px + 14, y: py + 25))
        arrow.addLine(to: CGPoint(x: px + 9, y: py + 16))
        arrow.addLine(to: CGPoint(x: px + 16, y: py + 16))
        arrow.closeSubpath()
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.addPath(arrow)
        context.fillPath()
        context.setStrokeColor(CGColor(gray: 1, alpha: 1))
        context.setLineWidth(1.5)
        context.addPath(arrow)
        context.strokePath()
        context.restoreGState()
    }
}

// MARK: - The project

extension ReferenceFootage {

    /// What a reference edit project is made of: the document, the table of
    /// files it plays, and where it is to be written. The caller writes it
    /// with `PackageIO.write(document, store: ImageStore(), media:, to: url)`;
    /// nothing in it is a picture, so the store is empty.
    public struct Project: Sendable {
        public let document: PhotonzDocument
        public let media: [ProjectMediaFile]
        public let url: URL
    }

    /// The edit at `minutes` long, with every file it plays written first
    /// where missing, under `folder`.
    public static func project(minutes: Int, in folder: URL, seed: UInt64 = ReferenceEdit.defaultSeed,
                               spec: Spec = .full,
                               progress: (@Sendable (String) -> Void)? = nil) async throws -> Project {
        let files = try await ensure(in: folder, spec: spec, progress: progress)
        let document = ReferenceEdit.build(minutes: minutes, seed: seed)
        let url = folder.appendingPathComponent(ReferenceEdit.projectName(minutes: minutes))
        let media = ProjectMedia.table(for: document, project: url) { files[$0] }
        return Project(document: document, media: media, url: url)
    }

    /// Where the reference edit is kept on this Mac unless asked otherwise:
    /// a cache, since everything in it can be made again.
    public static var defaultFolder: URL {
        if let asked = ProcessInfo.processInfo.environment["PHOTONZ_REFERENCE_EDIT_DIR"], !asked.isEmpty {
            return URL(fileURLWithPath: asked, isDirectory: true)
        }
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return caches.appendingPathComponent("Photonz Reference Edit", isDirectory: true)
    }
}
