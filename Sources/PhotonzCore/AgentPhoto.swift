import CoreGraphics
import Foundation

// add_photo (`docs/design/ask.md`, "A photo, a drawing or a painting"): a
// photographic picture painted for the request by the picture model on this
// Mac and kept as pixels, one picture layer, where add_drawing traces the
// painting into vector layers. Ask picks between them from the person's words
// (`AgentPictureKind`): the general words for a photo, a drawing or a
// painting, never anything about the subject.

/// How the person asked for a picture to be made.
public enum AgentPictureKind: String, Hashable, Sendable {
    /// A real photograph: one picture layer.
    case photo
    /// Vector art, a drawing, an icon: editable vector layers.
    case vector
    /// Painted with the brushes, stroke by stroke.
    case paint

    /// Words that say vector layers whatever else is said: "a photo icon" is an icon.
    static let vectorFirst: Set<String> = ["vector", "vectors", "svg", "icon", "icons", "logo", "logos", "glyph", "emoji"]
    static let photoWords: Set<String> = Set([
        "photo", "photos", "photograph", "photographs", "photographic", "photorealistic", "photoreal",
    ]).union(lifelikeWords)
    /// Words that say a photo only when nothing else names a kind: "a
    /// realistic painting" is a painting, "a realistic dog" a photo.
    static let lifelikeWords: Set<String> = ["realistic", "lifelike", "hyperrealistic", "hyperreal"]
    static let paintWords: Set<String> = ["paint", "paints", "painting", "paintings", "brush", "brushes", "brushstrokes"]
    /// Words for a drawing, which a photo or painting word beats: "draw a photorealistic apple".
    static let drawWords: Set<String> = [
        "draw", "drawing", "drawn", "illustration", "illustrated", "illustrate", "cartoon", "clipart", "sketch",
        "outline", "silhouette", "flat",
    ]

    /// The kind the words of `request` ask for, or nil when they name none
    /// and the planning model picks. "As a photo" at the end of a request
    /// (a request made again the other way) says it last and wins.
    public static func asked(in request: String) -> AgentPictureKind? {
        let typed = AgentDrawingWords.words(request)
        // The last "as a photo", "as vector art", "as a painting".
        for index in typed.indices.reversed() where typed[index] == "as" {
            let next = typed.dropFirst(index + 1).drop { ["a", "an", "the", "real", "one"].contains($0) }.prefix(1)
            if let word = next.first, let kind = kind(of: [word]) { return kind }
        }
        return kind(of: typed)
    }

    private static func kind(of typed: [String]) -> AgentPictureKind? {
        let words = Set(typed)
        let joined = " " + typed.joined(separator: " ") + " "
        if !words.isDisjoint(with: vectorFirst) || joined.contains(" line art ") || joined.contains(" clip art ") {
            return .vector
        }
        if !words.isDisjoint(with: photoWords.subtracting(lifelikeWords)) { return .photo }
        if !words.isDisjoint(with: paintWords) { return .paint }
        if !words.isDisjoint(with: drawWords) { return .vector }
        if !words.isDisjoint(with: lifelikeWords) { return .photo }
        return nil
    }

    /// Words a request to make the last thing again another way is made of,
    /// beside the kind it names: "now make it as a photo instead".
    static let againWords: Set<String> = [
        "as", "a", "an", "the", "it", "this", "that", "one", "again", "instead", "now", "make", "do", "try", "redo",
        "please", "same", "but", "then", "me", "real", "art", "image", "picture", "version", "way", "other", "thing",
        "can", "you", "could", "would", "want", "like", "how", "about", "into", "turn", "rather", "same",
    ]

    /// The last request made again as the kind `request` names, when
    /// `request` says nothing but that ("as a photo", "try it as vector art"):
    /// "draw a dog on a beach, as a photo". Nil when it says more, so a new
    /// request is its own.
    public static func remade(_ request: String, after earlier: String?) -> String? {
        guard let earlier = earlier?.trimmingCharacters(in: .whitespacesAndNewlines), !earlier.isEmpty,
              let kind = asked(in: request) else { return nil }
        let typed = AgentDrawingWords.words(request)
        let kindWords = vectorFirst.union(photoWords).union(paintWords).union(drawWords)
        guard typed.allSatisfy({ againWords.contains($0) || kindWords.contains($0) }) else { return nil }
        let phrase: String
        switch kind {
        case .photo: phrase = "as a photo"
        case .vector: phrase = typed.contains("icon") ? "as an icon" : "as vector art"
        case .paint: phrase = "as a painting"
        }
        let trimmed = earlier.trimmingCharacters(in: CharacterSet(charactersIn: " .!"))
        return "\(trimmed), \(phrase)"
    }
}

extension AgentPictureKind {
    /// Words that name how a picture is made, so "vector art" goes with "vector".
    private static let madeOf: Set<String> = ["art", "style", "styled", "version"]

