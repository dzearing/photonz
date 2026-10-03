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

    /// The newest complete frame the stream has delivered, and the moment of
    /// the file it sits at (its time less the first frame's). Nil before the
    /// first frame.
    var lastFrame: (frame: RecordedFrame, fileMS: Int)? {
        guard let first = firstFrame?.seconds, let newest = firstFrame?.newest else { return nil }
        return (newest, Int(((newest.seconds - first) * 1000).rounded()))
    }
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

    /// When each part of the last start happened, on the host clock, for the
    /// probe's start drill.
    struct StartTrace {
        var contentReady: Double?
        var streamBuilt: Double?
        var captureStarted: Double?
        var plan: RecordingWarmStart?
        var reusedWarmFilter = false
        var outputStarted: Double?
    }
    private(set) var lastStart = StartTrace()

    /// Microphones available for the audio picker (phase 12.2): unique id + name.
    static func availableMicrophones() -> [(id: String, name: String)] {
        let session = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified)
        return session.devices.map { ($0.uniqueID, $0.localizedName) }
    }

    /// The clock of a file begun on a warm stream, until macOS says the file
    /// has started: only then does it know which frame the file starts on.
    private let clockAwaitingFile = OSAllocatedUnfairLock<FirstFrameClock?>(initialState: nil)

    /// What was made ready while the recording card is up: the display and a
    /// filter that keeps the stop control and the card out of the picture,
    /// and, for a recording without sound, a stream that writes nothing yet.
    ///
    /// Measured 2026-10-03: a stream starts in about 60 ms with no sound, but
    /// 0.4 s with one sound source and 1.3 s with both, and a file added while
    /// it starts never begins. A second stream started while another is
    /// starting or stopping waits behind it, which took a start with sound
    /// from 90 ms to 1.4 s. So with sound there is no warm stream: Start makes
    /// one on the filter made ready, and macOS takes about 100 ms to its first
    /// frame (about 55 ms without sound). Which of the two Start uses is
    /// `RecordingWarmStart`.
    private final class Warm {
        let stream: SCStream?
        let filter: SCContentFilter
        let clock: FirstFrameClock
        let config: RecordingConfig
        let displayID: CGDirectDisplayID
        let display: SCDisplay
        let scale: CGFloat
        let screenFrame: CGRect
        /// macOS has finished starting it.
        var started = false
        /// A recording was begun on it, so it is no longer the warm-up's.
        var taken = false
        /// Nobody wants it any more: it stops as soon as it has started.
        var abandoned = false

        init(stream: SCStream?, filter: SCContentFilter, clock: FirstFrameClock, config: RecordingConfig,
             displayID: CGDirectDisplayID, display: SCDisplay, scale: CGFloat, screenFrame: CGRect) {
            self.stream = stream
            self.filter = filter
            self.clock = clock
            self.config = config
            self.displayID = displayID
            self.display = display
            self.scale = scale
            self.screenFrame = screenFrame
        }
    }
    private var warm: Warm?
    /// A warm-up is still finding the display, and has no stream yet.
    private var findingDisplay = false
    /// `start` is under way.
    private var isStarting = false

    /// The config a warm stream is running with, if one is.
    var warmConfig: RecordingConfig? { warm?.config }

    private static func displayID(of screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    /// Start a stream for `config` on `screen` that writes nothing, so a
    /// recording begun on it has its first frame at once. The windows in
    /// `excluding` (the stop control, the card) are kept out of its picture.
    /// Any stream warmed before is stopped first. Nothing here can ask for a
    /// permission: the caller only warms once Screen Recording is granted, and
    /// never with a microphone whose access is not yet settled.
    func warmUp(config: RecordingConfig, screen: NSScreen, excluding excludedWindows: [NSWindow]) async {
        trace("warmUp asked (recording \(isRecording), starting \(isStarting), warm \(warm != nil))")
        defer { trace("warmUp done (warm \(warm != nil), started \(warm?.started ?? false))") }
        guard !isRecording, !isStarting else { return }
        await coolDown()
        guard !isRecording, !isStarting, let id = Self.displayID(of: screen) else { return }
        findingDisplay = true
        // Every window, not only those on screen: the stop control is up but
        // not yet visible while the card is.
        let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        findingDisplay = false
        guard let content, let display = content.displays.first(where: { $0.displayID == id }),
              !isRecording, !isStarting, warm == nil
        else { return }
        let excludedNumbers = Set(excludedWindows.map { CGWindowID($0.windowNumber) })
        let filter = SCContentFilter(display: display,
                                     excludingWindows: content.windows.filter { excludedNumbers.contains($0.windowID) })
        let clock = FirstFrameClock()
        primeTheWriter(filter: filter)
        guard !config.audio.capturesAnyAudio else {
            warm = Warm(stream: nil, filter: filter, clock: clock, config: config, displayID: id,
                        display: display, scale: screen.backingScaleFactor, screenFrame: screen.frame)
            return
        }
        let streamConfig = Self.streamConfiguration(config, display: display, scale: screen.backingScaleFactor)
        let stream = SCStream(filter: filter, configuration: streamConfig, delegate: self)
        guard (try? stream.addStreamOutput(clock, type: .screen, sampleHandlerQueue: FirstFrameClock.queue)) != nil
        else { return }
        let warm = Warm(stream: stream, filter: filter, clock: clock, config: config, displayID: id,
                        display: display, scale: screen.backingScaleFactor, screenFrame: screen.frame)
        self.warm = warm
        do {
            try await stream.startCapture()
            if !Self.reframePrimed, !warm.abandoned, !warm.taken {
                // The first reframe of a launch takes over 300 ms against
                // 30-45 ms after it, and a region recording starts with one.
                // Reframing this stream to a sliver and back, while the card
                // is up, pays it here. (Reframing a second stream instead
                // killed this one: -3805, connection interrupted.)
                Self.reframePrimed = true
                let sliver = Self.streamConfiguration(config, display: display, scale: screen.backingScaleFactor)
                sliver.sourceRect = CGRect(x: 0, y: 0, width: 64, height: 64)
                sliver.width = 64
                sliver.height = 64
                try? await stream.updateConfiguration(sliver)
                try? await stream.updateConfiguration(streamConfig)
            }
            warm.started = true
            if warm.abandoned { try? await stream.stopCapture() }
        } catch {
            NSLog("Recording warm-up failed: \(error)")
            if self.warm === warm { self.warm = nil }
        }
    }

    private func trace(_ line: String) {
        #if PHOTONZ_PLAYTEST
        RecordingStartLatencyDiag.note("recorder: " + line)
        #endif
    }

    /// Whether this launch has reframed a stream yet.
    private static var reframePrimed = false

    /// Whether this launch has written a file yet.
    private static var writerPrimed = false

    /// The first file a launch attaches to a stream takes about 35 ms longer
    /// (measured 2026-10-03), which on a warm stream is the difference between
    /// the file starting before or after whatever the person does straight
    /// after Start. Attaching one to a stream that is never started pays it,
    /// capturing nothing, while the card is up.
    private func primeTheWriter(filter: SCContentFilter) {
        guard !Self.writerPrimed else { return }
        Self.writerPrimed = true
        let stream = SCStream(filter: filter, configuration: SCStreamConfiguration(), delegate: nil)
        let recConfig = SCRecordingOutputConfiguration()
        recConfig.outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("photonz-warm-\(UUID().uuidString).mp4")
        recConfig.outputFileType = .mp4
        let output = SCRecordingOutput(configuration: recConfig, delegate: WriterPrimer())
        try? stream.addRecordingOutput(output)
        try? stream.removeRecordingOutput(output)
    }

    /// Stop a warm stream nobody began a recording on. One macOS is still
    /// starting stops itself once it has started.
    func coolDown() async {
        guard let warm = abandonWarm(), warm.started, let stream = warm.stream else { return }
        try? await stream.stopCapture()
    }

    private func abandonWarm() -> Warm? {
        guard let warm, !warm.taken else { return nil }
        self.warm = nil
        warm.abandoned = true
        return warm
    }

    private static func streamConfiguration(_ config: RecordingConfig, display: SCDisplay,
                                            scale: CGFloat) -> SCStreamConfiguration {
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
        return streamConfig
    }

    private func recordingOutput(to url: URL) -> SCRecordingOutput {
        let recConfig = SCRecordingOutputConfiguration()
        recConfig.outputURL = url
        recConfig.outputFileType = .mp4
        return SCRecordingOutput(configuration: recConfig, delegate: self)
    }

    /// Begin recording per `config` on `screen`, writing MP4 to `url`. The
    /// windows in `excluding` (the stop HUD) are removed from the captured
    /// video. A stream warmed for these choices is begun on at once, with
    /// nothing to wait for; otherwise a stream is started from scratch.
    func start(config: RecordingConfig, screen: NSScreen, to url: URL,
               excluding excludedWindows: [NSWindow], pointer: PointerTracker? = nil) async throws {
        guard !isRecording, !isStarting else { throw RecorderError.alreadyRecording }
        isStarting = true
        defer { isStarting = false }
        lastStart = StartTrace()
        // The last recording's clock is not this one's.
        firstFrame = nil
        // A warm-up still finding the display (Start pressed the instant the
        // card came up) has its stream in a few tens of milliseconds.
        let deadline = ContinuousClock.now + .milliseconds(300)
        while warm == nil, findingDisplay, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(2))
        }
        let plan = RecordingWarmStart.plan(warm: warm?.config, chosen: config,
                                           sameDisplay: warm != nil && warm?.displayID == Self.displayID(of: screen))
        trace("start: plan \(plan), warm \(warm != nil), started \(warm?.started ?? false)")
        lastStart.plan = plan
        if plan != .cold, let warm, warm.started, let warmStream = warm.stream {
            do {
                try await begin(on: warm, stream: warmStream, config: config, reframe: plan == .reframe,
                                to: url, pointer: pointer)
                return
            } catch {
                // A warm stream that will not take the file is dropped and the
                // recording started the way it always was.
                NSLog("Recording could not begin on the warm stream: \(error)")
                trace("could not begin on warm: \(error)")
                lastStart.plan = .cold
                if self.warm === warm { self.warm = nil }
                try? await warmStream.stopCapture()
            }
        }
        // A warm stream still starting, or warmed with other sound, already
        // knows the display and keeps the stop control and the card out of
        // the picture: a new stream on its filter skips the look-up. It is
        // stopped without waiting for it.
        lastStart.plan = .cold
        lastStart.reusedWarmFilter = warm.map { $0.displayID == Self.displayID(of: screen) } ?? false
        let screenNumber = Self.displayID(of: screen)
        let reusable = warm.flatMap { $0.displayID == screenNumber ? $0 : nil }
        if let old = abandonWarm(), old.started, let stream = old.stream { Task { try? await stream.stopCapture() } }

        let display: SCDisplay
        let filter: SCContentFilter
        if let reusable {
            display = reusable.display
            filter = reusable.filter
        } else {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            lastStart.contentReady = PointerTracker.hostNow()
            guard let screenNumber,
                  let found = content.displays.first(where: { $0.displayID == screenNumber })
            else { throw RecorderError.displayNotFound }
            // Keep the floating stop control out of the recording.
            let excludedNumbers = Set(excludedWindows.map { CGWindowID($0.windowNumber) })
            display = found
            filter = SCContentFilter(display: found,
                                     excludingWindows: content.windows.filter { excludedNumbers.contains($0.windowID) })
        }

        let scale = screen.backingScaleFactor
        let streamConfig = Self.streamConfiguration(config, display: display, scale: scale)
        let rect = streamConfig.sourceRect
        recordedSize = CGSize(width: streamConfig.width, height: streamConfig.height)

        let stream = SCStream(filter: filter, configuration: streamConfig, delegate: self)

        let recordingOutput = recordingOutput(to: url)
        try stream.addRecordingOutput(recordingOutput)
        let clock = FirstFrameClock()
        try stream.addStreamOutput(clock, type: .screen, sampleHandlerQueue: FirstFrameClock.queue)
        self.firstFrame = clock

        // The pointer is followed from just before the first frame, so the
        // place it was in when the picture began is known.
        let space = PointerSpace(displayFrame: screen.frame, sourceRect: rect, pixelSize: recordedSize)
        pointerSpace = space
        pointer?.start(space: space)
        lastStart.streamBuilt = PointerTracker.hostNow()
        do {
            try await stream.startCapture()
            lastStart.captureStarted = PointerTracker.hostNow()
        } catch {
            pointer?.stop()
            throw error
        }

        self.stream = stream
        self.recordingOutput = recordingOutput
        self.outputURL = url
        self.isRecording = true
    }

    /// Begin the file on a stream that is already running. Reframing it to a
    /// region is the only wait; the file starts at the next frame the stream
    /// takes, and the first-frame clock starts counting from the same moment.
    private func begin(on warm: Warm, stream: SCStream, config: RecordingConfig, reframe: Bool, to url: URL,
                       pointer: PointerTracker?) async throws {
        let streamConfig = Self.streamConfiguration(config, display: warm.display, scale: warm.scale)
        if reframe {
            // Reframing a stream macOS is still starting is not something to
            // rely on; it starts in about 60 ms without sound.
            let deadline = ContinuousClock.now + .seconds(3)
            while !warm.started, self.warm === warm, ContinuousClock.now < deadline {
                try? await Task.sleep(for: .milliseconds(2))
            }
            guard warm.started, self.warm === warm else { throw RecorderError.notRecording }
            try await stream.updateConfiguration(streamConfig)
            lastStart.streamBuilt = PointerTracker.hostNow()
        }
        let rect = streamConfig.sourceRect
        recordedSize = CGSize(width: streamConfig.width, height: streamConfig.height)
        let space = PointerSpace(displayFrame: warm.screenFrame, sourceRect: rect, pixelSize: recordedSize)

        // A file added to a running stream starts at the first frame taken
        // after macOS reports it started (measured 2026-10-03: about 20 ms
        // after it is added), not at the next frame, so the clock waits for
        // that report before it counts.
        let recordingOutput = recordingOutput(to: url)
        let clock = warm.clock
        clock.waitForFile()
        clockAwaitingFile.withLock { $0 = clock }
        do {
            try stream.addRecordingOutput(recordingOutput)
        } catch {
            clockAwaitingFile.withLock { $0 = nil }
            throw error
        }
        lastStart.captureStarted = PointerTracker.hostNow()
        warm.taken = true
        self.warm = nil
        self.firstFrame = warm.clock
        pointerSpace = space
        pointer?.start(space: space)
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
            firstFrame?.release()
            self.stream = nil
            self.recordingOutput = nil
            self.outputURL = nil
        }
        return url
    }

    /// The recording's stream died under it.
    private func streamFailed() {
        isRecording = false
        resumeFinishIfNeeded()
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
        let stopped = ObjectIdentifier(stream)
        Task { @MainActor in
            NSLog("Recording stream stopped with error: \(error)")
            self.trace("stream stopped with error: \(error)")
            if let warm = self.warm, let warmStream = warm.stream, ObjectIdentifier(warmStream) == stopped {
                self.warm = nil
                return
            }
            self.streamFailed()
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

    nonisolated func recordingOutputDidStartRecording(_ recordingOutput: SCRecordingOutput) {
        let now = CMClockGetTime(CMClockGetHostTimeClock()).seconds
        clockAwaitingFile.withLock {
            $0?.arm(from: now)
            $0 = nil
        }
        Task { @MainActor in
            if self.lastStart.outputStarted == nil { self.lastStart.outputStarted = now }
        }
    }

    nonisolated func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        Task { @MainActor in
            self.lastStop?.outputFinished = Date()
            self.resumeFinishIfNeeded()
        }
    }
}

