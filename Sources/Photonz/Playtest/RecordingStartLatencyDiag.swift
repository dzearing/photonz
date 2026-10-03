#if PHOTONZ_PLAYTEST
import AppKit
import AVFoundation
import os
import PhotonzCore

/// Probe-only drill of how long a recording takes to begin once Return is
/// pressed on the recording card (`--recording-start-latency-diag <runs>`).
/// Each run puts the app's own card up (without taking the keyboard), leaves
/// it there for a beat the way a person reads it, presses Return on it, and
/// times every step up to the stream's first frame, through the app's own
/// `RecordingCoordinator` filing into a scratch folder.
///
/// It also checks the file, with two small windows of its own:
///
/// - a black square that turns white 50 ms after Return: the file has to
///   begin on black and show the white within its first second, so nothing
///   done straight after Return is missing from the start;
/// - a green square under the stop control: the file has to show green where
///   the control's red dot is, so the control stays out of the video.
///
/// `--region` records a region around the squares instead, timed from the
/// moment the region is chosen (the end of the drag); `--system-audio` and
/// `--with-microphone` record those too. The readings go to
/// `/tmp/photonz-recording-start-latency.json`.
@MainActor
enum RecordingStartLatencyDiag {
    static let resultPath = "/tmp/photonz-recording-start-latency.json"
    /// How long after Return the black square turns white.
    static let flipAfterMS: Double = 50

    static func runIfRequested() {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--recording-start-latency-diag") else { return }
        let runs = (i + 1 < args.count ? Int(args[i + 1]) : nil) ?? 10
        Task { await run(runs: runs, args: args) }
    }

    /// Progress, one line per step, so a drill that hangs says where.
    static func note(_ line: String) {
        let path = "/tmp/photonz-recording-start-progress.txt"
        let text = String(format: "%.3f ", PointerTracker.hostNow()) + line + "\n"
        if let handle = FileHandle(forWritingAtPath: path) {
            handle.seekToEndOfFile()
            handle.write(Data(text.utf8))
            try? handle.close()
        } else {
            try? text.write(toFile: path, atomically: false, encoding: .utf8)
        }
    }

    private static func ms(_ from: Double, _ to: Double?) -> Double? {
        to.map { (($0 - from) * 1000 * 10).rounded() / 10 }
    }

    private static func square(_ frame: CGRect, _ color: NSColor, level: NSWindow.Level) -> NSPanel {
        let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.backgroundColor = color
        panel.isOpaque = true
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = level
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.orderFrontRegardless()
        return panel
    }

