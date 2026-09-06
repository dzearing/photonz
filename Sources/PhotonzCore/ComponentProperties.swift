import CoreGraphics
import Foundation

/// Knobs on a component, and the answers a copy gives them
/// (`docs/design/ui-building.md`, step C6).
///
/// A copy is only useful if you can adjust it. The rule that keeps adjusting
/// from becoming drifting is that the ORIGINAL chooses what is adjustable: it
/// exposes a knob, and a copy may set that knob and nothing else. Everything
/// inside a copy is still the original's, so the only things a copy owns are
/// its answers.
///
/// There are five kinds of knob and they are deliberately the same shape as
/// each other: every one of them is one fact about one layer inside the
/// original.
///
/// - **wording** (`.text`) — what a text layer says.
/// - **show or hide** (`.visible`) — whether a layer is drawn at all.
/// - **a choice** (`.variant`) — which ONE of a group's children is drawn.
/// - **a colour** (`.color`) — what one PART of a layer is painted: its fill,
///   its outline, its ink, its border.
/// - **a number** (`.number`) — one of the numbers a layer already has: how
///   round it is, how thick the line round it is, how far apart a stack holds
///   its contents, how much room a group keeps inside its edges
///   (`ComponentNumberKnob.swift`).
///
/// The third is what makes "an instance can never show something the original
/// does not define" true rather than aspirational: a choice can only land on a
/// layer the group already holds, so there is nowhere for a copy to drift to.
///
/// The last two are the ones that name something narrower than a layer, and
/// they have to: one box has both a fill and an outline, and both a rounding
/// and a thickness, so those knobs carry the slot they turn alongside the layer
/// they reach.

// MARK: - The knob

/// What a knob adjusts.
public enum ComponentPropertyKind: String, Hashable, Codable, Sendable, CaseIterable {
    /// The wording of a text layer.
    case text
    /// Whether a layer shows at all.
    case visible
    /// Which one of a group's children shows.
    case variant
    /// What one part of a layer is painted. The part itself is the knob's
    /// `slot`, because a box has more than one colour.
    case color
    /// One of the numbers a layer already has. Which number is the knob's
    /// `numberSlot`, because a box has more than one number.
    case number

    /// What the knob is called where a person meets it. Plain words: nobody
    /// arrives knowing what "boolean" or "variant" means.
    public var label: String {
        switch self {
        case .text: return "Wording"
        case .visible: return "Show or hide"
        case .variant: return "Choice"
        case .color: return "Color"
        case .number: return "Number"
        }
    }

    /// What a knob of this kind is called when the layer it exposes has no name
    /// worth borrowing. It says what you are setting rather than repeating the
    /// chip beside it: "Shape", not "Choice · choice".
    public var defaultName: String {
        switch self {
        case .text: return "Wording"
        case .visible: return "Show"
        case .variant: return "Shape"
        // Never reached: a colour and a number knob are named after the part
        // they turn, so `defaultPropertyName` answers for them before this does.
        case .color: return "Color"
        case .number: return "Number"
        }
    }

    /// The one word on the chip beside a knob's name.
    public var chip: String {
        switch self {
        case .text: return "text"
        case .visible: return "show"
        case .variant: return "choice"
        case .color: return "color"
        case .number: return "number"
        }
    }
}

/// One knob an original exposes: a name, what kind of knob it is, and the
/// layer inside the original it reaches.
public struct ComponentProperty: Hashable, Codable, Sendable, Identifiable {
    public var id: UUID
    /// What the knob is called on a copy's panel. It starts as the name of the
    /// layer it exposes, because that is the thing the author was looking at.
    public var name: String
    public var kind: ComponentPropertyKind
    /// The layer inside the original this knob reaches. A copy's matching
    /// layer is derived from it, so this id is the one stable handle.
    public var target: UUID
    /// WHICH colour, on a `.color` knob. Nil for every other kind, and absent
    /// from anything written before colour knobs existed, so an old document
    /// decodes exactly as it did.
    public var slot: ColorSlot?
    /// WHICH number, on a `.number` knob. Nil for every other kind, and absent
    /// from the file entirely otherwise, so a document written before number
    /// knobs existed decodes exactly as it did.
    public var numberSlot: ComponentNumberSlot?

    public init(id: UUID = UUID(), name: String, kind: ComponentPropertyKind, target: UUID,
                slot: ColorSlot? = nil, numberSlot: ComponentNumberSlot? = nil) {
        self.id = id
        self.name = name
        self.kind = kind
        self.target = target
        self.slot = kind == .color ? slot : nil
        self.numberSlot = kind == .number ? numberSlot : nil
    }
}

/// A copy's answer to a colour knob: what it is painted, and the saved colour
/// it came from when it came from one.
///
/// It is the same two facts a LAYER carries, and deliberately so. The paint is
/// what gets drawn, so nothing downstream has to learn what a style is; the
/// pointer is the extra fact that says where the colour came from, so editing
/// that saved colour finds its way back here, and deleting it leaves the copy
/// exactly the colour it was wearing.
public struct ComponentColorAnswer: Hashable, Codable, Sendable {
    /// What this copy paints in the slot. Kept fresh while it points at a
    /// saved colour, so it is an honest answer the moment the name goes away.
    public var paint: Paint
    /// The saved colour it points at, or nil for a colour of its own.
    public var styleID: UUID?

    public init(paint: Paint, styleID: UUID? = nil) {
        self.paint = paint
        self.styleID = styleID
    }

    public init(colorHex: String, styleID: UUID? = nil) {
        self.init(paint: Paint(hex: colorHex), styleID: styleID)
    }

    /// The one flat colour it stands for, which is what a row that can only
    /// print one colour says.
    public var colorHex: String { paint.hex }
}

