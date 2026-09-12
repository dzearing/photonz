import CoreGraphics
import Foundation

/// Text treatments saved under a name, that pieces of text point at
/// (`docs/design/ui-building.md`, step D8).
///
/// The colour half of this idea is `ColorStyles.swift`, and this is the other
/// half the spec asks for: a **style** is a named paint OR a named text
/// treatment. A piece of text either carries its own font, size, weight and
/// colour, the way it always has, or points at a style; editing the style
/// re-sets every piece of text pointing at it, in one step.
///
/// The treatment is kept ON the layer as well as in the style, for exactly the
/// reason a colour is: nothing downstream — the renderer, export, thumbnails,
/// the package writer — has to learn what a text style is, because text wearing
/// one draws exactly like text somebody set by hand. The pointer is the extra
/// fact: it says where the type came from, so an edit to the style can find its
/// way back.
///
/// Not to be confused with `TextStyles` (plural), which is the tool's own
/// current settings — what the NEXT block of text will be typed in. This file
/// is about text already on the canvas wearing a name.

// MARK: - What a piece of text is set in

/// The four things a text style keeps together: the font, how big, how heavy,
/// and what colour. Everything else about a text layer — the words, the box,
/// where they sit in it — is the layer's own and is never touched by a style.
public struct TextTreatment: Hashable, Codable, Sendable {
    public var fontName: String
    public var fontSize: CGFloat
    public var weight: TextWeight
    public var colorHex: String

    public init(fontName: String, fontSize: CGFloat, weight: TextWeight, colorHex: String) {
        self.fontName = fontName
        self.fontSize = fontSize
        self.weight = weight
        self.colorHex = colorHex
    }

    public init(_ content: TextContent) {
        self.init(fontName: content.fontName, fontSize: content.fontSize,
                  weight: content.weight, colorHex: content.colorHex)
    }
}

/// A text treatment saved under a name. `id` is what layers point at, so
/// renaming one never loosens anything.
public struct TextStyle: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var name: String
    public var treatment: TextTreatment

    public init(id: UUID = UUID(), name: String, treatment: TextTreatment) {
        self.id = id
        self.name = name
        self.treatment = treatment
    }
}

extension TextContent {

    /// Sets these words in a treatment: the type changes, the words themselves
    /// and where they sit in their box do not.
    public mutating func setTreatment(_ treatment: TextTreatment) {
        fontName = treatment.fontName
        fontSize = treatment.fontSize
        weight = treatment.weight
        colorHex = treatment.colorHex
    }
}

// MARK: - The text on a layer

extension Layer {

    /// What this layer's text is set in, or nil when it is not text at all.
    public var textTreatment: TextTreatment? {
        guard case .text(let content) = self.content else { return nil }
        return TextTreatment(content)
    }

    /// Sets the type without touching the words, the box or where the words sit
    /// in it. Through the text builder, so re-colouring keeps the contrast halo
    /// every other way of colouring text maintains.
    mutating func setTextTreatment(_ treatment: TextTreatment) {
        guard case .text = content else { return }
        self = TextBuilder.restyled(layer: self, fontName: treatment.fontName,
                                    fontSize: treatment.fontSize, weight: treatment.weight,
                                    colorHex: treatment.colorHex)
    }
}

// MARK: - The document's text styles

extension PhotonzDocument {

    /// What a text style is called before anybody names it.
    public static let textStyleNameBase = "Text"

    /// The style behind an id.
    public func textStyle(id: UUID) -> TextStyle? {
        textStyles.first { $0.id == id }
    }

    /// A name nobody is using yet: "Text", then "Text 2", "Text 3"…
    public func freshTextStyleName(base: String = PhotonzDocument.textStyleNameBase) -> String {
        let taken = Set(textStyles.map(\.name))
        guard taken.contains(base) else { return base }
        var n = 2
        while taken.contains("\(base) \(n)") { n += 1 }
        return "\(base) \(n)"
    }

    /// Puts a treatment on the shelf under a name, and returns its id. A blank
    /// name becomes the made-up one rather than a nameless tile.
    @discardableResult
    public mutating func addTextStyle(name: String? = nil,
                                      treatment: TextTreatment) -> UUID {
        let style = TextStyle(name: ComponentNaming.normalized(name) ?? freshTextStyleName(),
                              treatment: treatment)
        textStyles.append(style)
        return style.id
    }

