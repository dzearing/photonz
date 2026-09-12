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
        guard count > 1 else { return nil }
        return count == 2 ? "both of them" : "all \(count) of them"
    }
}
