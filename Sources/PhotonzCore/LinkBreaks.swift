import CoreGraphics
import Foundation

/// When a link quietly breaks, the app says so, the same way every time.
///
/// Five things in a document follow something else, and all five can stop
/// following without anybody saying so: a color that came from a named style
/// is painted over, text that came from a named style is set some other way,
/// one part of a copy's look is set by hand, a copy is ungrouped into loose
/// layers, and an original is deleted out from under its copies. Each break is silent at the moment it happens and only shows up
/// later, when an edit to the original leaves something behind.
///
/// They are one fact with four shapes, so they are found in one place: a diff
/// of the document before and after an edit, run from `History.perform`. That
/// is what makes this reach every route in — a menu item, a key, a walk in the
/// playtest harness, a command written next year — instead of the ones somebody
/// remembered to wire up.

// MARK: - What broke

/// The kind of link that let go.
public enum LinkBreakKind: String, Hashable, Sendable, CaseIterable {
    /// An original was deleted (or ungrouped), and its copies were left behind.
    case originalDeleted
    /// A copy was taken apart into loose layers.
    case instanceUngrouped
    /// A color that was wearing a named style was painted some other way.
    case colorStyle
    /// Text that was wearing a named style was set some other way.
    case textStyle
    /// An effect that was wearing a named style was tuned some other way.
    case effectStyle
    /// One part of a copy's look was set by hand, so it stopped following.
    case instanceStyle

    /// Which break leads when an edit broke more than one thing. Heaviest
    /// first: work left stranded outranks one slider on one copy.
    var weight: Int {
        switch self {
        case .originalDeleted: return 0
        case .instanceUngrouped: return 1
        case .colorStyle: return 2
        case .textStyle: return 3
        case .effectStyle: return 4
        case .instanceStyle: return 5
        }
    }
}

/// One link that let go, with everything the sentence needs.
public struct LinkBreak: Hashable, Sendable {
    public var kind: LinkBreakKind
    /// How many things stopped following: colors, parts of a look, or copies.
    public var count: Int
    /// What they stopped following — a style's name, or an original's. Nil when
    /// there is no name to point at, and the sentence says "its original".
    public var source: String?
    /// The one part that let go, named the way its control is
    /// (`LayerStyleField.label`). Only set when exactly one part did.
    public var part: String?
    /// How many copies the parts were spread across, so one slider on one copy
    /// and one slider on each of three copies do not read the same.
    public var copies: Int

    public init(kind: LinkBreakKind, count: Int, source: String? = nil,
                part: String? = nil, copies: Int = 1) {
        self.kind = kind
        self.count = count
        self.source = source
        self.part = part
        self.copies = copies
    }

    /// What stopped following, as the head of the sentence.
    var subject: String {
        switch kind {
        case .colorStyle:
            return count == 1 ? "1 color" : "\(count) colors"
        case .textStyle:
            return count == 1 ? "1 piece of text" : "\(count) pieces of text"
        case .effectStyle:
            return count == 1 ? "1 effect" : "\(count) effects"
        case .instanceStyle:
            if count == 1, let part { return "\(part) on this copy" }
            let parts = "\(count) parts"
            return copies == 1 ? "\(parts) of this copy" : "\(parts) of \(copies) copies"
        case .instanceUngrouped:
            return count == 1 ? "The pieces of this copy" : "The pieces of \(count) copies"
        case .originalDeleted:
            return count == 1 ? "1 copy" : "\(count) copies"
        }
    }

    /// Whether the subject takes a plural verb. The pieces of one copy are
    /// still pieces.
    var isPlural: Bool {
        switch kind {
        case .instanceUngrouped: return true
        case .instanceStyle: return count != 1
        case .colorStyle, .textStyle, .effectStyle, .originalDeleted: return count != 1
        }
    }

    /// The whole sentence, in the one frame every break uses.
    var sentence: String {
        let followed = source ?? (isPlural ? "their originals" : "its original")
        return "\(subject) no longer \(isPlural ? "follow" : "follows") \(followed)"
    }
}