    private static func run(runs: Int, args: [String]) async {
        var out: [String: Any] = ["runs": runs, "flipAfterMS": flipAfterMS]
        var readings: [[String: Any]] = []
        defer {
            out["readings"] = readings
            if let data = try? JSONSerialization.data(withJSONObject: out, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: URL(fileURLWithPath: resultPath))
            }
            NSLog("[recording-start-latency-diag] \(out)")
        }
        guard let screen = NSScreen.main else { out["error"] = "no screen"; return }
        guard ScreenCapturer.hasPermission else { out["error"] = "no Screen Recording grant"; return }
        var audio: AudioSources = []
        if args.contains("--system-audio") { audio.insert(.systemAudio) }
        if args.contains("--with-microphone") { audio.insert(.microphone) }
        let region = args.contains("--region")
        let cold = args.contains("--cold")
        // Nothing of the drill's changes on screen: the square stays black.
        let still = args.contains("--still")
        let stopEarly = args.contains("--stop-early")
        let cancel = args.contains("--cancel")
        out["cancel"] = cancel
        out["stopEarly"] = stopEarly
        out["still"] = still
        out["warm"] = !cold
        out["audio"] = [audio.contains(.systemAudio) ? "system" : nil,
                        audio.contains(.microphone) ? "microphone" : nil].compactMap { $0 }
        out["source"] = region ? "region" : "full display"

        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("photonz-start-latency-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let store = CaptureStore(directory: scratch)
        store.start()
        let coordinator = RecordingCoordinator(store: store)
        let setup = RecordingSetupController()
        setup.playtestLeavesKeyAlone = true
        var landedEntry: CaptureEntry?
        coordinator.onRecordingComplete = { entry in
            store.whenLanded(entry.url) { landedEntry = $0 }
        }

        let hud = RecordingControlsController.frame(on: screen)
        let flipFrame = CGRect(x: hud.minX - 80, y: hud.minY + 2, width: 48, height: 48)
        let flip = square(flipFrame, .black, level: .floating)
        let underHUD = square(hud, NSColor(srgbRed: 0, green: 1, blue: 0, alpha: 1), level: .floating)
        defer { flip.orderOut(nil); underHUD.orderOut(nil) }
        // The stop control's red dot: 6 pt of glass inset, 14 pt of padding, 5 pt to its centre.
        let dot = CGPoint(x: hud.minX + 25, y: hud.midY)
        let flipCentre = CGPoint(x: flipFrame.midX, y: flipFrame.midY)
        let scale = screen.backingScaleFactor
        let pixelOrigin = region ? CGPoint(x: flipFrame.minX - 20, y: hud.maxY + 20)
                                 : CGPoint(x: screen.frame.minX, y: screen.frame.maxY)
        func streamPixel(_ p: CGPoint) -> (Int, Int) {
            (Int(((p.x - pixelOrigin.x) * scale).rounded()), Int(((pixelOrigin.y - p.y) * scale).rounded()))
        }
        // A region that holds both squares, in the display's top-left points.
        let regionRect = CGRect(x: flipFrame.minX - 20 - screen.frame.minX,
                                y: screen.frame.maxY - hud.maxY - 20,
                                width: hud.maxX - flipFrame.minX + 40, height: hud.height + 40)

        let mics = ScreenRecorder.availableMicrophones()
        let micID = audio.contains(.microphone) ? mics.first?.id : nil
        if audio.contains(.microphone), micID == nil { out["error"] = "no microphone attached"; return }
        let config = RecordingConfig(source: region ? .region(regionRect) : .fullDisplay, audio: audio,
                                     microphoneDeviceID: micID, format: .mp4)

        for run in 0..<runs {
            flip.backgroundColor = .black
            flip.display()
            landedEntry = nil
            var pressedAt = 0.0
            var startTask: Task<Void, Never>?
            // The app's own flow (CaptureCenter.beginRecordingFlow): the card,
            // the recording made ready while it is up, then Return.
            var chosenOnCard: RecordingConfig?
            setup.present(
                initial: config, microphones: mics,
                onChange: { chosen in
                    guard !cold else { return }
                    Task { @MainActor in
                        guard let card = setup.window else { return }
                        coordinator.prepare(config: CaptureCenter.warmConfig(for: chosen), screen: screen,
                                            alsoExcluding: [card])
                    }
                },
                onCancel: { coordinator.cancelPrepared() }
            ) { chosen in
                chosenOnCard = chosen
                // CaptureCenter.startRecording: microphone access is already settled here.
                if !region { startTask = Task { await coordinator.start(config: chosen, screen: screen) } }
            }
            try? await Task.sleep(for: .milliseconds(1000))
            if cancel {
                let readyBefore = coordinator.playtestSomethingPrepared
                let took = setup.playtestPressEscape()
                try? await Task.sleep(for: .milliseconds(700))
                readings.append(["readyWhileCardUp": readyBefore, "escapeTaken": took,
                                 "cardGone": setup.window == nil,
                                 "nothingLeftAfterCancel": !coordinator.playtestSomethingPrepared])
                continue
            }
            pressedAt = PointerTracker.hostNow()
            note("run \(run + 1): pressing Return")
            guard setup.playtestPressReturn(), chosenOnCard != nil else {
                setup.dismiss()
                out["error"] = "the card did not take Return"
                return
            }
            if region {
                // The drag is the person's: time from the moment it ends.
                try? await Task.sleep(for: .milliseconds(1000))
                pressedAt = PointerTracker.hostNow()
                startTask = Task { await coordinator.start(config: config, screen: screen) }
            }
            // Turn the square white 50 ms after Return, off the main thread's
            // timetable so a busy start cannot push it later.
            var flippedAt: Double?
            let flipTask = Task { @MainActor in
                let wake = pressedAt + flipAfterMS / 1000
                while PointerTracker.hostNow() < wake { try? await Task.sleep(for: .microseconds(500)) }
                guard !still else { return }
                flip.backgroundColor = .white
                flip.display()
                flippedAt = PointerTracker.hostNow()
            }
            // The first frame the stream itself shows the square white in.
            let streamTurn = OSAllocatedUnfairLock<Double?>(initialState: nil)
            let flipPixel = streamPixel(flipCentre)
            FirstFrameClock.playtestWatch.withLock { $0 = { buffer, seconds in
                guard streamTurn.withLock({ $0 }) == nil, let shade = shade(of: buffer, at: flipPixel), shade > 200 else { return }
                streamTurn.withLock { $0 = seconds }
            } }
            if stopEarly {
                // Stop pressed 300 ms in: with sound, macOS is still starting
                // the stream then.
                try? await Task.sleep(for: .milliseconds(300))
                let stillStarting = coordinator.isStarting
                await coordinator.stop()
                note("run \(run + 1): stop pressed while starting \(stillStarting)")
                await startTask?.value
                note("run \(run + 1): start returned, recording \(coordinator.isRecording)")
                await flipTask.value
                let deadline = Date().addingTimeInterval(10)
                while landedEntry == nil, Date() < deadline { try? await Task.sleep(for: .milliseconds(10)) }
                var reading: [String: Any] = ["stopPressedWhileStarting": stillStarting,
                                              "stoppedAfterStart": !coordinator.isRecording,
                                              "fileLanded": landedEntry != nil]
                if let entry = landedEntry {
                    reading["seconds"] = (try? await AVURLAsset(url: entry.url).load(.duration).seconds) ?? -1
                    try? FileManager.default.removeItem(at: entry.url)
                }
                readings.append(reading)
                note("run \(run + 1): \(reading)")
                try? await Task.sleep(for: .seconds(2))
                continue
            }
            note("run \(run + 1): waiting for start")
            await startTask?.value
            note("run \(run + 1): start returned, recording \(coordinator.isRecording)")
            await flipTask.value
            guard coordinator.isRecording else { out["error"] = "run \(run + 1) did not start"; return }
            NSLog("[recording-start-latency-diag] run \(run + 1) recording")
            try? await Task.sleep(for: .milliseconds(1500))
            FirstFrameClock.playtestWatch.withLock { $0 = nil }
            let start = coordinator.lastStartTrace
            let recorder = coordinator.lastRecorderStartTrace
            let firstFrame = coordinator.firstFrameHostSeconds
            note("run \(run + 1): stopping")
            await coordinator.stop()
            note("run \(run + 1): stopped; output started \(coordinator.lastRecorderStartTrace.outputStarted.map { ($0 - pressedAt) * 1000 } ?? -1) ms, first frame \(firstFrame.map { ($0 - pressedAt) * 1000 } ?? -1) ms, stop trace \(String(describing: coordinator.lastStopTrace))")
            let deadline = Date().addingTimeInterval(10)
            while landedEntry == nil, Date() < deadline { try? await Task.sleep(for: .milliseconds(10)) }
            note("run \(run + 1): landed \(landedEntry != nil)")

            var reading: [String: Any] = [
                "returnToFirstFrameMS": ms(pressedAt, firstFrame) as Any,
                "returnToStartCalledMS": ms(pressedAt, start?.requested) as Any,
                "returnToControlsShownMS": ms(pressedAt, start?.controlsShown) as Any,
                "returnToContentReadyMS": ms(pressedAt, recorder.contentReady) as Any,
                "returnToStreamBuiltMS": ms(pressedAt, recorder.streamBuilt) as Any,
                "returnToCaptureStartedMS": ms(pressedAt, recorder.captureStarted) as Any,
                "returnToTimerStartedMS": ms(pressedAt, start?.timerStarted) as Any,
                "returnToSquareWhiteMS": ms(pressedAt, flippedAt) as Any,
                "plan": recorder.plan.map { "\($0)" + (recorder.reusedWarmFilter ? "+" : "") } as Any,
                "returnToOutputStartedMS": ms(pressedAt, recorder.outputStarted) as Any,
            ]
            if let entry = landedEntry {
                let check = await readFirstSecond(of: entry.url, flip: streamPixel(flipCentre), dot: streamPixel(dot))
                for (k, v) in check { reading[k] = v }
                // The file is right about where it starts when the square turns
                // at the same distance from its first frame as the stream saw it
                // turn from the clock's first frame.
                if let turned = check["squareTurnedAtFileMS"] as? Double, let firstFrame,
                   let seen = streamTurn.withLock({ $0 }) {
                    reading["clockErrorMS"] = turned - ((seen - firstFrame) * 1000).rounded()
                    reading["returnToStreamTurnMS"] = ms(pressedAt, seen)
                }
                if run == 0, let turned = check["squareTurnedAtFileMS"] as? Double {
                    await savePictures(of: entry.url, turnedAtMS: turned,
                                       crop: CGRect(x: flipFrame.minX - 10, y: hud.maxY + 10,
                                                    width: hud.maxX - flipFrame.minX + 20, height: hud.height + 20),
                                       pixel: streamPixel, scale: scale)
                }
                try? FileManager.default.removeItem(at: entry.url)
            } else {
                reading["error"] = "the file never landed"
            }
            readings.append(reading)
            // A person does not start the next recording the instant the last
            // one lands, and macOS is slow to list windows straight after one.
            try? await Task.sleep(for: .seconds(2))
            NSLog("[recording-start-latency-diag] run \(run + 1): \(reading)")
            try? await Task.sleep(for: .milliseconds(300))
        }

        if cancel {
            out["passed"] = readings.count == runs && readings.allSatisfy {
                $0["readyWhileCardUp"] as? Bool == true && $0["escapeTaken"] as? Bool == true
                    && $0["cardGone"] as? Bool == true && $0["nothingLeftAfterCancel"] as? Bool == true
            }
            return
        }
        if stopEarly {
            out["passed"] = readings.count == runs && readings.allSatisfy {
                $0["stoppedAfterStart"] as? Bool == true && $0["fileLanded"] as? Bool == true
            }
            return
        }
        // A run with no first frame reads as not a number, which fails the
        // set; JSON cannot carry one, so only real readings are written.
        let firsts = readings.map { $0["returnToFirstFrameMS"] as? Double ?? .nan }
        let real = firsts.filter(\.isFinite).sorted()
        if !real.isEmpty {
            out["medianFirstFrameMS"] = RecordingStartBudget.median(real)
            out["worstFirstFrameMS"] = real.last
            out["bestFirstFrameMS"] = real.first
        }
        out["everyFileBeganBeforeTheSquareTurned"] = readings.allSatisfy { $0["firstFrameSquare"] as? String == "black" }
        out["everyFileShowedTheSquareTurn"] = still ? nil : readings.allSatisfy { $0["squareTurnedAtFileMS"] is Double }
        out["controlsAlwaysOutOfTheVideo"] = readings.allSatisfy { $0["controlsInVideo"] as? Bool == false }
        out["budgetMS"] = RecordingStartBudget.returnToFirstFrameMS
        out["passed"] = readings.count == runs
            && RecordingStartBudget.isWithin(readingsMS: firsts)
            && readings.allSatisfy { $0["firstFrameSquare"] as? String == "black" && (still || $0["squareTurnedAtFileMS"] is Double)
                && $0["controlsInVideo"] as? Bool == false }
    }

