import Testing
import PhotonzCore

/// What a right click on a clip on the timeline leads with (`ClipMenuPlan`).
///
/// The user, 2026-10-03: "when i right click on a video clip, it gives me
/// audio options. I only expect that on audio clips." A video clip's menu is
/// about its picture; its sound is one submenu away, and the sound drawn on
/// the Audio track under it answers like the audio clip it looks like.
@Suite("A clip's right-click menu leads with what was clicked")
struct ClipMenuPlanTests {

    @Test func aVideoClipLeadsWithItsPictureAndFoldsItsSoundIntoOneSubmenu() {
        let plan = ClipMenuPlan(hasPicture: true, hasSound: true, onTheSound: false)
        #expect(plan.offersPictureRows)
        #expect(plan.sound == .submenu)
        #expect(ClipMenuPlan.soundSubmenuTitle == "Audio")
    }

    /// Detach Audio is how a person gets to a video's sound, so it is never
    /// the thing tucked away.
    @Test func detachAudioStaysOnTheVideoClipsOwnMenu() {
        let plan = ClipMenuPlan(hasPicture: true, hasSound: true, onTheSound: false)
        #expect(plan.offersDetachAudio)
    }

    @Test func aSilentVideoClipHasNoSoundRowsAtAll() {
        let plan = ClipMenuPlan(hasPicture: true, hasSound: false, onTheSound: false)
        #expect(plan.offersPictureRows)
        #expect(plan.sound == .none)
        #expect(!plan.offersDetachAudio)
    }

    @Test func anAudioClipKeepsItsSoundRowsAtTheTop() {
        let plan = ClipMenuPlan(hasPicture: false, hasSound: true, onTheSound: false)
        #expect(!plan.offersPictureRows)
        #expect(plan.sound == .inline)
        #expect(!plan.offersDetachAudio, "a sound on its own has nothing to detach from")
    }

    /// The sound drawn under a video on the Audio track looks like an audio
    /// clip, so a right click there is about the sound.
    @Test func aVideosOwnSoundOnTheAudioTrackAnswersLikeAnAudioClip() {
        let plan = ClipMenuPlan(hasPicture: true, hasSound: true, onTheSound: true)
        #expect(!plan.offersPictureRows)
        #expect(plan.sound == .inline)
        #expect(plan.offersDetachAudio)
    }

    @Test func aTitleIsNeitherPictureMediaNorSound() {
        let plan = ClipMenuPlan(hasPicture: false, hasSound: false, onTheSound: false)
        #expect(!plan.offersPictureRows)
        #expect(plan.sound == .none)
    }
}