/// A copy's answer to one knob.
public enum ComponentPropertyValue: Hashable, Codable, Sendable {
    case text(String)
    case visible(Bool)
    /// The id, IN THE ORIGINAL, of the child that shows. Storing the original's
    /// id rather than the copy's own means the answer survives the copy being
    /// duplicated, and it can be checked against what the original holds.
    case variant(UUID)
    /// What one part of the copy is painted, and the saved colour it points at.
    case color(ComponentColorAnswer)
    /// What one of the copy's numbers is set to.
    case number(CGFloat)
    /// The room one of the copy's groups keeps inside its edges, all four
    /// sides of it.
    ///
    /// It is a `.number` answer like any other, because the knob a person
    /// added is the Padding knob and there is one of it. Four sides rather
    /// than one number because almost no real control keeps the same room all
    /// round: a button keeps 10 above and below and 16 beside, and a knob that
    /// could only write one number would turn every roomier copy of it into a
    /// square. Typing one number over the closed field still levels all four,
    /// exactly as it does on the canvas.
    case room(GroupPadding)

    /// The kind of knob this answer fits, so an answer can never land on a
    /// knob it makes no sense for.
    public var kind: ComponentPropertyKind {
        switch self {
        case .text: return .text
        case .visible: return .visible
        case .variant: return .variant
        case .color: return .color
        case .number, .room: return .number
        }
    }

    /// This answer with anything nobody could mean taken out of it: a number
    /// below nought, or one that is not a number at all, comes back as nought
    /// rather than being stored and drawn.
    var settled: ComponentPropertyValue {
        switch self {
        case .number(let value):
            return .number(value.isFinite ? max(0, value) : 0)
        case .room(let room):
            // `used` is the same floor the canvas holds room to, so a side
            // typed down past nought settles the same way whether it was typed
            // on a copy or on the group itself.
            return .room(room.used)
        default:
            return self
        }
    }

    public var textValue: String? {
        if case .text(let string) = self { return string }
        return nil
    }

    public var boolValue: Bool? {
        if case .visible(let flag) = self { return flag }
        return nil
    }

    public var optionValue: UUID? {
        if case .variant(let id) = self { return id }
        return nil
    }

    public var colorValue: ComponentColorAnswer? {
        if case .color(let answer) = self { return answer }
        return nil
    }

    public var numberValue: CGFloat? {
        if case .number(let value) = self { return value }
        return nil
    }

    /// The four sides they keep. Nil for every answer that is not room.
    public var roomValue: GroupPadding? {
        if case .room(let room) = self { return room }
        return nil
    }

    /// This answer as room, whatever shape it was stored in. An answer written
    /// before room carried four sides is one number, and one number means the
    /// same room all round, so it opens as that rather than as nothing.
    var asRoom: GroupPadding? {
        switch self {
        case .room(let room): return room
        case .number(let value): return GroupPadding(value)
        default: return nil
        }
    }

    private enum CodingKeys: String, CodingKey {
        case kind, text, visible, variant, color, number, room
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(kind, forKey: .kind)
        switch self {
        case .text(let string): try c.encode(string, forKey: .text)
        case .visible(let flag): try c.encode(flag, forKey: .visible)
        case .variant(let id): try c.encode(id, forKey: .variant)
        case .color(let answer): try c.encode(answer, forKey: .color)
        case .number(let value): try c.encode(value, forKey: .number)
        case .room(let room): try c.encode(room, forKey: .room)
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(ComponentPropertyKind.self, forKey: .kind) {
        case .text: self = .text(try c.decode(String.self, forKey: .text))
        case .visible: self = .visible(try c.decode(Bool.self, forKey: .visible))
        case .variant: self = .variant(try c.decode(UUID.self, forKey: .variant))
        case .color: self = .color(try c.decode(ComponentColorAnswer.self, forKey: .color))
        case .number:
            // Room and a plain number are both `.number` knobs, told apart by
            // which of the two payloads is on the file. A document written
            // before room carried four sides holds the number and opens as it
            // always did.
            if let room = try c.decodeIfPresent(GroupPadding.self, forKey: .room) {
                self = .room(room)
            } else {
                self = .number(try c.decode(CGFloat.self, forKey: .number))
            }
        }
    }
}

/// One answer, stored on the copy that gave it.
public struct ComponentOverride: Hashable, Codable, Sendable {
    public var property: UUID
    public var value: ComponentPropertyValue

    public init(property: UUID, value: ComponentPropertyValue) {
        self.property = property
        self.value = value
    }
}

/// A layer inside an original and the knobs it could become, which is what the
/// Add Property menu lists.
public struct ComponentPropertyCandidate: Hashable, Sendable {
    public var layerID: UUID
    public var name: String
    /// The names from just inside the original down to this layer, so a menu
    /// row can say "Control ▸ Toggle" and two layers called the same thing in
    /// different groups are tellable apart.
    public var path: [String]
    /// Only the kinds that mean something for this layer, and only the ones it
    /// is not already exposed as.
    public var kinds: [ComponentPropertyKind]
    /// The colours this layer could still offer, in the order the inspector
    /// lists them. `.color` appears in `kinds` exactly while this is not empty,
    /// because "already exposed" is about ONE colour and not about the layer:
    /// exposing a box's fill leaves its outline on offer.
    public var colorSlots: [ColorSlot]
    /// The numbers this layer could still offer, in the order the inspector
    /// lists them. `.number` appears in `kinds` exactly while this is not empty,
    /// for the same reason a colour does: "already exposed" is about ONE number
    /// and not about the layer, so exposing a box's rounding leaves its
    /// thickness on offer.
    public var numberSlots: [ComponentNumberSlot]
    /// What an unnamed text layer says, so a menu of rows all reading "Text" is
    /// still a menu you can choose from. Nil for anything the author named,
    /// where the name already says which layer this is.
    public var words: String?

