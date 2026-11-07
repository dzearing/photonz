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
        let width = pathLineStyleSelection(layerIDs: layerIDs).savableStrokeLook?.width ?? 0
        let icon = layerIDs.first.flatMap(iconFrameID(containing:))
        return freshSavedStrokeName(base: Self.savedStrokeNameBase(
            width: width, unit: icon.map(iconUnit(of:)) ?? 1, onIcon: icon != nil))
    }

    /// Saves the line these paths share under a name, and points them at it:
    /// the point of saving is to keep using it, so what you saved from is the
    /// stroke's first wearer. Nil when they disagree, or have no line at all.
    @discardableResult
    public mutating func saveStroke(from layerIDs: [UUID], name: String? = nil) -> UUID? {
        guard let look = pathLineStyleSelection(layerIDs: layerIDs).savableStrokeLook,
              look.width > 0 else { return nil }
        let base = Self.savedStrokeNameBase(width: look.width, unit: 1, onIcon: false)
        let stroke = SavedStroke(name: ComponentNaming.normalized(name)
                                 ?? freshSavedStrokeName(base: base), look: look)
        savedStrokes.append(stroke)
        wearSavedStroke(layerIDs: layerIDs, styleID: stroke.id)
        return stroke.id
    }

    /// Dresses every picked path in a saved stroke, all four values in one
    /// step. Returns how many took it. Locked layers and anything that is not a
    /// path are left exactly as they are.
    @discardableResult
    public mutating func wearSavedStroke(layerIDs: [UUID], styleID: UUID) -> Int {
        guard let stroke = savedStroke(id: styleID) else { return 0 }
        var changed = 0
        for id in layerIDs {
            guard let layer = layer(id: id), !layer.isLocked, var path = layer.path else { continue }
            path.wear(stroke.look)
            path.savedStrokeID = styleID
            updateLayer(id: id) { $0.content = .path(path) }
            changed += 1
        }
        return changed
    }

    /// Lets the picked paths go back to owning their line. Nothing is re-set:
    /// each keeps exactly the line it is wearing.
    public mutating func unwearSavedStroke(layerIDs: [UUID]) {
        for id in layerIDs {
            guard var path = layer(id: id)?.path, path.savedStrokeID != nil else { continue }
            path.savedStrokeID = nil
            updateLayer(id: id) { $0.content = .path(path) }
        }
    }

    /// Re-sets a stroke, and with it every path wearing it. Returns how many
    /// followed. One mutation, so `History.perform` records the stroke and
    /// everything it dresses as a single undo step.
    ///
    /// A stroke of no width is refused: it would take the line off every glyph
    /// in the set rather than change its weight.
    @discardableResult
    public mutating func setSavedStroke(styleID: UUID, look: StrokeLook) -> Int {
        guard look.width > 0,
              let index = savedStrokes.firstIndex(where: { $0.id == styleID }) else { return 0 }
        savedStrokes[index].look = look
        var dressed = 0
        mapEffectLayers { layer in
            guard var path = layer.path, path.savedStrokeID == styleID else { return }
            path.wear(look)
            layer.content = .path(path)
            dressed += 1
        }
        return dressed
    }

    /// Renames a stroke. A blank name is refused rather than leaving a nameless
    /// tile on the shelf.
    public mutating func renameSavedStroke(id: UUID, to name: String) {
        guard let index = savedStrokes.firstIndex(where: { $0.id == id }),
              let chosen = ComponentNaming.normalized(name) else { return }
        savedStrokes[index].name = chosen
    }

    /// Takes a stroke off the shelf. Every path wearing it keeps the line it
    /// has and simply owns it again: deleting a name must never undo work.
    public mutating func deleteSavedStroke(id: UUID) {
        guard savedStrokes.contains(where: { $0.id == id }) else { return }
        savedStrokes.removeAll { $0.id == id }
        mapEffectLayers { layer in
            guard var path = layer.path, path.savedStrokeID == id else { return }
            path.savedStrokeID = nil
            layer.content = .path(path)
        }
    }

    /// How many paths wear this stroke.
    public func savedStrokeUsageCount(id: UUID) -> Int {
        allLayers.count { $0.path?.savedStrokeID == id }
    }

    /// Every path wearing this stroke, so the app can select them.
    public func layersUsingSavedStroke(id: UUID) -> [UUID] {
        allLayers.filter { $0.path?.savedStrokeID == id }.map(\.id)
    }

    /// The strokes a path's Line settings can offer as buttons: the ones most
    /// used first, a tie in the order they were saved. Three at most, because
    /// past that a row of choices is a dropdown, and the menu beside the
    /// buttons has them all.
    public func savedStrokeChoices(limit: Int) -> [SavedStroke] {
        let uses = Dictionary(grouping: allLayers.compactMap { $0.path?.savedStrokeID }, by: { $0 })
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
        func drifted(_ layer: Layer) -> Bool {
            guard let path = layer.path, let id = path.savedStrokeID else { return false }
            guard let look = looks[id] else { return true }
            return !path.matches(look)
        }
        guard allLayers.contains(where: drifted)
                || componentOriginals.contains(where: { $0.selfAndDescendants.contains(where: drifted) })
        else { return 0 }
        var broken = 0
        mapEffectLayers { layer in
            guard drifted(layer), var path = layer.path else { return }
            path.savedStrokeID = nil
            layer.content = .path(path)
            broken += 1
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

// MARK: - What the Style row reads

/// What the Style row on a path's line has to show.
public enum SavedStrokeReading: Hashable, Sendable {
    /// No path picked, so there is no row.
    case empty
    /// They all draw the same line, and none of them wears a name.
    case own(StrokeLook)
    /// Every one of them wears this stroke.
    case style(UUID)
    /// They differ: different lines, different names, or some named and some
    /// not.
    case mixed
}

extension PathLineStyleSelection {

    public var savedStrokeReading: SavedStrokeReading {
        guard let first = members.first?.content else { return .empty }
        let rest = members.dropFirst().map(\.content)
        if let id = first.savedStrokeID {
            return rest.allSatisfy { $0.savedStrokeID == id } ? .style(id) : .mixed
        }
        guard rest.allSatisfy({ $0.savedStrokeID == nil && $0.strokeLook == first.strokeLook }) else {
            return .mixed
        }
        return .own(first.strokeLook)
    }

    /// The stroke every picked path already wears, when there is one.
    public var boundSavedStrokeID: UUID? {
        if case .style(let id) = savedStrokeReading { return id }
        return nil
    }

    /// Whether Unlink has anything to let go of.
    public var wearsAnySavedStroke: Bool { members.contains { $0.content.savedStrokeID != nil } }

    /// What Save as Style would keep: the line they all share, while none of
    /// them wears a name. Nil means it is not offered.
    public var savableStrokeLook: StrokeLook? {
        if case .own(let look) = savedStrokeReading, look.width > 0 { return look }
        return nil
    }
}
