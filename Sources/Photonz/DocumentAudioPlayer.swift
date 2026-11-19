import AVFoundation
import Foundation
import PhotonzCore
import QuartzCore

// Playing the document's sound (`docs/design/video-audio.md`).
//
// **It works nothing out.** `PhotonzDocument.audioMix()` says which file, where
// it lands, what it reads, how fast and how loud; this schedules exactly that,
// and `AudioMixdown` writes exactly that. So "what you hear matches what
// exports" is not a thing to keep true, it is a thing that cannot go wrong:
// there is one plan and two renderers of it.
//
// One player node per piece of sound, all of a layer's pieces through one mixer
// so the layer's level is one number to move. A piece not at the speed it was
// recorded at gets a varispeed in front of it, which raises its pitch as it
// goes faster — the sound going with the picture, exactly as
// `ClipPiece.soundRatePercent` says it should.
//
// **Nothing here runs on the main thread except the arithmetic.** Making an
// audio engine costs about 45 ms the first time, starting it about 30 ms more,
// and opening the files and wiring the nodes a few more on every press. All of
// that used to happen inside the press of play, so the first L on a five
// minute recording held the window for a tenth of a second before the picture
// moved (2026-09-29). The engine now lives in `DocumentAudioEngine` below, on
// its own queue, and the press only hands it the plan.
@MainActor
final class DocumentAudioPlayer {

    private let engine = DocumentAudioEngine()

    /// How many pieces of sound the last playthrough left out so far: more
    /// were due at once than the engine holds (`AudioScheduleWindow.budget`),
    /// or the top-up did not get to them in time. Nought nearly always. Read
    /// off the engine, which keeps the count as it tops up.
    var droppedSegments: Int { engine.read { $0.leftOutCount } }

    /// Whether the engine is running and has something scheduled on it.
    ///
    /// The one thing about playing that can be checked without ears, so a
    /// scripted walk can say the sound really started rather than photographing
    /// a playhead moving in silence. Asked of the engine itself, after anything
    /// already handed to it has been done.
    var isPlaying: Bool { engine.read { $0.isPlaying } }

    /// How many pieces of sound are on the engine right now.
    var scheduledCount: Int { engine.read { $0.scheduledCount } }

    /// How loud the engine's output is: the transport's speaker and slider
    /// (`PlayerVolume.outputGain`). Muted, the pieces keep playing silently,
    /// so turning it back up is in step with the picture rather than
    /// restarting anything.
    func setOutputGain(_ gain: Double) {
        let held = Float(min(max(0, gain), 1))
        engine.run { $0.setOutputGain(held) }
    }

    /// What the engine's output is set to right now, read back off the engine
    /// itself so a walk checks what is heard rather than what was asked for.
    var outputGain: Double { engine.read { Double($0.outputGain) } }

    /// Start the sound from a moment of the document's clock.
    ///
    /// Everything still to come is scheduled against one engine start, so all
    /// of it stays in step with everything else however long a decode takes:
    /// the engine's own clock is what the pieces are hung on, not a timer.
    ///
    /// `speed` is the transport's (`PlaybackSpeed`): off normal the whole mix
    /// goes through one time stretch that keeps its pitch, the way QuickTime's
    /// half speed sounds slow rather than low.
    ///
    /// `playhead` is where the picture's clock was and when (seconds on the
    /// `CACurrentMediaTime` clock), and how fast it runs: the sound opens on
    /// the moment that clock will have reached when the sound is first heard,
    /// so it comes out in step with the picture rather than a fifth of a
    /// second behind it (`SoundStartMoment`). Without one, the playhead is
    /// taken as at `fromMS` now.
    func play(_ mix: [AudioMixSegment], fromMS: Int, speed: Double = PlaybackSpeed.normal,
              playhead: DocumentAudioEngine.Playhead? = nil) {
        let playhead = playhead
            ?? DocumentAudioEngine.Playhead(ms: fromMS, atSeconds: CACurrentMediaTime(), rate: speed)
        // Every piece still to come, in order of start: the engine puts on
        // the stretch just ahead of the playhead and tops it up as it plays
        // (`AudioScheduleWindow`), so a long edit is heard to its end.
        let pieces: [DocumentAudioEngine.Piece] = mix
            .filter { $0.endMS > fromMS && $0.isAudible }
            .sorted { $0.startMS < $1.startMS }
            .compactMap { segment in
                guard let url = SoundLibrary.shared.url(for: segment.sound) else { return nil }
                return DocumentAudioEngine.Piece(segment: segment, url: url)
            }
        let stretch = Float(PlaybackSpeed.holdsPitch(atRate: speed) ? speed : PlaybackSpeed.normal)
        engine.run { $0.play(pieces, playhead: playhead, speed: stretch) }
        follow(mix, atMS: fromMS)
    }