    public init(layerID: UUID, name: String, path: [String], kinds: [ComponentPropertyKind],
                colorSlots: [ColorSlot] = [], numberSlots: [ComponentNumberSlot] = [],
                words: String? = nil) {
        self.layerID = layerID
        self.name = name
        self.path = path
        self.kinds = kinds
        self.colorSlots = colorSlots
        self.numberSlots = numberSlots
        self.words = words
    }

    /// How deep inside the original it sits.
    public var depth: Int { max(0, path.count - 1) }

    /// The whole path in one line, for a menu row.
    public var pathLabel: String { path.joined(separator: " ▸ ") }

    /// What the Add menu row reads. An unnamed text layer carries its words
    /// here so two of them can be told apart, which is the one job the words
    /// do well: read once while choosing, never kept as the knob's name.
    public var menuLabel: String {
        guard let words else { return pathLabel }
        return "\(pathLabel) \u{201C}\(words)\u{201D}"
    }
}

// MARK: - Reading a layer's knobs

extension Layer {

    /// The knobs this layer exposes, empty for everything that is not an
    /// original.
    public var componentProperties: [ComponentProperty] { group?.properties ?? [] }

    /// The answers this layer gives, empty for everything that is not a copy.
    public var componentOverrides: [ComponentOverride] { group?.overrides ?? [] }

    /// Whether this layer's wording could be a knob.
    var hasWording: Bool {
        if case .text = content { return true }
        return false
    }

    /// Whether this layer could be a choice: a group holding two or more
    /// alternatives, and not one whose contents belong to somebody else.
    var canBeVariant: Bool {
        guard let group, !isComponentInstance, group.children.count > 1 else { return false }
        return true
    }

    /// The colours of this layer that could become knobs: the slots it has AND
    /// has something in.
    ///
    /// A fill that has been switched off is not a colour anybody can expose,
    /// because there is nothing there for a copy to follow. The row is still
    /// the way back to a fill on the layer itself; it is only as a KNOB that an
    /// absent colour means nothing.
    var knobColorSlots: [ColorSlot] {
        colorSlots.filter { paint(for: $0) != nil }
    }
}

// MARK: - Choosing what is adjustable

extension PhotonzDocument {

    /// How far inside an original the Add Property menu looks. A knob reaching
    /// six levels down is a knob nobody can name.
    static let componentPropertyDepthLimit = 6

    /// The knobs an original exposes. With `version` named, the knobs THAT
    /// version exposes: each version of a component is a drawing of its own, so
    /// each carries its own knobs, pointed at its own layers. A duplicate keeps
    /// the knob ids of the version it came from, which is what lets a copy keep
    /// its answers when it is switched between them (`ComponentVersions`).
    public func componentProperties(of componentID: UUID,
                                    version: UUID? = nil) -> [ComponentProperty] {
        mainComponent(componentID: componentID, version: version)?.componentProperties ?? []
    }

    /// Every knob id any version of this component exposes, which is what "a
    /// knob this copy could be answering" means once versions exist.
    func componentPropertyIDs(across componentID: UUID) -> Set<UUID> {
        var ids: Set<UUID> = []
        for version in componentVersions(of: componentID) {
            guard let main = layer(id: version.layerID) else { continue }
            ids.formUnion(main.componentProperties.map(\.id))
        }
        return ids
    }

    /// One knob by id.
    public func componentProperty(componentID: UUID, version: UUID? = nil,
                                  propertyID: UUID) -> ComponentProperty? {
        componentProperties(of: componentID, version: version).first { $0.id == propertyID }
    }

    /// Every layer inside the original that could become a knob, and which
    /// kinds it could become.
    ///
    /// Only the kinds that MEAN something are offered: wording belongs to a
    /// text layer, a choice needs a group with alternatives in it, and a layer
    /// already exposed one way is not offered that way twice. A component of
    /// eight layers would otherwise open a menu of twenty-four rows, most of
    /// which do nothing anybody wants.
    ///
    /// A copy nested inside the original is skipped whole: its contents are not
    /// the original's to expose, so a knob reaching into one would be rewritten
    /// away by the next sync.
    ///
    /// The original ITSELF comes first, offering the two numbers it holds its
    /// contents with and nothing else (`ComponentNumberSlot.onTheComponentItself`).
    /// It is first because it is the outermost thing, and a menu that listed
    /// the pieces of a card and then the card would read inside out.
    public func componentPropertyCandidates(componentID: UUID,
                                            version: UUID? = nil) -> [ComponentPropertyCandidate] {
        guard let main = mainComponent(componentID: componentID, version: version) else { return [] }
        let taken = Set(main.componentProperties.map { PropertyKey($0) })
        var found: [ComponentPropertyCandidate] = []

        let ownNumbers = ComponentNumberSlot.onTheComponentItself.filter {
            main.knobValue(for: $0) != nil
                && !taken.contains(PropertyKey(target: main.id, kind: .number, numberSlot: $0))
        }
        if !ownNumbers.isEmpty {
            found.append(ComponentPropertyCandidate(layerID: main.id, name: main.name,
                                                    path: [main.name], kinds: [.number],
                                                    numberSlots: ownNumbers))
        }

        func walk(_ layers: [Layer], path: [String]) {
            guard path.count <= Self.componentPropertyDepthLimit else { return }
            for layer in layers {
                var kinds: [ComponentPropertyKind] = []
                if layer.hasWording { kinds.append(.text) }
                kinds.append(.visible)
                if layer.canBeVariant { kinds.append(.variant) }
                kinds.removeAll { taken.contains(PropertyKey(target: layer.id, kind: $0)) }
                // Colours are counted one at a time: a box whose fill is
                // already a knob still has an outline to offer.
                let slots = layer.knobColorSlots.filter {
                    !taken.contains(PropertyKey(target: layer.id, kind: .color, slot: $0))
                }
                if !slots.isEmpty { kinds.append(.color) }
                // Numbers are counted one at a time for the same reason: a box
                // whose rounding is already a knob still has a thickness to
                // offer.
                let numbers = layer.knobNumberSlots.filter {
                    !taken.contains(PropertyKey(target: layer.id, kind: .number, numberSlot: $0))
                }
                if !numbers.isEmpty { kinds.append(.number) }
                let here = path + [layer.name]
                if !kinds.isEmpty {
                    found.append(ComponentPropertyCandidate(layerID: layer.id, name: layer.name,
                                                            path: here, kinds: kinds,
                                                            colorSlots: slots, numberSlots: numbers,
                                                            words: Self.menuWords(of: layer)))
                }
                // A copy's insides belong to ITS original, so there is nothing
                // here to expose.
                if layer.isOpenableGroup { walk(layer.children, path: here) }
            }
        }
        walk(main.children, path: [])
        return found
    }

