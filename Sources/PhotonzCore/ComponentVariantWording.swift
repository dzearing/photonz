import Foundation

/// The ONE word the app uses for the looks a component holds, in whatever the
/// author called it.
///
/// A component's looks are a property (`ComponentVariantProperty`), and the
/// author names that property: "Variant" until they type State, or Type, or
/// Size over it. Before this existed only the panel row took the new name. The
/// Add menu still offered "A second look" under a heading that said Variant,
/// the Layer menu still said Add Variant, the button that pushes one edit onto
/// the other drawings still said "Other Variants Already Match", and the notice
/// that came up on the canvas still said "Variant added". So somebody who had
/// just renamed the question to State had to work out, four more times, that
/// all of those sentences were about their States.
///
/// Everything that says any of it reads the word from here, so there is one
/// place to change and nowhere left to disagree.
public struct ComponentVariantWording: Hashable, Sendable {
    /// One of them: "Variant", "State".
    public var one: String
    /// More than one: "Variants", "States".
    public var many: String

    /// Built from what the author called the property, falling back to the word
    /// the panel starts it at. A blank name is not a name: it falls back rather
    /// than leaving a menu reading "Add ".
    public init(_ name: String?) {
        let chosen = ComponentNaming.normalized(name) ?? ComponentNaming.defaultVariantPropertyName
        self.one = chosen
        self.many = ComponentNaming.plural(chosen)
    }

    /// The row on the component's Add menu that makes another drawing of the
    /// whole thing. It names the property rather than describing the act,
    /// because the list it lands in is named after the property too.
    public func addRow(hasAny: Bool) -> String {
        hasAny ? "Another \(one)" : "A second \(one)"
    }

    /// The same errand on the Layer menu, where there is no list above it to
    /// lean on, so it carries the verb.
    public var addCommand: String { "Add \(one)" }
}

extension ComponentNaming {

    /// More than one of a word somebody typed into a name box.
    ///
    /// This is deliberately the small rule rather than an English pluraliser:
    /// what goes through it is a short noun an author chose for a property, so
    /// hisses take -es, a consonant before a final y turns it into -ies, and
    /// everything else takes an s. A word it gets wrong is a word the author
    /// can still read, which is the bar here.
    public static func plural(_ word: String) -> String {
        let lower = word.lowercased()
        if lower.hasSuffix("s") || lower.hasSuffix("x") || lower.hasSuffix("z")
            || lower.hasSuffix("ch") || lower.hasSuffix("sh") {
            return word + "es"
        }
        if lower.hasSuffix("y"), let before = lower.dropLast().last,
           !"aeiou".contains(before) {
            return word.dropLast() + "ies"
        }
        return word + "s"
    }
}

extension PhotonzDocument {

    /// The word every sentence about this component's looks is said in.
    public func componentVariantWording(of componentID: UUID) -> ComponentVariantWording {
        ComponentVariantWording(componentVariantName(of: componentID))
    }
}
