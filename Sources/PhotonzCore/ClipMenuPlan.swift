import Foundation

/// **What a right click on a clip on the timeline leads with.** A rule, so the
/// app's menu and its tests say the same sentence.
///
/// A video clip is about its picture: its menu leads with the picture's verbs
/// (freeze, punch in, zoom, transition, key) and its sound is one submenu,
/// Audio, away. Detach Audio stays on the clip's own menu, because it is how a
/// person gets to the sound at all, which is where Final Cut keeps it too.
///
/// The sound drawn on the Audio track under a video, still linked to it, looks
/// like an audio clip, so a right click THERE answers like one: the sound's
/// rows at the top and none of the picture's.
///
/// The user, 2026-10-03: "when i right click on a video clip, it gives me
/// audio options. I only expect that on audio clips."
public struct ClipMenuPlan: Equatable, Sendable {

    /// Where a clip's sound rows (Normalize, Clean Noise, Reset Gain, Add
    /// Captions) go.
    public enum SoundRows: Equatable, Sendable {
        /// It has no sound.
        case none
        /// At the top of the menu, as on an audio clip.
        case inline
        /// Inside one submenu named `soundSubmenuTitle`.
        case submenu
    }

    /// The submenu a video clip's sound rows live in: Premiere's own heading
    /// for a clip's sound.
    public static let soundSubmenuTitle = "Audio"

    /// Whether the menu offers the rows that act on a picture: freeze, punch
    /// in, clicks, zooms, transitions, keys.
    public let offersPictureRows: Bool
    public let sound: SoundRows
    /// Whether Detach Audio is offered: a picture carrying a sound of its own.
    public let offersDetachAudio: Bool

    /// - Parameters:
    ///   - hasPicture: the clip plays pictures (a recording, a video).
    ///   - hasSound: the clip makes a sound, its own or a recording's.
    ///   - onTheSound: the click landed on the clip's linked sound, drawn on
    ///     the Audio track under it.
    public init(hasPicture: Bool, hasSound: Bool, onTheSound: Bool) {
        offersPictureRows = hasPicture && !onTheSound
        offersDetachAudio = hasPicture && hasSound
        if !hasSound {
            sound = .none
        } else if hasPicture && !onTheSound {
            sound = .submenu
        } else {
            sound = .inline
        }
    }
}
