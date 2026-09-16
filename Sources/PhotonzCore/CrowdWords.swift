import Foundation

/// The words a sentence uses for the crowd it is about to change.
///
/// A drop line has to say how far letting go reaches, and the app used to say
/// it by counting: "Paints Fill on all 2 of them with Danger". Two things are
/// BOTH, and nobody says "all 2". Counting starts being useful at three, where
/// there is no single word for the number and knowing it is the whole point.
///
/// It lives in one place because the same crowd is described by the colour
/// drop, the text style drop and the Effects list, and three copies of one
/// sentence fragment is three chances to fix it in one and leave it wrong in
/// the others — which is exactly what the 2026-09-09 audit caught.
public enum CrowdWords {

    /// The crowd as an object: "both of them", "all 5 of them".
    ///
    /// Nil when the sentence is about one thing, because there is no crowd to
    /// name and every caller says something different about a single target
    /// ("this text", "Fill", nothing at all).
    public static func them(_ count: Int) -> String? {
        guard let all = all(count) else { return nil }
        return "\(all) of them"
    }

    /// The crowd standing in front of a noun, or on its own: "both copies",
    /// "all 3 labels", "for both".
    ///
    /// Same rule as `them`, which is built out of this one so the two can never
    /// disagree about where counting starts. Sentences in the panel needed a
    /// word for the crowd that was not "of them" — a Detach tip, a menu section
    /// heading, a font menu tip — and every one of them was counting at two
    /// because there was nothing else to reach for.
    ///
    /// Nil when the sentence is about one thing, for the same reason `them` is.
    public static func all(_ count: Int) -> String? {
        guard count > 1 else { return nil }
        return count == 2 ? "both" : "all \(count)"
    }
}
