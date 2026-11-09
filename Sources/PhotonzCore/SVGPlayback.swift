import Foundation

/// When an exported icon plays, and whether it takes the colour of the page it
/// is placed in.
///
/// Both are choices about where the file is going rather than about the
/// drawing, so they are applied to the finished file (`apply(to:id:)`) after
/// `SVGExport` has written it: Export, Copy SVG, Preview as Web Page and the
/// agent's export all write the same file and then hand it through here. A
/// document remembers its own answer (`PhotonzDocument.svgPlayback`).
///
/// **On hover** is SMIL's own event timing: every animation begins on the
/// icon's `mouseenter` and ends on its `mouseleave`, with nothing frozen, so
/// it rests on its first frame (the still pose every animated group already
/// carries as its plain attribute) until the pointer is on it, plays while it
/// is, and starts again from the top on the next visit. `mouseenter` rather
/// than `mouseover`: the latter bubbles up from every shape inside the icon, so
/// moving across it would restart the motion at each edge. Checked in WebKit
/// and Chromium on 2026-11-09, including the empty corners of the icon's box.
///
/// **Follow the page** turns the drawing's main ink (`mainInk(in:)`) into
/// `currentColor`, so the icon is drawn in the text colour of wherever it is
/// placed and shows on a dark page as well as a light one. Accent colours are
/// left as drawn.
public struct SVGPlayback: Hashable, Codable, Sendable {

    /// When the motion plays.
    public enum Plays: String, Hashable, Codable, Sendable, CaseIterable {
        /// Round and round, from the moment the file is shown: what Export
        /// has always written.
        case always
        /// While the pointer is on the icon, from the top each time.
        case onHover
        /// One lap, then held on its last frame.
        case once

        public var title: String {
            switch self {
            case .always: "Always"
            case .onHover: "On hover"
            case .once: "Once"
            }
        }
    }

    /// What colour the icon's ink is.
    public enum Ink: String, Hashable, Codable, Sendable, CaseIterable {
        /// Every colour exactly as drawn.
        case asDrawn
        /// The main ink is the page's text colour.
        case followsPage

        public var title: String {
            switch self {
            case .asDrawn: "As drawn"
            case .followsPage: "Follow the page"
            }
        }
    }

    public var plays: Plays
    public var ink: Ink

    public init(plays: Plays = .always, ink: Ink = .asDrawn) {
        self.plays = plays
        self.ink = ink
    }

    /// Loops, as drawn: the file Export wrote before there was a choice.
    public static let standard = SVGPlayback()

    public var isStandard: Bool { self == .standard }

    /// The id an icon is given when hovering it has to be named and the file
    /// names nothing itself.
    /// No minus in it: SMIL reads `a-b.mouseenter` as `a` minus an offset.
    public static let defaultID = "photonzIcon"

    /// An id SMIL reads whole inside an event: letters, digits and
    /// underscores, starting with a letter.
    static func eventSafe(_ id: String) -> String {
        var safe = String(id.map { $0.isLetter || $0.isNumber || $0 == "_" ? $0 : "_" })
        if safe.first.map({ !$0.isLetter }) ?? true { safe = "i" + safe }
        return safe
    }

    // MARK: - The file

    /// The finished file, made to play and colour itself as chosen. A
    /// standard choice hands the file back exactly as it came.
    public func apply(to svg: String, id: String = SVGPlayback.defaultID) -> String {
        var text = svg
        if ink == .followsPage { text = Self.followingThePage(text) }
        switch plays {
        case .always: break
        case .onHover: text = Self.playingOnHover(text, id: id)
        case .once: text = Self.playingOnce(text)
        }
        return text
    }

    // MARK: Plays

    /// Every animation element in the file: `<animate…/>`, `<animateTransform…/>`,
    /// `<animateMotion…/>`, `<set…/>`.
    private static var animationTag: Regex<Substring> {
        /<(?:animate|animateTransform|animateMotion|animateColor|set)\s[^>]*>/
    }

