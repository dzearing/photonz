import Foundation

/// What the inspector calls a shape and the colors it paints.
///
/// The settings for a picked shape used to be headed "Annotation" — the name of
/// the content KIND in the model, not the name of anything on screen — and its
/// two color rows were labelled by the shape and by nothing at all. So a person
/// looking at a rectangle read "Annotation", then "Rectangle" beside a color,
/// and could not tell which of the two colors was the outline.
///
/// These are the words that fix that, and they live here rather than in the
/// view so the section header and the row label can never drift apart, and so
/// they can be checked without running the app.
extension AnnotationShape {

    /// The shape's own name, which is what its settings section is headed.
    public var title: String {
        switch self {
        case .arrow: return "Arrow"
        case .line: return "Line"
        case .rectangle: return "Rectangle"
        case .ellipse: return "Ellipse"
        case .highlight: return "Highlight"
        }
    }

    /// Whether this shape has any settings of its own once its colors have
    /// moved out to the Color section.
    ///
    /// Every shape has a thickness except a highlight, which is a band of one
    /// color and nothing else. So a picked highlight brings no settings section
    /// at all, rather than one headed "Highlight" with nothing under it.
    public var hasSettingsBesidesColor: Bool { self != .highlight }

    /// What a color row on this shape paints, in the words the row shows. Nil
    /// for a slot this shape does not have, so a caller cannot invent a row.
    ///
    /// A box has two parts worth naming, so they get named: Outline and Fill. A
    /// line, an arrow or a highlight is all one color, and calling that an
    /// outline would be a small lie, so it is just Color — the section header
    /// above it already says which shape it belongs to.
    public func colorTitle(for slot: ColorSlot) -> String? {
        switch (self, slot) {
        case (.rectangle, .stroke), (.ellipse, .stroke): return "Outline"
        case (.rectangle, .fill), (.ellipse, .fill): return "Fill"
        case (.arrow, .stroke), (.line, .stroke), (.highlight, .stroke): return "Color"
        default: return nil
        }
    }
}
