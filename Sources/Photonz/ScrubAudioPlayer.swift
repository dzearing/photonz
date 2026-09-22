import AVFoundation
import Foundation
import PhotonzCore

// Hearing the sound under the playhead while you drag it
// (`docs/design/video-audio.md` §5b).
//
// **It works nothing out.** `ScrubAudition.windows(in:movingFromMS:toMS:)`
// says which file, which frames of it, which way round and how loud; this
// reads exactly that out of the file and plays it once. So a scrub is the same
// sound as playing and the same sound as an export, for the same reason those
// two agree: there is one plan and three renderers of it.
//
// Its own engine rather than a second path through `DocumentAudioPlayer`,
// because the two want opposite things. Playing schedules whole pieces against
// one engine start and lets the engine's clock carry them. A scrub has no
// clock: the clock is somebody's hand, so there is nothing to schedule ahead
// and every grain is decided at the moment the hand asks for it.
//
// **Nothing here runs on the main thread except the arithmetic.** Starting an
// audio engine costs tens of milliseconds and seeking a compressed file can
// cost a frame, and either of those on the main thread is the playhead
// visibly stopping to listen. So the engine and the files live in
// `ScrubAudioEngine` below, off the main actor, and the hand only ever hands
// it a list of values and carries on.

/// The hand on the playhead: how often a grain is due, and what has come out
/// so far. The engine itself is somewhere else.
@MainActor
final class ScrubAudioPlayer {

    /// How often a grain is allowed to start, which is exactly how long one
    /// is: they butt up against each other, so a hand moving steadily makes a
    /// continuous sound and a hand that stops goes quiet inside a grain.
    static let grainInterval = Double(ScrubAudition.windowMS) / 1000

    private let engine = ScrubAudioEngine()

    /// Where the playhead was when the last grain was taken, and when that
    /// was. The pair is the whole of the pacing: a grain covers the ground
    /// between them, which is what makes the direction of the drag the
    /// direction of the sound.
    private var lastGrainMS: Int?
    private var lastGrainAt: Date?
    /// Which grain this is, so one that arrives at the engine behind a later
    /// one is dropped rather than played out of order.
    private var grainNumber = 0

    /// How many grains this drag has sent. Nought until the hand has actually
    /// moved for a grain's worth of time, which is what keeps a single CLICK
    /// on the timeline silent: a click is over before the first grain is due.
    private(set) var grainsPlayed = 0

    /// How many of those played back to front, which is the whole of dragging
    /// backwards.
    private(set) var grainsReversed = 0

    /// Which layers have actually been heard during this drag. Two sounds laid
    /// over each other put two ids in here, which is how a walk says they were
    /// both heard rather than only the top one.
    private(set) var layersHeard: Set<UUID> = []

    /// The longest a single grain has cost THE HAND, in milliseconds: the
    /// arithmetic and handing it over, and nothing else. The one number that
    /// says whether the sound is costing the picture.
    private(set) var worstGrainMS: Double = 0

    /// Whether a drag is in hand.
    var isAuditioning: Bool { lastGrainMS != nil }

    /// Whether sound has actually come out of this drag.
    var isMakingSound: Bool { isAuditioning && grainsPlayed > 0 }

    /// The loudest sample this drag has actually put on the engine.
    ///
    /// The difference between "fifteen grains were scheduled" and "something
    /// was audible": fifteen grains of silence schedule exactly as well as
    /// fifteen grains of somebody talking. Nought means nothing came out.
    func loudestSample() async -> Float { await engine.loudestSample }

    // MARK: - The drag

    /// A drag on the playhead started here. Nothing is heard yet: what is
    /// heard is movement, and so far there has been none.
    ///
    /// The files are opened and the engine started from here, off the main
    /// thread, so by the time the first grain is due — a sixteenth of a second
    /// later — there is something to play it on.
    func begin(_ mix: [AudioMixSegment], atMS ms: Int) {
        lastGrainMS = ms
        lastGrainAt = Date()
        grainNumber = 0
        grainsPlayed = 0
        grainsReversed = 0
        layersHeard = []
        worstGrainMS = 0
        var urls: [UUID: URL] = [:]
        for segment in mix where segment.isAudible && urls[segment.sound.id] == nil {
            urls[segment.sound.id] = SoundLibrary.shared.url(for: segment.sound)
        }
        let opening = urls.compactMapValues { $0 }
        // Which file each layer plays, because a node has to be wired up at
        // the format of the file it will be handed buffers from: a recording
        // at 48kHz and a piece of music at 44.1kHz cannot share one.
        var layerSounds: [UUID: UUID] = [:]
        for segment in mix where segment.isAudible { layerSounds[segment.layerID] = segment.sound.id }
        Task { [engine] in await engine.warmUp(files: opening, layerSounds: layerSounds) }
    }

