import AVFoundation
import Foundation
import PhotonzCore

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

    /// The most pieces of sound one playthrough will schedule.
    ///
    /// Each one is an engine node and a decode, and a timeline with more than
    /// this many pieces of sound alive at once is one nobody is auditioning by
    /// ear. The rest are dropped rather than the engine being ground to a halt,
    /// and `droppedSegments` says how many so the app can tell somebody.
    static let segmentBudget = 48

    private let engine = DocumentAudioEngine()

    /// How many pieces of sound were left out of the last playthrough because
    /// there were more than the budget. Nought nearly always.
    private(set) var droppedSegments = 0

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
    func play(_ mix: [AudioMixSegment], fromMS: Int) {
        let live = mix.filter { $0.endMS > fromMS && $0.isAudible }
            .sorted { $0.startMS < $1.startMS }
        droppedSegments = max(0, live.count - Self.segmentBudget)
        let pieces: [DocumentAudioEngine.Piece] = live.prefix(Self.segmentBudget).compactMap { segment in
            guard let url = SoundLibrary.shared.url(for: segment.sound) else { return nil }
            return DocumentAudioEngine.Piece(segment: segment, url: url)
        }
        engine.run { $0.play(pieces, fromMS: fromMS) }
        follow(mix, atMS: fromMS)
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
    struct Piece: Sendable {
        let segment: AudioMixSegment
        let url: URL
    }

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
    private var playing: [(node: AVAudioPlayerNode, extra: [AVAudioNode])] = []
    private var running = false

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

    var isPlaying: Bool { running && !playing.isEmpty }
    var scheduledCount: Int { playing.count }
    var outputGain: Float { engine.mainMixerNode.outputVolume }

    func setOutputGain(_ gain: Float) {
        engine.mainMixerNode.outputVolume = gain
    }

    func play(_ pieces: [Piece], fromMS: Int) {
        stop()
        guard !pieces.isEmpty else { return }

        var files: [URL: AVAudioFile] = [:]
        var attached: [(node: AVAudioPlayerNode, extra: [AVAudioNode], segment: AudioMixSegment,
                        file: AVAudioFile)] = []

        for piece in pieces {
            let segment = piece.segment
            let file: AVAudioFile
            if let known = files[piece.url] {
                file = known
            } else {
                guard let opened = try? AVAudioFile(forReading: piece.url) else { continue }
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
                let speed = AVAudioUnitVarispeed()
                speed.rate = Float(segment.speedPercent) / 100
                engine.attach(speed)
                engine.connect(node, to: speed, format: file.processingFormat)
                engine.connect(speed, to: mixer, format: file.processingFormat)
                extra.append(speed)
            } else {
                engine.connect(node, to: mixer, format: file.processingFormat)
            }
            attached.append((node, extra, segment, file))
        }
        guard !attached.isEmpty else { return }

        engine.prepare()
        guard (try? engine.start()) != nil else {
            for item in attached { detach(item.node, extra: item.extra) }
            return
        }
        running = true

        // One moment in the future that everything is hung off, so two sounds
        // meant to start together do, whatever order they were scheduled in.
        let rate = attached[0].file.processingFormat.sampleRate
        let lead = AVAudioTime(sampleTime: AVAudioFramePosition(rate * 0.08), atRate: rate)
        for item in attached {
            schedule(item.node, file: item.file, segment: item.segment, fromMS: fromMS,
                     lead: lead, rate: rate)
            playing.append((item.node, item.extra))
            item.node.play()
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
        guard running || !playing.isEmpty else { return }
        for item in playing {
            item.node.stop()
            detach(item.node, extra: item.extra)
        }
        playing = []
        for (_, mixer) in mixers { engine.detach(mixer) }
        mixers = [:]
        if running { engine.stop() }
        running = false
    }

    // MARK: - The pieces of it

    private func voiceMixer(for voice: Voice) -> AVAudioMixerNode {
        if let known = mixers[voice] { return known }
        let mixer = AVAudioMixerNode()
        engine.attach(mixer)
        engine.connect(mixer, to: engine.mainMixerNode, format: nil)
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
