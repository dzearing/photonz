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

    /// The word a copy adds to a name somebody chose.
    static let copyWord = "copy"

    /// What to call a copy of a layer called `source`, given every name
    /// already spoken for.
    ///
    /// A name the app wrote is numbered exactly as a freshly drawn shape is, so
    /// duplicating a rectangle reads "Rectangle 2" and matches what you get by
    /// drawing another one or pasting the first. A name a person typed is
    /// theirs: the copy keeps their word and adds "copy", then numbers that
    /// ("Card copy", "Card copy 2"), and copying a copy never stacks the word
    /// up into "Card copy copy".
    public static func copyName(of source: String, taken: Set<String>) -> String {
        firstFree(base: stem(of: source) ?? "\(copyBase(of: source)) \(copyWord)", taken: taken)
    }

    /// What to call a layer arriving from the clipboard, given every name
    /// already spoken for where it lands.
    ///
    /// Copying a layer and pasting it lands a copy beside the original, so it
    /// is named exactly as duplicating that layer names it: an app-written name
    /// takes the next number, a name a person typed keeps their word and gains
    /// "copy". Nothing is renamed until there is something to tell apart — a
    /// layer pasted into another document, or cut and pasted back, keeps the
    /// name it arrived with, and the layer that was already there is never
    /// touched.
    public static func pastedName(of source: String, taken: Set<String>) -> String {
        guard taken.contains(source) else { return source }
        return copyName(of: source, taken: taken)
    }

    /// `base`, then "base 2", "base 3"… — the first one nobody is using.
    static func firstFree(base: String, taken: Set<String>) -> String {
        guard taken.contains(base) else { return base }
        var n = 2
        while taken.contains("\(base) \(n)") { n += 1 }
        return "\(base) \(n)"
    }

    /// The word a copy's name is built on: "Card" for "Card", for "Card copy"
    /// and for "Card copy 4" alike.
    static func copyBase(of name: String) -> String {
        var base = name
        while let shorter = withoutCopySuffix(base) { base = shorter }
        return base
    }

    /// `name` with one trailing "copy", and the number after it, taken off, or
    /// nil when it does not end that way.
    private static func withoutCopySuffix(_ name: String) -> String? {
        var head = Substring(name)
        if let space = head.lastIndex(of: " "), Int(head[head.index(after: space)...]) != nil {
            head = head[..<space]
        }
        guard head.hasSuffix(" \(copyWord)") else { return nil }
        let base = head.dropLast(copyWord.count + 1)
        return base.isEmpty ? nil : String(base)
    }
}

extension PhotonzDocument {

    /// A name no layer in the document is using yet: "Rectangle", then
    /// "Rectangle 2", "Rectangle 3"… A name in use anywhere counts, groups and
    /// screens included, because the layers list can show all of them at once.
    public func freshLayerName(base: String) -> String {
        freshGroupName(base: base)
    }

    /// Names the copies a duplicate just made, once they are all in place.
    ///
    /// Each entry pairs a copy with the name of the layer it came from. The
    /// naming happens here, after the tree is rebuilt, rather than as each copy
    /// is inserted, because until the walk is finished the document does not
    /// know every name that is spoken for — which is how duplicating one layer
    /// twice used to leave two rows both reading "Rectangle copy". The copies
    /// themselves do not count as taken, so the first one is free to keep the
    /// obvious name, and each name is booked as it is handed out so the second
    /// copy cannot take the first one's.
    mutating func nameDuplicates(_ made: [(copy: UUID, source: String)]) {
        guard !made.isEmpty else { return }
        let copies = Set(made.map(\.copy))
        var taken = Set(allLayers.lazy.filter { !copies.contains($0.id) }.map(\.name))
        for entry in made {
            let name = LayerNaming.copyName(of: entry.source, taken: taken)
            taken.insert(name)
            updateLayer(id: entry.copy) { $0.name = name }
        }
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