    private static func editingAnimations(_ svg: String,
                                          _ edit: (inout SVGTag) -> Void) -> String {
        svg.replacing(animationTag) { match in
            var tag = SVGTag(String(match.output))
            edit(&tag)
            return tag.text
        }
    }

    private static func hasAnimation(_ svg: String) -> Bool {
        svg.firstMatch(of: animationTag) != nil
    }

    private static func playingOnHover(_ svg: String, id requested: String) -> String {
        guard hasAnimation(svg) else { return svg }
        var text = svg
        let id: String
        if let root = text.firstMatch(of: /<svg\b[^>]*>/) {
            var tag = SVGTag(String(root.output))
            if let existing = tag.value(of: "id"), eventSafe(existing) == existing {
                id = existing
            } else {
                // A name SMIL would misread is replaced rather than escaped:
                // the escape is read differently from one engine to the next.
                id = eventSafe(requested)
                tag.remove("id")
                tag.insertFirst("id", id)
                text.replaceSubrange(root.range, with: tag.text)
            }
        } else {
            return svg
        }
        return editingAnimations(text) { tag in
            // A part that waits its turn in the lap waits it after the hover.
            let offset = tag.value(of: "begin").flatMap { $0.hasSuffix("ms") || $0.hasSuffix("s") ? $0 : nil }
            tag.set("begin", offset.map { "\(id).mouseenter+\($0)" } ?? "\(id).mouseenter")
            tag.set("end", "\(id).mouseleave")
            tag.set("restart", "whenNotActive")
            tag.remove("fill")
        }
    }

    private static func playingOnce(_ svg: String) -> String {
        guard hasAnimation(svg) else { return svg }
        return editingAnimations(svg) { tag in
            tag.set("repeatCount", "1")
            tag.remove("repeatDur")
            tag.set("fill", "freeze")
        }
    }

    // MARK: Colour

    private static var paintAttribute: Regex<(Substring, Substring, Substring)> {
        /\b(fill|stroke)="(#[0-9A-Fa-f]{3,8})"/
    }

    /// The colour most of the drawing is drawn in: the solid fill or stroke
    /// named most often. On a tie, the plainest of them (the least saturated,
    /// then the darkest), because an icon's ink is its near black and its
    /// accent is the red badge, whichever was drawn first. Upper case. Nil for
    /// a file with no solid colour at all (gradients only, or nothing).
    public static func mainInk(in svg: String) -> String? {
        var counts: [String: Int] = [:]
        for match in svg.matches(of: paintAttribute) {
            counts[String(match.output.2).uppercased(), default: 0] += 1
        }
        guard let most = counts.values.max() else { return nil }
        return counts.filter { $0.value == most }.map(\.key)
            .min { plainness($0) < plainness($1) }
    }

    /// How far a colour is from a plain dark grey: saturation first (any grey
    /// counting as none), then lightness, then the text itself so the answer
    /// never depends on order.
    private static func plainness(_ hex: String) -> (Double, Double, String) {
        guard let rgba = RGBA(hex: hex) else { return (1, 1, hex) }
        let high = max(rgba.r, rgba.g, rgba.b)
        let low = min(rgba.r, rgba.g, rgba.b)
        let saturation = high > 0 ? (high - low) / high : 0
        // A grey with a hint of blue (Apple's own label greys) is still grey.
        return (saturation < 0.2 ? 0 : saturation, high, hex)
    }

