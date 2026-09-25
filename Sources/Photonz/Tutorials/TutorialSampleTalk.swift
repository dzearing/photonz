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

    /// The same talk, written wherever `url` says, with its picture written
    /// beside it rather than over the shared sample: the captions guide keeps
    /// its files in a folder of its own (`TutorialVideoSample.folderName`).
    static func fresh(at url: URL) async -> URL? {
        let manager = FileManager.default
        try? manager.createDirectory(at: url.deletingLastPathComponent(),
                                     withIntermediateDirectories: true)
        try? manager.removeItem(at: url)
        try? manager.removeItem(at: VideoOriginals.url(for: url))
        try? manager.removeItem(at: VideoEditsSidecar.url(for: url))
        let pictureURL = url.deletingPathExtension().appendingPathExtension("picture.mp4")
        defer { try? manager.removeItem(at: pictureURL) }
        guard let picture = TutorialSampleRecording.fresh(at: pictureURL),
              let voice = await TutorialSampleVoiceover.fresh() else { return nil }
        return await merge(picture: picture, voice: voice, into: url) ? url : nil
    }

    /// The picture played round until the voice has had its say, written as
    /// one file. `preset` and `type` let a long talk be written without
    /// encoding five minutes of picture again (`PlaytestLongTalk`).
    static func merge(picture: URL, voice: URL, into url: URL,
                      preset: String = AVAssetExportPresetHighestQuality,
                      as type: AVFileType = .mp4) async -> Bool {
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
              let session = AVAssetExportSession(asset: composition, presetName: preset)
        else { return false }
        do {
            try await session.export(to: url, as: type)
            return true
        } catch {
            return false
        }
    }
}
