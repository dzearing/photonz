import CoreGraphics
import Foundation

// What somebody set by hand on a chart's bars or a title's parts survives a
// change of numbers or a restyle (task
// `a-chart-or-title-keeps-what-you-set-by-hand-when`).
//
// Two things used to go. A chart laid out again from new numbers matched its
// old pieces to its new ones by NAME, "Bar 2" to "Bar 2", so taking the first
// row away moved every bar's keys and looks onto the bar of the next row and
// left the last row's on nothing. And a restyle wrote its own version of an
// effect over the one the person had edited (a shade, a glow's size, the
// motion blur's shutter), because it could not tell an effect it drew from
// one somebody changed.
//
// So a chart's rows are told apart by their labels (`rowSources`), and a
// title remembers the effects its own drawing gave every piece
// (`TitleRecipe.drawnEffects`). An effect that is still exactly what the
// drawing gave is the drawing's to change; one that differs is the person's
// and stays as they left it (`LayerEffect.keepingHandEdits`).

// MARK: - Which row is which

extension ChartSpec {

    /// For each of these rows, the row of `old` it is, nil for a row that is
    /// new. Rows are matched by label, in order, so taking one away or adding
    /// one leaves every other row itself. Between two rows matched that way,
    /// the rows left on each side pair off in order as far as both go: a row
    /// renamed where it stands, or a whole new table pasted over the old.
    public func rowSources(from old: ChartSpec) -> [Int?] {
        let was = old.rows.map(\.label)
        let now = rows.map(\.label)
        // The longest run of labels the two share, in order.
        var common = Array(repeating: Array(repeating: 0, count: now.count + 1), count: was.count + 1)
        for i in stride(from: was.count - 1, through: 0, by: -1) {
            for j in stride(from: now.count - 1, through: 0, by: -1) {
                common[i][j] = was[i] == now[j] ? common[i + 1][j + 1] + 1 : max(common[i + 1][j], common[i][j + 1])
            }
        }
        var pairs: [(Int, Int)] = []
        var i = 0, j = 0
        while i < was.count, j < now.count {
            if was[i] == now[j] {
                pairs.append((i, j))
                i += 1
                j += 1
            } else if common[i + 1][j] >= common[i][j + 1] {
                i += 1
            } else {
                j += 1
            }
        }
        var sources = [Int?](repeating: nil, count: now.count)
        for (i, j) in pairs { sources[j] = i }
        var lastWas = -1, lastNow = -1
        for (i, j) in pairs + [(was.count, now.count)] {
            let olds = Array((lastWas + 1)..<i)
            let news = Array((lastNow + 1)..<j)
            for (o, n) in zip(olds, news) { sources[n] = o }
            lastWas = i
            lastNow = j
        }
        return sources
    }

    /// For each of `old`'s rows, the row of these it became, nil for one
    /// taken away.
    func rowDestinations(from old: ChartSpec) -> [Int?] {
        var destinations = [Int?](repeating: nil, count: old.rows.count)
        for (now, was) in rowSources(from: old).enumerated() {
            if let was, destinations.indices.contains(was) { destinations[was] = now }
        }
        return destinations
    }
}

extension ChartPen {

    /// "Bar 3" is the third row's bar: every piece drawn for a row is named
    /// its kind and the row's number, and no other piece ends in a number.
    static func row(of name: String) -> (stem: Substring, index: Int)? {
        guard let space = name.lastIndex(of: " "), let number = Int(name[name.index(after: space)...]),
              number >= 1 else { return nil }
        return (name[..<space], number - 1)
    }

    /// What the piece called `name` is called after rows move, where `map`
    /// says which row each row becomes (or came from): a piece of no row
    /// keeps its name, and nil is a row that has no counterpart.
    static func renamed(_ name: String, _ map: [Int?]) -> String? {
        guard let (stem, index) = row(of: name) else { return name }
        guard map.indices.contains(index), let other = map[index] else { return nil }
        return "\(stem) \(other + 1)"
    }
}

extension TitleRecipe {

    /// The part of this recipe (the one after a change) that `part` of `old`
    /// became, and whether the change left its in, hold and out alone. On a
    /// chart a part follows its row, and a row whose place moved but whose
    /// timing nobody touched still counts as left alone: its beat follows its
    /// place.
    func part(following part: TitlePart, from old: TitleRecipe) -> (part: TitlePart, untouched: Bool)? {
        guard let was = old.chart, let now = chart else {
            guard let same = design.parts.first(where: { $0.path == part.path }) else { return nil }
            return (same, same == part)
        }
        guard let path = ChartPen.renamed(part.path, now.rowDestinations(from: was)),
              let became = design.parts.first(where: { $0.path == path }) else { return nil }
        if became.in == part.in, became.hold == part.hold, became.out == part.out { return (became, true) }
        let usualBefore = ChartPen.design(was).parts.first { $0.path == part.path }
        let usualNow = ChartPen.design(now).parts.first { $0.path == path }
        return (became, part == usualBefore && became == usualNow)
    }
}

// MARK: - Effects: the drawing's against the hand's

