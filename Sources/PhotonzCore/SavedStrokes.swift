import CoreGraphics
import Foundation

/// A line saved under a name, that drawn paths point at.
///
/// The icon drawing mock's Stroke section: "1.75 with round caps and round
/// joins is the set's weight. It is saved as a style, so this is one click
/// rather than three fields, and if the set ever changes weight every glyph
/// follows." Colours, words and effects could already be named
/// (`ColorStyles.swift`, `TextStyleLibrary.swift`, `EffectStyles.swift`). A
/// line could not, so a person changing a set's weight had to visit every
/// glyph.
///
/// It keeps the shape the effect one has: the values stay ON the path as well
/// as in the style, so nothing downstream (the renderer, export, thumbnails)
/// has to learn what a saved stroke is. The pointer is the extra fact: it says
/// where the line came from, so a change to the style can find its way back.
///
/// ## Which values
///
/// The mock's four: width, caps, corners and which side of the edge the line
/// sits on. Colour is not one of them, because a colour has its own name
/// already, and dashes are not, so a dashed line in a set keeps the set's
/// weight.
///
/// ## Width is in document points
///
/// Like every length in a document. On an Icon picture a unit is many points
/// long, and whatever shows the number says it in units, so 1.75 on a 24 unit
/// picture is one number from the row to the file.

/// The four values a saved stroke keeps.
public struct StrokeLook: Hashable, Codable, Sendable {
    public var width: CGFloat
    public var lineEnd: PathLineEnd
    public var lineCorner: PathLineCorner
    public var strokePosition: BorderPosition

    public init(width: CGFloat, lineEnd: PathLineEnd, lineCorner: PathLineCorner,
                strokePosition: BorderPosition) {
        self.width = width
        self.lineEnd = lineEnd
        self.lineCorner = lineCorner
        self.strokePosition = strokePosition
    }
}

extension StrokeLook {

    /// The few words a hover tip has room for, in the terms the rows use.
    public func summary(in lengths: LengthUnit) -> String {
        "\(lengths.spell(lengths.reading(width))) • \(lineEnd.title) caps • "
            + "\(lineCorner.title) corners • \(strokePosition.title)"
    }
}

/// A line saved under a name. `id` is what paths point at, so renaming one
/// never loosens anything.
public struct SavedStroke: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var name: String
    public var look: StrokeLook

    public init(id: UUID = UUID(), name: String, look: StrokeLook) {
        self.id = id
        self.name = name
        self.look = look
    }
}

extension PathContent {

    /// The line as it is drawn. An open path is drawn centred whatever side it
    /// holds, so that is the side it has to give away.
    public var strokeLook: StrokeLook {
        StrokeLook(width: strokeWidth, lineEnd: lineEnd, lineCorner: lineCorner,
                   strokePosition: effectiveStrokePosition)
    }

    /// Whether this path still draws the line it claims. The side it holds is
    /// compared rather than the side it is drawn on, so an open path wearing an
    /// Inside stroke stays honest and can be closed without letting go.
    func matches(_ look: StrokeLook) -> Bool {
        strokeWidth == look.width && lineEnd == look.lineEnd
            && lineCorner == look.lineCorner && strokePosition == look.strokePosition
    }

    /// Takes on the four values. A closed path with no line yet gains one that
    /// can be seen against its fill, as any first outline does.
    ///
    /// The side is written on an open path too, which `setPathStrokePosition`
    /// deliberately does not: a side nobody can see would only surprise whoever
    /// closes the path later, but here the name asked for it, and leaving it
    /// out would break the name the moment the path closed.
    mutating func wear(_ look: StrokeLook) {
        if strokeWidth > 0 { strokeWidth = look.width } else { gainingALineThatReads(width: look.width) }
        lineEnd = look.lineEnd
        lineCorner = look.lineCorner
        strokePosition = look.strokePosition
    }
}

// MARK: - The document's saved strokes

extension PhotonzDocument {

    /// What a saved stroke opens on before anybody names it: the mock's
    /// `Glyph / stroke 1.75` on an icon, and plain `Stroke 4` anywhere else.
    /// `unit` is how long a unit is, so an Icon picture says its own number.
    public static func savedStrokeNameBase(width: CGFloat, unit: CGFloat, onIcon: Bool) -> String {
        let number = MotionNumber.text(Double(width / unit))
        return onIcon ? "Glyph / stroke \(number)" : "Stroke \(number)"
    }

