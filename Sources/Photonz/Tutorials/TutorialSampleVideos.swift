import Foundation
import PhotonzCore

// The recordings the editor's video guides open on.
//
// Each sample keeps its files in a folder of its own, so starting the captions
// guide never rewrites the recording the cut guide's window is still playing.
// What goes IN each document beyond the recording itself (b-roll on the shelf,
// two clips meeting at a cut) is `TutorialVideoSample`, in the core, where it
// is tested.
@MainActor
enum TutorialSampleVideos {

    static func folder(for sample: TutorialSample) -> URL {
        TutorialSampleRecording.url.deletingLastPathComponent()
            .appendingPathComponent(TutorialVideoSample.folderName(for: sample), isDirectory: true)
    }

    /// Writes what `sample` opens on, fresh: the recording, and the b-roll
    /// that goes with it where the sample has one. Nil when the recording
    /// itself would not write; a missing b-roll only leaves the shelf short.
    static func write(_ sample: TutorialSample) async -> (recording: URL, broll: URL?)? {
        let folder = folder(for: sample)
        switch sample {
        case .videoTalk:
            let url = folder.appendingPathComponent(TutorialSampleTalk.fileName)
            guard let written = await TutorialSampleTalk.fresh(at: url) else { return nil }
            return (written, nil)
        default:
            let url = folder.appendingPathComponent(TutorialSampleRecording.fileName)
            guard let written = TutorialSampleRecording.fresh(at: url) else { return nil }
            let broll = TutorialSampleRecording.fresh(
                at: folder.appendingPathComponent(TutorialVideoSample.brollFileName),
                background: TutorialSampleRecording.brollBackground)
            return (written, broll)
        }
    }
}
