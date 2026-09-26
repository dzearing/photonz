import Foundation

// The Properties pane beside a clip, a title or a sound
// (`docs/design/mocks/pages/video.html`, `renderProps`).
//
// The timeline says WHEN, this pane says WHAT. It opens on one line that names
// the thing and says where it starts, where it ends, how long it is and how
// fast it plays, then lists only the values that are ANIMATING. Every other
// value is one click away in a picker, because the list only grows: effects
// bring their own values, and a clip already offers fifteen.

/// The pane's first line: `Sample Talk        2.0s → 14.9s  12.9s · 1.0x`.
public struct ClipLine: Hashable, Sendable {
    public let name: String
    public let startMS: Int
    public let endMS: Int
    /// How fast it plays: 100 as recorded, 0 for a held frame.
    public let speedPercent: Int

    /// The line for a layer with time: for a cut clip, the piece at `piece`
    /// (the one the timeline has in hand), since each piece is its own clip on
    /// the timeline and has its own in, out and speed. Nil without time.
    public init?(layer: Layer, piece: Int? = nil) {
        guard let time = layer.time else { return nil }
        name = layer.displayName
        if let piece, let pieces = layer.clipPieces, let one = pieces.piece(at: piece) {
            startMS = time.inMS + pieces.startMS(ofPiece: piece)
            endMS = startMS + one.lengthMS
            speedPercent = one.speedPercent
        } else {
            startMS = time.inMS
            endMS = time.outMS
            speedPercent = ClipPiece.asRecordedPercent
        }
    }

    public var lengthMS: Int { max(0, endMS - startMS) }

    public var inText: String { Self.seconds(startMS) }
    public var outText: String { Self.seconds(endMS) }
    public var lengthText: String { Self.seconds(lengthMS) }
    public var speedText: String { Self.speedText(percent: speedPercent) }

    /// Everything after the name, as one string for a walk to read back.
    public var reading: String {
        "\(inText) \u{2192} \(outText) \u{00B7} \(lengthText) \u{00B7} \(speedText)"
    }

    /// Seconds to one decimal, the mock's `12.9s`.
    public static func seconds(_ ms: Int) -> String {
        String(format: "%.1fs", Double(ms) / 1000)
    }

    /// `1.0x`, `0.5x`, `0.25x`: one decimal, two where one would round a
    /// speed the menu offers into one it does not.
    public static func speedText(percent: Int) -> String {
        guard percent > 0 else { return "held" }
        let format = percent % 10 == 0 ? "%.1fx" : "%.2fx"
        return String(format: format, Double(percent) / 100)
    }

    /// The chip on the pane's header: what kind of thing is picked, in the
    /// mock's words.
    public static func kind(of layer: Layer) -> String {
        if layer.isCaptionsLayer { return "Captions" }
        if layer.isCaption { return "Caption" }
        if layer.isComponentInstance { return "Instance" }
        switch TimePanelOrder.role(of: layer) {
        case .heard: return "Audio"
        case .onScreen:
            if layer.isText { return "Title" }
            // A shape, a line, a picture placed in time: Premiere's Graphic.
            return layer.isPlacedInTime && !layer.isGroup ? "Graphic" : "Clip"
        case .playing, nil: return "Clip"
        }
    }
}

/// Animating's count and the Animate a property picker.
public enum PropertyPicker {

    /// One group of the picker: a small caps heading and its values.
    public struct Group: Hashable, Sendable {
        public let title: String
        public let properties: [KeyedProperty]
    }

    /// The mock's `2 of 9 properties`, or `nothing yet`.
    public static func countText(keyed: Int, of total: Int) -> String {
        guard keyed > 0 else { return "nothing yet" }
        return "\(keyed) of \(total) \(total == 1 ? "property" : "properties")"
    }

    /// Which heading a value sits under in the picker, the mock's `g`.
    public static func group(_ property: KeyedProperty) -> String {
        switch property {
        case .volume:
            return "Levels"
        case let .motion(motion):
            switch motion {
            case .position, .scale, .rotation: return "Transform"
            case .opacity, .cornerRadius, .strokeWidth, .color: return "Appearance"
            case .blur, .shadow, .glow: return "Effects"
            case .textSize: return "Text"
            case .cropLeft, .cropTop, .cropRight, .cropBottom: return "Crop"
            }
        }
    }

    /// What the picker offers: every value not already animating whose name
    /// holds the query, grouped in the order the values come.
    public static func groups(all: [KeyedProperty], keyed: Set<KeyedProperty>,
                              query: String) -> [Group] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var order: [String] = []
        var members: [String: [KeyedProperty]] = [:]
        for property in all where !keyed.contains(property) {
            if !needle.isEmpty, !property.title.lowercased().contains(needle) { continue }
            let title = group(property)
            if members[title] == nil { order.append(title) }
            members[title, default: []].append(property)
        }
        return order.map { Group(title: $0, properties: members[$0] ?? []) }
    }

    /// What the picker says when it has nothing to offer.
    public static func emptyText(query: String) -> String {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Every property is already animating."
                               : "Nothing matches \u{201C}\(trimmed)\u{201D}."
    }
}