    /// Saves what the picked text is set in under a name, and dresses every one
    /// of those layers in it — the point of saving is to keep using it, so what
    /// you saved from is the style's first wearer.
    ///
    /// Nil when nothing picked is text, or when the picked text does not agree:
    /// there is no one treatment to keep, and a style quietly made out of
    /// whichever layer came first is a style that means nothing.
    @discardableResult
    public mutating func saveTextStyle(from layerIDs: [UUID],
                                       name: String? = nil) -> UUID? {
        guard let treatment = sharedTextTreatment(layerIDs: layerIDs) else { return nil }
        let styleID = addTextStyle(name: name, treatment: treatment)
        _ = bindTextStyle(layerIDs: layerIDs, styleID: styleID)
        return styleID
    }

    /// The one treatment every picked piece of text shares, or nil when they
    /// disagree or none of them is text.
    public func sharedTextTreatment(layerIDs: [UUID]) -> TextTreatment? {
        var shared: TextTreatment?
        for id in layerIDs {
            guard let treatment = layer(id: id)?.textTreatment else { continue }
            if let shared, shared != treatment { return nil }
            shared = treatment
        }
        return shared
    }

    /// Dresses every picked piece of text in a style. False when the style is
    /// not in this document, or nothing picked is text.
    @discardableResult
    public mutating func bindTextStyle(layerIDs: [UUID], styleID: UUID) -> Bool {
        guard let style = textStyle(id: styleID) else { return false }
        var dressed = false
        for id in layerIDs {
            guard layer(id: id)?.textTreatment != nil else { continue }
            updateLayer(id: id) { layer in
                layer.setTextTreatment(style.treatment)
                layer.textStyleID = styleID
                // A text style keeps a colour of its own, so a colour style on
                // the same text would be a second name claiming one colour. The
                // text style wins, and the colour it was wearing is now the
                // text style's.
                layer.unbindColorStyle(for: .text)
            }
            dressed = true
        }
        return dressed
    }

    /// Lets text go back to type of its own. Nothing is re-set: the layer keeps
    /// exactly what it is wearing.
    public mutating func unbindTextStyle(layerIDs: [UUID]) {
        for id in layerIDs {
            updateLayer(id: id) { $0.textStyleID = nil }
        }
    }

    /// Re-sets a style, and with it every piece of text wearing it. Returns how
    /// many followed, which is what a notice can say out loud.
    ///
    /// One mutation, so `History.perform` records the style and everything it
    /// dresses as a single undo step. The BOXES are not re-measured here —
    /// measuring words needs CoreText, which the core cannot import — so the
    /// app re-derives them in the same step (`EditorState.setTextStyle`).
    @discardableResult
    public mutating func setTextStyle(styleID: UUID, treatment: TextTreatment) -> Int {
        guard let index = textStyles.firstIndex(where: { $0.id == styleID }) else { return 0 }
        textStyles[index].treatment = treatment
        // A copy wearing this name on words inside it follows the edit too,
        // through the answer it stored rather than through the layer, because
        // the layer is rebuilt from the original after every edit.
        refreshPieceTextStyles()
        var dressed = 0
        mapTextLayers { layer in
            guard layer.textStyleID == styleID else { return }
            layer.setTextTreatment(treatment)
            dressed += 1
        }
        return dressed
    }

    /// Renames a style. A blank name is refused rather than leaving a nameless
    /// tile on the shelf.
    public mutating func renameTextStyle(id: UUID, to name: String) {
        guard let index = textStyles.firstIndex(where: { $0.id == id }),
              let chosen = ComponentNaming.normalized(name) else { return }
        textStyles[index].name = chosen
    }

    /// Takes a style off the shelf. Every piece of text wearing it keeps the
    /// type it has and simply owns it again: deleting a name must never re-set
    /// somebody's work.
    public mutating func deleteTextStyle(id: UUID) {
        guard textStyles.contains(where: { $0.id == id }) else { return }
        textStyles.removeAll { $0.id == id }
        mapTextLayers { layer in
            if layer.textStyleID == id { layer.textStyleID = nil }
        }
        // ...and a copy that set words inside it in this name keeps the type
        // as its own, for exactly the same reason.
        refreshPieceTextStyles()
    }

    /// How many pieces of text wear this style.
    public func textStyleUsageCount(id: UUID) -> Int {
        allLayers.count { $0.textStyleID == id }
    }