    /// The stroke behind an id.
    public func savedStroke(id: UUID) -> SavedStroke? {
        savedStrokes.first { $0.id == id }
    }

    /// A name nobody is using yet: "Stroke 2", then "Stroke 2 2"...
    public func freshSavedStrokeName(base: String) -> String {
        let taken = Set(savedStrokes.map(\.name))
        guard taken.contains(base) else { return base }
        var n = 2
        while taken.contains("\(base) \(n)") { n += 1 }
        return "\(base) \(n)"
    }

    /// The name a stroke saved from these paths opens on.
    public func suggestedSavedStrokeName(for layerIDs: [UUID]) -> String {
        let width = savedStrokeSelection(layerIDs: layerIDs).savableStrokeLook?.width ?? 0
        let icon = layerIDs.first.flatMap(iconFrameID(containing:))
        return freshSavedStrokeName(base: Self.savedStrokeNameBase(
            width: width, unit: icon.map(iconUnit(of:)) ?? 1, onIcon: icon != nil))
    }

    /// Saves the line these paths and straight lines share under a name, and
    /// points them at it: the point of saving is to keep using it, so what you
    /// saved from is the stroke's first wearer. Nil when they disagree, or have
    /// no line at all. A box or an oval is not saved from: the corners of its
    /// edge are its Corner Radius, not a stroke's.
    @discardableResult
    public mutating func saveStroke(from layerIDs: [UUID], name: String? = nil) -> UUID? {
        guard let look = savedStrokeSelection(layerIDs: layerIDs).savableStrokeLook,
              look.width > 0 else { return nil }
        let base = Self.savedStrokeNameBase(width: look.width, unit: 1, onIcon: false)
        let stroke = SavedStroke(name: ComponentNaming.normalized(name)
                                 ?? freshSavedStrokeName(base: base), look: look)
        savedStrokes.append(stroke)
        wearSavedStroke(layerIDs: layerIDs, styleID: stroke.id)
        return stroke.id
    }

    /// Dresses every picked layer's line in a saved stroke, in one step:
    /// a path takes all four values, a straight line its width and caps, and a
    /// box or an oval its edge's width and side. Returns how many took it.
    ///
    /// `borderAt` names one Border in a box's or an oval's Effects list, the
    /// one whose row was used; without it a box or an oval dresses its first,
    /// which is the edge it was drawn with (`OutlineRetirement.swift`).
    /// Locked layers, and anything with no line to dress, are left exactly as
    /// they are.
    @discardableResult
    public mutating func wearSavedStroke(layerIDs: [UUID], styleID: UUID,
                                         borderAt index: Int? = nil) -> Int {
        guard let stroke = savedStroke(id: styleID) else { return 0 }
        var changed = 0
        for id in layerIDs {
            guard var layer = layer(id: id), !layer.isLocked else { continue }
            let wore: Bool
            if let index {
                wore = layer.wearOnBorder(at: index, stroke)
            } else if layer.edgeIsABorder {
                wore = layer.style.borderEffectIndex.map { layer.wearOnBorder(at: $0, stroke) } ?? false
            } else {
                wore = layer.wearOnItsOwnLine(stroke)
            }
            guard wore else { continue }
            updateLayer(id: id) { $0 = layer }
            changed += 1
        }
        return changed
    }

    /// Lets the picked layers go back to owning their line. Nothing is re-set:
    /// each keeps exactly the line it is wearing. `borderAt` lets go of that
    /// one Border alone; without it every name on those layers goes.
    public mutating func unwearSavedStroke(layerIDs: [UUID], borderAt index: Int? = nil) {
        for id in layerIDs {
            guard var layer = layer(id: id) else { continue }
            let released: Int
            if let index {
                guard layer.style.borderEffect(at: index)?.savedStrokeID != nil else { continue }
                layer.style.updateBorderEffect(at: index) { $0.savedStrokeID = nil }
                released = 1
            } else {
                released = layer.letGoOfSavedStroke(nil)
            }
            guard released > 0 else { continue }
            updateLayer(id: id) { $0 = layer }
        }
    }

