import AVFoundation
import Foundation
import XCTest
@testable import PhotonzCore
@testable import PhotonzMedia

// Listening, for real (`Sources/PhotonzMedia/SpeechTranscription.swift`).
//
// These tests put actual speech through the actual recogniser, because the one
// claim this file makes — that a recording's words come back with the moments
// they were said at — cannot be checked against a mock of itself. The speech is
// made on the spot by the Mac's own `say`, so there is no audio fixture in the
// repository and nothing to keep in step with anything.
//
// The forty minute case is the one that matters most and is far too slow to run
// on every commit, so it runs only when it is handed a file:
//
//     PHOTONZ_LONG_SPEECH=/tmp/long.aiff Scripts/test.sh --filter SpeechTranscription
//
// What it found the day it was written is in the audit.
final class SpeechTranscriptionTests: XCTestCase {

    /// One sentence spoken by the Mac, or nil where `say` is not there.
    private func spoken(_ words: String, named name: String) throws -> URL? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("photonz-speech-\(name).aiff")
        try? FileManager.default.removeItem(at: url)
        let say = Process()
        say.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        say.arguments = ["-v", "Samantha", "-o", url.path, words]
        do { try say.run() } catch { return nil }
        say.waitUntilExit()
        guard say.terminationStatus == 0,
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    func testTheMachineCanTranscribeAtAllWithNobodyAskedForPermission() async throws {
        try XCTSkipUnless(SpeechTranscription.isAvailable, "no speech recognition on this Mac")
        let languages = await SpeechTranscription.languages()
        XCTAssertFalse(languages.isEmpty)
        let english = await SpeechTranscription.language(nearest: Locale(identifier: "en-US"))
        XCTAssertNotNil(english)
    }

    func testWordsComeBackWithTheMomentsTheyWereSaidAt() async throws {
        try XCTSkipUnless(SpeechTranscription.isAvailable, "no speech recognition on this Mac")
        guard let url = try spoken("Open a screen recording and the timeline appears.",
                                   named: "short") else {
            throw XCTSkip("this Mac has no `say`")
        }
        defer { try? FileManager.default.removeItem(at: url) }

        let heard = try await SpeechTranscription.words(of: url)
        XCTAssertFalse(heard.isEmpty, "a sentence of clear speech should come back as words")
        XCTAssertFalse(heard.wasStopped)

        // Word level, not sentence level: the whole point, because a caption
        // that cannot be cut at a word cannot be corrected at one either.
        XCTAssertGreaterThan(heard.words.count, 4)
        for word in heard.words {
            XCTAssertFalse(word.text.contains(" "), "one word per run: \(word.text)")
            XCTAssertGreaterThan(word.lengthMS, 0)
        }
        // In order, inside the recording, and none of them on top of each other.
        for (a, b) in zip(heard.words, heard.words.dropFirst()) {
            XCTAssertLessThanOrEqual(a.startMS, b.startMS)
        }
        XCTAssertLessThanOrEqual(heard.words.last!.endMS, heard.ofMS + 500)

        let said = heard.words.map { Captions.spine(of: $0.text) }
        XCTAssertTrue(said.contains("recording"), "heard: \(heard.words.map(\.text))")
        XCTAssertTrue(said.contains("timeline"), "heard: \(heard.words.map(\.text))")
    }

