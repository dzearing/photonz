import Foundation

/// The question asked before a shape or a piece of text becomes a picture.
///
/// A marquee only takes a piece out of a picture (`RegionTarget`), so a person
/// who draws one over half a rectangle is told they cannot cut that
/// (`RegionSliceRefusal`). This is the other half of the answer: the command
/// that makes the rectangle into pixels, so the piece really can come out.
///
/// It asks first because the thing it takes away is invisible. The instant
/// after, the picture is identical: same shape, same colour, same place. What
/// is gone is everything the layer USED to be adjustable by, the corner radius,
/// the words, the stroke, and nothing on screen says so. A person who finds out
/// by reaching for the text a week later has lost the words. One sentence up
/// front is the whole difference, and "Don't ask again" is there so it costs
/// nothing after the first time.
///
/// Pure copy: it holds no layer and touches no document, so the words can be
/// read in a test without an app around them.
public struct RasterizePrompt: Hashable, Sendable {
    /// What the layer is, in the noun a person would use for it, because what
    /// they lose is different: a shape loses its shape, text loses its words.
    public enum Subject: Hashable, Sendable {
        case shape
        case text
    }

    /// The name the layer wears in the layers panel, so the question is about
    /// the thing they picked and not about "a layer". Empty when it has none.
    public var name: String
    public var subject: Subject

    public init(name: String, subject: Subject) {
        self.name = name
        self.subject = subject
    }

    /// The question this layer would raise, or nil when there is nothing to
    /// turn. The yes/no half is `Layer.isRasterizable` and nothing else, so the
    /// question can never appear over a layer the command would refuse.
    public init?(layer: Layer) {
        guard layer.isRasterizable else { return nil }
        switch layer.content {
        case .text: self.init(name: layer.name, subject: .text)
        default: self.init(name: layer.name, subject: .shape)
        }
    }

    /// What the menu row says, in both the Layer menu and the layer's own row
    /// menu. The ellipsis is the macOS promise that a question comes next.
    public static let menuItem = "Turn Into Picture\u{2026}"

    /// The checkbox on the question. Standard macOS wording, so it reads as the
    /// same control it is everywhere else.
    public static let suppression = "Don't ask again"

    private var noun: String {
        switch subject {
        case .shape: return "shape"
        case .text: return "text"
        }
    }

    /// The question itself, naming the layer when it has a name.
    public var title: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Turn this \(noun) into a picture?" }
        return "Turn \u{201C}\(trimmed)\u{201D} into a picture?"
    }

    /// Why you would say yes, then what it costs, then the way back. In that
    /// order: the gain is what they came for, and the cost is the part they
    /// cannot see.
    public var message: String {
        let lost = subject == .text ? "The words stop being editable"
                                    : "The shape stops being editable"
        return "It becomes pixels, so a marquee can cut a piece out of it. "
            + "\(lost). Undo puts it back."
    }

    /// The button, carrying the verb: a person reading only the buttons still
    /// knows which one does the thing.
    public var confirm: String { "Turn Into Picture" }

    public var cancel: String { "Cancel" }
}

/// The question asked before SEVERAL layers become pictures at once.
///
/// `RasterizePrompt` names the one layer it is about, which is the right
/// sentence for one row and a lie about three: "Turn “Rectangle” into a
/// picture?" over a pick of three says nothing about the other two, and they
/// are about to change as well. So a batch asks its own question, and the
/// question's whole job is to say HOW MANY rows change and what each of them
/// loses, before the button is pressed.
///
/// It counts only the rows the command will really take: a picture picked
/// alongside two shapes is already pixels and is left exactly where it is, so
/// it is not in the number and not in the sentence.
///
/// Pure copy, like the singular one: it holds no document, so the words can be
/// read in a test without an app around them.
public struct RasterizeQuestion: Hashable, Sendable {
    /// How many of the picked rows are shapes, and how many are text. The two
    /// are counted apart because they lose different things, and the sentence
    /// has to say which.
    public var shapes: Int
    public var texts: Int

    /// How many rows change. The question exists to say this number.
    public var takes: Int { shapes + texts }

    public init(shapes: Int, texts: Int) {
        self.shapes = shapes
        self.texts = texts
    }

    /// The question these layers would raise, or nil when fewer than two of
    /// them can be turned — one layer asks `RasterizePrompt`, which can name it,
    /// and none asks nothing.
    public init?(layers: [Layer]) {
        var shapes = 0
        var texts = 0
        for layer in layers where layer.isRasterizable {
            if case .text = layer.content { texts += 1 } else { shapes += 1 }
        }
        guard shapes + texts > 1 else { return nil }
        self.init(shapes: shapes, texts: texts)
    }

    /// What the rows ARE, in the plural. "Layers" only where they are a mix,
    /// because a person who picked three rectangles thinks of them as shapes
    /// and being told about "layers" is the app talking about its own model.
    private var noun: String {
        if shapes > 0 && texts > 0 { return "layers" }
        return texts > 0 ? "pieces of text" : "shapes"
    }

    /// "Turn both shapes into pictures?", "Turn all 3 layers into pictures?" —
    /// counting where counting starts being useful (`CrowdWords`), because
    /// nobody says "all 2".
    public var title: String {
        let crowd = CrowdWords.all(takes) ?? "both"
        return "Turn \(crowd) \(noun) into pictures?"
    }

    /// What you gain, then what it costs, then the way back — the same order
    /// the singular question uses, so the two read as one sentence learnt once.
    ///
    /// The last line is the part only a batch needs: three rows just changed
    /// together and it says, before the press, that one undo takes all three
    /// back rather than leaving somebody pressing ⌘Z three times and hoping.
    public var message: String {
        let lost: String
        if shapes > 0 && texts > 0 {
            lost = "The shapes and the words stop being editable."
        } else if texts > 0 {
            lost = "The words stop being editable."
        } else {
            lost = "The shapes stop being editable."
        }
        return "They become pixels, so a marquee can cut a piece out of them. "
            + "\(lost) One undo puts them all back."
    }

    /// The button, carrying the verb in the plural: a person reading only the
    /// buttons still knows which one does the thing, and that it does it to
    /// more than one row.
    public var confirm: String { "Turn Into Pictures" }

    public var cancel: String { "Cancel" }
}
