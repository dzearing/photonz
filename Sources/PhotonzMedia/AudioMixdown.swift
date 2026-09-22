import AVFoundation
import Foundation
import PhotonzCore

/// Turning the document's mix plan into something AVFoundation can write
/// (`docs/design/video-audio.md`).
///
/// **This is the one place an export works out what it should sound like, and
/// it does not work anything out.** `PhotonzDocument.audioMix()` already said
/// which file, where it lands, what it reads, how fast and how loud; all that
/// happens here is saying it in AVFoundation's words. The player is handed the
/// same list, so what you hear and what you export cannot be two different
/// intentions — there is only the one intention and two renderers of it.
///
/// Built to be reused: `composition(for:urls:)` hands back an audio track and
/// its volume ramps, and when video export moves onto the document path it
/// adds a video track to the same composition rather than growing a second
/// idea of what a mix is.
public enum AudioMixdown {

    public enum MixError: Error { case nothingToMix, noFileForSound, exportFailed }

    /// The composition the mix describes, and the volume ramps that go over it.
    public struct Mixed {
        public let composition: AVMutableComposition
        public let audioMix: AVMutableAudioMix
        /// How long the mix runs for, in milliseconds.
        public let durationMS: Int
        /// How loud the mix was BEFORE it was held down, so whoever asked for
        /// it can say that it was. `isOver` here means the file on disk is
        /// quieter than the plan asked for, on purpose.
        public let headroom: AudioHeadroom
    }

    /// Lay the plan into a composition.
    ///
    /// Segments are dealt onto as few tracks as they fit on: AVFoundation will
    /// not let two stretches of one track overlap, so two sounds playing at the
    /// same moment take two tracks and a voiceover after music takes the same
    /// one. That is the whole of what "several pieces play together" needs.
    ///
    /// **Nothing leaves here louder than a file can hold.** The plan is read
    /// for how loud it gets (`AudioHeadroom`) and held under full scale before
    /// a single sample is laid down, so three sounds at the level they were
    /// recorded at come out as three sounds instead of as the flat top of a
    /// clipped waveform. A mix that already fits is untouched, and holding an
    /// already-held mix down changes nothing, so it does not matter whether the
    /// caller did it first.
    ///
    /// `peaks` is the shape of each sound, which the app has already read to
    /// draw its waveform. Leave it out and the files are read here instead;
    /// pass it and the export does not read them twice.
    public static func composition(for plan: [AudioMixSegment],
                                   urls: [UUID: URL],
                                   peaks: [UUID: Waveform]? = nil) async throws -> Mixed {
        guard !plan.isEmpty else { throw MixError.nothingToMix }
        var shapes: [UUID: Waveform]
        if let peaks { shapes = peaks } else { shapes = await Self.shapes(of: plan, urls: urls) }
        let headroom = AudioHeadroom.reading(of: plan, peaks: shapes)
        let mix = AudioHeadroom.limited(plan, by: headroom.trim)
        let composition = AVMutableComposition()
        var tracks: [AVMutableCompositionTrack] = []
        /// Where each track has been filled up to, so a segment can be dealt
        /// onto the first one that is free when it starts.
        var filledToMS: [Int] = []
        var parameters: [AVMutableAudioMixInputParameters] = []
        var durationMS = 0

        for segment in mix.sorted(by: { $0.startMS < $1.startMS }) {
            guard let url = urls[segment.sound.id] else { throw MixError.noFileForSound }
            let asset = AVURLAsset(url: url)
            guard let source = try? await asset.loadTracks(withMediaType: .audio).first
            else { continue }

            let index = tracks.indices.first { filledToMS[$0] <= segment.startMS } ?? tracks.count
            if index == tracks.count {
                guard let track = composition.addMutableTrack(
                    withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
                else { continue }
                tracks.append(track)
                filledToMS.append(0)
                parameters.append(AVMutableAudioMixInputParameters(track: track))
            }
            let track = tracks[index]

            // What to read out of the file, and where to put it. A piece
            // playing faster reads MORE of the file into the same stretch of
            // timeline, which is what `sourceLengthMS` already says.
            let read = CMTimeRange(start: ms(segment.sourceInMS),
                                   duration: ms(max(1, segment.sourceLengthMS)))
            let at = ms(segment.startMS)
            do {
                try track.insertTimeRange(read, of: source, at: at)
            } catch {
                continue
            }
            // ...and then squeezed or stretched to the length it occupies, which
            // is what makes a piece at 200% play twice as fast and rise in
            // pitch, exactly as its picture does.
            if segment.speedPercent != ClipPiece.asRecordedPercent {
                composition.scaleTimeRange(CMTimeRange(start: at, duration: read.duration),
                                           toDuration: ms(segment.lengthMS))
            }
            filledToMS[index] = segment.endMS
            durationMS = max(durationMS, segment.endMS)

            for ramp in segment.ramps where ramp.toMS > ramp.fromMS {
                parameters[index].setVolumeRamp(
                    fromStartVolume: Float(ramp.fromGain), toEndVolume: Float(ramp.toGain),
                    timeRange: CMTimeRange(start: ms(ramp.fromMS),
                                           duration: ms(ramp.toMS - ramp.fromMS)))
            }
        }

        guard !tracks.isEmpty else { throw MixError.nothingToMix }
        let audioMix = AVMutableAudioMix()
        audioMix.inputParameters = parameters
        return Mixed(composition: composition, audioMix: audioMix, durationMS: durationMS,
                     headroom: headroom)
    }

    /// The shape of every sound the plan plays, read off the files.
    ///
    /// Only used when the caller has none to hand. The app always does — the
    /// timeline read them to draw the waveforms — so this is the path a test or
    /// a headless export takes.
    static func shapes(of mix: [AudioMixSegment], urls: [UUID: URL]) async -> [UUID: Waveform] {
        var found: [UUID: Waveform] = [:]
        for segment in mix where found[segment.sound.id] == nil {
            guard let url = urls[segment.sound.id],
                  let reading = await SoundFile.read(at: url), !reading.waveform.isEmpty
            else { continue }
            found[segment.sound.id] = reading.waveform
        }
        return found
    }

    /// Write the mix out as one sound file.
    ///
    /// An m4a, because it is what every Mac plays without being asked twice.
    /// The picture is not in it: this is the mix on its own, which is what the
    /// Audio menu's Export Sound means and what makes the mix checkable by ear
    /// before there is any video export to check it inside of.
    /// Hands back how loud the mix was before it was written, so the app can
    /// say in its notice that it had to be held down.
    @discardableResult
    public static func write(_ mix: [AudioMixSegment], urls: [UUID: URL],
                             to destination: URL,
                             peaks: [UUID: Waveform]? = nil) async throws -> AudioHeadroom {
        let mixed = try await composition(for: mix, urls: urls, peaks: peaks)
        guard let session = AVAssetExportSession(asset: mixed.composition,
                                                 presetName: AVAssetExportPresetAppleM4A)
        else { throw MixError.exportFailed }
        session.audioMix = mixed.audioMix
        try? FileManager.default.removeItem(at: destination)
        try await session.export(to: destination, as: .m4a)
        return mixed.headroom
    }

    private static func ms(_ value: Int) -> CMTime {
        CMTime(value: CMTimeValue(max(0, value)), timescale: 1000)
    }
}
