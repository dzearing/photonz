import CoreGraphics
import Foundation

/// The drawings Ask draws a thing from when someone asks for one
/// (`docs/design/ask.md`, "Drawing a thing"): clean flat drawings of about a
/// thousand everyday things, each found by the words people use for it. Built
/// by `Scripts/make-drawings.mjs` from the Twemoji graphics (CC-BY 4.0) and
/// Unicode's names; the app reads the file, this finds in it.
///
/// A drawing from here is not a picture pasted in: it comes in through
/// `SVGArtwork` as layers, a face's parts named Face, Left eye, Right eye and
/// Mouth, so a person can recolour or reshape any of it.
public struct DrawingLibrary: Sendable {

    public struct Entry: Hashable, Sendable {
        /// Unicode's name for it, lower case ("hot beverage").
        public let name: String
        /// Words it is known by (CLDR's keywords).
        public let words: [String]
        public let svg: String
        /// What people call it where the name is not that ("coffee cup").
        public let aliases: [String]
        /// Whether it is a face, whose parts are named.
        public let isFace: Bool

        public init(name: String, words: [String], svg: String, aliases: [String] = [], isFace: Bool = false) {
            self.name = name
            self.words = words
            self.svg = svg
            self.aliases = aliases
            self.isFace = isFace
        }

        /// The drawing, read, with a face's parts named.
        public func drawing() -> Result<SVGArtwork, SVGArtworkError> {
            SVGArtwork.parse(svg).map { isFace ? FaceParts.named($0) : $0 }
        }
    }

    public let entries: [Entry]

    public init(entries: [Entry]) {
        self.entries = entries
    }

    /// The set as `Scripts/make-drawings.mjs` writes it.
    public static func decode(_ data: Data) -> DrawingLibrary? {
        struct File: Decodable {
            struct Drawing: Decodable {
                let n: String
                let w: [String]?
                let s: String
                let a: [String]?
                let f: Bool?
            }
            let drawings: [Drawing]
        }
        guard let file = try? JSONDecoder().decode(File.self, from: data) else { return nil }
        return DrawingLibrary(entries: file.drawings.map {
            Entry(name: $0.n, words: $0.w ?? [], svg: $0.s, aliases: $0.a ?? [], isFace: $0.f ?? false)
        })
    }

    // MARK: Finding

    /// The drawing that is what `subject` names, or nil when the set has none.
    ///
    /// Best first: a name or alias that IS the words; then a name holding all
    /// of them, the fewer other words the better; then all of them among its
    /// words; last, the thing the words end on ("a happy dog" is a dog).
    public func match(_ subject: String) -> Entry? {
        let wanted = Self.words(subject)
        guard !wanted.isEmpty else { return nil }
        let asWritten = Self.words(subject, singular: false)
        let wantedSet = Set(wanted)
        let head = wanted.last.map { [$0] } ?? []
        var best: (score: Int, entry: Entry)?
        for entry in entries {
            var score = 0
            let labels = ([entry.name] + entry.aliases).map { Self.words($0) }
            for (label, written) in zip(labels, ([entry.name] + entry.aliases).map { Self.words($0, singular: false) }) {
                // "houses" is a drawing of its own, before "house" made singular.
                if written == asWritten { score = max(score, 101) }
                if label == wanted { score = max(score, 100) }
                let labelSet = Set(label)
                if labelSet == wantedSet { score = max(score, 90) }
                if wantedSet.isSubset(of: labelSet) { score = max(score, 70 - 3 * (labelSet.count - wantedSet.count)) }
                if wanted.count > 1, label == head { score = max(score, 40) }
            }
            let known = Set(labels.flatMap { $0 }).union(entry.words.flatMap { Self.words($0) })
            if wantedSet.isSubset(of: known) { score = max(score, 50) }
            if score > (best?.score ?? 0) { best = (score, entry) }
        }
        return best?.entry
    }

    /// Words that say nothing about WHICH thing: how it is asked for, not what.
    static let setAside: Set<String> = [
        "a", "an", "the", "of", "some", "picture", "pic", "drawing", "draw", "image", "illustration", "icon",
        "emoji", "simple", "cute", "little", "small", "big", "large", "nice", "clean", "flat", "cartoon",
        "vector", "please", "me", "make", "create", "with", "on", "in", "over", "and", "at", "for", "my", "one",
    ]

    /// A phrase as the words that matter, lower case and singular.
    static func words(_ text: String, singular: Bool = true) -> [String] {
        let lowered = text.lowercased()
        let pieces = lowered.split { !($0.isLetter || $0.isNumber) }.map(String.init)
        let kept = pieces.filter { !setAside.contains($0) }
        return singular ? kept.map(Self.singular) : kept
    }

    static func singular(_ word: String) -> String {
        guard word.count > 3 else { return word }
        if word.hasSuffix("ies") { return String(word.dropLast(3)) + "y" }
        if word.hasSuffix("ches") || word.hasSuffix("shes") || word.hasSuffix("xes") { return String(word.dropLast(2)) }
        if word.hasSuffix("s"), !word.hasSuffix("ss"), !word.hasSuffix("us") { return String(word.dropLast()) }
        return word
    }
}

/// Names a face drawing's parts from where they sit on it: the big round
/// thing at the bottom is the face, two alike shapes either side above the
/// middle are the eyes, the wide one low in the middle is the mouth.
enum FaceParts {

    static func named(_ drawing: SVGArtwork) -> SVGArtwork {
        guard let face = drawing.parts.first else { return drawing }
        let box = SVGArtwork.shapeBounds(face.shape)
        guard box.width > 0, box.height > 0 else { return drawing }
        // Each part's box in the face's own units, 0 to 1 across and down.
        let boxes = drawing.parts.map { part -> CGRect in
            let own = SVGArtwork.shapeBounds(part.shape)
            return CGRect(x: (own.minX - box.minX) / box.width, y: (own.minY - box.minY) / box.height,
                          width: own.width / box.width, height: own.height / box.height)
        }
        var names: [String?] = Array(repeating: nil, count: drawing.parts.count)
        names[0] = "Face"
        func eyeLike(_ r: CGRect) -> Bool {
            r.midY > 0.15 && r.midY < 0.58 && r.width < 0.36 && r.height < 0.45
        }
        // The first two alike shapes mirrored about the middle.
        search: for i in 1..<boxes.count where eyeLike(boxes[i]) && names[i] == nil {
            for j in (i + 1)..<max(i + 1, boxes.count) where eyeLike(boxes[j]) && names[j] == nil {
                let a = boxes[i], b = boxes[j]
                let mirrored = abs(a.midX + b.midX - 1) < 0.1 && abs(a.midY - b.midY) < 0.08
                let alike = abs(a.width - b.width) < 0.08 && abs(a.height - b.height) < 0.08
                if mirrored, alike, abs(a.midX - b.midX) > 0.15 {
                    names[i] = a.midX < b.midX ? "Left eye" : "Right eye"
                    names[j] = a.midX < b.midX ? "Right eye" : "Left eye"
                    break search
                }
            }
        }
        if let mouth = boxes.indices.dropFirst().first(where: { index in
            let r = boxes[index]
            return names[index] == nil && r.midY > 0.55 && r.midY < 0.95 && abs(r.midX - 0.5) < 0.12 && r.width > 0.15
        }) {
            names[mouth] = "Mouth"
        }
        var named = drawing
        for (index, name) in names.enumerated() {
            if let name { named = named.named(Array(repeating: "", count: index) + [name]) }
        }
        return named
    }
}