// MARK: - The first frame, and the last

/// Remembers the presentation time of the stream's first complete frame, on
/// the host clock. The recording file starts at that frame, so it is the zero
/// every pointer time is counted from.
///
/// It also holds on to the newest complete frame, and only that one: the
/// buffer the stream handed over, retained rather than copied, swapped for the
/// next as it arrives. At Stop it is the picture the recording ends on, in
/// memory while macOS is still closing the file, which is what lets the tile
/// and the editor show the recording at once (`ClosingRecording`). Nothing
/// here touches a pixel: it is a pointer swap per frame under a lock, and the
/// one surface held back is one of the eight the stream keeps by default.
final class FirstFrameClock: NSObject, SCStreamOutput, Sendable {
    static let queue = DispatchQueue(label: "photonz.recording.first-frame", qos: .userInitiated)
    private let first = OSAllocatedUnfairLock<Double?>(initialState: nil)
    private let last = OSAllocatedUnfairLock<RecordedFrame?>(initialState: nil)

    /// Frames taken before this moment, on the host clock, are not the
    /// recording's: a warm stream runs before its file begins.
    private let armedAt = OSAllocatedUnfairLock<Double>(initialState: 0)

    var seconds: Double? { first.withLock { $0 } }
    var newest: RecordedFrame? { last.withLock { $0 } }