    /// Every layer wearing this style, so the app can select them.
    public func layersUsingTextStyle(id: UUID) -> [UUID] {
        allLayers.filter { $0.textStyleID == id }.map(\.id)
    }

    /// What the Library's Styles scope shows for text: one tile per style, with
    /// how much of the document leans on it. They sit on the same shelf as the
    /// saved colours, because to a person they are the same kind of thing.
    public var textStyleLibraryEntries: [LibraryEntry] {
        textStyles.map { style in
            LibraryEntry(id: style.id.uuidString, scope: .styles, name: style.name,
                         detail: TextStyleNaming.detail(usageCount: textStyleUsageCount(id: style.id)))
        }
    }

    /// The safety net, run after every edit (`History.perform`), and the exact
    /// counterpart of `reconcileColorStyles`.
    ///
    /// Pointing at a style is a claim: "this type came from that name". Setting
    /// the text some other way — the Font menu, a paste, a tool default — would
    /// leave the claim false, and a panel saying "Heading" over 12pt text that
    /// is nothing like Heading is worse than no styles at all. So text that has
    /// drifted from its style, or whose style is gone, quietly lets go and
    /// keeps what it is wearing. Returns how many claims broke.
    ///
    /// The looking is read-only and the writing only happens when something
    /// actually drifted, so the overwhelmingly common edit — one that broke
    /// nothing — costs one optional check per layer and no copying at all.
    @discardableResult
    public mutating func reconcileTextStyles() -> Int {
        let styles = Dictionary(textStyles.map { ($0.id, $0.treatment) },
                                uniquingKeysWith: { first, _ in first })
        var stale: Set<UUID> = []
        for layer in allLayers {
            guard let styleID = layer.textStyleID else { continue }
            // A name this document no longer has is a claim that cannot be
            // true, which is the state a file can arrive in; type that no
            // longer matches the name is the quiet one an edit leaves behind.
            if styles[styleID] != layer.textTreatment { stale.insert(layer.id) }
        }
        guard !stale.isEmpty else { return 0 }
        mapTextLayers { layer in
            if stale.contains(layer.id) { layer.textStyleID = nil }
        }
        return stale.count
    }

    /// Every layer in the tree run through a mutation in place. Named for what
    /// text styles use it for; it walks everything, because a piece of text can
    /// be anywhere in the tree.
    private mutating func mapTextLayers(_ body: (inout Layer) -> Void) {
        func walk(_ list: inout [Layer]) {
            for index in list.indices {
                body(&list[index])
                if list[index].isGroup {
                    var children = list[index].children
                    walk(&children)
                    list[index].children = children
                }
            }
        }
        walk(&layers)
    }
}

/// What a text style's tile and its section say about it.
public enum TextStyleNaming {

    /// The detail line: how much of the document an edit to this style would
    /// re-set, which is the question a shelf full of styles raises.
    public static func detail(usageCount: Int) -> String {
        switch usageCount {
        case 0: return "not used yet"
        case 1: return "1 use"
        default: return "\(usageCount) uses"
        }
    }

    /// What the tile draws, so a style is legible as type rather than as a
    /// name on an empty square. Short on purpose: a tile is about 100 points
    /// wide and two letters at 32pt already fill it.
    public static let sample = "Ag"

    /// The few words a hover tip has room for: the family, the size and the
    /// weight, in the order the panel asks for them.
    public static func treatmentText(_ treatment: TextTreatment) -> String {
        "\(treatment.fontName) • \(TextStyles.sizeWords(treatment.fontSize))"
            + " • \(treatment.weight.rawValue.capitalized)"
    }

    /// What the style's own section says about itself: how much of the document
    /// an edit here would re-set, which is the one fact somebody about to
    /// change it needs.
    public static func standing(usageCount: Int) -> String {
        switch usageCount {
        case 0: return "Nothing uses this yet. Pick it from the Style row in Text to use it."
        case 1: return "1 piece of text uses this. Changing it re-sets that text."
        case let count:
            return "\(count) pieces of text use this. Changing it re-sets them all in one step."
        }
    }
}

// MARK: - What the Style row speaks for