    func testSomethingThatIsNotARecordingSaysSoInPlainWords() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("photonz-speech-silent.txt")
        try "not a recording".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        do {
            _ = try await SpeechTranscription.words(of: url)
            XCTFail("a file with no sound in it should say so")
        } catch let trouble as TranscriptionTrouble {
            guard case .unreadable = trouble else { return XCTFail("\(trouble)") }
            XCTAssertTrue(trouble.errorDescription?.hasPrefix("That recording's sound could not be read")
                          ?? false)
        }
    }

    func testAFilmWithNoSoundTrackSaysThereIsNothingToHear() async throws {
        // A recording with a picture and no sound: there is nothing to
        // caption, and saying so beats an empty caption track.
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("photonz-speech-mute.mov")
        try? FileManager.default.removeItem(at: url)
        try await writeSilentFilm(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        do {
            _ = try await SpeechTranscription.words(of: url)
            XCTFail("a film with no sound should say there is nothing to hear")
        } catch let trouble as TranscriptionTrouble {
            XCTAssertEqual(trouble, .noSound)
            XCTAssertEqual(trouble.errorDescription, Captions.nothingToHear)
        }
    }

    /// One second of black, with no sound track at all.
    private func writeSilentFilm(to url: URL) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 160, AVVideoHeightKey: 90,
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String:
                                            kCVPixelFormatType_32BGRA])
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        var pool: CVPixelBuffer?
        CVPixelBufferCreate(nil, 160, 90, kCVPixelFormatType_32BGRA, nil, &pool)
        if let pixels = pool {
            for frame in 0..<10 {
                while !input.isReadyForMoreMediaData { await Task.yield() }
                adaptor.append(pixels, withPresentationTime: CMTime(value: CMTimeValue(frame),
                                                                   timescale: 10))
            }
        }
        input.markAsFinished()
        await writer.finishWriting()
    }

    func testAskingForALanguageThisMacDoesNotHaveSaysSo() async throws {
        try XCTSkipUnless(SpeechTranscription.isAvailable, "no speech recognition on this Mac")
        guard let url = try spoken("Hello.", named: "language") else {
            throw XCTSkip("this Mac has no `say`")
        }
        defer { try? FileManager.default.removeItem(at: url) }
        let madeUp = Locale(identifier: "zz-ZZ")
        guard await SpeechTranscription.language(nearest: madeUp) == nil else {
            throw XCTSkip("this Mac somehow speaks zz-ZZ")
        }
        do {
            _ = try await SpeechTranscription.words(of: url, locale: madeUp)
            XCTFail("a language nobody has should say so")
        } catch let trouble as TranscriptionTrouble {
            guard case .noSuchLanguage = trouble else { return XCTFail("\(trouble)") }
        }
    }

    func testStoppingPartWayKeepsWhatItAlreadyHeard() async throws {
        try XCTSkipUnless(SpeechTranscription.isAvailable, "no speech recognition on this Mac")
        guard let url = try spoken(String(repeating: "This is a sentence about editing video. ",
                                          count: 24), named: "stoppable") else {
            throw XCTSkip("this Mac has no `say`")
        }
        defer { try? FileManager.default.removeItem(at: url) }

        // Stopped the moment the first piece lands, rather than after a wait:
        // transcription runs about thirty times faster than listening, so a
        // test that stops it "after a second and a half" is a test that
        // usually stops nothing.
        let window = ChunkWindow(targetMS: 8_000, slackMS: 1_000, overlapMS: 3_000)
        let held = TaskHolder()
        let job = Task {
            try await SpeechTranscription.words(of: url, window: window) { _ in
                held.cancel()
            }
        }
        held.hold(job)
        let heard = try await job.value
        XCTAssertTrue(heard.wasStopped, "it should say it was stopped")
        XCTAssertFalse(heard.isEmpty, "and keep what it already heard")
        XCTAssertLessThan(heard.listenedToMS, heard.ofMS, "and not claim to have heard it all")
        XCTAssertEqual(CaptionProgress.stopped(doneMS: heard.listenedToMS, ofMS: heard.ofMS,
                                               words: heard.words.count).hasPrefix("Stopped at"),
                       true)
    }

    // MARK: - The long one

    func testALongRecordingIsHeardInPiecesWithTheSeamsInvisible() async throws {
        guard let path = ProcessInfo.processInfo.environment["PHOTONZ_LONG_SPEECH"] else {
            throw XCTSkip("set PHOTONZ_LONG_SPEECH to a long spoken file to run this")
        }
        let url = URL(fileURLWithPath: path)
        let tally = ProgressTally()
        let heard = try await SpeechTranscription.words(of: url) { progress in
            tally.note(progress.reading)
        }
        let readings = tally.readings

        XCTAssertGreaterThan(heard.ofMS, 30 * 60 * 1000, "this test is about a long recording")
        XCTAssertGreaterThan(readings.count, 10, "a long one is heard in pieces, not in one go")
        XCTAssertFalse(heard.wasStopped)

        // Timings stay absolute to the very end: the last word is near the end
        // of the recording, not near the end of the last piece.
        let last = try XCTUnwrap(heard.words.last)
        XCTAssertGreaterThan(last.endMS, heard.ofMS - 30_000,
                             "the last word should land near the end of the recording")
        for (a, b) in zip(heard.words, heard.words.dropFirst()) {
            XCTAssertLessThanOrEqual(a.startMS, b.startMS, "in order across every seam")
        }

        // Nothing doubled at a join: the same three words never appear twice in
        // a row at nearly the same moment.
        for index in heard.words.indices.dropLast(5) {
            let here = heard.words[index..<(index + 3)].map(\.spine)
            for ahead in (index + 1)..<min(index + 4, heard.words.count - 3) {
                let there = heard.words[ahead..<(ahead + 3)].map(\.spine)
                if here == there {
                    XCTAssertGreaterThan(abs(heard.words[ahead].startMS - heard.words[index].startMS),
                                         2_000, "a phrase doubled at a seam")
                }
            }
        }

        print("LONG: \(heard.words.count) words over \(CaptionProgress.clock(heard.ofMS)), "
              + "\(readings.count) pieces, "
              + "\(CaptionCues.cues(from: heard.words).count) captions")
    }
}

/// Somewhere for the progress readings to land: they arrive off whatever
/// thread the listening happened on, so they cannot simply be appended to a
/// local.
private final class ProgressTally: @unchecked Sendable {
    private let lock = NSLock()
    private var kept: [String] = []

    func note(_ reading: String) {
        lock.lock(); defer { lock.unlock() }
        kept.append(reading)
    }

    var readings: [String] {
        lock.lock(); defer { lock.unlock() }
        return kept
    }
}

/// Somewhere a progress callback can reach the job it is reporting on, so a
/// test can stop it the instant the first piece lands.
private final class TaskHolder: @unchecked Sendable {
    private let lock = NSLock()
    private var job: Task<HeardWords, Error>?

    func hold(_ job: Task<HeardWords, Error>) {
        lock.lock(); defer { lock.unlock() }
        self.job = job
    }

    func cancel() {
        lock.lock(); defer { lock.unlock() }
        job?.cancel()
    }
}