    private static func followingThePage(_ svg: String) -> String {
        guard let ink = mainInk(in: svg) else { return svg }
        // The shapes' own paint.
        var text = svg.replacing(paintAttribute) { match in
            String(match.output.2).uppercased() == ink
                ? "\(match.output.1)=\"currentColor\"" : String(match.output.0)
        }
        // A colour change that passes through the ink passes through the
        // page's colour instead.
        text = editingAnimations(text) { tag in
            guard let name = tag.value(of: "attributeName"), name == "fill" || name == "stroke"
            else { return }
            for attribute in ["values", "from", "to", "by"] {
                guard let value = tag.value(of: attribute) else { continue }
                let swapped = value.split(separator: ";", omittingEmptySubsequences: false)
                    .map { $0.trimmingCharacters(in: .whitespaces).uppercased() == ink ? "currentColor" : String($0) }
                    .joined(separator: ";")
                tag.set(attribute, swapped)
            }
        }
        return text
    }

    // MARK: - Several copies on one page

    private static var idAttribute: Regex<(Substring, Substring)> { /\bid="([^"]+)"/ }

    /// The file with every id it declares made its own by `suffix`, and every
    /// reference to one (`url(#…)`, `href="#…"`, an event's `id.mouseenter`)
    /// following, so two copies on one page never reach into each other.
    public static func uniquingIDs(in svg: String, suffix: String) -> String {
        let ids = Set(svg.matches(of: idAttribute).map { String($0.output.1) })
        guard !ids.isEmpty else { return svg }
        var text = svg.replacing(idAttribute) { match in
            "id=\"\(match.output.1)\(suffix)\""
        }
        text = text.replacing(/url\(#([^)]+)\)/) { match in
            let name = String(match.output.1)
            return ids.contains(name) ? "url(#\(name)\(suffix))" : String(match.output.0)
        }
        text = text.replacing(/href="#([^"]+)"/) { match in
            let name = String(match.output.1)
            return ids.contains(name) ? "href=\"#\(name)\(suffix)\"" : String(match.output.0)
        }
        text = text.replacing(/(begin|end)="([^"]+)"/) { match in
            let parts = match.output.2.split(separator: ";").map { part -> String in
                let trimmed = part.trimmingCharacters(in: .whitespaces)
                guard let dot = trimmed.firstIndex(of: "."),
                      ids.contains(String(trimmed[..<dot])) else { return String(part) }
                return String(trimmed[..<dot]) + suffix + String(trimmed[dot...])
            }
            return "\(match.output.1)=\"\(parts.joined(separator: ";"))\""
        }
        return text
    }
}

// MARK: - One tag

/// One element's opening tag, edited attribute by attribute. Only ever used on
/// the tags `SVGExport` writes itself, which put each attribute in double
/// quotes and end a childless element with `/>`.
struct SVGTag {
    private(set) var text: String

    init(_ text: String) { self.text = text }

    private func range(of name: String) -> Range<String.Index>? {
        let pattern = " \(name)=\""
        guard let start = text.range(of: pattern),
              let close = text[start.upperBound...].firstIndex(of: "\"") else { return nil }
        return start.lowerBound..<text.index(after: close)
    }

    func value(of name: String) -> String? {
        guard let range = range(of: name) else { return nil }
        let quoted = text[range]
        guard let open = quoted.firstIndex(of: "\"") else { return nil }
        return String(quoted[quoted.index(after: open)..<quoted.index(before: quoted.endIndex)])
    }

    mutating func set(_ name: String, _ value: String) {
        let attribute = " \(name)=\"\(value)\""
        if let range = range(of: name) {
            text.replaceSubrange(range, with: attribute)
        } else if let end = text.range(of: "/>", options: .backwards) {
            text.insert(contentsOf: attribute, at: end.lowerBound)
        } else if let end = text.lastIndex(of: ">") {
            text.insert(contentsOf: attribute, at: end)
        }
    }

    /// Right after the element's name, where a person reading the file looks
    /// for an id.
    mutating func insertFirst(_ name: String, _ value: String) {
        guard let space = text.firstIndex(of: " ") else { return set(name, value) }
        text.insert(contentsOf: " \(name)=\"\(value)\"", at: space)
    }

    mutating func remove(_ name: String) {
        if let range = range(of: name) { text.removeSubrange(range) }
    }
}
