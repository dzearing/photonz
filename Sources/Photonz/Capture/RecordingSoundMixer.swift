import AVFoundation
import os
import PhotonzCore
import PhotonzMedia
import ScreenCaptureKit

/// Hears a recording's two sounds, the Mac's and the microphone's, and mixes
/// them into a sound file as it records, so the recording is playable the
/// moment Stop is pressed.
///
/// macOS mixes the two itself when one stream records both, but only after
/// Stop, at about 0.45 s per recorded second of a full screen (measured
/// 2026-10-10: 4.6 s for 10 s, 20 s for 45 s); with one sound it closes the
/// file in under 100 ms. So with both chosen, macOS records the pictures and
/// the Mac's sound, this hears the Mac's sound from the same stream and the
/// microphone on its own, mixes them on the host clock from the first frame
/// (`SoundMixTimeline`), and writes the mix (`RecordingSoundWriter`). At Stop
/// the pictures and the mix are put in one file (`RecordingSoundMerge`).
///
/// Everything it holds is touched on `queue` only, except the capture
/// session, which lives on `sessionQueue`.
final class RecordingSoundMixer: NSObject, SCStreamOutput, AVCaptureAudioDataOutputSampleBufferDelegate,
                                 @unchecked Sendable {
    // @unchecked: every mutable property is confined to `queue` (the mix) or
    // `sessionQueue` (the capture session), as marked.
    static let sampleRate = 48_000.0
    static let channelCount = 2

    /// Where macOS writes the pictures and the Mac's sound.
    let pictureURL: URL
    /// Where the mix is written.
    let soundURL: URL
    let queue = DispatchQueue(label: "photonz.recording.sound-mix", qos: .userInitiated)
    private let sessionQueue = DispatchQueue(label: "photonz.recording.microphone", qos: .userInitiated)
    private let firstFrame: FirstFrameClock
    private let microphoneDeviceID: String?

    // On `queue`.
    private var timeline: SoundMixTimeline
    private let writer: RecordingSoundWriter
    private var closed = false
    private var micClock: CMClock?

    // On `sessionQueue`.
    private var session: AVCaptureSession?

    /// When each sound was first heard, on the host clock, and how long its
    /// first buffer took to arrive after that, for the probe's drill. A
    /// microphone stamped on the wrong clock arrives seconds early or late.
    private struct Heard { var at: Double?; var arrivedAfter: Double? }
    private let firstHeard = OSAllocatedUnfairLock<[SoundMixTimeline.Source: Heard]>(initialState: [:])
    func firstHeard(_ source: SoundMixTimeline.Source) -> (at: Double, arrivedAfter: Double)? {
        firstHeard.withLock { heard in
            guard let at = heard[source]?.at, let after = heard[source]?.arrivedAfter else { return nil }
            return (at, after)
        }
    }

    init(recordingTo url: URL, firstFrame: FirstFrameClock, microphoneDeviceID: String?) throws {
        let stem = url.deletingPathExtension().lastPathComponent
        let folder = url.deletingLastPathComponent()
        pictureURL = folder.appendingPathComponent("\(stem)-picture.mp4")
        soundURL = folder.appendingPathComponent("\(stem)-sound.m4a")
        self.firstFrame = firstFrame
        self.microphoneDeviceID = microphoneDeviceID
        timeline = SoundMixTimeline(sources: [.mac, .microphone], channelCount: Self.channelCount,
                                    sampleRate: Self.sampleRate)
        writer = try RecordingSoundWriter(url: soundURL, channelCount: Self.channelCount,
                                          sampleRate: Self.sampleRate)
    }

    /// Start hearing the microphone. Returns at once; the device opens on a
    /// queue of its own, in parallel with the stream starting. A microphone
    /// that is missing or not allowed leaves the Mac's sound on its own.
    func startMicrophone() {
        sessionQueue.async { [self] in
            guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized,
                  let device = microphoneDeviceID.flatMap(AVCaptureDevice.init(uniqueID:))
                    ?? AVCaptureDevice.default(for: .audio),
                  let input = try? AVCaptureDeviceInput(device: device)
            else {
                NSLog("Recording: the microphone could not be opened; recording the Mac's sound only")
                queue.async { self.timeline = SoundMixTimeline(sources: [.mac], channelCount: Self.channelCount,
                                                               sampleRate: Self.sampleRate) }
                return
            }
            let session = AVCaptureSession()
            let output = AVCaptureAudioDataOutput()
            output.audioSettings = [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: Self.sampleRate,
                AVLinearPCMBitDepthKey: 32,
                AVLinearPCMIsFloatKey: true,
                AVLinearPCMIsNonInterleaved: true,
            ]
            output.setSampleBufferDelegate(self, queue: queue)
            session.beginConfiguration()
            if session.canAddInput(input) { session.addInput(input) }
            if session.canAddOutput(output) { session.addOutput(output) }
            session.commitConfiguration()
            let clock = session.synchronizationClock
            queue.async { self.micClock = clock }
            self.session = session
            session.startRunning()
        }
    }

    // MARK: Hearing

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio else { return }
        let at = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        guard at.isValid else { return }
        hear(.mac, sampleBuffer, atHostSeconds: at.seconds)
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        var at = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        guard at.isValid else { return }
        // The microphone is stamped on its own session's clock.
        if let micClock { at = CMSyncConvertTime(at, from: micClock, to: CMClockGetHostTimeClock()) }
        hear(.microphone, sampleBuffer, atHostSeconds: at.seconds)
    }

    /// On `queue`.
    private func hear(_ source: SoundMixTimeline.Source, _ sampleBuffer: CMSampleBuffer, atHostSeconds seconds: Double) {
        guard !closed, let channels = PCMSamples.channels(of: sampleBuffer) else { return }
        firstHeard.withLock {
            guard $0[source] == nil else { return }
            let now = CMClockGetTime(CMClockGetHostTimeClock()).seconds
            $0[source] = Heard(at: seconds, arrivedAfter: now - seconds)
        }
        timeline.add(source, atSeconds: seconds, channels: channels)
        writeWhatIsReady(finishing: false)
    }

    /// On `queue`.
    private func writeWhatIsReady(finishing: Bool) {
        if let zero = firstFrame.seconds { timeline.setZero(atSeconds: zero) }
        while let chunk = timeline.take(finishing: finishing) { writer.append(chunk) }
    }

    // MARK: Stopping

    /// Stop hearing, write the rest of the mix and close its file. True when
    /// the file holds the mix.
    func finishSound() async -> Bool {
        await stopMicrophone()
        queue.sync {
            writeWhatIsReady(finishing: true)
            closed = true
        }
        return await writer.finish()
    }

    /// Stop the microphone, if it is open, and wait until it has stopped.
    private func stopMicrophone() async {
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            sessionQueue.async { [self] in
                session?.stopRunning()
                session = nil
                done.resume()
            }
        }
    }

    /// Put the pictures and the mix in one file at `url`. When there is no
    /// mix, or they cannot be joined, the pictures with the Mac's sound go
    /// there instead, so a recording is never lost for its microphone.
    func join(into url: URL, soundWritten: Bool) async -> Bool {
        let files = FileManager.default
        defer {
            try? files.removeItem(at: pictureURL)
            try? files.removeItem(at: soundURL)
        }
        if soundWritten, files.fileExists(atPath: pictureURL.path) {
            do {
                try await RecordingSoundMerge.merge(picture: pictureURL, sound: soundURL, into: url)
                return true
            } catch {
                NSLog("Recording: the pictures and the mixed sound could not be joined: \(error)")
            }
        }
        try? files.removeItem(at: url)
        try? files.moveItem(at: pictureURL, to: url)
        return false
    }

    /// The recording ended without a Stop (its stream died): let go of the
    /// microphone and the files.
    func abandon() {
        Task {
            _ = await finishSound()
            try? FileManager.default.removeItem(at: soundURL)
        }
    }
}