    /// The words a menu row shows beside an unnamed text layer, shortened so a
    /// paragraph does not become a menu row nobody can read. A layer the author
    /// named needs none: the name is the better hint.
    static func menuWords(of layer: Layer) -> String? {
        guard ComponentNaming.isPlaceholderLayerName(layer.name),
              case .text(let content) = layer.content,
              let words = ComponentNaming.normalized(content.string) else { return nil }
        return words.count > 24 ? String(words.prefix(24)) + "\u{2026}" : words
    }

    /// Whether a layer inside the original could take this kind of knob, which
    /// is the check `addComponentProperty` makes and the menu asks first.
    public func canAddComponentProperty(componentID: UUID, version: UUID? = nil, target: UUID,
                                        kind: ComponentPropertyKind,
                                        slot: ColorSlot? = nil,
                                        numberSlot: ComponentNumberSlot? = nil) -> Bool {
        guard let candidate = componentPropertyCandidates(componentID: componentID, version: version)
            .first(where: { $0.layerID == target }) else { return false }
        switch kind {
        case .color:
            // "The colour" of a box that has two is not a thing, so a colour
            // knob with no part named is refused rather than guessed at.
            guard let slot, numberSlot == nil else { return false }
            return candidate.colorSlots.contains(slot)
        case .number:
            // Nor is "the number" of a box that has a rounding and a thickness.
            guard let numberSlot, slot == nil else { return false }
            return candidate.numberSlots.contains(numberSlot)
        case .text, .visible, .variant:
            return slot == nil && numberSlot == nil && candidate.kinds.contains(kind)
        }
    }

    /// Exposes a layer inside an original as a knob, and returns the knob's id.
    ///
    /// A knob starts named after the layer it exposes, because that is the
    /// thing the author was looking at when they made it; a second knob on the
    /// same layer takes a numbered name so a copy's panel never shows two rows
    /// nobody can tell apart.
    ///
    /// Exposing a CHOICE also settles the original on one option: a group whose
    /// alternatives are all drawn at once is not a choice, and picking an
    /// option on a copy would stack a second shape on the first rather than
    /// swapping it.
    @discardableResult
    public mutating func addComponentProperty(componentID: UUID, version: UUID? = nil,
                                              target: UUID,
                                              kind: ComponentPropertyKind,
                                              slot: ColorSlot? = nil,
                                              numberSlot: ComponentNumberSlot? = nil,
                                              name: String? = nil) -> UUID? {
        guard canAddComponentProperty(componentID: componentID, version: version, target: target,
                                      kind: kind, slot: slot, numberSlot: numberSlot),
              let main = mainComponent(componentID: componentID, version: version),
              let targetLayer = layer(id: target) else { return nil }
        let chosen = ComponentNaming.normalized(name)
            ?? freshPropertyName(base: Self.defaultPropertyName(for: targetLayer, kind: kind,
                                                                slot: slot, numberSlot: numberSlot),
                                 taken: main.componentProperties.map(\.name))
        let property = ComponentProperty(name: chosen, kind: kind, target: target, slot: slot,
                                         numberSlot: numberSlot)
        if kind == .variant { settleVariant(target: target) }
        updateLayer(id: main.id) { layer in
            guard var group = layer.group else { return }
            group.properties.append(property)
            layer.content = .group(group)
        }
        return property.id
    }

    /// Stops exposing a knob. Every copy's answer to it goes with it: a value
    /// keyed to a knob that no longer exists is a value nothing will ever read.
    public mutating func removeComponentProperty(componentID: UUID, version: UUID? = nil,
                                                 propertyID: UUID) {
        guard let main = mainComponent(componentID: componentID, version: version) else { return }
        updateLayer(id: main.id) { layer in
            guard var group = layer.group else { return }
            group.properties.removeAll { $0.id == propertyID }
            layer.content = .group(group)
        }
        // A knob another version still exposes is one a copy showing that
        // version can still be answering, so the answers only go when no
        // version has the knob left.
        guard !componentPropertyIDs(across: componentID).contains(propertyID) else { return }
        forgetOverrides(of: componentID, propertyIDs: [propertyID])
    }

    /// Renames a knob. A blank name is refused rather than leaving a nameless
    /// row on every copy's panel.
    public mutating func renameComponentProperty(componentID: UUID, version: UUID? = nil,
                                                 propertyID: UUID, to name: String) {
        guard let main = mainComponent(componentID: componentID, version: version),
              let chosen = ComponentNaming.normalized(name) else { return }
        updateLayer(id: main.id) { layer in
            guard var group = layer.group,
                  let index = group.properties.firstIndex(where: { $0.id == propertyID }) else { return }
            group.properties[index].name = chosen
            layer.content = .group(group)
        }
    }

