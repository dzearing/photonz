// A five minute screen recording with somebody talking the whole way through,
// for the walk that times the timeline once its captions have written
// themselves (`a-long-captioned-recording-walk`). Probe-only, like the rest of
// the harness.
#if PHOTONZ_PLAYTEST
import AVFoundation
import PhotonzCore
import Foundation

/// The long sibling of `TutorialSampleTalk`: the sample picture played round
/// for about five minutes under the Mac's own voice reading plain sentences
/// about the app, so the captions that write themselves come out at about the
/// thousand words and hundred and seventy cues a real five minute talk gives.
///
/// Speaking five minutes takes a while, so the talk is written once per
/// machine and kept; each walk opens a fresh COPY of it, because a copy that
/// had been captioned and saved would open with its captions already there
/// and nothing would write itself.
@MainActor
enum PlaytestLongTalk {

    static let fileName = "Long Talk.mov"
    private static let masterName = "Long Talk master 2.mov"
    private static let voiceName = "Long Talk voice.m4a"

    /// Forty plain sentences, said twice over and then the first sixteen
    /// again: about five minutes at the pace the sample voiceover talks at.
    static let script: String = {
        let sentences = [
            "Today I will show you how to set up a new project in the dashboard.",
            "First open the settings page and choose the team you want to work with.",
            "Then press the new project button in the top right corner.",
            "Give the project a short name, and pick a template from the list.",
            "The template decides which folders and checks you start with.",
            "Now we wait while the files copy across, which takes a few seconds.",
            "While that happens, look at the panel on the left of the window.",
            "It lists every page in the project, with the newest at the top.",
            "Click a page to open it, or drag it to change the order.",
            "A small dot beside a page means somebody else is editing it.",
            "Let us open the home page and change the heading.",
            "Select the heading, type the new words, and press return.",
            "The change is saved as you type, so there is no save button.",
            "If you make a mistake, press command Z to take it back.",
            "Next we add a picture under the heading.",
            "Drag the picture from the desktop straight onto the page.",
            "Grab a corner to make it smaller, and hold shift to keep its shape.",
            "The guides show you when it lines up with the text above it.",
            "Now we will invite a colleague to look at the draft.",
            "Press share, type their address, and choose whether they can edit.",
            "They get an email with a link that opens this same page.",
            "Comments they leave show up in the margin on the right.",
            "You can answer a comment, or mark it done when it is fixed.",
            "Let us look at the history of the page for a moment.",
            "Every change is listed with the time and the person who made it.",
            "Click any line to see the page as it was at that moment.",
            "If you like an older version better, you can bring it back.",
            "Next we set the page to publish on Monday morning.",
            "Open the publish menu, pick a date, and pick a time.",
            "The page stays a draft until then, and nobody else can see it.",
            "When it goes live, everybody on the team gets a short note.",
            "Finally, we check how the page looks on a phone.",
            "Press the phone button at the top to switch the preview.",
            "The picture moves under the text, and the menu folds away.",
            "Tap the menu to open it, the way a visitor would.",
            "Everything looks right, so we switch back to the full view.",
            "That is all it takes to start a project and share a first page.",
            "In the next video we will look at forms and how answers are collected.",
            "Thanks for watching, and see you in the next one.",
            "Let us start again from the top and go a little slower this time.",
        ]
        let once = sentences.joined(separator: " ")
        return [once, once, sentences.prefix(16).joined(separator: " ")].joined(separator: " ")
    }()

    private static var folder: URL { TutorialSampleVoiceover.url.deletingLastPathComponent() }
    static var url: URL { folder.appendingPathComponent(fileName) }

    /// A clean copy of the talk, written first if this Mac has never had one.
    static func fresh() async -> URL? {
        guard let master = await master() else { return nil }
        let url = Self.url
        for leftover in [url, VideoOriginals.url(for: url), VideoEditsSidecar.url(for: url)] {
            try? FileManager.default.removeItem(at: leftover)
        }
        return (try? FileManager.default.copyItem(at: master, to: url)) == nil ? nil : url
    }

    private static func master() async -> URL? {
        let master = folder.appendingPathComponent(masterName)
        if FileManager.default.fileExists(atPath: master.path) { return master }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let voice = folder.appendingPathComponent(voiceName)
        guard let picture = TutorialSampleRecording.fresh(),
              await TutorialSampleVoiceover.speak(script, to: voice),
              // The sample picture is already encoded: passing it through
              // round and round costs a copy, where encoding five minutes of
              // it again would cost a minute.
              await TutorialSampleTalk.merge(picture: picture, voice: voice, into: master,
                                             preset: AVAssetExportPresetPassthrough, as: .mov)
        else {
            try? FileManager.default.removeItem(at: master)
            return nil
        }
        return master
    }
}
#endif