    /// Re-sets a stroke, and with it every line wearing it: paths, straight
    /// lines and the edges of boxes and ovals. Returns how many followed. One
    /// mutation, so `History.perform` records the stroke and everything it
    /// dresses as a single undo step.
    ///
    /// A stroke of no width is refused: it would take the line off every glyph
    /// in the set rather than change its weight.
    @discardableResult
    public mutating func setSavedStroke(styleID: UUID, look: StrokeLook) -> Int {
        guard look.width > 0,
              let index = savedStrokes.firstIndex(where: { $0.id == styleID }) else { return 0 }
        savedStrokes[index].look = look
        guard allLayers.contains(where: { $0.savedStrokeIDs.contains(styleID) })
                || componentOriginals.contains(where: {
                    $0.selfAndDescendants.contains { $0.savedStrokeIDs.contains(styleID) }
                }) else { return 0 }
        var dressed = 0
        mapEffectLayers { layer in dressed += layer.redress(styleID, in: look) }
        return dressed
    }

    /// Renames a stroke. A blank name is refused rather than leaving a nameless
    /// tile on the shelf.
    public mutating func renameSavedStroke(id: UUID, to name: String) {
        guard let index = savedStrokes.firstIndex(where: { $0.id == id }),
              let chosen = ComponentNaming.normalized(name) else { return }
        savedStrokes[index].name = chosen
    }

    /// Takes a stroke off the shelf. Every line wearing it keeps the line it
    /// has and simply owns it again: deleting a name must never undo work.
    public mutating func deleteSavedStroke(id: UUID) {
        guard savedStrokes.contains(where: { $0.id == id }) else { return }
        savedStrokes.removeAll { $0.id == id }
        mapEffectLayers { layer in _ = layer.letGoOfSavedStroke(id) }
    }

    /// How many lines wear this stroke: a path, a straight line, an edge.
    public func savedStrokeUsageCount(id: UUID) -> Int {
        allLayers.reduce(0) { $0 + $1.savedStrokeIDs.count { $0 == id } }
    }

    /// Every layer wearing this stroke, so the app can select them.
    public func layersUsingSavedStroke(id: UUID) -> [UUID] {
        allLayers.filter { $0.savedStrokeIDs.contains(id) }.map(\.id)
    }

    /// The strokes a path's Line settings can offer as buttons: the ones most
    /// used first, a tie in the order they were saved. Three at most, because
    /// past that a row of choices is a dropdown, and the menu beside the
    /// buttons has them all.
    public func savedStrokeChoices(limit: Int) -> [SavedStroke] {
        let uses = Dictionary(grouping: allLayers.flatMap(\.savedStrokeIDs), by: { $0 })
            .mapValues(\.count)
        let ranked = savedStrokes.enumerated().sorted { a, b in
            let (usesA, usesB) = (uses[a.element.id] ?? 0, uses[b.element.id] ?? 0)
            return usesA == usesB ? a.offset < b.offset : usesA > usesB
        }
        return ranked.prefix(limit).map(\.element)
    }

    /// What the Library's Styles scope shows for strokes: one tile each, with
    /// how much of the document leans on it.
    public var savedStrokeLibraryEntries: [LibraryEntry] {
        savedStrokes.map { stroke in
            LibraryEntry(id: stroke.id.uuidString, scope: .styles, name: stroke.name,
                         detail: EffectStyleNaming.detail(
                            usageCount: savedStrokeUsageCount(id: stroke.id)))
        }
    }

    /// The safety net, run after every edit (`History.perform`), and the
    /// counterpart of `reconcileEffectStyles`.
    ///
    /// Pointing at a stroke is a claim: "this line came from that name". Tuning
    /// the width or the corners by hand leaves the claim false, and a row
    /// naming a stroke over a line that is nothing like it is worse than no
    /// names at all. So a path that has drifted, or whose stroke is gone,
    /// quietly lets go and keeps what it is wearing. Returns how many broke.
    ///
    /// The looking is read-only, so an edit that broke nothing costs one
    /// optional check per layer and no copying.
    @discardableResult
    public mutating func reconcileSavedStrokes() -> Int {
        let looks = Dictionary(savedStrokes.map { ($0.id, $0.look) },
                               uniquingKeysWith: { first, _ in first })
        let drifted = { (layer: Layer) in layer.hasDriftedSavedStroke(looks) }
        guard allLayers.contains(where: drifted)
                || componentOriginals.contains(where: { $0.selfAndDescendants.contains(where: drifted) })
        else { return 0 }
        var broken = 0
        mapEffectLayers { layer in
            guard drifted(layer) else { return }
            broken += layer.letGoOfDriftedSavedStrokes(looks)
        }
        return broken
    }
}

// MARK: - The mock's note

extension PhotonzDocument {

