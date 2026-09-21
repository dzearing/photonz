import AVFoundation
import Foundation

// A piece of music to put under something (`docs/design/video-audio.md`).
//
// The sound half of `TutorialSampleRecording`, and it exists for the same
// reason: bringing a sound in from a file is a thing to be shown, and a guide
// or a walk cannot depend on the person happening to have a piece of music on
// their Mac.
//
// It is DELIBERATELY LONGER than the recording, because that is the case worth
// showing: a bed of music runs under the whole thing and past the end of it, so
// the timeline has to grow to hold it and the level has to be pulled down to
// let a voice through.
@MainActor
enum TutorialSampleSound {
    static let seconds = 14.0
    static let sampleRate: Double = 44_100
    static let fileName = "Sample Music.m4a"

    static var url: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return caches.appendingPathComponent("Photonz", isDirectory: true)
            .appendingPathComponent("Tutorials", isDirectory: true)
            .appendingPathComponent(fileName)
            .standardizedFileURL
    }

    /// A clean copy, written once and reused: unlike the recording, nothing
    /// ever edits this file in place.
    static func fresh() -> URL? {
        let url = Self.url
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: url.path) { return url }
        return write(to: url) ? url : nil
    }

    /// Four bars of a rising figure, played over and over, swelling gently.
    ///
    /// Something with a BEAT in it, so the waveform on the timeline has
    /// somewhere to aim a cut at, and so that pulling it down under a voice is
    /// a thing you can hear rather than a thing you have to trust.
    private static func write(to url: URL) -> Bool {
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
        ]
        try? FileManager.default.removeItem(at: url)
        guard let file = try? AVAudioFile(forWriting: url, settings: settings),
              let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)
        else { return false }

        let notes: [Double] = [261.63, 329.63, 392.00, 523.25]   // a plain major chord, rising
        let beat = 0.5
        let chunk = AVAudioFrameCount(4410)
        var written: AVAudioFramePosition = 0
        let total = AVAudioFramePosition(seconds * sampleRate)
        while written < total {
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunk),
                  let samples = buffer.floatChannelData?[0] else { return false }
            let count = AVAudioFrameCount(min(AVAudioFramePosition(chunk), total - written))
            buffer.frameLength = count
            for index in 0..<Int(count) {
                let at = Double(written + AVAudioFramePosition(index)) / sampleRate
                let note = notes[Int(at / beat) % notes.count]
                // Each note starts loud and dies away, which is what puts a
                // visible beat in the waveform.
                let intoBeat = at.truncatingRemainder(dividingBy: beat) / beat
                let envelope = 0.55 * (1 - intoBeat) + 0.1
                samples[index] = Float(envelope * sin(2 * .pi * note * at))
            }
            guard (try? file.write(from: buffer)) != nil else { return false }
            written += AVAudioFramePosition(count)
        }
        return true
    }
}