    /// Writes the file's first frame and the frame the square turns white in,
    /// cut down to the squares and the stop control's place (nothing else of
    /// the person's screen), to /tmp/photonz-start-frame-first.png and -turn.png.
    private static func savePictures(of url: URL, turnedAtMS: Double, crop: CGRect,
                                     pixel: (CGPoint) -> (Int, Int), scale: CGFloat) async {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let topLeft = pixel(CGPoint(x: crop.minX, y: crop.minY))
        let cut = CGRect(x: topLeft.0, y: topLeft.1, width: Int(crop.width * scale), height: Int(crop.height * scale))
        for (name, ms) in [("first", 0.0), ("turn", turnedAtMS)] {
            let at = CMTime(value: CMTimeValue(ms), timescale: 1000)
            guard let image = try? await generator.image(at: at).image, let piece = image.cropping(to: cut),
                  let dest = CGImageDestinationCreateWithURL(
                    URL(fileURLWithPath: "/tmp/photonz-start-frame-\(name).png") as CFURL, "public.png" as CFString, 1, nil)
            else { continue }
            CGImageDestinationAddImage(dest, piece, nil)
            CGImageDestinationFinalize(dest)
        }
    }

    /// The mean of a BGRA pixel's channels, or nil off the picture.
    nonisolated private static func shade(of buffer: CVPixelBuffer, at p: (Int, Int)) -> Int? {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard p.0 >= 0, p.1 >= 0, p.0 < CVPixelBufferGetWidth(buffer), p.1 < CVPixelBufferGetHeight(buffer)
        else { return nil }
        if CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_32BGRA {
            guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
            let px = base.advanced(by: p.1 * CVPixelBufferGetBytesPerRow(buffer) + p.0 * 4).assumingMemoryBound(to: UInt8.self)
            return (Int(px[0]) + Int(px[1]) + Int(px[2])) / 3
        }
        // Y'CbCr: the first plane is brightness, one byte a pixel.
        guard CVPixelBufferIsPlanar(buffer), let base = CVPixelBufferGetBaseAddressOfPlane(buffer, 0) else { return nil }
        return Int(base.advanced(by: p.1 * CVPixelBufferGetBytesPerRowOfPlane(buffer, 0) + p.0)
            .assumingMemoryBound(to: UInt8.self).pointee)
    }