    /// The shapes a choice can land on: the children of the group it exposes,
    /// in the order they are stacked. This list IS the no-drift rule, because
    /// nothing outside it is an answer the model will take.
    public func componentVariantOptions(componentID: UUID, version: UUID? = nil,
                                        propertyID: UUID) -> [Layer] {
        guard let property = componentProperty(componentID: componentID, version: version,
                                               propertyID: propertyID),
              property.kind == .variant,
              let target = layer(id: property.target) else { return [] }
        return target.children
    }

    /// The shapes a choice offers, each with a label a person can tell apart.
    ///
    /// Two rectangles drawn one after the other are both called "Rectangle", so
    /// a menu of their names is a menu of identical rows. Repeats are numbered
    /// for DISPLAY only: nothing renames a layer behind anybody's back, and
    /// naming the layers properly makes the numbers go away.
    public func componentVariantOptionLabels(componentID: UUID, version: UUID? = nil,
                                             propertyID: UUID) -> [(id: UUID, label: String)] {
        let options = componentVariantOptions(componentID: componentID, version: version,
                                              propertyID: propertyID)
        let labels = ComponentNaming.distinctLabels(options.map(\.name))
        return zip(options, labels).map { (id: $0.id, label: $1) }
    }

    /// What the original itself says for a knob: the value a copy shows until
    /// somebody sets that knob on it.
    public func componentDefaultValue(componentID: UUID, version: UUID? = nil,
                                      propertyID: UUID) -> ComponentPropertyValue? {
        guard let property = componentProperty(componentID: componentID, version: version,
                                               propertyID: propertyID),
              let target = layer(id: property.target) else { return nil }
        return Self.value(of: property.kind, slot: property.slot,
                          numberSlot: property.numberSlot, on: target)
    }

    /// One layer's own answer to a kind of knob.
    static func value(of kind: ComponentPropertyKind, slot: ColorSlot? = nil,
                      numberSlot: ComponentNumberSlot? = nil,
                      on layer: Layer) -> ComponentPropertyValue? {
        switch kind {
        case .text:
            guard case .text(let content) = layer.content else { return nil }
            return .text(content.string)
        case .visible:
            return .visible(layer.isVisible)
        case .variant:
            guard let shown = layer.children.first(where: \.isVisible) ?? layer.children.first
            else { return nil }
            return .variant(shown.id)
        case .color:
            // A colour that has been switched off since the knob was made
            // leaves the knob with nothing to read. It stays on the list rather
            // than being dropped, because dropping it would throw away every
            // copy's answer over a checkbox somebody may be about to tick back.
            guard let slot, let paint = layer.paint(for: slot) else { return nil }
            return .color(ComponentColorAnswer(paint: paint,
                                               styleID: layer.colorStyleID(for: slot)))
        case .number:
            // A number the layer has stopped having — a stack turned back into
            // a group that arranges nothing — leaves the knob with nothing to
            // read, and the knob stays on the list for the same reason a
            // switched-off colour does.
            guard let numberSlot else { return nil }
            return layer.knobValue(for: numberSlot)
        }
    }

    /// What a knob is called before anybody renames it: the name of the layer
    /// it exposes, because that is the thing the author was looking at.
    ///
    /// Every text layer in the app is called "Text" and every group the Group
    /// command makes is called "Group", so a knob named after one of those says
    /// nothing on a copy's panel. Those fall back to what the knob DOES
    /// ("Wording", "Show", "Shape").
    ///
    /// A knob is named for what it CONTROLS and never for what its layer
    /// happens to say. A wording knob that took the words would be called
    /// "Save", and the first copy to answer "Cancel" leaves a panel reading
    /// Save above Cancel, which looks like a bug in the app. The words still
    /// appear while the author is choosing the layer, on the Add menu row.
    ///
    /// Every one of these is a starting point. The name is a field on the
    /// original's list, so anything better is one rename away.
    /// A COLOUR knob is the exception, and always takes the part it paints:
    /// "Fill", "Outline", "Text", "Border". One box has two colours, so a knob
    /// named after the box says nothing about which of them it turns, and the
    /// rest of the app already names colours this way.
    static func defaultPropertyName(for layer: Layer, kind: ComponentPropertyKind,
                                    slot: ColorSlot? = nil,
                                    numberSlot: ComponentNumberSlot? = nil) -> String {
        if kind == .color { return slot?.selectionTitle ?? kind.defaultName }
        // A number knob is named the same way and for the same reason: one box
        // has a rounding and a thickness, so a knob named after the box says
        // nothing about which of them it turns.
        if kind == .number { return numberSlot?.title ?? kind.defaultName }
        if ComponentNaming.isPlaceholderLayerName(layer.name) { return kind.defaultName }
        return layer.name
    }

    /// A knob name nobody is using yet: "Label", then "Label 2", "Label 3"…
    func freshPropertyName(base: String, taken: [String]) -> String {
        let root = ComponentNaming.normalized(base) ?? "Property"
        guard taken.contains(root) else { return root }
        var index = 2
        while taken.contains("\(root) \(index)") { index += 1 }
        return "\(root) \(index)"
    }

    /// Leaves exactly one of a group's children showing, so a choice is a
    /// choice. The one already showing wins; with none showing, the first does.
    private mutating func settleVariant(target: UUID) {
        guard let group = layer(id: target), !group.children.isEmpty else { return }
        let shown = (group.children.first(where: \.isVisible) ?? group.children[0]).id
        updateLayer(id: target) { layer in
            guard var content = layer.group else { return }
            for index in content.children.indices {
                content.children[index].isVisible = content.children[index].id == shown
            }
            layer.content = .group(content)
        }
    }

