import CoreGraphics
import Foundation

// Pass 1 of an illustration (`docs/design/ask.md`, "Drawing an
// illustration"): the brief. What the picture is of, in which style, at what
// time of day, read from the few words the person and the model gave. The
// model only makes these narrow choices; everything after is the
// illustrator's craft (`Illustrator`).

/// The look an illustration is drawn in.
public enum IllustrationStyle: String, CaseIterable, Codable, Hashable, Sendable {
    /// Painted depth: a gradient sky, every form with a lit and a shadow
    /// side, ranges fading lighter and bluer into the distance.
    case painted
    /// Ridge bands stepping in value under a sunset sky.
    case sunset
    /// Flat colour shapes, two tones a form, no ramps.
    case flat
    /// Ink outlines only, the outline heaviest.
    case lineArt
    /// One ink, with snow and ridge highlights cut out of it.
    case silhouette

    /// How the change row names it.
    public var title: String {
        switch self {
        case .painted: "painted"
        case .sunset: "sunset"
        case .flat: "flat"
        case .lineArt: "line art"
        case .silhouette: "silhouette"
        }
    }
}

/// When the picture is set: it decides the light and the palette.
public enum IllustrationTime: String, CaseIterable, Codable, Hashable, Sendable {
    case day, golden, dusk, night
}

/// The things an illustration knows how to draw.
public enum IllustrationElement: String, CaseIterable, Codable, Hashable, Sendable {
    case mountains, hills, forest, lake, sea, sun, moon, stars, birds, clouds, lighthouse, cliff, city, fox

    /// The words that ask for it.
    var words: [String] {
        switch self {
        case .mountains: ["mountain", "mountains", "peak", "peaks", "alps", "alpine", "range", "summit", "ridge", "ridges"]
        case .hills: ["hill", "hills", "meadow", "valley", "countryside", "field", "fields"]
        case .forest: ["forest", "forests", "woods", "woodland", "pine", "pines", "trees", "treeline", "evergreen"]
        case .lake: ["lake", "lakes", "pond", "river", "reflection", "reflections"]
        case .sea: ["sea", "ocean", "coast", "coastal", "beach", "shore", "waves", "bay", "harbour", "harbor"]
        case .sun: ["sun", "sunny", "sunshine"]
        case .moon: ["moon", "moonlight", "moonlit"]
        case .stars: ["stars", "starry", "starlit"]
        case .birds: ["bird", "birds", "gulls", "seagulls", "geese"]
        case .clouds: ["cloud", "clouds", "cloudy"]
        case .lighthouse: ["lighthouse", "beacon"]
        case .cliff: ["cliff", "cliffs", "headland", "bluff"]
        case .city: ["city", "skyline", "town", "skyscrapers", "buildings", "downtown", "metropolis"]
        case .fox: ["fox", "foxes", "vixen"]
        }
    }
}

/// Everything the illustrator needs to start.
public struct IllustrationBrief: Hashable, Codable, Sendable {
    public var subject: String
    public var style: IllustrationStyle
    /// Cut into a circle with a frame line.
    public var badge: Bool
    public var time: IllustrationTime
    /// What is in it, in the order it was asked for.
    public var elements: [IllustrationElement]
    /// Whether the person named the style; if not, the illustrator picked it
    /// and the change row says which.
    public var styleNamed: Bool
    public var seed: UInt64

    public init(subject: String, style: IllustrationStyle, badge: Bool = false, time: IllustrationTime,
                elements: [IllustrationElement], styleNamed: Bool = true, seed: UInt64 = 7) {
        self.subject = subject
        self.style = style
        self.badge = badge
        self.time = time
        self.elements = elements
        self.styleNamed = styleNamed
        self.seed = seed
    }

    public func has(_ element: IllustrationElement) -> Bool { elements.contains(element) }

    /// The words of a request, lower case, apostrophes and punctuation gone.
    static func words(_ text: String) -> [String] {
        text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }

    /// The scene words a subject that is not a single thing carries.
    static let sceneWords: Set<String> = [
        "landscape", "scene", "scenery", "illustration", "illustrated", "vista", "view", "panorama", "poster",
        "sunset", "sunrise", "dusk", "dawn", "twilight", "night", "skyline",
    ]