    /// The icon mock's note under its Stroke section, word for word. It is far
    /// over the panel's budget, so it lives behind the question mark on the
    /// section's header (UX-PATTERNS section 4).
    public static let savedStrokeNote = "1.75 with round caps and round joins is the set's "
        + "weight. It is saved as a style, so this is one click rather than three fields, "
        + "and if the set ever changes weight every glyph follows."

    /// What that question mark says for these picked layers, or nil: it talks
    /// about an icon set's line, so it only speaks over a line in an icon.
    public func savedStrokeNote(for layerIDs: [UUID]) -> String? {
        let hasALine = pathLineStyleSelection(layerIDs: layerIDs).hasALine
        let inAnIcon = layerIDs.contains { iconFrameID(containing: $0) != nil }
        return hasALine && inAnIcon ? Self.savedStrokeNote : nil
    }
}

// MARK: - A straight line, and the edge of a box or an oval

extension AnnotationContent {

    /// Whether this shape's own line can wear a saved stroke: a straight line
    /// from the Line tool. An arrow's weight also sizes its head, so a set's
    /// weight would quietly regrow it; a box's and an oval's line is the Border
    /// in their Effects list, which wears one there; a highlight is a wash.
    public var canWearSavedStroke: Bool { shape == .line }

    /// The line a straight line draws, as a saved stroke reads it. It has no
    /// corners, so any corner is true of it and it reads the round a glyph's
    /// line is drawn with, and it is always drawn down its middle.
    var savedStrokeLook: StrokeLook {
        StrokeLook(width: strokeWidth, lineEnd: lineEnd, lineCorner: .round,
                   strokePosition: .center)
    }

    /// Whether it still draws the line it claims: the two values a straight
    /// line has.
    func matches(_ look: StrokeLook) -> Bool {
        strokeWidth == look.width && lineEnd == look.lineEnd
    }
}

extension BorderEffect {

    /// Whether this ring still draws the line it claims: the two values a ring
    /// has. Its colour is its own, as a path's is.
    func matches(_ look: StrokeLook) -> Bool {
        width == look.width && position == look.strokePosition
    }

    /// Takes on the width and the side, and paints again if it was off: the
    /// name was asked for so the edge would show at the set's weight. Caps and
    /// corners stay with the stroke: a closed ring has no ends, and its corners
    /// are the box's own Corner Radius.
    mutating func wear(_ look: StrokeLook) {
        width = look.width
        position = look.strokePosition
        isOn = true
    }
}

extension Layer {

    /// A box or an oval, whose line is a Border in its Effects list
    /// (`OutlineRetirement.swift`).
    var edgeIsABorder: Bool { annotation?.drawsARingRatherThanBeingOne == true }

    /// The saved stroke this layer's own line wears: a path's, or a straight
    /// line's.
    var ownSavedStrokeID: UUID? { path?.savedStrokeID ?? annotation?.savedStrokeID }

    /// Every saved stroke this layer wears, once for each place it wears one:
    /// its own line first, then its borders in list order.
    var savedStrokeIDs: [UUID] {
        let rings = style.borderEffects.compactMap(\.savedStrokeID)
        guard let own = ownSavedStrokeID else { return rings }
        return [own] + rings
    }

    /// A path or a straight line takes the stroke on its own line. False for
    /// anything else, which is left exactly as it was.
    mutating func wearOnItsOwnLine(_ stroke: SavedStroke) -> Bool {
        if var path {
            path.wear(stroke.look)
            path.savedStrokeID = stroke.id
            content = .path(path)
            return true
        }
        guard var line = annotation, line.canWearSavedStroke else { return false }
        line.lineEnd = stroke.look.lineEnd
        line.savedStrokeID = stroke.id
        content = .annotation(line)
        // Through the one way a line's width is set, so its box grows round
        // the new weight and its ends stay where they were drawn.
        setOwnStrokeWidth(stroke.look.width)
        return true
    }

    /// A box or an oval takes the stroke on the Border at this place in its
    /// Effects list. False when there is none there.
    mutating func wearOnBorder(at index: Int, _ stroke: SavedStroke) -> Bool {
        guard edgeIsABorder, style.borderEffect(at: index) != nil else { return false }
        style.updateBorderEffect(at: index) {
            $0.wear(stroke.look)
            $0.savedStrokeID = stroke.id
        }
        return true
    }