    /// Reads the file's first second and reports what the black square and
    /// the stop control's dot look like in it.
    private static func readFirstSecond(of url: URL, flip: (Int, Int), dot: (Int, Int)) async -> [String: Any] {
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .video).first,
              let reader = try? AVAssetReader(asset: asset) else { return ["error": "unreadable file"] }
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        reader.add(output)
        reader.timeRange = CMTimeRange(start: .zero, duration: CMTime(value: 1, timescale: 1))
        guard reader.startReading() else { return ["error": "unreadable file"] }
        var result: [String: Any] = [:]
        var frames = 0
        var controlsInVideo = false
        var firstPTS: Double?
        while let sample = output.copyNextSampleBuffer() {
            guard let buffer = CMSampleBufferGetImageBuffer(sample) else { continue }
            let pts = CMSampleBufferGetPresentationTimeStamp(sample).seconds
            if firstPTS == nil { firstPTS = pts; result["fileFirstPTS"] = pts }
            CVPixelBufferLockBaseAddress(buffer, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
            guard let base = CVPixelBufferGetBaseAddress(buffer) else { continue }
            let row = CVPixelBufferGetBytesPerRow(buffer)
            let w = CVPixelBufferGetWidth(buffer), h = CVPixelBufferGetHeight(buffer)
            func bgr(_ p: (Int, Int)) -> (Int, Int, Int)? {
                guard p.0 >= 0, p.1 >= 0, p.0 < w, p.1 < h else { return nil }
                let px = base.advanced(by: p.1 * row + p.0 * 4).assumingMemoryBound(to: UInt8.self)
                return (Int(px[0]), Int(px[1]), Int(px[2]))
            }
            if let (b, g, r) = bgr(flip) {
                let shade = (r + g + b) / 3
                if frames == 0 { result["firstFrameSquare"] = shade < 60 ? "black" : shade > 200 ? "white" : "grey \(shade)" }
                if shade > 200, result["squareTurnedAtFileMS"] == nil {
                    result["squareTurnedAtFileMS"] = ((pts - (firstPTS ?? pts)) * 1000).rounded()
                }
            }
            // Pure green comes out about r118 g252 b76 in the display's own colours.
            if let (b, g, r) = bgr(dot), !(g > 200 && r < 170 && b < 130) {
                controlsInVideo = true
                if result["controlsSeenAs"] == nil { result["controlsSeenAs"] = "r\(r) g\(g) b\(b)" }
            }
            frames += 1
        }
        result["framesInFirstSecond"] = frames
        result["controlsInVideo"] = controlsInVideo
        return result
    }
}
#endif