    /// The brief for `subject`, or nil when it is not an illustration: a
    /// single thing (a dog, a cup), an icon, or a scene the illustrator has
    /// no pieces for. `style` is the model's words for the look; `request`
    /// is what the person typed, read for style words the model dropped.
    public static func make(subject: String, style: String? = nil, request: String = "",
                            icon: Bool = false) -> IllustrationBrief? {
        guard !icon else { return nil }
        let subjectWords = words(subject)
        let styleWords = words(style ?? "") + words(request)
        let all = subjectWords + styleWords
        var elements: [IllustrationElement] = []
        for word in subjectWords + words(style ?? "") + words(request) {
            for element in IllustrationElement.allCases where element.words.contains(word) && !elements.contains(element) {
                elements.append(element)
            }
        }
        let (named, badge) = Self.style(in: styleWords)
        let askedForIllustration = !Set(all).isDisjoint(with: sceneWords) || named != nil || badge
        let scenery: Set<IllustrationElement> = [.mountains, .hills, .forest, .lake, .sea, .lighthouse, .cliff, .city]
        let isScene = elements.contains { scenery.contains($0) }
        guard !elements.isEmpty, isScene || askedForIllustration else { return nil }
        // A lone subject is a scene only when an illustration was asked for
        // and the illustrator has a piece for it (a fox); a lone bird, sun or
        // moon is the built-in drawing.
        if !isScene, !(askedForIllustration && elements.contains(.fox)) { return nil }

        let time = Self.time(in: all, elements: elements)
        if elements.contains(.lighthouse) {
            if !elements.contains(.cliff) { elements.append(.cliff) }
            if !elements.contains(.sea) { elements.append(.sea) }
        }
        if elements.contains(.cliff), !elements.contains(.sea), !elements.contains(.lake) { elements.append(.sea) }
        if elements.contains(.fox) {
            if !elements.contains(.hills) { elements.append(.hills) }
            if !elements.contains(.forest) { elements.append(.forest) }
        }
        let lights: [IllustrationElement] = [.sun, .moon]
        if !elements.contains(where: lights.contains) {
            elements.append(time == .night ? .moon : .sun)
        }
        if time == .night, !elements.contains(.stars) { elements.append(.stars) }
        if elements.contains(.city), time != .night, !elements.contains(.clouds) { elements.append(.clouds) }
        let picked = named ?? Self.pick(for: elements, time: time, badge: badge)
        return IllustrationBrief(subject: subject, style: picked, badge: badge, time: time, elements: elements,
                                 styleNamed: named != nil, seed: seed(subject))
    }

    /// The style the words name, and whether they asked for a badge.
    static func style(in words: [String]) -> (IllustrationStyle?, Bool) {
        let set = Set(words)
        let joined = " " + words.joined(separator: " ") + " "
        let badge = !set.isDisjoint(with: ["badge", "circle", "circular", "round", "emblem", "patch", "logo", "monogram", "sticker", "seal"])
        var style: IllustrationStyle?
        if joined.contains(" line art ") || joined.contains(" line drawing ") || !set.isDisjoint(with: ["lineart", "outline", "outlines", "linework", "ink"]) {
            style = .lineArt
        } else if !set.isDisjoint(with: ["silhouette", "silhouettes", "silhouetted", "stencil", "monochrome", "black"]) {
            style = .silhouette
        } else if !set.isDisjoint(with: ["flat", "minimal", "minimalist", "simple", "geometric"]) {
            style = .flat
        } else if !set.isDisjoint(with: ["sunset", "layered", "layers"]) {
            style = .sunset
        } else if !set.isDisjoint(with: ["painted", "painterly", "detailed", "realistic", "depth"]) {
            style = .painted
        }
        return (style, badge)
    }

    static func time(in words: [String], elements: [IllustrationElement]) -> IllustrationTime {
        let set = Set(words)
        if !set.isDisjoint(with: ["night", "midnight", "starry", "nighttime", "moonlit", "moonlight", "stars"]) || elements.contains(.moon) { return .night }
        if !set.isDisjoint(with: ["dusk", "twilight", "evening", "blue", "gloaming"]) { return .dusk }
        if !set.isDisjoint(with: ["sunset", "sunrise", "dawn", "golden", "morning"]) { return .golden }
        if !set.isDisjoint(with: ["day", "daytime", "noon", "midday", "sunny"]) { return .day }
        if elements.contains(.city) { return .night }
        if elements.contains(.lighthouse) { return .dusk }
        return .golden
    }

    /// The illustrator's own pick when the person named no style.
    static func pick(for elements: [IllustrationElement], time: IllustrationTime, badge: Bool) -> IllustrationStyle {
        if badge { return .silhouette }
        if elements.contains(.mountains) && time == .golden { return .sunset }
        return .painted
    }

    /// The same subject always draws the same picture.
    static func seed(_ subject: String) -> UInt64 {
        var hash: UInt64 = 1_469_598_103_934_665_603
        for byte in subject.lowercased().utf8 { hash = (hash ^ UInt64(byte)) &* 1_099_511_628_211 }
        return hash
    }

    /// The words of a request that say how an illustration should look or
    /// that it is one, in the order typed: what Ask adds to an add_drawing
    /// call's style when the model left them out.
    public static func lookWords(in request: String) -> [String] {
        let typed = words(request)
        let joined = " " + typed.joined(separator: " ") + " "
        var found: [String] = []
        if joined.contains(" line art ") || joined.contains(" line drawing ") { found.append("line art") }
        let looks: Set<String> = ["illustration", "illustrated", "silhouette", "badge", "circle", "circular", "emblem",
                                  "flat", "minimal", "layered", "sunset", "painted", "outline", "stencil", "black"]
        for word in typed where looks.contains(word) && !found.contains(word) { found.append(word) }
        return found
    }

    /// The words of a request that name things the illustrator can put in
    /// a scene ("with pines", "by a lake").
    public static func sceneWords(in request: String) -> [String] {
        var found: [String] = []
        for word in words(request) where IllustrationElement.allCases.contains(where: { $0.words.contains(word) }) && !found.contains(word) {
            found.append(word)
        }
        return found
    }

    /// The change row's words for the look: "sunset", "line art badge".
    public var lookTitle: String { badge ? "\(style.title) badge" : style.title }
}