extension LayerEffect {

    /// A piece's effects after its drawing changed: `hand` is what it wears,
    /// `drawn` what the old drawing gave it, `fresh` what the new one gives.
    ///
    /// Effects are matched kind by kind, in order (a piece's second shadow
    /// against the drawing's second shadow). One still exactly as drawn takes
    /// the new drawing's; one that differs was edited and stays; one beyond
    /// what was drawn was added and stays; one drawn and no longer there was
    /// deleted and stays deleted; one the new drawing gives beyond what the
    /// old one did arrives.
    public static func keepingHandEdits(_ hand: [LayerEffect], drawn: [LayerEffect],
                                        fresh: [LayerEffect]) -> [LayerEffect] {
        func byKind(_ list: [LayerEffect]) -> [EffectKind: [LayerEffect]] {
            Dictionary(grouping: list, by: \.kind)
        }
        let drawnByKind = byKind(drawn)
        let freshByKind = byKind(fresh)
        var seen: [EffectKind: Int] = [:]
        var kept: [LayerEffect] = []
        for effect in hand {
            let ordinal = seen[effect.kind, default: 0]
            seen[effect.kind] = ordinal + 1
            let drew = drawnByKind[effect.kind] ?? []
            guard drew.indices.contains(ordinal), drew[ordinal] == effect else {
                kept.append(effect)
                continue
            }
            let draws = freshByKind[effect.kind] ?? []
            if draws.indices.contains(ordinal) { kept.append(draws[ordinal]) }
        }
        var arrived: [EffectKind: Int] = [:]
        for effect in fresh {
            let ordinal = arrived[effect.kind, default: 0]
            arrived[effect.kind] = ordinal + 1
            if ordinal >= (drawnByKind[effect.kind]?.count ?? 0) && ordinal >= seen[effect.kind, default: 0] {
                kept.append(effect)
            }
        }
        return kept
    }
}

// MARK: - A title's drawing, remembered

/// A title's pieces by where they sit: "" is the title itself, "Card/Name"
/// the Name inside its Card. Only paths that name one piece count.
enum TitlePieces {

    static func paths(_ group: Layer) -> [UUID: String] {
        var found: [(UUID, String)] = [(group.id, "")]
        func walk(_ layer: Layer, _ path: String) {
            for child in layer.children {
                let here = path.isEmpty ? child.name : "\(path)/\(child.name)"
                found.append((child.id, here))
                walk(child, here)
            }
        }
        walk(group, "")
        var counts: [String: Int] = [:]
        for (_, path) in found { counts[path, default: 0] += 1 }
        return Dictionary(found.filter { counts[$0.1] == 1 }, uniquingKeysWith: { first, _ in first })
    }

    /// How tall every line of words in `group` is, by path.
    static func textHeights(_ group: Layer) -> [String: CGFloat] {
        let paths = paths(group)
        var heights: [String: CGFloat] = [:]
        for piece in group.selfAndDescendants where piece.text != nil {
            if let path = paths[piece.id] { heights[path] = piece.frame.height }
        }
        return heights
    }

    /// The effects every piece of `group` wears, by path.
    static func effects(_ group: Layer) -> [String: [LayerEffect]] {
        let paths = paths(group)
        var drawn: [String: [LayerEffect]] = [:]
        for piece in group.selfAndDescendants {
            if let path = paths[piece.id] { drawn[path] = piece.style.effects }
        }
        return drawn
    }

    /// `group` with every piece the drawing remembers wearing what it drew.
    static func wearing(_ drawn: [String: [LayerEffect]]?, _ group: Layer) -> Layer {
        guard let drawn else { return group }
        let paths = paths(group)
        func put(_ layer: Layer) -> Layer {
            var layer = layer
            if let path = paths[layer.id], let effects = drawn[path] { layer.style.effects = effects }
            if case .group(var content) = layer.content {
                content.children = content.children.map(put)
                layer.content = .group(content)
            }
            return layer
        }
        return put(group)
    }

    /// `drawn`, the title as its new drawing leaves it, wearing again every
    /// effect somebody edited, added or took away on `hand`, the title as
    /// they left it. `remembered` is what the old drawing gave each piece by
    /// path; `fallback` stands in for a piece it does not know.
    static func keepingHandEdits(_ hand: Layer, in drawn: Layer, remembered: [String: [LayerEffect]]?,
                                 fallback: (Layer) -> [LayerEffect]?) -> Layer {
        let handPaths = paths(hand)
        let handPieces = Dictionary(hand.selfAndDescendants.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        func keep(_ layer: Layer) -> Layer {
            var layer = layer
            if let was = handPieces[layer.id] {
                let before = handPaths[was.id].flatMap { remembered?[$0] } ?? fallback(was) ?? was.style.effects
                layer.style.effects = LayerEffect.keepingHandEdits(was.style.effects, drawn: before,
                                                                   fresh: layer.style.effects)
            }
            if case .group(var content) = layer.content {
                content.children = content.children.map(keep)
                layer.content = .group(content)
            }
            return layer
        }
        return keep(drawn)
    }
}
