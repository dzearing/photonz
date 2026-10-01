import AppKit
import AVFoundation
import os
import PhotonzCore
import ScreenCaptureKit

/// Records the screen to an MP4 via ScreenCaptureKit's modern `SCRecordingOutput`
/// (macOS 15+) — no hand-rolled `AVAssetWriter`. The stream captures video plus
/// (optionally) system audio and a microphone, and writes the file itself; we
/// just configure, start, and finalize on stop. The floating stop control is
/// excluded from the captured video via the content filter (phase 12.3).
///
/// Recording session *config* is the testable `RecordingConfig` (PhotonzCore);
/// this class is the thin SCK/AVFoundation shell.
@MainActor
final class ScreenRecorder: NSObject {
    enum RecorderError: Error { case displayNotFound, alreadyRecording, notRecording }

    private var stream: SCStream?
    private var recordingOutput: SCRecordingOutput?
    private var finishContinuation: CheckedContinuation<Void, Never>?
    /// Hears the stream's frames only to learn when the first one was taken,
    /// which is the moment the file counts from (`PointerTracker`).
    private var firstFrame: FirstFrameClock?

    /// The host-clock moment of the recording's first frame, once the stream
    /// has delivered one: what a click's time is counted from.
    var firstFrameHostSeconds: Double? { firstFrame?.seconds }
    /// How the screen lands in the recording's pixels, for the pointer.
    private(set) var pointerSpace: PointerSpace?

    private(set) var isRecording = false
    private(set) var outputURL: URL?
    /// Recorded pixel size (after backing scale) — used to plan GIF/HEIC exports.
    private(set) var recordedSize: CGSize = .zero

    /// When each part of the last stop happened, for the probe's latency drill.
    struct StopTrace {
        var requested = Date()
        var stopCaptureReturned: Date?
        var outputFinished: Date?
        var fallbackFired: Date?
        var resumed: Date?
    }
    private(set) var lastStop: StopTrace?