    /// The pieces of the plan on the engine right now, for a walk: what is
    /// due in the next stretch, never the whole edit.
    var scheduledSegments: [AudioMixSegment] { engine.read { $0.scheduledSegments } }

    /// Where the engine's own clock says the document is, for a walk to set
    /// beside the picture's. Nil when nothing is playing.
    var engineClockMS: Int? { engine.read { $0.clockMS() } }

    /// The moment of the document heard from the speaker at `hostSeconds`,
    /// output latency and all, and that latency in milliseconds. For a walk
    /// to set beside the picture on screen. Nil when nothing is playing.
    func heard(atHostSeconds hostSeconds: Double) -> (ms: Double, outputLatencyMS: Double)? {
        engine.read { engine in
            engine.heardMS(atHostSeconds: hostSeconds).map { ($0, engine.outputLatencySeconds * 1000) }
        }
    }

    /// The furthest a piece put on after the press landed from where the
    /// press's clock says it belongs, in milliseconds. For a walk.
    var worstLateSkewMS: Double { engine.read { $0.worstLateSkewMS } }

    /// The speed the engine's time stretch is running at: 1 when the mix goes
    /// straight out. Read off the engine, for a walk.
    var speed: Double { engine.read { Double($0.speed) } }

    /// The pitch of what the engine is putting out right now, listened to for
    /// `seconds` at the end of the chain (after the time stretch and the
    /// speaker's level): what a walk reads to say a test tone kept its pitch
    /// at half speed (`TonePitch`). Nil when nothing is playing.
    func listenForPitch(seconds: Double) async -> Double? {
        let heard = await engine.listen(seconds: seconds)
        guard let heard else { return nil }
        return TonePitch.hertz(of: heard.samples, sampleRate: heard.sampleRate)
    }

    /// How loud the engine's output is over `seconds`, as the root mean
    /// square of its samples: nought is silence. What a walk reads to say
    /// sound is really coming out at a moment, not just scheduled. Nil when
    /// nothing is playing.
    func listenForLevel(seconds: Double) async -> Double? {
        let heard = await engine.listen(seconds: seconds)
        guard let heard, !heard.samples.isEmpty else { return nil }
        let power = heard.samples.reduce(0.0) { $0 + Double($1) * Double($1) }
        return (power / Double(heard.samples.count)).squareRoot()
    }

    /// Keep each layer's level where the plan says it is at this moment.
    ///
    /// Called on the document's own clock as the playhead moves, which is what
    /// makes a duck a slide rather than a step: the tick is thirty times a
    /// second and a duck is a third of a second long.
    func follow(_ mix: [AudioMixSegment], atMS ms: Int) {
        var wanted: [DocumentAudioEngine.Voice: Float] = [:]
        for segment in mix where segment.contains(ms: ms) {
            wanted[DocumentAudioEngine.Voice(segment)] = Float(segment.gain(atMS: ms))
        }
        engine.run { [wanted] in $0.setLevels(wanted) }
    }

    /// Stop, and give every node back.
    func stop() {
        engine.run { $0.stop() }
    }
}

/// The engine, the open files and the nodes, all on one queue of their own.
///
/// A queue rather than an actor, like `ScrubAudioEngine`, for two reasons: a
/// press of play followed at once by a press of stop has to reach the engine
/// in that order, which a queue promises and a pair of tasks does not; and a
/// walk asks what is on the engine and needs the answer there and then
/// (`read`). Everything crossing into it is a value (a piece of the plan, a
/// file's location, a level), and nothing outside touches the engine.
///
/// `@unchecked Sendable` because every stored property below is only ever
/// touched inside `queue`: `run` and `read` are the only ways in.
final class DocumentAudioEngine: @unchecked Sendable {

