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
    }

    /// Lay the plan into a composition.
    ///
    /// Segments are dealt onto as few tracks as they fit on: AVFoundation will
    /// not let two stretches of one track overlap, so two sounds playing at the
    /// same moment take two tracks and a voiceover after music takes the same
    /// one. That is the whole of what "several pieces play together" needs.
    public static func composition(for mix: [AudioMixSegment],
                                   urls: [UUID: URL]) async throws -> Mixed {
        guard !mix.isEmpty else { throw MixError.nothingToMix }
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
        return Mixed(composition: composition, audioMix: audioMix, durationMS: durationMS)
    }

    /// Write the mix out as one sound file.
    ///
    /// An m4a, because it is what every Mac plays without being asked twice.
    /// The picture is not in it: this is the mix on its own, which is what the
    /// Audio menu's Export Sound means and what makes the mix checkable by ear
    /// before there is any video export to check it inside of.
    public static func write(_ mix: [AudioMixSegment], urls: [UUID: URL],
                             to destination: URL) async throws {
        let mixed = try await composition(for: mix, urls: urls)
        guard let session = AVAssetExportSession(asset: mixed.composition,
                                                 presetName: AVAssetExportPresetAppleM4A)
        else { throw MixError.exportFailed }
        session.audioMix = mixed.audioMix
        try? FileManager.default.removeItem(at: destination)
        try await session.export(to: destination, as: .m4a)
    }

    private static func ms(_ value: Int) -> CMTime {
        CMTime(value: CMTimeValue(max(0, value)), timescale: 1000)
    }
}