    /// A layer plus a kind, which is what "already exposed that way" means.
    private struct PropertyKey: Hashable {
        var target: UUID
        var kind: ComponentPropertyKind
        /// Which colour, on a colour knob, so "already exposed that way" means
        /// one colour rather than the whole layer.
        var slot: ColorSlot?
        /// Which number, on a number knob, for the same reason.
        var numberSlot: ComponentNumberSlot?
        init(target: UUID, kind: ComponentPropertyKind, slot: ColorSlot? = nil,
             numberSlot: ComponentNumberSlot? = nil) {
            self.target = target
            self.kind = kind
            self.slot = slot
            self.numberSlot = numberSlot
        }
        init(_ property: ComponentProperty) {
            self.init(target: property.target, kind: property.kind, slot: property.slot,
                      numberSlot: property.numberSlot)
        }
    }
}

// MARK: - Setting a knob on one copy

extension PhotonzDocument {

    /// The knobs a copy can set: the ones its original exposes, in the order
    /// the original lists them.
    public func instanceProperties(instance: UUID) -> [ComponentProperty] {
        guard let componentID = layer(id: instance)?.instanceOf else { return [] }
        return componentProperties(of: componentID, version: instanceVersion(of: instance))
    }

    /// Which knobs this copy has answered for itself, as opposed to following
    /// the original. This is what puts the revert control on a row.
    public func instanceOverrides(instance: UUID) -> Set<UUID> {
        Set((layer(id: instance)?.componentOverrides ?? []).map(\.property))
    }

    /// What a copy shows for a knob: its own answer, or the original's.
    public func instanceValue(instance: UUID, property propertyID: UUID) -> ComponentPropertyValue? {
        guard let copy = layer(id: instance), let componentID = copy.instanceOf else { return nil }
        if let own = copy.componentOverrides.first(where: { $0.property == propertyID }) {
            // An answer stored before room carried four sides is one number,
            // and one number has always meant the same room all round, so it
            // is read as that rather than as an answer of the wrong shape.
            if let slot = componentProperty(componentID: componentID,
                                            version: instanceVersion(of: instance),
                                            propertyID: propertyID)?.numberSlot,
               slot.isFourSided, let room = own.value.asRoom {
                return .room(room)
            }
            return own.value
        }
        return componentDefaultValue(componentID: componentID,
                                     version: instanceVersion(of: instance),
                                     propertyID: propertyID)
    }

    /// Whether an answer is one this knob will take. A choice may only land on
    /// a shape the original holds, and an answer of the wrong kind has nowhere
    /// to go at all.
    public func canSetInstanceOverride(instance: UUID, property propertyID: UUID,
                                       value: ComponentPropertyValue) -> Bool {
        guard let copy = layer(id: instance), let componentID = copy.instanceOf, !copy.isLocked
        else { return false }
        let version = instanceVersion(of: instance)
        guard let property = componentProperty(componentID: componentID, version: version,
                                               propertyID: propertyID),
              property.kind == value.kind else { return false }
        if case .color(let answer) = value {
            // A colour the original does not have is nothing to override: the
            // knob's own slot is empty, so painting here would give the copy a
            // fill the original never defined.
            guard componentDefaultValue(componentID: componentID, version: version,
                                        propertyID: propertyID) != nil
            else { return false }
            // ...and a name this document has never heard of is a claim nothing
            // can honour, so it is refused rather than stored.
            guard let styleID = answer.styleID else { return true }
            return colorStyle(id: styleID) != nil
        }
        if value.kind == .number {
            // Four sides may only land on a knob that has four sides to put
            // them in: a gap handed a room has nowhere to write three of the
            // numbers, so the answer is refused rather than half stored.
            guard property.numberSlot?.isFourSided == true || value.roomValue == nil
            else { return false }
            // A number the original no longer has is nothing to override: the
            // knob's own slot reads nothing, so setting it here would give the
            // copy a gap its original does not define.
            return componentDefaultValue(componentID: componentID, version: version,
                                         propertyID: propertyID) != nil
        }
        guard case .variant(let option) = value else { return true }
        return componentVariantOptions(componentID: componentID, version: version,
                                       propertyID: propertyID)
            .contains { $0.id == option }
    }

    /// Sets one knob on one copy. Nothing else about the copy changes, and the
    /// link to the original is untouched: this is the whole point of the step.
    @discardableResult
    public mutating func setInstanceOverride(instance: UUID, property propertyID: UUID,
                                             value: ComponentPropertyValue) -> Bool {
        // A number nobody could mean is settled before it is stored rather than
        // refused: typing over a field passes through a minus sign on the way
        // to a number, and a row that simply refused would be a row that
        // silently did nothing.
        let value = value.settled
        guard canSetInstanceOverride(instance: instance, property: propertyID, value: value)
        else { return false }
        updateLayer(id: instance) { layer in
            guard var group = layer.group else { return }
            if let index = group.overrides.firstIndex(where: { $0.property == propertyID }) {
                group.overrides[index].value = value
            } else {
                group.overrides.append(ComponentOverride(property: propertyID, value: value))
            }
            layer.content = .group(group)
        }
        return true
    }

    /// Puts one knob back to following the original.
    public mutating func clearInstanceOverride(instance: UUID, property propertyID: UUID) {
        updateLayer(id: instance) { layer in
            guard var group = layer.group, group.overrides.contains(where: { $0.property == propertyID })
            else { return }
            group.overrides.removeAll { $0.property == propertyID }
            layer.content = .group(group)
        }
    }

    /// Drops copies' answers to knobs that no longer exist, everywhere in the
    /// tree.
    mutating func forgetOverrides(of componentID: UUID, propertyIDs: Set<UUID>) {
        guard !propertyIDs.isEmpty else { return }
        func strip(_ list: [Layer]) -> [Layer] {
            list.map { layer in
                var copy = layer
                if var group = copy.group {
                    if layer.instanceOf == componentID {
                        group.overrides.removeAll { propertyIDs.contains($0.property) }
                    }
                    group.children = strip(group.children)
                    copy.content = .group(group)
                }
                return copy
            }
        }
        layers = strip(layers)
    }
}

// MARK: - Applying the answers

extension PhotonzDocument {