    /// One piece of the plan and the file it plays.
    typealias Span = AudioScheduleWindow.Span

    struct Piece: Sendable {
        let segment: AudioMixSegment
        let url: URL
    }

    /// The picture's clock at one instant: the playhead's moment, when it
    /// was there (seconds on the `CACurrentMediaTime` clock), and how fast
    /// it runs.
    struct Playhead: Sendable {
        let ms: Int
        let atSeconds: Double
        let rate: Double
    }

    /// How far after the engine is running everything at the press is
    /// started, so every node is on and scheduled before its first sample is
    /// due and two sounds meant to start together do.
    private static let leadSeconds = 0.05

    /// One mixer per voice of a layer: the level is this node's volume, and
    /// following a level over time is setting it as the playhead moves. A
    /// layer has one voice, except while a transition on a join inside it has
    /// two of its pieces sounding at once, each on its own fader
    /// (`AudioMixSegment.voice`).
    struct Voice: Hashable, Sendable {
        let layerID: UUID
        let voice: Int
        init(_ segment: AudioMixSegment) {
            layerID = segment.layerID
            voice = segment.voice
        }
    }

    private let queue = DispatchQueue(label: "photonz.document-audio", qos: .userInitiated)

    /// Made on the queue, the first time anything is handed over, so even
    /// building it is off the main thread.
    private var engineStorage: AVAudioEngine?
    private var mixers: [Voice: AVAudioMixerNode] = [:]
    /// What is on the engine, by its index in `window.spans`.
    private var playing: [Int: OnEngine] = [:]
    private var running = false

    /// A piece on the engine: its node, a varispeed if it has one, and the
    /// piece of the plan it plays.
    private struct OnEngine {
        let node: AVAudioPlayerNode
        let extra: [AVAudioNode]
        let segment: AudioMixSegment
    }

    /// This playthrough: every piece still to come when play was pressed, in
    /// order of start, and which of them are on the engine
    /// (`AudioScheduleWindow`). Topped up by `topUp` off the engine's own
    /// clock, never the main thread's, so a window busy for seconds does not
    /// make the sound miss a cut.
    private var pieces: [Piece] = []
    private var window = AudioScheduleWindow(spans: [], fromMS: 0)
    private var files: [URL: AVAudioFile] = [:]
    private var tick: DispatchSourceTimer?
    /// How often the stretch ahead is topped up: far inside its twenty
    /// seconds, so a slow tick still lands every piece in time.
    private static let tickSeconds = 0.5

    /// The playthrough's clock: a player node with nothing on it, started
    /// with everything scheduled at the press and silent. Its own time is
    /// the document's time since then (upstream of the time stretch, so at
    /// 2x it runs at the document's pace too), which is what a piece put on
    /// later is placed against.
    private var clock: AVAudioPlayerNode?
    /// The moment of the document the clock's first sample plays. The
    /// clock and every piece at the press start at one host instant, so the
    /// clock's own time is the document's time since this moment.
    private var clockFromMS = 0
    /// Kept at nought: the press's pieces start at the clock's sample nought.
    private var leadSeconds = 0.0
    /// Pieces put on after the press, waiting to be checked against the
    /// clock once they have played a moment, and the worst any of them
    /// landed off the clock: how far a late piece is from where the press
    /// would have put it.
    private var lateToCheck: [(node: AVAudioPlayerNode, anchorMS: Double)] = []
    private(set) var worstLateSkewMS: Double = 0

    /// Between the voices and the output while the transport plays off normal
    /// speed: the voices gather in `gather` and that goes through `stretch`,
    /// which stretches time and keeps the pitch (`PlaybackSpeed`). A time
    /// pitch unit has ONE input: two voices connected straight to it left the
    /// first cut off, and its player crashed on play (2026-11-13). Nil at
    /// normal speed, when the voices go straight out.
    private var stretch: AVAudioUnitTimePitch?
    private var gather: AVAudioMixerNode?
    /// The rate `stretch` runs at, 1 without one.
    private(set) var speed: Float = 1

