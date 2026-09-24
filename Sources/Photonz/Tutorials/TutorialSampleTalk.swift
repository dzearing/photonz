import AVFoundation
import Foundation
import PhotonzCore

// A screen recording with somebody talking over it (`Captions.swift`).
//
// The tutorial recording's own sound is tones and blips, and the spoken
// voiceover is a sound on its own. Captions that write themselves are about
// what happens the moment a recording WITH speech opens, so a walk needs one:
// this is the tutorial picture, played round until the voice has finished,
// with the Mac's own voice as its sound track, written into one file.
@MainActor
enum TutorialSampleTalk {

    static let fileName = "Sample Talk.mp4"

    static var url: URL {
        TutorialSampleRecording.url.deletingLastPathComponent().appendingPathComponent(fileName)
    }

    /// A clean copy every time: opening it fresh is the whole point, and a
    /// copy with captions saved beside it would open with them already there.
    static func fresh() async -> URL? {
        let url = Self.url
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.removeItem(at: VideoOriginals.url(for: url))
        try? FileManager.default.removeItem(at: VideoEditsSidecar.url(for: url))
        guard let picture = TutorialSampleRecording.fresh(),
              let voice = await TutorialSampleVoiceover.fresh() else { return nil }
        return await merge(picture: picture, voice: voice, into: url) ? url : nil
    }

    private static func merge(picture: URL, voice: URL, into url: URL) async -> Bool {
        let pictureAsset = AVURLAsset(url: picture)
        let voiceAsset = AVURLAsset(url: voice)
        guard let videoTrack = try? await pictureAsset.loadTracks(withMediaType: .video).first,
              let voiceTrack = try? await voiceAsset.loadTracks(withMediaType: .audio).first,
              let pictureLength = try? await pictureAsset.load(.duration),
              let voiceLength = try? await voiceAsset.load(.duration),
              pictureLength.seconds > 0
        else { return false }
        let composition = AVMutableComposition()
        guard let video = composition.addMutableTrack(withMediaType: .video,
                                                      preferredTrackID: kCMPersistentTrackID_Invalid),
              let audio = composition.addMutableTrack(withMediaType: .audio,
                                                      preferredTrackID: kCMPersistentTrackID_Invalid)
        else { return false }
        // The picture, round and round until the voice has had its say.
        var at = CMTime.zero
        while at < voiceLength {
            let left = CMTimeSubtract(voiceLength, at)
            let take = CMTimeMinimum(pictureLength, left)
            guard (try? video.insertTimeRange(CMTimeRange(start: .zero, duration: take),
                                              of: videoTrack, at: at)) != nil else { return false }
            at = CMTimeAdd(at, take)
        }
        guard (try? audio.insertTimeRange(CMTimeRange(start: .zero, duration: voiceLength),
                                          of: voiceTrack, at: .zero)) != nil,
              let session = AVAssetExportSession(asset: composition,
                                                 presetName: AVAssetExportPresetHighestQuality)
        else { return false }
        do {
            try await session.export(to: url, as: .mp4)
            return true
        } catch {
            return false
        }
    }
}