    /// Microphones available for the audio picker (phase 12.2): unique id + name.
    static func availableMicrophones() -> [(id: String, name: String)] {
        let session = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified)
        return session.devices.map { ($0.uniqueID, $0.localizedName) }
    }

    /// Begin recording per `config` on `screen`, writing MP4 to `url`. The
    /// windows in `excluding` (the stop HUD) are removed from the captured video.
    func start(config: RecordingConfig, screen: NSScreen, to url: URL,
               excluding excludedWindows: [NSWindow], pointer: PointerTracker? = nil) async throws {
        guard !isRecording else { throw RecorderError.alreadyRecording }

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
              let display = content.displays.first(where: { $0.displayID == screenNumber.uint32Value })
        else { throw RecorderError.displayNotFound }

        // Keep the floating stop control out of the recording.
        let excludedNumbers = Set(excludedWindows.map { CGWindowID($0.windowNumber) })
        let excludedSCWindows = content.windows.filter { excludedNumbers.contains($0.windowID) }

        let scale = screen.backingScaleFactor
        let displaySize = CGSize(width: display.width, height: display.height)
        let rect = config.source.sourceRect(displaySize: displaySize)

        let streamConfig = SCStreamConfiguration()
        streamConfig.sourceRect = rect
        streamConfig.width = Int(rect.width * scale)
        streamConfig.height = Int(rect.height * scale)
        streamConfig.showsCursor = true
        streamConfig.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        streamConfig.capturesAudio = config.audio.capturesSystemAudio
        if config.audio.capturesMicrophone {
            streamConfig.captureMicrophone = true
            streamConfig.microphoneCaptureDeviceID = config.microphoneDeviceID
        }
        recordedSize = CGSize(width: streamConfig.width, height: streamConfig.height)

        let filter = SCContentFilter(display: display, excludingWindows: excludedSCWindows)
        let stream = SCStream(filter: filter, configuration: streamConfig, delegate: self)

        let recConfig = SCRecordingOutputConfiguration()
        recConfig.outputURL = url
        recConfig.outputFileType = .mp4
        let recordingOutput = SCRecordingOutput(configuration: recConfig, delegate: self)
        try stream.addRecordingOutput(recordingOutput)
        let clock = FirstFrameClock()
        try stream.addStreamOutput(clock, type: .screen, sampleHandlerQueue: FirstFrameClock.queue)
        self.firstFrame = clock

        // The pointer is followed from just before the first frame, so the
        // place it was in when the picture began is known.
        let space = PointerSpace(displayFrame: screen.frame, sourceRect: rect, pixelSize: recordedSize)
        pointerSpace = space
        pointer?.start(space: space)
        do {
            try await stream.startCapture()
        } catch {
            pointer?.stop()
            throw error
        }

        self.stream = stream
        self.recordingOutput = recordingOutput
        self.outputURL = url
        self.isRecording = true
    }

    /// Stop and finalize the recording, returning the written MP4 URL.
    @discardableResult
    func stop() async throws -> URL {
        guard isRecording, let stream, let url = outputURL else { throw RecorderError.notRecording }
        isRecording = false
        lastStop = StopTrace()

        // Wait for the recording output to flush before handing back the URL, so
        // callers can immediately read a complete file.
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            finishContinuation = continuation
            Task {
                try? await stream.stopCapture()
                self.lastStop?.stopCaptureReturned = Date()
                // stopCapture may return before didFinishRecording fires; if the
                // delegate never calls back, don't hang the caller forever.
                try? await Task.sleep(for: .milliseconds(400))
                if self.finishContinuation != nil { self.lastStop?.fallbackFired = Date() }
                self.resumeFinishIfNeeded()
            }
        }

        // A new recording may have started while this one was closing (the
        // stop control goes away at Stop); leave its stream alone.
        if self.stream === stream {
            self.stream = nil
            self.recordingOutput = nil
            self.outputURL = nil
        }
        return url
    }

    private func resumeFinishIfNeeded() {
        if finishContinuation != nil { lastStop?.resumed = Date() }
        finishContinuation?.resume()
        finishContinuation = nil
    }
}

// MARK: - SCStreamDelegate

extension ScreenRecorder: SCStreamDelegate {
    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor in
            NSLog("Recording stream stopped with error: \(error)")
            self.isRecording = false
            self.resumeFinishIfNeeded()
        }
    }
}

// MARK: - SCRecordingOutputDelegate

extension ScreenRecorder: SCRecordingOutputDelegate {
    nonisolated func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: Error) {
        Task { @MainActor in
            NSLog("Recording output failed: \(error)")
            self.resumeFinishIfNeeded()
        }
    }

    nonisolated func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        Task { @MainActor in
            self.lastStop?.outputFinished = Date()
            self.resumeFinishIfNeeded()
        }
    }
}

// MARK: - When the first frame was taken

/// Remembers the presentation time of the stream's first complete frame, on
/// the host clock. The recording file starts at that frame, so it is the zero
/// every pointer time is counted from. Everything after the first frame is
/// returned from at once: this never touches the picture.
private final class FirstFrameClock: NSObject, SCStreamOutput, Sendable {
    static let queue = DispatchQueue(label: "photonz.recording.first-frame", qos: .userInitiated)
    private let first = OSAllocatedUnfairLock<Double?>(initialState: nil)

    var seconds: Double? { first.withLock { $0 } }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                of type: SCStreamOutputType) {
        guard type == .screen, first.withLock({ $0 }) == nil else { return }
        // Idle frames (nothing changed) carry no picture and are not written.
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
            as? [[SCStreamFrameInfo: Any]],
           let raw = attachments.first?[.status] as? Int,
           let status = SCFrameStatus(rawValue: raw), status != .complete {
            return
        }
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        guard pts.isValid else { return }
        first.withLock { if $0 == nil { $0 = pts.seconds } }
    }
}