    init() {
        // Build the engine and its output now rather than at the first press:
        // a player is made when a document with sound opens its timeline.
        run { _ = $0.engine.mainMixerNode }
    }

    /// Hand work to the engine and carry on.
    func run(_ work: @escaping @Sendable (DocumentAudioEngine) -> Void) {
        queue.async { work(self) }
    }

    /// Ask the engine something, once everything already handed to it is done.
    /// Waits for the queue, so only a walk asks this.
    func read<T>(_ question: (DocumentAudioEngine) -> T) -> T {
        queue.sync { question(self) }
    }

    // MARK: - On the queue

    private var engine: AVAudioEngine {
        if let engineStorage { return engineStorage }
        let made = AVAudioEngine()
        engineStorage = made
        return made
    }

    /// A playthrough is under way: the engine is running with its clock.
    /// Pieces come and go on it as the playhead moves, so between two
    /// sounds far apart it can be running with nothing on it.
    var isPlaying: Bool { running && clock != nil }
    var scheduledCount: Int { playing.count }
    var scheduledSegments: [AudioMixSegment] { playing.values.map(\.segment) }
    var leftOutCount: Int { window.leftOut.count }
    var outputGain: Float { engine.mainMixerNode.outputVolume }

    func setOutputGain(_ gain: Float) {
        engine.mainMixerNode.outputVolume = gain
    }