/// What the Style row in the Text section has to show when it is speaking for
/// more than one piece of text.
///
/// Two headings that both wear Heading have one thing to say. Two that wear
/// different things have none, and picking one of them to print would be a row
/// claiming a name the other is not wearing.
public enum TextStyleReading: Hashable, Sendable {
    /// Nothing picked is text, so there is no row.
    case empty
    /// They are all set the same way, and none of them wears a name.
    case own(TextTreatment)
    /// Every one of them wears this style.
    case style(UUID)
    /// They differ: different type, different names, or some named and some not.
    case mixed
}

/// The text one Style row speaks for, and what picking a name in it does to all
/// of them. One piece of text or twenty, the row means the same thing.
public struct TextStyleSelection: Hashable, Sendable {

    /// One picked piece of text: what it is set in, and the style setting it
    /// when a style is.
    public struct Member: Hashable, Sendable {
        public let id: UUID
        public let treatment: TextTreatment
        public let styleID: UUID?

        public init(id: UUID, treatment: TextTreatment, styleID: UUID? = nil) {
            self.id = id
            self.treatment = treatment
            self.styleID = styleID
        }
    }

    /// What the row shows in place of a name when they differ. The app's one
    /// word for it, so no two controls can spell it differently.
    public static let mixedText = MixedValue.text

    public let members: [Member]
    /// How many layers are picked altogether, including the ones that are not
    /// text, so the row can say what it does and does not reach.
    public let selectionCount: Int

    public init(members: [Member], selectionCount: Int) {
        self.members = members
        self.selectionCount = selectionCount
    }

    public var count: Int { members.count }
    public var isEmpty: Bool { members.isEmpty }

    /// The layers a pick in this row re-sets, in the order they were given.
    public var layerIDs: [UUID] { members.map(\.id) }

    public var reading: TextStyleReading {
        guard let first = members.first else { return .empty }
        if let styleID = first.styleID {
            for member in members.dropFirst() where member.styleID != styleID { return .mixed }
            return .style(styleID)
        }
        for member in members.dropFirst() where member.styleID != nil { return .mixed }
        for member in members.dropFirst() where member.treatment != first.treatment {
            return .mixed
        }
        return .own(first.treatment)
    }

    /// The style every picked piece of text already wears, when there is one.
    public var boundStyleID: UUID? {
        if case .style(let id) = reading { return id }
        return nil
    }

    /// Whether Unlink has anything to let go of: true as soon as one picked
    /// piece of text comes from a style.
    public var wearsAnyStyle: Bool { members.contains { $0.styleID != nil } }

    /// What "Save as Style" would keep: the type they all share, and only while
    /// none of them already wears a name. Nil means the button is not offered,
    /// because there is no one treatment to give a name to.
    public var savableTreatment: TextTreatment? {
        if case .own(let treatment) = reading { return treatment }
        return nil
    }

    /// What the row says out loud when the selection holds things that are not
    /// text, so a Style row over a heading and a box is not read as speaking
    /// for the box.
    public var note: String? {
        guard count > 0, count < selectionCount else { return nil }
        return "Applies to \(count) of the \(selectionCount) selected layers."
    }

    /// What the row says before the Font, Size or Weight menus are touched,
    /// when what they would change comes from a name: setting the type by hand
    /// takes it off the style. Said BEFORE the click, because a name that
    /// quietly stopped being worn is one nobody notices until an edit to it
    /// fails to reach a layer.
    public var unlinkNote: String? {
        let styled = members.count { $0.styleID != nil }
        guard styled > 0 else { return nil }
        if case .style = reading {
            return count > 1
                ? "Changing the font, size, weight or colour takes all \(count) of them off the style."
                : "Changing the font, size, weight or colour takes this off the style."
        }
        return "Changing the font, size, weight or colour takes \(styled) of them off their style."
    }
}

extension PhotonzDocument {

    /// What the Style row shows for the picked layers. Locked text sits out,
    /// the same way a locked layer sits out of a colour row: a command aimed at
    /// what is on top of it must not re-set it.
    public func textStyleSelection(layerIDs: [UUID]) -> TextStyleSelection {
        var members: [TextStyleSelection.Member] = []
        for id in layerIDs {
            guard let layer = layer(id: id), !layer.isLocked,
                  let treatment = layer.textTreatment else { continue }
            members.append(TextStyleSelection.Member(id: id, treatment: treatment,
                                                     styleID: layer.textStyleID))
        }
        return TextStyleSelection(members: members, selectionCount: layerIDs.count)
    }
}