    /// Every place wearing `id` re-dressed in `look`. Returns how many.
    mutating func redress(_ id: UUID, in look: StrokeLook) -> Int {
        var dressed = 0
        if var path, path.savedStrokeID == id {
            path.wear(look)
            content = .path(path)
            dressed += 1
        } else if var line = annotation, line.savedStrokeID == id {
            line.lineEnd = look.lineEnd
            content = .annotation(line)
            setOwnStrokeWidth(look.width)
            dressed += 1
        }
        for index in style.effects.indices where style.borderEffect(at: index)?.savedStrokeID == id {
            style.updateBorderEffect(at: index) { $0.wear(look) }
            dressed += 1
        }
        return dressed
    }

    /// Lets go of `id` wherever it is worn, or of every name when it is nil.
    /// Nothing is re-set. Returns how many places let go.
    mutating func letGoOfSavedStroke(_ id: UUID?) -> Int {
        var released = 0
        if var path, let worn = path.savedStrokeID, id == nil || worn == id {
            path.savedStrokeID = nil
            content = .path(path)
            released += 1
        } else if var line = annotation, let worn = line.savedStrokeID, id == nil || worn == id {
            line.savedStrokeID = nil
            content = .annotation(line)
            released += 1
        }
        for index in style.effects.indices {
            guard let worn = style.borderEffect(at: index)?.savedStrokeID,
                  id == nil || worn == id else { continue }
            style.updateBorderEffect(at: index) { $0.savedStrokeID = nil }
            released += 1
        }
        return released
    }

    /// Whether any line here claims a name it no longer draws, or one the
    /// document does not have. Read-only, so asking costs no copying.
    func hasDriftedSavedStroke(_ looks: [UUID: StrokeLook]) -> Bool {
        func off(_ id: UUID?, _ matches: (StrokeLook) -> Bool) -> Bool {
            guard let id else { return false }
            guard let look = looks[id] else { return true }
            return !matches(look)
        }
        if let path, off(path.savedStrokeID, path.matches) { return true }
        if let line = annotation, off(line.savedStrokeID, line.matches) { return true }
        return style.borderEffects.contains { off($0.savedStrokeID, $0.matches) }
    }

    /// Lets go wherever a line has drifted off its name. Returns how many.
    mutating func letGoOfDriftedSavedStrokes(_ looks: [UUID: StrokeLook]) -> Int {
        func off(_ id: UUID?, _ matches: (StrokeLook) -> Bool) -> Bool {
            guard let id else { return false }
            guard let look = looks[id] else { return true }
            return !matches(look)
        }
        var released = 0
        if var path, off(path.savedStrokeID, path.matches) {
            path.savedStrokeID = nil
            content = .path(path)
            released += 1
        } else if var line = annotation, off(line.savedStrokeID, line.matches) {
            line.savedStrokeID = nil
            content = .annotation(line)
            released += 1
        }
        for index in style.effects.indices {
            guard let ring = style.borderEffect(at: index), off(ring.savedStrokeID, ring.matches)
            else { continue }
            style.updateBorderEffect(at: index) { $0.savedStrokeID = nil }
            released += 1
        }
        return released
    }
}

// MARK: - What the Style row reads

/// What the Style row on a line has to show.
public enum SavedStrokeReading: Hashable, Sendable {
    /// No line picked, so there is no row.
    case empty
    /// They all draw the same line, and none of them wears a name.
    case own(StrokeLook)
    /// Every one of them wears this stroke.
    case style(UUID)
    /// They differ: different lines, different names, or some named and some
    /// not.
    case mixed
}

/// The picked lines ONE Style row speaks for: the paths and straight lines
/// under a Line or Outline row in Appearance, or the boxes and ovals whose
/// Border at one place in the Effects list is the row's.
public struct SavedStrokeSelection: Hashable, Sendable {

    public struct Member: Hashable, Sendable {
        public let id: UUID
        /// The line it draws, read the way a saved stroke reads one.
        public let look: StrokeLook
        public let savedStrokeID: UUID?
        /// Whether this line can be saved as a stroke. A box's or an oval's
        /// edge cannot: its corners are the shape's Corner Radius, not a
        /// stroke's, so a name saved from it would have to invent them.
        public let isSavable: Bool
        /// Painted with a brush, which shapes its own ends and corners.
        public let isBrushed: Bool

        public init(id: UUID, look: StrokeLook, savedStrokeID: UUID?,
                    isSavable: Bool = true, isBrushed: Bool = false) {
            self.id = id
            self.look = look
            self.savedStrokeID = savedStrokeID
            self.isSavable = isSavable
            self.isBrushed = isBrushed
        }
    }