// MARK: - What one edit broke

/// Everything one edit broke, and the one line the canvas says about it.
public struct LinkBreakReport: Hashable, Sendable {
    /// Heaviest break first, so the line leads with the one worth reading.
    public private(set) var breaks: [LinkBreak]

    public init(breaks: [LinkBreak] = []) {
        self.breaks = breaks.enumerated()
            .sorted { ($0.element.kind.weight, $0.offset) < ($1.element.kind.weight, $1.offset) }
            .map(\.element)
    }

    public var isEmpty: Bool { breaks.isEmpty }

    /// The verdict, the same words for all four: what happened is that
    /// something stopped following what it came from.
    public var title: String { "Stopped following" }

    /// The one line under it. An edit that broke two unrelated things leads
    /// with the heavier one and counts the rest, rather than stacking pills or
    /// quietly dropping half of what happened.
    public var detail: String? {
        guard let lead = breaks.first else { return nil }
        let rest = breaks.count - 1
        guard rest > 0 else { return lead.sentence }
        return "\(lead.sentence), and \(rest) more link\(rest == 1 ? "" : "s") broke"
    }
}

// MARK: - Finding them

extension LinkBreakReport {

    /// Everything that stopped following between two versions of a document.
    ///
    /// `after` is the document as it will be kept: the color styles have
    /// already been reconciled and the copies already put back in step, so what
    /// is compared here is what the person will actually see.
    ///
    /// A document with no saved colors and no copies in it cannot break a link,
    /// and leaves after one walk that allocates nothing.
    public static func between(_ before: PhotonzDocument,
                               _ after: PhotonzDocument) -> LinkBreakReport {
        let holdsCopies = before.holdsComponentInstance
        guard !before.colorStyles.isEmpty || !before.textStyles.isEmpty
                || !before.effectStyles.isEmpty || holdsCopies else {
            return LinkBreakReport()
        }

        var afterByID: [UUID: Layer] = [:]
        for layer in after.allLayers { afterByID[layer.id] = layer }
        let edited = editableLayers(before)

        var breaks: [LinkBreak] = []
        breaks.append(contentsOf: colorBreaks(before, after, edited, afterByID))
        breaks.append(contentsOf: textBreaks(before, after, edited, afterByID))
        breaks.append(contentsOf: effectBreaks(before, after, edited, afterByID))
        if holdsCopies {
            breaks.append(contentsOf: componentBreaks(before, after, edited, afterByID))
        }
        return LinkBreakReport(breaks: breaks)
    }

    /// Every layer somebody could have edited: the tree, stopping at a copy.
    ///
    /// What is INSIDE a copy is the original's, rewritten from it after every
    /// edit, so a link that breaks in there broke in the original and is
    /// counted once, there. Without this, painting over one color inside an
    /// original with four copies out would say four colors let go of the style
    /// when a person changed one.
    private static func editableLayers(_ document: PhotonzDocument) -> [Layer] {
        var found: [Layer] = []
        func walk(_ list: [Layer]) {
            for layer in list {
                found.append(layer)
                if layer.isGroup, !layer.isComponentInstance { walk(layer.children) }
            }
        }
        walk(document.layers)
        return found
    }

