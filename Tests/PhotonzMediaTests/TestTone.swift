import AVFoundation
import Foundation

/// Synthesizes small, real sound files so the mix tests can assert on an actual
/// file instead of on bookkeeping.
///
/// A tone rather than noise, and a tone whose LOUDNESS is a known function of
/// time, because that is the thing every one of these tests is about: an export
/// honouring a level is the export coming back quieter in the places the plan
/// said quieter. Reading a peak back off the written file is the only way to
/// check that without a pair of ears.
enum TestTone {

    static let sampleRate: Double = 44_100

    /// Write `seconds` of a 440Hz tone whose amplitude at each moment is
    /// `amplitude(secondsIn)`.
    ///
    /// An m4a, the same container the mix is written to, so nothing in a test
    /// turns on a format the app never uses.
    static func write(to url: URL, seconds: Double,
                      amplitude: (Double) -> Double) throws {
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
        ]
        try? FileManager.default.removeItem(at: url)
        let file = try AVAudioFile(forWriting: url, settings: settings)
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)
        else { throw Failure.noFormat }

        let chunk = AVAudioFrameCount(4410)          // a tenth of a second
        var written: AVAudioFramePosition = 0
        let total = AVAudioFramePosition(seconds * sampleRate)
        while written < total {
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunk)
            else { throw Failure.noBuffer }
            let count = AVAudioFrameCount(min(AVAudioFramePosition(chunk), total - written))
            buffer.frameLength = count
            guard let samples = buffer.floatChannelData?[0] else { throw Failure.noBuffer }
            for index in 0..<Int(count) {
                let at = Double(written + AVAudioFramePosition(index)) / sampleRate
                samples[index] = Float(amplitude(at) * sin(2 * .pi * 440 * at))
            }
            try file.write(from: buffer)
            written += AVAudioFramePosition(count)
        }
        return
    }

    /// A tone at one level the whole way through.
    static func writeFlat(to url: URL, seconds: Double, amplitude: Double = 0.8) throws {
        try write(to: url, seconds: seconds) { _ in amplitude }
    }

    /// A tone that is loud only between two moments, silent either side. What a
    /// cut test needs: the file says which part of itself it is.
    static func writeBurst(to url: URL, seconds: Double,
                           loudFrom: Double, loudTo: Double) throws {
        try write(to: url, seconds: seconds) { at in
            at >= loudFrom && at < loudTo ? 0.8 : 0
        }
    }

    enum Failure: Error { case noFormat, noBuffer }

    /// A folder to write into that cleans up after itself.
    static func scratch() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("photonz-mix-tests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