    public let members: [Member]
    public let selectionCount: Int

    public init(members: [Member], selectionCount: Int) {
        self.members = members
        self.selectionCount = selectionCount
    }

    public var isEmpty: Bool { members.isEmpty }
    public var layerIDs: [UUID] { members.map(\.id) }

    /// The part of this selection one row speaks for.
    public func of(_ ids: [UUID]) -> SavedStrokeSelection {
        let wanted = Set(ids)
        return SavedStrokeSelection(members: members.filter { wanted.contains($0.id) },
                                    selectionCount: ids.count)
    }

    /// Whether there is a line to talk about at all.
    public var hasALine: Bool { members.contains { $0.look.width > 0 } }

    /// Whether every line here is painted with a brush, which a saved stroke
    /// cannot dress (`PathBrush.swift`).
    public var isAllBrushed: Bool { !members.isEmpty && members.allSatisfy(\.isBrushed) }

    public var savedStrokeReading: SavedStrokeReading {
        guard let first = members.first else { return .empty }
        let rest = members.dropFirst()
        if let id = first.savedStrokeID {
            return rest.allSatisfy { $0.savedStrokeID == id } ? .style(id) : .mixed
        }
        guard rest.allSatisfy({ $0.savedStrokeID == nil && $0.look == first.look }) else {
            return .mixed
        }
        return .own(first.look)
    }

    /// The stroke every picked line already wears, when there is one.
    public var boundSavedStrokeID: UUID? {
        if case .style(let id) = savedStrokeReading { return id }
        return nil
    }

    /// Whether Unlink has anything to let go of.
    public var wearsAnySavedStroke: Bool { members.contains { $0.savedStrokeID != nil } }

    /// What Save as Style would keep: the line they all share, while none of
    /// them wears a name and every one of them can be saved from. Nil means it
    /// is not offered.
    public var savableStrokeLook: StrokeLook? {
        guard members.allSatisfy(\.isSavable) else { return nil }
        if case .own(let look) = savedStrokeReading, look.width > 0 { return look }
        return nil
    }
}

extension PhotonzDocument {

    /// The Style row's view of a set of picked layers, in the order given.
    ///
    /// Without `borderAt`: every unlocked path and straight line among them,
    /// the lines a Line or Outline row in Appearance tunes. With it: every
    /// unlocked box and oval with a Border at that place in its Effects list.
    public func savedStrokeSelection(layerIDs: [UUID], borderAt index: Int? = nil) -> SavedStrokeSelection {
        var members: [SavedStrokeSelection.Member] = []
        for id in layerIDs {
            guard let layer = layer(id: id), !layer.isLocked else { continue }
            if let index {
                guard layer.edgeIsABorder, let ring = layer.style.borderEffect(at: index) else { continue }
                let look = StrokeLook(width: ring.isOn ? ring.width : 0, lineEnd: .round,
                                      lineCorner: .round, strokePosition: ring.position)
                members.append(.init(id: id, look: look, savedStrokeID: ring.savedStrokeID,
                                     isSavable: false))
            } else if let path = layer.path {
                members.append(.init(id: id, look: path.strokeLook, savedStrokeID: path.savedStrokeID,
                                     isBrushed: path.brush != nil))
            } else if let line = layer.annotation, line.canWearSavedStroke {
                members.append(.init(id: id, look: line.savedStrokeLook,
                                     savedStrokeID: line.savedStrokeID))
            }
        }
        return SavedStrokeSelection(members: members, selectionCount: layerIDs.count)
    }
}

extension PathLineStyleSelection {

    /// The same reading over these paths alone.
    public var savedStrokes: SavedStrokeSelection {
        SavedStrokeSelection(members: members.map {
            .init(id: $0.id, look: $0.content.strokeLook, savedStrokeID: $0.content.savedStrokeID,
                  isBrushed: $0.content.brush != nil)
        }, selectionCount: selectionCount)
    }

    public var savedStrokeReading: SavedStrokeReading { savedStrokes.savedStrokeReading }

    /// The stroke every picked path already wears, when there is one.
    public var boundSavedStrokeID: UUID? { savedStrokes.boundSavedStrokeID }

    /// Whether Unlink has anything to let go of.
    public var wearsAnySavedStroke: Bool { savedStrokes.wearsAnySavedStroke }

    /// What Save as Style would keep.
    public var savableStrokeLook: StrokeLook? { savedStrokes.savableStrokeLook }
}