    /// Colors that drifted off a style.
    ///
    /// A slot that now points at a DIFFERENT style is a choice somebody made,
    /// not a break. A slot whose style was taken off the shelf is not one
    /// either: Remove Style already means "these colors are their own now", and
    /// saying so afterwards is the app repeating your own command back at you.
    /// What is left is the quiet one: the color was painted some other way and
    /// the name it claimed stopped being true.
    private static func colorBreaks(_ before: PhotonzDocument, _ after: PhotonzDocument,
                                    _ edited: [Layer],
                                    _ afterByID: [UUID: Layer]) -> [LinkBreak] {
        guard !before.colorStyles.isEmpty else { return [] }
        let names = Dictionary(after.colorStyles.map { ($0.id, $0.name) },
                               uniquingKeysWith: { first, _ in first })
        var lost: [UUID: Int] = [:]
        var order: [UUID] = []
        for layer in edited {
            let bindings = layer.colorStyleBindings ?? []
            guard !bindings.isEmpty, let now = afterByID[layer.id] else { continue }
            let after = now.colorStyleBindings ?? []
            // A slot and an EFFECT'S colour are told apart, because both can
            // name the same slot: a border ring on the layer and a border in
            // the Effects list are two colours, and one of them going plain is
            // not the other one going plain.
            let stillBound = Set(after.filter { $0.effectIndex == nil }.map(\.slot))
            // An effect's name is followed by which STYLE it wears rather than
            // by where it sits: taking a row out of the list moves every row
            // under it up a place, and a name that simply slid up a row has not
            // been lost.
            let stillOnAnEffect = Set(after.filter { $0.effectIndex != nil }.map(\.styleID))
            let listShrank = now.style.effects.count < layer.style.effects.count
            for binding in bindings {
                if binding.effectIndex != nil {
                    // A shorter list is a row you took out, and its name went
                    // with it. The app repeating your own delete back at you is
                    // not news, exactly as Remove Style is not.
                    guard !listShrank, !stillOnAnEffect.contains(binding.styleID) else { continue }
                } else {
                    guard !stillBound.contains(binding.slot) else { continue }
                }
                guard names[binding.styleID] != nil else { continue }
                if lost[binding.styleID] == nil { order.append(binding.styleID) }
                lost[binding.styleID, default: 0] += 1
            }
        }
        return order.map { LinkBreak(kind: .colorStyle, count: lost[$0] ?? 0, source: names[$0]) }
    }

    /// Text that drifted off a style.
    ///
    /// The same three exceptions the colours make. Text now pointing at a
    /// DIFFERENT style is a choice somebody made, not a break, and text whose
    /// style was taken off the shelf is not one either: Remove already means
    /// "this text is its own now". What is left is the quiet one, where the
    /// type was set some other way and the name it claimed stopped being true.
    private static func textBreaks(_ before: PhotonzDocument, _ after: PhotonzDocument,
                                   _ edited: [Layer],
                                   _ afterByID: [UUID: Layer]) -> [LinkBreak] {
        guard !before.textStyles.isEmpty else { return [] }
        let names = Dictionary(after.textStyles.map { ($0.id, $0.name) },
                               uniquingKeysWith: { first, _ in first })
        var lost: [UUID: Int] = [:]
        var order: [UUID] = []
        for layer in edited {
            guard let styleID = layer.textStyleID, names[styleID] != nil,
                  let now = afterByID[layer.id], now.textStyleID == nil else { continue }
            if lost[styleID] == nil { order.append(styleID) }
            lost[styleID, default: 0] += 1
        }
        return order.map { LinkBreak(kind: .textStyle, count: lost[$0] ?? 0, source: names[$0]) }
    }

    /// Effects that drifted off a style.
    ///
    /// The same three exceptions the colours and the text make. An entry now
    /// pointing at a DIFFERENT style is a choice somebody made, not a break,
    /// and an entry whose style was taken off the shelf is not one either:
    /// Remove already means "these effects are their own now". What is left is
    /// the quiet one, where the shadow was tuned by hand and the name it
    /// claimed stopped being true.
    ///
    /// A row TAKEN OUT of the list is not a break either. Its name went with
    /// it, and the app repeating your own delete back at you is not news. It is
    /// told from a drift the same way an effect's colour is: by which STYLE is
    /// still worn rather than by where it sits, since taking a row out moves
    /// every row under it up a place.
    private static func effectBreaks(_ before: PhotonzDocument, _ after: PhotonzDocument,
                                     _ edited: [Layer],
                                     _ afterByID: [UUID: Layer]) -> [LinkBreak] {
        guard !before.effectStyles.isEmpty else { return [] }
        let names = Dictionary(after.effectStyles.map { ($0.id, $0.name) },
                               uniquingKeysWith: { first, _ in first })
        var lost: [UUID: Int] = [:]
        var order: [UUID] = []
        for layer in edited {
            let bindings = layer.effectStyleBindings ?? []
            guard !bindings.isEmpty, let now = afterByID[layer.id] else { continue }
            let stillWorn = Set((now.effectStyleBindings ?? []).map(\.styleID))
            let listShrank = now.style.effects.count < layer.style.effects.count
            for binding in bindings {
                guard !listShrank, !stillWorn.contains(binding.styleID) else { continue }
                guard names[binding.styleID] != nil else { continue }
                if lost[binding.styleID] == nil { order.append(binding.styleID) }
                lost[binding.styleID, default: 0] += 1
            }
        }
        return order.map { LinkBreak(kind: .effectStyle, count: lost[$0] ?? 0, source: names[$0]) }
    }

