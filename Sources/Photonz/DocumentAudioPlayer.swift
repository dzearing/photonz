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
@MainActor
final class DocumentAudioPlayer {

    /// The most pieces of sound one playthrough will schedule.
    ///
    /// Each one is an engine node and a decode, and a timeline with more than
    /// this many pieces of sound alive at once is one nobody is auditioning by
    /// ear. The rest are dropped rather than the engine being ground to a halt,
    /// and `droppedSegments` says how many so the app can tell somebody.
    static let segmentBudget = 48

    private let engine = AVAudioEngine()
    /// One mixer per layer: the layer's level is this node's volume, and
    /// following a level over time is setting it as the playhead moves.
    private var mixers: [UUID: AVAudioMixerNode] = [:]
    private var playing: [(node: AVAudioPlayerNode, extra: [AVAudioNode])] = []
    private var running = false

    /// How many pieces of sound were left out of the last playthrough because
    /// there were more than the budget. Nought nearly always.
    private(set) var droppedSegments = 0

    /// Whether the engine is running and has something scheduled on it.
    ///
    /// The one thing about playing that can be checked without ears, so a
    /// scripted walk can say the sound really started rather than photographing
    /// a playhead moving in silence.
    var isPlaying: Bool { running && !playing.isEmpty }

    /// How many pieces of sound are on the engine right now.
    var scheduledCount: Int { playing.count }

    /// Start the sound from a moment of the document's clock.
    ///
    /// Everything still to come is scheduled against one engine start, so all
    /// of it stays in step with everything else however long a decode takes:
    /// the engine's own clock is what the pieces are hung on, not a timer.
    func play(_ mix: [AudioMixSegment], fromMS: Int) {
        stop()
        let live = mix.filter { $0.endMS > fromMS && $0.isAudible }
            .sorted { $0.startMS < $1.startMS }
        droppedSegments = max(0, live.count - Self.segmentBudget)
        let scheduled = Array(live.prefix(Self.segmentBudget))
        guard !scheduled.isEmpty else { return }

        var files: [UUID: AVAudioFile] = [:]
        var attached: [(node: AVAudioPlayerNode, extra: [AVAudioNode], segment: AudioMixSegment,
                        file: AVAudioFile)] = []

        for segment in scheduled {
            guard let url = SoundLibrary.shared.url(for: segment.sound) else { continue }
            let file: AVAudioFile
            if let known = files[segment.sound.id] {
                file = known
            } else {
                guard let opened = try? AVAudioFile(forReading: url) else { continue }
                files[segment.sound.id] = opened
                file = opened
            }
            let mixer = layerMixer(for: segment.layerID)
            let node = AVAudioPlayerNode()
            engine.attach(node)
            var extra: [AVAudioNode] = []
            if segment.speedPercent != ClipPiece.asRecordedPercent {
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
        follow(scheduled, atMS: fromMS)
    }

    /// Keep each layer's level where the plan says it is at this moment.
    ///
    /// Called on the document's own clock as the playhead moves, which is what
    /// makes a duck a slide rather than a step: the tick is thirty times a
    /// second and a duck is a third of a second long.
    func follow(_ mix: [AudioMixSegment], atMS ms: Int) {
        guard running else { return }
        var wanted: [UUID: Float] = [:]
        for segment in mix where segment.contains(ms: ms) {
            wanted[segment.layerID] = Float(segment.gain(atMS: ms))
        }
        for (layerID, mixer) in mixers {
            mixer.volume = wanted[layerID] ?? 0
        }
    }

    /// Stop, and give every node back.
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

    private func layerMixer(for layerID: UUID) -> AVAudioMixerNode {
        if let known = mixers[layerID] { return known }
        let mixer = AVAudioMixerNode()
        engine.attach(mixer)
        engine.connect(mixer, to: engine.mainMixerNode, format: nil)
        mixers[layerID] = mixer
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
