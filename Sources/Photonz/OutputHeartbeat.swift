import AVFoundation
import Synchronization

/// Counts the audio cycles an engine has run, so nothing starts a player on
/// it before its output is really turning over.
///
/// **Why it exists.** `AVAudioPlayerNode.play` waits for the engine's next
/// audio cycle, and if none comes within about five seconds it raises an
/// Objective-C exception, "player did not see an IO cycle.", which no Swift
/// code can catch: the app is gone. Right after `AVAudioEngine.start()` the
/// first cycle is the output device's to give, and a device slow to wake
/// (AirPlay, Bluetooth headphones coming out of sleep, a stalled process) can
/// take longer than that. The probe died exactly so on 2026-11-20, pressing
/// play while a debugger held the process.
///
/// A silent source node on the engine's main mixer counts each cycle it is
/// pulled in. Two counts since the start means one whole cycle has finished,
/// which is the one thing the player needs. The engine's own `lastRenderTime`
/// cannot say it: it is set as a cycle BEGINS, and after a restart it reads a
/// stale time from the run before.
///
/// `Sendable` because all it holds is two atomics; the node itself is made by
/// `makeNode` and belongs to the engine it is attached to.
final class OutputHeartbeat: Sendable {

    private let beats = Atomic<Int>(0)
    /// Microseconds to hold the next cycle up for, then nought. Only a walk
    /// sets it (`holdNextCycle`), to stand in for a slow output.
    private let holdMicroseconds = Atomic<Int>(0)

    /// Cycles run so far, over the engine's whole life.
    var count: Int { beats.load(ordering: .acquiring) }

    /// Whether a whole cycle has finished since `count` read `before`.
    func hasTurnedOver(since before: Int) -> Bool {
        count - before >= 2
    }

    /// The node to attach and connect to the engine's main mixer. Made here,
    /// in a class with no actor, on purpose: the render block runs on the
    /// audio thread, and a closure formed inside an actor (`ScrubAudioEngine`)
    /// would be checked against that actor there and stop the app.
    private func makeNode() -> AVAudioSourceNode {
        AVAudioSourceNode { [self] isSilence, _, _, audioBufferList in
            let hold = holdMicroseconds.exchange(0, ordering: .relaxed)
            if hold > 0 { usleep(useconds_t(hold)) }
            for buffer in UnsafeMutableAudioBufferListPointer(audioBufferList) {
                if let data = buffer.mData { memset(data, 0, Int(buffer.mDataByteSize)) }
            }
            isSilence.pointee = true
            beats.add(1, ordering: .releasing)
            return noErr
        }
    }

    /// Attach a fresh node to `engine` and connect it to the main mixer,
    /// silent and mono at the output's rate. Returns the node so its owner
    /// can keep it.
    func attach(to engine: AVAudioEngine) -> AVAudioSourceNode {
        let node = makeNode()
        engine.attach(node)
        let rate = engine.mainMixerNode.outputFormat(forBus: 0).sampleRate
        let format = AVAudioFormat(standardFormatWithSampleRate: rate > 0 ? rate : 48_000, channels: 1)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        return node
    }

    /// Hold the next cycle up for `seconds`, on the audio thread itself, the
    /// way an output device slow to start holds it up. For a walk only.
    func holdNextCycle(seconds: Double) {
        holdMicroseconds.store(Int(seconds * 1_000_000), ordering: .relaxed)
    }
}
