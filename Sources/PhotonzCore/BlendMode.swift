import Foundation

/// How a layer mixes with what is under it.
///
/// The second half of the question Opacity asks. Opacity says how MUCH of what
/// is below shows through; this says HOW the two are mixed once it does. A tint
/// burnt into a screenshot, a highlighter mark over text, a region lifted out
/// of the dark: one setting each, rather than a trick with a faded rectangle.
///
/// Five, and deliberately not twenty. Photoshop's list is the prior art the
/// user named as powerful but unintuitive, and the reason is not the maths, it
/// is that a name like Linear Burn tells you nothing and the only way to find
/// the one you want is to try them all. Every mode here is one a person can
/// predict from one sentence, and that sentence is `explanation`, printed under
/// the name in the menu rather than hidden behind a tooltip. Anything whose
/// result cannot be said that way — overlay, soft light, the burns and dodges —
/// stays out.
///
/// The order is the order of the menu, and it is not alphabetical: Normal
/// leads because it is what every layer already is, then the two that change
/// everything they cover (Multiply, Screen), then the two that change only part
/// of it (Darken, Lighten).
///
/// The renderer's half is `DocumentRenderer.composite(_:over:mode:extent:)`.
public enum BlendMode: String, Hashable, Codable, Sendable, CaseIterable {
    /// Paints straight over. What every layer is until somebody says otherwise.
    case normal
    /// Always darker or the same: ink on paper, a highlighter over words.
    case multiply
    /// Always lighter or the same: light thrown at what is already there.
    case screen
    /// Takes the darker of the two, pixel by pixel.
    case darken
    /// Takes the lighter of the two, pixel by pixel.
    case lighten

    /// The word in the menu and in the closed box.
    ///
    /// These are the names every other tool uses — Photoshop, Figma, Sketch,
    /// Keynote — kept on purpose. The complaint was never the word Multiply, it
    /// was a list of twenty of them with nothing saying what they do; renaming
    /// the five that survive would only mean that somebody who already knows
    /// what they want cannot find it. The plain words are in `explanation`,
    /// where they are read by everybody rather than only by whoever hovers.
    public var title: String {
        switch self {
        case .normal: "Normal"
        case .multiply: "Multiply"
        case .screen: "Screen"
        case .darken: "Darken"
        case .lighten: "Lighten"
        }
    }

    /// What this does, for somebody who has never opened Photoshop. One
    /// sentence, no vocabulary you would have had to learn somewhere else, and
    /// where it helps, the everyday thing it behaves like.
    public var explanation: String {
        switch self {
        case .normal:
            "Paints straight over what is under it."
        case .multiply:
            "Darkens what is under it, the way a highlighter pen does. Detail underneath still shows."
        case .screen:
            "Lightens what is under it, the way shining a light on it would."
        case .darken:
            "Keeps whichever is darker, this layer or what is under it."
        case .lighten:
            "Keeps whichever is lighter, this layer or what is under it."
        }
    }

    /// A mode written by a build that knows more of them than this one does.
    ///
    /// Unknown means Normal, never a document that refuses to open. `BlendMode`
    /// is a string in the file, and a plain `decode` throws on a word it does
    /// not have a case for — which would have taken the whole file with it, not
    /// just the one layer's mixing.
    static func named(_ raw: String?) -> BlendMode {
        guard let raw else { return .normal }
        return BlendMode(rawValue: raw) ?? .normal
    }
}