    /// `text` without the words that ask for another kind of picture than
    /// `kind`, so "make vector art of a fox, as a photo" paints a fox, not
    /// vector art: "make of a fox as a photo". Only the general kind words go,
    /// never anything about the subject.
    public static func withoutOtherKinds(_ text: String, keeping kind: AgentPictureKind) -> String {
        let own: Set<String> = switch kind {
        case .photo: photoWords
        case .vector: vectorFirst.union(drawWords)
        case .paint: paintWords
        }
        let other = vectorFirst.union(drawWords).union(photoWords).union(paintWords)
            .union(["line", "clip"]).subtracting(own)
        var kept: [String] = []
        var dropping = false
        for word in AgentDrawingWords.words(text) {
            if other.contains(word) || (dropping && madeOf.contains(word)) {
                dropping = true
                continue
            }
            dropping = false
            kept.append(word)
        }
        return kept.joined(separator: " ")
    }
}

/// What an add_photo call asks for.
public struct AgentPhotoCall: Hashable, Sendable {
    /// What a photo looks like: a real photograph, or a painting while the
    /// brushes are not ready to paint one stroke by stroke.
    public enum Look: String, Hashable, Sendable, CaseIterable {
        case photo
        case painting
    }

    /// What it shows, in the person's words: "a dog on a beach".
    public var subject: String
    /// The person's own words, when they say more than the subject.
    public var asked: String?
    /// The box the photo fills; the whole canvas when nil.
    public var frame: CGRect?
    public var name: String?
    public var look: Look

    public init(subject: String, asked: String? = nil, frame: CGRect? = nil, name: String? = nil, look: Look = .photo) {
        self.subject = subject
        self.asked = asked
        self.frame = frame
        self.name = name
        self.look = look
    }

    /// The layer's name, as a drawing's is: the one asked for, else the
    /// subject cut to a label.
    public var layerName: String {
        AgentDrawingCall(subject: subject, name: name).layerName
    }
}

/// What the picture model on this Mac is asked to paint for add_photo
/// (`Scripts/picture-model/server.py`, POST /photo): the whole prompt and
/// the picture's size. Nothing in it knows any subject.
public struct PictureModelPhotoRequest: Codable, Hashable, Sendable {
    public var prompt: String
    public var width: Int
    public var height: Int

    /// About what the picture model paints best at, in pixels: its own
    /// 1024 by 1024. More is slower without being better.
    public static let pixels: Double = 1024 * 1024
    /// The longest a side is against the other: past it the model paints
    /// two pictures side by side.
    public static let widest: Double = 3
    /// The smallest a side is painted: under it a photo comes out mush.
    public static let shortest: Double = 256

    /// How a photograph looks, in general words.
    static let photoLook = "A real photograph taken with a camera: natural light, true colours, sharp focus, fine realistic detail. No text, no watermark, no border."
    /// How a painting looks, while the brushes cannot paint it stroke by stroke.
    static let paintingLook = "A painting on canvas with visible brush strokes, rich colour and depth. No text, no signature, no border, no frame."

    public init(_ call: AgentPhotoCall, box: CGSize) {
        let subject = call.subject.trimmingCharacters(in: .whitespacesAndNewlines)
        let asked = AgentPictureKind.withoutOtherKinds(call.asked ?? "", keeping: call.look == .painting ? .paint : .photo)
        var described = subject
        if !asked.isEmpty, asked.lowercased() != subject.lowercased() {
            described = "\(subject), from the request: \(asked)"
        }
        prompt = "\(described). \(call.look == .painting ? Self.paintingLook : Self.photoLook)"
        (width, height) = Self.size(for: box)
    }

    /// The box's aspect at about `pixels`, never more than twice the box
    /// itself (a Retina screen's worth), every side a multiple of 16.
    static func size(for box: CGSize) -> (Int, Int) {
        let w = max(1, Double(box.width)), h = max(1, Double(box.height))
        let aspect = min(widest, max(1 / widest, w / h))
        let area = min(pixels, w * h * 4)
        var height = (area / aspect).squareRoot()
        var width = height * aspect
        if min(width, height) < shortest {
            let grow = shortest / min(width, height)
            width *= grow
            height *= grow
        }
        func sixteen(_ v: Double) -> Int { max(16, Int((v / 16).rounded()) * 16) }
        return (sixteen(width), sixteen(height))
    }
}

/// Where a photo lands.
public enum AgentPhotoPlacement {
    /// The box asked for, kept on the canvas, or the whole canvas when none
    /// was asked for or none of it is on the canvas.
    public static func box(_ asked: CGRect?, on canvas: CGSize) -> CGRect {
        let whole = CGRect(origin: .zero, size: canvas)
        guard let asked else { return whole }
        let kept = asked.intersection(whole)
        guard !kept.isNull, kept.width >= 16, kept.height >= 16 else { return whole }
        return kept
    }
}