    /// The three ways a copy stops following its original.
    private static func componentBreaks(_ before: PhotonzDocument, _ after: PhotonzDocument,
                                        _ edited: [Layer],
                                        _ afterByID: [UUID: Layer]) -> [LinkBreak] {
        var namesBefore: [UUID: String] = [:]
        for layer in before.allLayers {
            if let componentID = layer.componentID { namesBefore[componentID] = layer.name }
        }
        var mainsAfter: Set<UUID> = []
        for layer in after.allLayers {
            if let componentID = layer.componentID { mainsAfter.insert(componentID) }
        }

        var ownedParts: [UUID: (fields: Int, copies: Int, only: String?)] = [:]
        var ungrouped: [UUID: Int] = [:]
        var stranded: [UUID: Int] = [:]
        var order: [(LinkBreakKind, UUID)] = []
        func note(_ kind: LinkBreakKind, _ componentID: UUID) {
            if !order.contains(where: { $0.0 == kind && $0.1 == componentID }) {
                order.append((kind, componentID))
            }
        }

        for layer in edited {
            guard let componentID = layer.instanceOf else { continue }
            guard let now = afterByID[layer.id] else {
                // The copy is gone. Its pieces surviving is what tells an
                // ungroup apart from a delete: ungroup promotes the children
                // and keeps their ids, deleting takes them with it.
                if layer.children.contains(where: { afterByID[$0.id] != nil }) {
                    ungrouped[componentID, default: 0] += 1
                    note(.instanceUngrouped, componentID)
                }
                continue
            }
            if now.instanceOf == componentID {
                let fresh = now.ownStyleFields.subtracting(layer.ownStyleFields)
                guard !fresh.isEmpty else { continue }
                var entry = ownedParts[componentID] ?? (0, 0, nil)
                entry.fields += fresh.count
                entry.copies += 1
                let onlyOne = fresh.count == 1 ? fresh.first?.label : nil
                entry.only = entry.fields == 1 ? onlyOne : nil
                ownedParts[componentID] = entry
                note(.instanceStyle, componentID)
            } else if now.instanceOf == nil, !mainsAfter.contains(componentID) {
                // The original is gone and this copy kept what it was drawing.
                // A copy DETACHED on purpose is not this: its original is still
                // there, and Detach says so itself.
                stranded[componentID, default: 0] += 1
                note(.originalDeleted, componentID)
            }
        }

        return order.compactMap { kind, componentID in
            let name = namesBefore[componentID]
            switch kind {
            case .instanceStyle:
                guard let entry = ownedParts[componentID] else { return nil }
                return LinkBreak(kind: kind, count: entry.fields, source: name,
                                 part: entry.only, copies: entry.copies)
            case .instanceUngrouped:
                guard let count = ungrouped[componentID] else { return nil }
                return LinkBreak(kind: kind, count: count, source: name)
            case .originalDeleted:
                guard let count = stranded[componentID] else { return nil }
                return LinkBreak(kind: kind, count: count, source: name)
            case .colorStyle, .textStyle, .effectStyle:
                return nil
            }
        }
    }
}
