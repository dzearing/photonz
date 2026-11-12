/// **On a video, Captions and Transitions show only where they apply to what
/// is picked.**
///
/// Both are about the whole video rather than a setting of one layer, and
/// both used to sit under EVERY pick: a recording's own sections, then the
/// captions' whole style form, then a folded Transitions header, so a picked
/// arrow or line had the document's captions under its own rows and a sound's
/// Fades went under the fold on a laptop window (2026-10-13, 2026-10-20).
///
/// The rule, as a Premiere or Final Cut editor finds it:
///
/// - **Captions** are the document's when nothing is picked (what the panel
///   says about the video as a whole: Time, then Captions, as Premiere's Text
///   panel holds the transcript), and the pick's when the captions or a caption
///   are picked (`video-captions.html` opens its panel on them). Under a
///   picked clip, title, sound, graphic, cut or zoom they are not a setting of
///   that thing, so they are absent; Add Captions stays in the menu bar, the
///   clip's and the sound's right click, and the timeline's add-track menu.
/// - **Transitions**, the tiles, show while a cut is picked, which is the
///   place a transition goes (`video-transitions.html`: the transition's
///   Properties, then the tiles). Everywhere else the Library's Transitions
///   kind is where you find one to drag (`video-library.html`), so a video
///   offers its transitions in one place at a time rather than twice. The
///   user, 2026-10-30: "it doesn't even need to be there when i have nothing
///   selected".
///
/// Sections are named by their raw ids (`InspectorSectionID` in the app), so
/// the rule stays pure.
public enum VideoDocumentSections {

    /// What is in hand, as far as these two sections care.
    public enum Pick: Sendable, Equatable {
        /// No layer, cut, zoom or track picked: the panel speaks for the video.
        case nothing
        /// The Captions layer, or one of its captions.
        case captions
        /// A cut (an edit point between two pieces) picked.
        case cut
        /// Anything else: a clip, a title, a sound, a graphic, a zoom, a track.
        case other
    }

    public static let captions = "captions"
    public static let transitions = "transitions"

    /// Whether the section is shown for this pick. Nil for a section the rule
    /// does not decide, which keeps whatever the panel already said.
    public static func shows(_ section: String, for pick: Pick) -> Bool? {
        switch section {
        case captions: pick == .nothing || pick == .captions
        case transitions: pick == .cut
        default: nil
        }
    }

    /// The panel's sections with the two this rule decides kept or taken out
    /// for the pick; every other section, and the order, untouched.
    public static func filter(_ sections: [String], for pick: Pick) -> [String] {
        sections.filter { shows($0, for: pick) ?? true }
    }
}
