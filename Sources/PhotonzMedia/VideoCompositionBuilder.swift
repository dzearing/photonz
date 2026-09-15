import AVFoundation
import Foundation
import PhotonzCore

/// Builds the thing the editor actually plays once a recording has been cut
/// into pieces: one `AVComposition` holding the kept stretches back to back.
///
/// Why a composition and not clever seeking: a player told to jump over a
/// dropped piece has to notice it has arrived, stop, seek, and start again, and
/// every one of those is a visible hitch at exactly the moment the person is
/// judging their cut. A composition has no join to jump — the frames either
/// side of a cut are neighbours in one asset, so playback runs straight through
/// it the way it runs through any other frame.
///
/// The composition's own clock IS timeline time, so the editor's playhead,
/// scrubber and cut strip all read straight off the player with no offset
/// bookkeeping.
public enum VideoCompositionBuilder {

    /// The composition that plays `cuts` of the file at `url`, or nil when the
    /// file has no video track to read. Audio comes along when the recording has
    /// any, cut at the same points so sound and picture stay together.
    public static func composition(of url: URL, cuts: VideoCutList) async -> AVComposition? {
        let asset = AVURLAsset(url: url)
        guard let videoTrack = try? await asset.loadTracks(withMediaType: .video).first else {
            return nil
        }
        let audioTrack = try? await asset.loadTracks(withMediaType: .audio).first
        let preferred = (try? await videoTrack.load(.preferredTransform)) ?? .identity

        let composition = AVMutableComposition()
        guard let compVideo = composition.addMutableTrack(
            withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else { return nil }
        // Orientation lives on the track, so a portrait recording keeps playing
        // portrait after being cut.
        compVideo.preferredTransform = preferred

        let compAudio = audioTrack == nil ? nil : composition.addMutableTrack(
            withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)

        var cursor = CMTime.zero
        for piece in cuts.sourceRanges {
            let range = CMTimeRange(
                start: CMTime(seconds: piece.start, preferredTimescale: 600),
                duration: CMTime(seconds: piece.length, preferredTimescale: 600))
            guard range.duration.seconds > 0 else { continue }
            do {
                try compVideo.insertTimeRange(range, of: videoTrack, at: cursor)
            } catch {
                continue
            }
            if let audioTrack, let compAudio {
                try? compAudio.insertTimeRange(range, of: audioTrack, at: cursor)
            }
            cursor = CMTimeAdd(cursor, range.duration)
        }
        guard cursor.seconds > 0 else { return nil }
        return composition
    }
}
