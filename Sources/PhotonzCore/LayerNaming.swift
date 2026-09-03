import Foundation

/// The names the app writes for a layer nobody has named yet, and the rule that
/// keeps two of them apart.
///
/// Drawing two rectangles used to leave a document holding two layers both
/// called "Rectangle": the layers list, a component's variant menu and an
/// exported spec all showed the same word twice, and the only way to tell which
/// row was which was to click each one and watch the canvas. A new layer whose
/// automatic name is already spoken for takes the next free number instead, so
/// the second one is "Rectangle 2".
///
/// Only names the APP wrote are numbered. A name a person typed is theirs and
/// is never touched, before or after the fact, which is why the numbering
/// happens once, as the layer is filed, and never again.
public enum LayerNaming {

    /// What the New Layer command calls an empty layer.
    public static let newLayerName = "Layer"

    /// Every stem the app mints a layer name from. A name is automatic when it
    /// is one of these on its own, or one of these followed by a number.
    ///
    /// Measurements are deliberately absent: a caliper's stock name is the
    /// signal that nobody renamed it (`MeasureSpecList.displayName`), and its
    /// row already reads as what it measures ("Width", "Gap"), so it is
    /// tellable apart without a number and numbering it would only break the
    /// signal.
    ///
    /// Components and starter pieces are absent too: their name comes from the
    /// original they copy, and copies of one component are meant to share it.
    public static var autoStems: [String] {
        AnnotationShape.allCases.map(\.title) + [
            "Group",
            "Frame",
            PhotonzDocument.componentNameBase,
            TextBuilder.defaultLayerName,
            "Zoom",
            "Collage",
            newLayerName,
            PlacedImageNaming.clipboardName,
        ]
    }

    /// The stem an automatic name was made from ("Rectangle" for both
    /// "Rectangle" and "Rectangle 7"), or nil when the name is not one the app
    /// wrote.
    public static func stem(of name: String) -> String? {
        autoStems.first { matches(name, stem: $0) }
    }

    /// Whether the app wrote this name rather than a person.
    public static func isAutoName(_ name: String) -> Bool {
        stem(of: name) != nil
    }

    /// "Stem", "Stem 2", "Stem 17": the shape every automatic name takes.
    static func matches(_ name: String, stem: String) -> Bool {
        guard name.hasPrefix(stem) else { return false }
        let tail = name.dropFirst(stem.count).trimmingCharacters(in: .whitespaces)
        return tail.isEmpty || Int(tail) != nil
    }
}

extension PhotonzDocument {

    /// A name no layer in the document is using yet: "Rectangle", then
    /// "Rectangle 2", "Rectangle 3"… A name in use anywhere counts, groups and
    /// screens included, because the layers list can show all of them at once.
    public func freshLayerName(base: String) -> String {
        freshGroupName(base: base)
    }

    /// The layer as it should be filed. An automatic name already in use takes
    /// the next free number; anything else is left exactly as it arrived.
    func uniquelyNamed(_ layer: Layer) -> Layer {
        guard let stem = LayerNaming.stem(of: layer.name),
              allLayers.contains(where: { $0.name == layer.name }) else { return layer }
        var renamed = layer
        renamed.name = freshLayerName(base: stem)
        return renamed
    }
}
