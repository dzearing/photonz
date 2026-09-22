import AVFoundation
import Foundation

// A voice to caption (`Captions.swift`).
//
// The third sample beside the recording and the music, and it exists for the
// same reason as both: showing that the app can write the captions needs
// somebody talking, and a walk cannot depend on the person happening to have
// recorded a voiceover. The tutorial recording's sound is tones and blips,
// which is the right sound for teaching a cut aimed at a beat and exactly the
// wrong sound for teaching captions: there are no words in it.
//
// **Spoken by the Mac itself, in process.** `AVSpeechSynthesizer` will write
// its speech into buffers rather than out of the speakers, so this needs no
// audio fixture in the repository, no shelling out, and nothing to keep in step
// with anything. It is the Mac's own voice reading the app's own sentences, so
// what it says is short, plain and full of the words a screen recording about
// this app would actually contain.
//
// It is deliberately imperfect as a test of captioning, and that is the point:
// a synthesised voice saying "Photonz" is exactly the out-of-vocabulary word
// the recogniser gets wrong, so the sample shows the correcting as well as the
// writing.
@MainActor
enum TutorialSampleVoiceover {

    static let fileName = "Sample Voiceover.m4a"

    /// What it says. Five sentences with pauses between them, so the caption
    /// breaks land where a person would put them, and long enough that the
    /// recording it is laid over has to grow to hold it.
    static let script = """
    Photonz opens a screen recording as an ordinary document with time in it. \
    The transport bar and the timeline appear under the canvas. \
    You can cut a clip with the blade, or drag either end to trim it. \
    A title is a text layer that happens to have a start and an end. \
    Nothing about the window changes to edit a video.
    """

    static var url: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return caches.appendingPathComponent("Photonz", isDirectory: true)
            .appendingPathComponent("Tutorials", isDirectory: true)
            .appendingPathComponent(fileName)
            .standardizedFileURL
    }

    /// A clean copy, written once and reused: nothing ever edits this in place.
    static func fresh() async -> URL? {
        let url = Self.url
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: url.path) { return url }
        return await write(to: url) ? url : nil
    }

    /// Speak the script into a file.
    ///
    /// The buffers arrive on the synthesizer's own schedule through a callback,
    /// so the whole thing is one continuation that finishes when a buffer of
    /// nothing arrives, which is how `AVSpeechSynthesizer` says it has stopped.
    private static func write(to url: URL) async -> Bool {
        let synthesizer = AVSpeechSynthesizer()
        let utterance = AVSpeechUtterance(string: script)
        // A shade under the default, which lands nearer the pace somebody
        // narrating their own screen recording actually talks at.
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.92
        if let voice = AVSpeechSynthesisVoice(language: "en-US") { utterance.voice = voice }

        let writer = Writer(url: url)
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let once = Finish(continuation)
            synthesizer.write(utterance) { buffer in
                guard let pcm = buffer as? AVAudioPCMBuffer else { return }
                guard pcm.frameLength > 0 else { once.finish(); return }
                writer.append(pcm)
            }
        }
        // Held to here so ARC does not take the synthesizer away mid-sentence.
        withExtendedLifetime(synthesizer) {}
        return writer.close()
    }

    /// The file being written, made on the first buffer because that is when
    /// the format the voice came out in is finally known.
    private final class Writer {
        private let url: URL
        private var file: AVAudioFile?
        private var wrote = false

        init(url: URL) { self.url = url }

        func append(_ buffer: AVAudioPCMBuffer) {
            if file == nil {
                try? FileManager.default.removeItem(at: url)
                let settings: [String: Any] = [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVSampleRateKey: buffer.format.sampleRate,
                    AVNumberOfChannelsKey: buffer.format.channelCount,
                ]
                file = try? AVAudioFile(forWriting: url, settings: settings)
            }
            guard let file, (try? file.write(from: buffer)) != nil else { return }
            wrote = true
        }

        func close() -> Bool {
            file = nil
            return wrote && FileManager.default.fileExists(atPath: url.path)
        }
    }

    /// Resumes a continuation exactly once, however many empty buffers the
    /// synthesizer decides to send.
    private final class Finish: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<Void, Never>?

        init(_ continuation: CheckedContinuation<Void, Never>) {
            self.continuation = continuation
        }

        func finish() {
            lock.lock()
            let waiting = continuation
            continuation = nil
            lock.unlock()
            waiting?.resume()
        }
    }
}