    /// Puts one copy's answers onto the contents it has just been refilled
    /// with. Runs after the refill rather than instead of it, which is exactly
    /// why an edit to the original still reaches a copy that has overridden
    /// something else: the copy takes the original's picture whole, and then
    /// the few facts it owns are written over the top.
    func applyOverrides(_ overrides: [ComponentOverride], of componentID: UUID,
                        version: UUID? = nil,
                        to children: inout [Layer], instance: UUID,
                        contents: LayerPlacement? = nil) {
        // A knob naming the original's own outermost layer has nothing to write
        // on any of these: what it turns lives in the copy's own layout, put on
        // by `applyRootOverrides` where that layout is built.
        let root = mainComponent(componentID: componentID, version: version)?.id
        let properties = componentProperties(of: componentID, version: version)
            .filter { $0.target != root }
        guard !properties.isEmpty, !overrides.isEmpty else { return }
        let answers = Dictionary(overrides.map { ($0.property, $0.value) },
                                 uniquingKeysWith: { _, last in last })
        for property in properties {
            guard var value = answers[property.id], value.kind == property.kind else { continue }
            if case .color(let answer) = value {
                // A colour that has gone from the original since the knob was
                // made has nothing for the copy to override.
                guard let slot = property.slot,
                      layer(id: property.target)?.paint(for: slot) != nil else { continue }
                // What a saved colour paints TODAY, so a copy pointing at one
                // follows every edit to it without storing the colour twice.
                value = .color(resolvedColorAnswer(answer, slot: slot))
            }
            if property.kind == .number {
                // A number the original has stopped having — a stack turned
                // back into a plain group — has nothing for the copy to
                // override. The answer is kept, so turning the stack back on
                // brings it straight back.
                guard let numberSlot = property.numberSlot,
                      layer(id: property.target)?.knobValue(for: numberSlot) != nil
                else { continue }
            }
            let derived = ComponentIdentity.derived(instance: instance, source: property.target)
            Self.mutate(id: derived, in: &children, contents: contents) { layer, holder in
                Self.apply(value, to: &layer, instance: instance, slot: property.slot,
                           numberSlot: property.numberSlot, contents: holder)
            }
        }
    }

    /// Puts one copy's answers to the knobs that name the original ITSELF onto
    /// the layout that copy works to.
    ///
    /// The room a card keeps inside its own edges, and how far apart it holds
    /// what it holds, are facts about the card and not about any one piece in
    /// it, so they live in the copy's own layout rather than in its contents.
    /// It runs where that layout is built, and AFTER the size the copy owns is
    /// written into it, for the same reason `applyOverrides` runs after the
    /// refill: the original's answer first, the copy's own over the top. The
    /// two never fight, because they are different fields of one layout.
    func applyRootOverrides(_ overrides: [ComponentOverride], of componentID: UUID,
                            version: UUID? = nil, to layout: inout GroupLayout?) {
        guard !overrides.isEmpty, layout != nil,
              let main = mainComponent(componentID: componentID, version: version) else { return }
        let properties = componentProperties(of: componentID, version: version)
            .filter { $0.target == main.id && $0.kind == .number }
        guard !properties.isEmpty else { return }
        let answers = Dictionary(overrides.map { ($0.property, $0.value) },
                                 uniquingKeysWith: { _, last in last })
        for property in properties {
            // A number the original has stopped having — a stack turned back
            // into a plain group — has nothing for the copy to override. The
            // answer is kept, so turning the stack back on brings it straight
            // back.
            guard let slot = property.numberSlot, main.knobValue(for: slot) != nil,
                  let value = answers[property.id], value.kind == .number else { continue }
            layout?.setKnobValue(value, for: slot)
        }
    }

    /// What a colour answer actually paints: the saved colour it points at
    /// while that colour is still on the shelf, and the colour it is wearing
    /// once that name is gone.
    func resolvedColorAnswer(_ answer: ComponentColorAnswer,
                             slot: ColorSlot) -> ComponentColorAnswer {
        guard let styleID = answer.styleID, let style = colorStyle(id: styleID) else {
            return ComponentColorAnswer(paint: answer.paint)
        }
        return ComponentColorAnswer(paint: style.paint(for: slot), styleID: styleID)
    }

    /// One answer written onto one layer inside a copy. `contents` is how the
    /// group around this layer lines its contents up, which is what decides
    /// which edge a label grows from when its wording gets longer.
    private static func apply(_ value: ComponentPropertyValue, to layer: inout Layer,
                              instance: UUID, slot: ColorSlot?,
                              numberSlot: ComponentNumberSlot?, contents: LayerPlacement?) {
        switch value {
        case .text(let string):
            guard case .text(var content) = layer.content else { return }
            // A copy told to say something longer says all of it: the box
            // re-measures around the new words. A label that hugged its words
            // keeps hugging (one line, wider, growing from whichever edge its
            // group lines contents up on); a box somebody had already narrowed
            // is a paragraph and keeps that wrap width, growing downward.
            let hugging = layer.textHugsItsWords
            content.string = string
            layer.content = .text(content)
            layer = layer.textRefitted(
                hugging: hugging,
                anchor: LayerPlacement.resolving(child: layer.placement,
                                                 container: contents).horizontal)
        case .visible(let flag):
            layer.isVisible = flag
        case .variant(let option):
            // The answer names a child of the ORIGINAL; inside a copy that
            // child wears a derived id, so the same derivation finds it.
            guard var group = layer.group else { return }
            let wanted = ComponentIdentity.derived(instance: instance, source: option)
            // A choice made against one version names a shape THAT version
            // holds. Another version has its own shapes, so the answer matches
            // nothing there, and hiding every child would leave a hole on the
            // canvas. The version's own picture stands instead, and the answer
            // is kept: switching back brings it straight back.
            guard group.children.contains(where: { $0.id == wanted }) else { return }
            for index in group.children.indices {
                group.children[index].isVisible = group.children[index].id == wanted
            }
            layer.content = .group(group)
        case .color(let answer):
            guard let slot else { return }
            layer.setPaint(answer.paint, for: slot)
            // The binding travels with the colour, so a copy wearing a saved
            // name looks exactly like a layer wearing it: the Library counts
            // it as a use, and the next edit to that name reaches it.
            if let styleID = answer.styleID {
                layer.bindColorStyle(styleID, for: slot)
            } else {
                layer.unbindColorStyle(for: slot)
            }
        case .number, .room:
            guard let numberSlot else { return }
            layer.setKnobValue(value, for: numberSlot)
        }
    }

