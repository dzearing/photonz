// How a heading in the inspector dock is drawn, in one place.
//
// The dock has two sizes of heading and they are the same idea at two scales:
//
// - A SECTION heading — Layers, Appearance, Effects — is the big one. A
//   chevron you press to fold the whole section away, and a title lit up in
//   the panel's primary ink.
// - An EFFECT heading — Shadow, Border 2 — is the small one. The same chevron
//   and the same lit title one step down the type scale, because an effect is
//   a small pane of its own: a name with settings under it that fold away
//   (asked for by the user on 2026-09-08, whose Border row read as a list row
//   whose title weighed exactly what the settings under it weighed).
//
// The numbers live here rather than in either view so the small one cannot
// drift from the big one. `subheadline` is 11pt and `footnote` is 10pt on
// macOS 26, so "one step smaller" is a real step and not a wish.
import SwiftUI

enum PanelSectionLook {
    /// A dock section's own heading: `CollapsibleSection`.
    enum Section {
        static let chevronSize: CGFloat = 10
        static let chevronWeight: Font.Weight = .bold
        static var titleFont: Font { .subheadline.weight(.semibold) }
    }

    /// One effect's heading inside the Effects list: `EffectRowView`.
    ///
    /// The chevron is the layers list's group twist, glyph for glyph — 9pt
    /// semibold, secondary, rotating a quarter turn — because that is already
    /// what "press this to see what is inside" looks like in this app.
    enum EffectRow {
        static let chevronSize: CGFloat = 9
        static let chevronWeight: Font.Weight = .semibold
        static var titleFont: Font { .footnote.weight(.semibold) }
        /// How far a folded or switched-off effect's settings are faded. Not
        /// disabled: an effect that is off keeps every number on it and you
        /// can still open it and change them, so the settings stay live and
        /// only say quietly that nothing they describe is being painted.
        static let offSettingsOpacity: Double = 0.6
    }
}
