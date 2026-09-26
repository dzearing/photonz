import Foundation
import PhotonzCore

// What the captions mock draws round the captions rather than in them
// (`CaptionGuides.swift`, `docs/design/mocks/pages/video-captions.html`): the
// title-safe and action-safe guides over the picture, the AUTO · EN badge, and
// the Caption track bar's Reset.
//
// The guides and the badge are for placing and checking captions, so they are
// up only while there are captions and the timeline is open. A recording
// opened to watch, with the editing tucked away, stays a clean picture.
extension EditorState {

    /// **Safe areas.** Whether the guides are wanted. One switch for the whole
    /// app, on until somebody turns it off, as the mock opens.
    static var showsSafeAreas: Bool {
        get { UserDefaults.standard.object(forKey: safeAreasKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: safeAreasKey) }
    }
    private static let safeAreasKey = "captions.safeAreas"

    func toggleSafeAreas() {
        Self.showsSafeAreas.toggle()
        captionSettingsTick += 1
    }

    /// Whether the picture is being worked on as captioned video right now.
    private var isCaptioningOnScreen: Bool {
        Experiments.shared.captionsFromTheSoundEnabled && documentHasTime && hasCaptions
            && motionStripPhase == .open
    }

    /// Whether the safe-area guides are drawn over the picture.
    var showsSafeAreaGuides: Bool {
        _ = captionSettingsTick
        return Self.showsSafeAreas && isCaptioningOnScreen
    }

    /// The AUTO · EN badge, while the captions are the ones the app heard.
    var captionBadge: String? {
        _ = captionSettingsTick
        guard isCaptioningOnScreen else { return nil }
        return CaptionBadge.text(language: Self.captionsLanguage)
    }

    // MARK: - Reset

    var canResetCaptions: Bool {
        canClearCaptions && captionsLayerInFocus != nil
    }

    /// **Reset.** The Captions layer in focus back in the standard look and
    /// the box a fresh one lands in, as one undo step. The words stay.
    func resetCaptions() {
        guard canResetCaptions, let layer = captionsLayerInFocus else { return }
        perform { $0.resetCaptions(layer.id) }
        documentMomentChanged()
    }

    // MARK: - The Caption track bar's readings

    /// The word being said under the playhead, on any Captions layer.
    var captionWordBeingSaid: String? {
        guard let document = shownDocument else { return nil }
        let now = documentTimeMS
        for captions in document.captionsLayers {
            for cue in captions.children {
                guard let time = cue.time, time.inMS <= now, now < time.outMS,
                      let words = document.captionCue(of: cue)?.words else { continue }
                if let word = CaptionTrackBar.word(atMS: now, in: CaptionCue.words(words, fittedTo: time)) {
                    return word.text
                }
            }
        }
        return nil
    }
}