    /// Stop counting until `arm`: the frames from now on may come before the
    /// file's first.
    func waitForFile() {
        armedAt.withLock { $0 = .infinity }
        first.withLock { $0 = nil }
        last.withLock { $0 = nil }
    }

    /// Count from the first frame taken at or after `hostSeconds`.
    func arm(from hostSeconds: Double) {
        armedAt.withLock { $0 = hostSeconds }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                of type: SCStreamOutputType) {
        guard type == .screen else { return }
        // Idle frames (nothing changed) carry no picture and are not written.
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
            as? [[SCStreamFrameInfo: Any]],
           let raw = attachments.first?[.status] as? Int,
           let status = SCFrameStatus(rawValue: raw), status != .complete {
            return
        }
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        guard pts.isValid else { return }
        guard pts.seconds >= armedAt.withLock({ $0 }) else { return }
        first.withLock { if $0 == nil { $0 = pts.seconds } }
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        #if PHOTONZ_PLAYTEST
        Self.playtestWatch.withLock { $0 }?(buffer, pts.seconds)
        #endif
        let frame = RecordedFrame(buffer: buffer, seconds: pts.seconds)
        last.withLock { $0 = frame }
    }

    #if PHOTONZ_PLAYTEST
    /// Probe drill: sees every complete frame counted, with its host time.
    static let playtestWatch = OSAllocatedUnfairLock<(@Sendable (CVPixelBuffer, Double) -> Void)?>(initialState: nil)
    #endif

    /// Lets go of the frame held, so its surface goes back to the stream.
    func release() { last.withLock { $0 = nil } }
}

/// The delegate a primed, never-started file is given: it hears nothing.
private final class WriterPrimer: NSObject, SCRecordingOutputDelegate, Sendable {}

/// One frame the stream delivered, and when, on the host clock.
struct RecordedFrame: @unchecked Sendable {
    // A CVPixelBuffer is a reference-counted, IOSurface-backed buffer the
    // stream never writes to again once it has been delivered; it is only
    // read from here on. Core Video does not mark it Sendable.
    let buffer: CVPixelBuffer
    let seconds: Double
}