    /// The playhead landed on a new moment. Takes a grain if one is due, and
    /// says whether it did.
    @discardableResult
    func moved(_ mix: [AudioMixSegment], toMS ms: Int) -> Bool {
        guard let fromMS = lastGrainMS, let since = lastGrainAt else { return false }
        let now = Date()
        guard now.timeIntervalSince(since) >= Self.grainInterval else { return false }
        lastGrainMS = ms
        lastGrainAt = now
        let windows = ScrubAudition.windows(in: mix, movingFromMS: fromMS, toMS: ms)
        guard !windows.isEmpty else { return false }
        grainNumber += 1
        grainsPlayed += 1
        if windows.contains(where: \.isReversed) { grainsReversed += 1 }
        layersHeard.formUnion(windows.map(\.layerID))
        let number = grainNumber
        Task { [engine] in await engine.play(windows, number: number) }
        worstGrainMS = max(worstGrainMS, Date().timeIntervalSince(now) * 1000)
        return true
    }

    /// The hand let go. Everything stops at once and every node goes back:
    /// what is under the playhead when nobody is dragging is a picture, not a
    /// sound.
    func end() {
        lastGrainMS = nil
        lastGrainAt = nil
        Task { [engine] in await engine.stop() }
    }
}

/// The engine, the open files and the nodes, all off the main actor.
///
/// Everything crossing into it is a value — a window, a file's location, a
/// layer's id — so nothing about audio ever has to be held still for the main
/// thread, and the main thread never waits on a decode.
actor ScrubAudioEngine {

    private let engine = AVAudioEngine()
    /// One node per LAYER, so two sounds under the playhead stay two sounds
    /// and neither cuts the other off.
    private var nodes: [UUID: AVAudioPlayerNode] = [:]
    /// The files this scrub has opened, kept for the length of the drag: a
    /// drag asks for the same file twenty times a second.
    private var files: [UUID: AVAudioFile] = [:]
    private var running = false
    /// The last grain actually played, so one that arrives late is dropped
    /// rather than played after the one that should have followed it.
    private var lastPlayed = 0
    /// The loudest sample put on the engine since the last warm up.
    private(set) var loudestSample: Float = 0

    /// Open the files, wire a node per layer, start the engine. Called at the
    /// press, so the first grain a sixteenth of a second later has somewhere
    /// to go.
    func warmUp(files opening: [UUID: URL], layerSounds: [UUID: UUID]) {
        lastPlayed = 0
        loudestSample = 0
        for (id, url) in opening where files[id] == nil {
            files[id] = try? AVAudioFile(forReading: url)
        }
        for (layer, soundID) in layerSounds where nodes[layer] == nil {
            // Each node at ITS OWN file's format: a node handed a buffer in a
            // format it was not connected at is a crash, not a wrong noise.
            guard let format = files[soundID]?.processingFormat else { continue }
            let node = AVAudioPlayerNode()
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: format)
            nodes[layer] = node
        }
        guard !nodes.isEmpty, !running else { return }
        engine.prepare()
        running = (try? engine.start()) != nil
    }

    /// Play one tick's worth: a grain per piece of sound under the playhead.
    func play(_ windows: [ScrubWindow], number: Int) {
        guard running, number > lastPlayed else { return }
        lastPlayed = number
        for window in windows {
            guard let file = files[window.sound.id],
                  let node = nodes[window.layerID],
                  let buffer = grain(from: file, window: window) else { continue }
            node.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
            if !node.isPlaying { node.play() }
        }
    }

    /// Everything back: the nodes stopped and detached, the files closed, the
    /// engine given up, so nothing is left running between drags.
    func stop() {
        for (_, node) in nodes {
            node.stop()
            engine.detach(node)
        }
        nodes = [:]
        files = [:]
        if running { engine.stop() }
        running = false
    }

    /// The samples themselves: read where the window says, turned round where
    /// the hand is going backwards, and faded at both ends.
    ///
    /// The fade is not decoration. A grain is a waveform cut off wherever it
    /// happened to be, and a waveform cut off mid-cycle is a click; a run of
    /// them is a buzz loud enough to drown what you were listening for.
    private func grain(from file: AVAudioFile, window: ScrubWindow) -> AVAudioPCMBuffer? {
        let format = file.processingFormat
        let rate = format.sampleRate
        guard rate > 0 else { return nil }
        let start = AVAudioFramePosition((Double(window.sourceInMS) / 1000 * rate).rounded())
        guard start >= 0, start < file.length else { return nil }
        let wanted = AVAudioFrameCount(max(1, (Double(window.lengthMS) / 1000 * rate).rounded()))
        let count = min(wanted, AVAudioFrameCount(file.length - start))
        guard count > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: count)
        else { return nil }
        file.framePosition = start
        guard (try? file.read(into: buffer, frameCount: count)) != nil,
              buffer.frameLength > 0, let channels = buffer.floatChannelData else { return nil }

        let frames = Int(buffer.frameLength)
        let fade = max(1, min(Int(Double(ScrubAudition.fadeMS) / 1000 * rate), frames / 2))
        let gain = Float(window.gain)
        for channel in 0..<Int(format.channelCount) {
            let samples = channels[channel]
            if window.isReversed {
                var head = 0, tail = frames - 1
                while head < tail {
                    let keep = samples[head]
                    samples[head] = samples[tail]
                    samples[tail] = keep
                    head += 1
                    tail -= 1
                }
            }
            for index in 0..<frames {
                var level = gain
                if index < fade {
                    level *= Float(index) / Float(fade)
                } else if index >= frames - fade {
                    level *= Float(frames - 1 - index) / Float(fade)
                }
                samples[index] *= level
                loudestSample = max(loudestSample, abs(samples[index]))
            }
        }
        return buffer
    }
}