    func play(_ pieces: [Piece], playhead: Playhead, speed: Float = 1) {
        stop()
        self.pieces = pieces
        worstLateSkewMS = 0
        guard !pieces.isEmpty else {
            window = AudioScheduleWindow(spans: [], fromMS: playhead.ms)
            return
        }
        if speed != 1 {
            // Every voice through one stretch, so everything slows together.
            // The player nodes upstream run on the document's clock, which
            // the stretch turns into the speaker's: a piece scheduled a
            // second of the document from now is heard half a second from
            // now at 2x, exactly where the picture is.
            let made = AVAudioUnitTimePitch()
            made.rate = speed
            made.pitch = 0
            let voices = AVAudioMixerNode()
            engine.attach(made)
            engine.attach(voices)
            engine.connect(voices, to: made, format: nil)
            engine.connect(made, to: engine.mainMixerNode, format: nil)
            stretch = made
            gather = voices
        }
        self.speed = speed

        // Which pieces go on first is judged from about where the sound will
        // open (the engine has not started, so not exactly): the stretch on
        // is twenty seconds long, so a tenth of a second either way changes
        // nothing about what is on it.
        let expected = SoundStartMoment.documentMS(
            playheadMS: playhead.ms, playheadAtSeconds: playhead.atSeconds,
            startsAtSeconds: Self.hostSecondsNow() + 0.1, outputLatencySeconds: outputLatencySeconds,
            rate: playhead.rate)
        window = AudioScheduleWindow(spans: pieces.map { Span(startMS: $0.segment.startMS, endMS: $0.segment.endMS) },
                                     fromMS: expected)
        let first = window.start()
        var attached: [(index: Int, node: AVAudioPlayerNode, file: AVAudioFile)] = []
        for index in first.add {
            guard let (node, file) = attach(index) else { continue }
            attached.append((index, node, file))
        }
        // The clock, silent, in the first piece's format or the output's when
        // nothing sounds in the first stretch: it starts either way, so a
        // sound that begins half a minute after the press is still put on
        // when its time comes.
        let format = attached.first?.file.processingFormat
            ?? AVAudioFormat(standardFormatWithSampleRate: engine.mainMixerNode.outputFormat(forBus: 0).sampleRate,
                             channels: 2)
        guard let format else {
            stop()
            return
        }
        let ticking = AVAudioPlayerNode()
        engine.attach(ticking)
        engine.connect(ticking, to: gather ?? engine.mainMixerNode, format: format)
        ticking.volume = 0
        clock = ticking

        engine.prepare()
        guard (try? engine.start()) != nil else {
            stop()
            return
        }
        running = true

        // One host instant a little ahead, now the engine runs, that the
        // clock and every piece start at, so two sounds meant to start
        // together do whatever order they were scheduled in. The sound opens
        // on the moment the picture will be showing when that instant comes
        // out of the speaker, not the moment play was pressed.
        let startsAt = Self.hostSecondsNow() + Self.leadSeconds
        clockFromMS = SoundStartMoment.documentMS(
            playheadMS: playhead.ms, playheadAtSeconds: playhead.atSeconds,
            startsAtSeconds: startsAt, outputLatencySeconds: outputLatencySeconds, rate: playhead.rate,
            pictureLagMS: SoundStartMoment.pictureLagMS)
        leadSeconds = 0
        let when = AVAudioTime(hostTime: AVAudioTime.hostTime(forSeconds: startsAt))
        let rate = format.sampleRate
        for item in attached {
            schedule(item.node, file: item.file, segment: pieces[item.index].segment, fromMS: clockFromMS,
                     lead: AVAudioTime(sampleTime: 0, atRate: rate), rate: rate)
        }
        for item in attached { item.node.play(at: when) }
        ticking.play(at: when)

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + Self.tickSeconds, repeating: Self.tickSeconds,
                       leeway: .milliseconds(100))
        timer.setEventHandler { [weak self] in self?.topUp() }
        timer.resume()
        tick = timer
    }

    /// Now, in seconds on the host clock (the one `CACurrentMediaTime` and
    /// `AVAudioTime`'s host times count).
    private static func hostSecondsNow() -> Double {
        AVAudioTime.seconds(forHostTime: mach_absolute_time())
    }

    /// Where the document is by the engine's own clock, in milliseconds.
    func clockMS() -> Int? {
        clockSeconds().map { Int((Double(clockFromMS) + ($0 - leadSeconds) * 1000).rounded()) }
    }

    /// What the output device adds between the engine and the room, in
    /// seconds: the hardware's latency and its safety offset, which is a
    /// tenth of a second or more on wireless headphones.
    var outputLatencySeconds: Double { engine.outputNode.presentationLatency }

    /// The moment of the document coming out of the speaker at `hostSeconds`
    /// (the `CACurrentMediaTime` clock), in milliseconds: the clock node's
    /// last render, carried on to that instant at the speed it runs, less the
    /// output's own latency. Nil when nothing is playing.
    func heardMS(atHostSeconds hostSeconds: Double) -> Double? {
        guard running, let clock, let rendered = clock.lastRenderTime, rendered.isHostTimeValid,
              rendered.isSampleTimeValid, let own = clock.playerTime(forNodeTime: rendered) else { return nil }
        let renderedDocMS = Double(clockFromMS) + (Double(own.sampleTime) / own.sampleRate - leadSeconds) * 1000
        let since = hostSeconds - AVAudioTime.seconds(forHostTime: rendered.hostTime) - outputLatencySeconds
        return renderedDocMS + since * 1000 * Double(speed)
    }

    /// Seconds on the clock node's own time since the press.
    private func clockSeconds() -> Double? {
        guard running, let clock, let rendered = clock.lastRenderTime, rendered.isSampleTimeValid,
              let own = clock.playerTime(forNodeTime: rendered) else { return nil }
        return Double(own.sampleTime) / own.sampleRate
    }

    /// The playhead has moved on: take off what has finished and put on what
    /// is coming up, each placed against the clock.
    private func topUp() {
        checkLatePieces()
        guard running, let clock, let rendered = clock.lastRenderTime, rendered.isHostTimeValid,
              rendered.isSampleTimeValid, let own = clock.playerTime(forNodeTime: rendered) else { return }
        let nowMS = Double(clockFromMS) + (Double(own.sampleTime) / own.sampleRate - leadSeconds) * 1000
        let step = window.advance(toMS: Int(nowMS))
        for index in step.retire {
            guard let gone = playing.removeValue(forKey: index) else { continue }
            gone.node.stop()
            detach(gone.node, extra: gone.extra)
            lateToCheck.removeAll { $0.node === gone.node }
        }
        dropIdleMixers()
        guard !step.add.isEmpty else { return }
        // Each new node starts at one exact instant a little ahead, a moment
        // of the document the clock says that instant is: the clock's last
        // render, plus the document time between, at the speed it runs. So a
        // piece put on now lands where the press would have put it, rather
        // than wherever the next render happens to fall.
        let aheadMS = 150.0
        let anchorMS = nowMS + aheadMS
        let startsAt = AVAudioTime(hostTime: rendered.hostTime
            + AVAudioTime.hostTime(forSeconds: aheadMS / 1000 / Double(max(speed, 0.01))))
        for index in step.add {
            guard let (node, file) = attach(index) else { continue }
            let rate = file.processingFormat.sampleRate
            schedule(node, file: file, segment: pieces[index].segment, fromMS: Int(anchorMS.rounded()),
                     lead: AVAudioTime(sampleTime: 0, atRate: rate), rate: rate)
            node.play(at: startsAt)
            lateToCheck.append((node, anchorMS.rounded()))
        }
    }

    /// For each piece put on after the press that has played a moment: where
    /// its own time says the document is against where the clock says, at
    /// the same instant. The worst is kept for a walk to read.
    private func checkLatePieces() {
        guard let clock, let clockRendered = clock.lastRenderTime, clockRendered.isHostTimeValid,
              let clockOwn = clock.playerTime(forNodeTime: clockRendered) else { return }
        let clockDocMS = Double(clockFromMS)
            + (Double(clockOwn.sampleTime) / clockOwn.sampleRate - leadSeconds) * 1000
        lateToCheck.removeAll { late in
            guard let rendered = late.node.lastRenderTime, rendered.isHostTimeValid,
                  let own = late.node.playerTime(forNodeTime: rendered), own.sampleTime > 0 else { return false }
            let lateDocMS = late.anchorMS + Double(own.sampleTime) / own.sampleRate * 1000
            // The two were read at their own last renders: bring both to the
            // clock's instant.
            let apart = AVAudioTime.seconds(forHostTime: rendered.hostTime)
                - AVAudioTime.seconds(forHostTime: clockRendered.hostTime)
            let skew = lateDocMS - apart * 1000 * Double(speed) - clockDocMS
            worstLateSkewMS = max(worstLateSkewMS, abs(skew))
            return true
        }
    }

    /// Open the file and wire a node for one piece of `pieces`, ready to be
    /// scheduled. Nil when its file cannot be read.
    private func attach(_ index: Int) -> (AVAudioPlayerNode, AVAudioFile)? {
        let piece = pieces[index]
        let segment = piece.segment
        let file: AVAudioFile
        if let known = files[piece.url] {
            file = known
        } else {
            guard let opened = try? AVAudioFile(forReading: piece.url) else { return nil }
            files[piece.url] = opened
            file = opened
        }
        let mixer = voiceMixer(for: Voice(segment))
        let node = AVAudioPlayerNode()
        engine.attach(node)
        var extra: [AVAudioNode] = []
        if segment.speedPercent != ClipPiece.asRecordedPercent {
            // Always a rate a varispeed can actually take. `AVAudioUnitVarispeed`
            // runs from 0.25 to 4, and the mix only ever carries pieces
            // between half speed and double, because outside that band a
            // piece plays silent and contributes no segment at all
            // (`ClipSpeedSound`, `ClipPiece.playsSound`). Before that rule
            // existed a piece at 10x asked this node for a rate of 10.
            let varispeed = AVAudioUnitVarispeed()
            varispeed.rate = Float(segment.speedPercent) / 100
            engine.attach(varispeed)
            engine.connect(node, to: varispeed, format: file.processingFormat)
            engine.connect(varispeed, to: mixer, format: file.processingFormat)
            extra.append(varispeed)
        } else {
            engine.connect(node, to: mixer, format: file.processingFormat)
        }
        playing[index] = OnEngine(node: node, extra: extra, segment: segment)
        return (node, file)
    }

    /// A voice with nothing left on it gives its mixer back, so an hour of
    /// playing does not leave an hour of layers' mixers on the engine.
    private func dropIdleMixers() {
        let used = Set(playing.values.map { Voice($0.segment) })
        for (voice, mixer) in mixers where !used.contains(voice) {
            engine.detach(mixer)
            mixers[voice] = nil
        }
    }

    /// Every voice at the level asked for; a voice with nothing sounding at
    /// this moment is silent.
    func setLevels(_ wanted: [Voice: Float]) {
        guard running else { return }
        for (voice, mixer) in mixers {
            mixer.volume = wanted[voice] ?? 0
        }
    }

    func stop() {
        tick?.cancel()
        tick = nil
        guard running || !playing.isEmpty || clock != nil else { return }
        for item in playing.values {
            item.node.stop()
            detach(item.node, extra: item.extra)
        }
        playing = [:]
        lateToCheck = []
        if let clock {
            clock.stop()
            engine.detach(clock)
        }
        clock = nil
        for (_, mixer) in mixers { engine.detach(mixer) }
        mixers = [:]
        if let stretch { engine.detach(stretch) }
        if let gather { engine.detach(gather) }
        stretch = nil
        gather = nil
        speed = 1
        files = [:]
        if running { engine.stop() }
        running = false
    }

    /// What the output puts out for `seconds`, the first channel of it, from
    /// a tap on the main mixer. Waits off the queue, so playing carries on.
    func listen(seconds: Double) async -> (samples: [Float], sampleRate: Double)? {
        let heard = HeardSamples()
        // Installed and taken off on the queue, like everything else that
        // touches the engine.
        let sampleRate: Double = read { engine in
            guard engine.running else { return 0 }
            let mixer = engine.engine.mainMixerNode
            let format = mixer.outputFormat(forBus: 0)
            mixer.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
                guard let channel = buffer.floatChannelData?[0] else { return }
                heard.append(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
            }
            return format.sampleRate
        }
        guard sampleRate > 0 else { return nil }
        try? await Task.sleep(for: .seconds(seconds))
        read { $0.engine.mainMixerNode.removeTap(onBus: 0) }
        let samples = heard.samples
        return samples.isEmpty ? nil : (samples, sampleRate)
    }

    // MARK: - The pieces of it

    private func voiceMixer(for voice: Voice) -> AVAudioMixerNode {
        if let known = mixers[voice] { return known }
        let mixer = AVAudioMixerNode()
        engine.attach(mixer)
        engine.connect(mixer, to: gather ?? engine.mainMixerNode, format: nil)
        mixers[voice] = mixer
        return mixer
    }

    /// Which frames of the file this piece plays, and when.
    ///
    /// A piece already under way when play was pressed starts part of the way
    /// into itself, which is what makes pressing space in the middle of a
    /// sentence carry on from the middle of the sentence.
    private func schedule(_ node: AVAudioPlayerNode, file: AVAudioFile,
                          segment: AudioMixSegment, fromMS: Int,
                          lead: AVAudioTime, rate: Double) {
        // A piece over before the sound opens (it ended in the moment the
        // engine took to start) plays nothing, not its last sample.
        guard segment.endMS > fromMS else { return }
        let intoSegment = max(0, fromMS - segment.startMS)
        let speed = Double(max(1, segment.speedPercent)) / 100
        let sourceStartMS = segment.sourceInMS + Int(Double(intoSegment) * speed)
        let sourceLengthMS = max(1, segment.sourceOutMS - sourceStartMS)

        let fileRate = file.processingFormat.sampleRate
        let start = AVAudioFramePosition(Double(sourceStartMS) / 1000 * fileRate)
        let frames = AVAudioFrameCount(max(1, Double(sourceLengthMS) / 1000 * fileRate))
        guard start >= 0, start < file.length else { return }
        let available = AVAudioFrameCount(min(AVAudioFramePosition(frames), file.length - start))
        guard available > 0 else { return }

        let delaySeconds = max(0, Double(segment.startMS - fromMS) / 1000)
        let at = AVAudioTime(sampleTime: lead.sampleTime + AVAudioFramePosition(delaySeconds * rate),
                             atRate: rate)
        node.scheduleSegment(file, startingFrame: start, frameCount: available, at: at)
    }

    private func detach(_ node: AVAudioPlayerNode, extra: [AVAudioNode]) {
        engine.detach(node)
        for one in extra { engine.detach(one) }
    }
}

/// Samples a tap hands over on the audio thread, read once listening stops.
/// `@unchecked Sendable` because the one lock guards everything in it.
private final class HeardSamples: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [Float] = []

    func append(_ more: UnsafeBufferPointer<Float>) {
        lock.lock()
        stored.append(contentsOf: more)
        lock.unlock()
    }

    var samples: [Float] {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }
}