    /// Reaches a layer by id anywhere in a list of subtrees. The copy being
    /// built is not in the document yet, so the document's own helpers cannot
    /// be used.
    ///
    /// `contents` is how the group holding this list lines its contents up; it
    /// travels down with the walk so the change knows what the layer it lands
    /// on is following.
    @discardableResult
    private static func mutate(id: UUID, in layers: inout [Layer],
                               contents: LayerPlacement?,
                               _ change: (inout Layer, LayerPlacement?) -> Void) -> Bool {
        for index in layers.indices {
            if layers[index].id == id {
                change(&layers[index], contents)
                return true
            }
            if var group = layers[index].group {
                if mutate(id: id, in: &group.children, contents: group.contentPlacement, change) {
                    layers[index].content = .group(group)
                    return true
                }
            }
        }
        return false
    }

    /// Drops knobs whose layer is gone from the original, and the answers that
    /// went with them. Called from the sync that runs after every edit, so
    /// deleting a piece out of an original leaves nothing dangling.
    mutating func pruneComponentProperties() {
        var dropped: [UUID: Set<UUID>] = [:]
        for main in mainComponents {
            let properties = main.componentProperties
            guard !properties.isEmpty, let componentID = main.componentID else { continue }
            let inside = Set(main.selfAndDescendants.map(\.id))
            let gone = properties.filter { !inside.contains($0.target) }
            guard !gone.isEmpty else { continue }
            dropped[componentID, default: []].formUnion(gone.map(\.id))
            updateLayer(id: main.id) { layer in
                guard var group = layer.group else { return }
                group.properties.removeAll { property in gone.contains { $0.id == property.id } }
                layer.content = .group(group)
            }
        }
        for (componentID, propertyIDs) in dropped {
            // A knob another version of the same component still exposes is a
            // knob a copy can still be answering, so only the ones no version
            // has left are forgotten.
            forgetOverrides(of: componentID,
                            propertyIDs: propertyIDs.subtracting(componentPropertyIDs(across: componentID)))
        }
        // An answer to a knob the original no longer exposes is dead weight
        // too, whichever way the knob went.
        pruneStaleOverrides()
    }

    /// Drops any answer keyed to a knob its original does not expose.
    private mutating func pruneStaleOverrides() {
        var known: [UUID: Set<UUID>] = [:]
        func live(_ componentID: UUID) -> Set<UUID> {
            if let cached = known[componentID] { return cached }
            let ids = componentPropertyIDs(across: componentID)
            known[componentID] = ids
            return ids
        }
        func strip(_ list: [Layer]) -> [Layer] {
            list.map { layer in
                var copy = layer
                guard var group = copy.group else { return copy }
                if let componentID = layer.instanceOf, !group.overrides.isEmpty {
                    // A copy whose original is gone keeps its picture and lets
                    // go of its answers along with the link.
                    let allowed = mainComponent(componentID: componentID) == nil ? [] : live(componentID)
                    group.overrides.removeAll { !allowed.contains($0.property) }
                }
                group.children = strip(group.children)
                copy.content = .group(group)
                return copy
            }
        }
        layers = strip(layers)
    }
}

// MARK: - Detach

extension PhotonzDocument {

    /// Whether Layer ▸ Detach Instance would do anything: exactly one unlocked
    /// copy is selected.
    public func canDetachInstance(ids: Set<UUID>) -> Bool {
        !detachableInstances(ids: ids).isEmpty
    }

    /// The picked layers Detach would actually reach: the copies among them
    /// that are not locked. Anything else picked alongside is left alone, the
    /// same way every other whole-selection command leaves out what it cannot
    /// honestly touch.
    public func detachableInstances(ids: Set<UUID>) -> Set<UUID> {
        ids.filter { layer(id: $0)?.isComponentInstance == true && layer(id: $0)?.isLocked == false }
    }

    /// Layer ▸ Detach Instance (⌥⌘B): turns a copy into ordinary layers.
    ///
    /// It keeps exactly the picture it was drawing, answers and all, and stops
    /// following the original. There is no way back other than undo, which is
    /// why the command says what it does in plain words before it runs.
    /// The same over a whole selection, in one step: every picked copy stops
    /// following. Returns how many did, so the word on screen can say it.
    @discardableResult
    public mutating func detachInstances(ids: [UUID]) -> Int {
        var count = 0
        for id in ids where detachInstance(id: id) { count += 1 }
        return count
    }

    @discardableResult
    public mutating func detachInstance(id: UUID) -> Bool {
        guard canDetachInstance(ids: [id]) else { return false }
        updateLayer(id: id) { layer in
            guard var group = layer.group else { return }
            group.instanceOf = nil
            group.overrides = []
            // A size of its own is a fact about following an original, and it
            // has already been written into the layout the copy is wearing, so
            // letting go of the record changes nothing on screen.
            group.instanceSize = nil
            layer.content = .group(group)
        }
        return true
    }
}
