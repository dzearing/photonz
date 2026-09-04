import CoreGraphics
import Foundation

/// Editing a piece INSIDE a copy (`docs/design/ui-building.md`, step C6).
///
/// A copy's contents are its original's. They are rebuilt from the original
/// every time the document is put back in step, which is after every edit, so
/// anything written straight onto one of those pieces is gone by the next
/// redraw. That is not a bug to work around, it is what "a copy follows its
/// original" means.
///
/// So there are only two honest answers to somebody typing over a piece:
///
/// - the original exposes a **wording knob** for exactly that piece, and the
///   words land on the copy's own answer to it, where they stay; or
/// - there is no knob, and the edit is **refused with a reason** and a way
///   forward — make it adjustable, or stop following the original.
///
/// Silently taking the words and dropping them is not one of them.

// MARK: - Which copy a piece belongs to

/// A layer inside a copy, and where it came from.
public struct ComponentPiece: Hashable, Sendable {
    /// The piece itself, as it appears inside the copy.
    public var layer: UUID
    /// The copy it is part of.
    public var instance: UUID
    /// The original that copy follows.
    public var componentID: UUID
    /// The layer inside the original this piece is a picture of. Every knob
    /// points at one of these, so it is the handle that matches the two up.
    public var source: UUID
    /// Whether the copy is itself inside another copy. A nested copy is rebuilt
    /// by the OUTER copy's sync, from the original's own nested copy, so an
    /// answer given to it has nowhere to live.
    public var isNested: Bool

    public init(layer: UUID, instance: UUID, componentID: UUID, source: UUID, isNested: Bool) {
        self.layer = layer
        self.instance = instance
        self.componentID = componentID
        self.source = source
        self.isNested = isNested
    }
}

/// The way forward a refusal offers, which is what decides the button beside
/// the message.
public enum ComponentPieceRemedy: Hashable, Sendable {
    /// The original could expose this piece's wording, and one press would.
    case exposeWording
    /// Nothing here can become a knob, so the only way in is to stop following.
    case detach
    /// The copy is locked, and nothing about it changes until it is not.
    case unlock
}

/// Why an edit inside a copy was refused, in words a person can act on.
public struct ComponentPieceRefusal: Hashable, Sendable {
    public var piece: ComponentPiece
    /// What the original is called.
    public var component: String
    /// What the piece is called.
    public var pieceName: String
    public var remedy: ComponentPieceRemedy

    public init(piece: ComponentPiece, component: String, pieceName: String,
                remedy: ComponentPieceRemedy) {
        self.piece = piece
        self.component = component
        self.pieceName = pieceName
        self.remedy = remedy
    }

    /// The verdict, in its own weight at the head of the notice.
    public var title: String {
        remedy == .unlock ? "Locked" : "Follows the original"
    }

    /// One line saying why, and what to do about it. Named things are named:
    /// "Label follows Button" tells you which two things are involved, and a
    /// person who has ten copies on screen needs that.
    public var detail: String {
        switch remedy {
        case .unlock:
            return "\(pieceName) is part of \(component), and this copy is locked."
        case .exposeWording:
            return "\(component) decides what \(pieceName) says. Make its wording adjustable to change it here."
        case .detach:
            return "\(pieceName) comes from \(component). Detach this copy to edit it."
        }
    }
}

/// What typing over a layer means.
public enum ComponentPieceEdit: Hashable, Sendable {
    /// Not inside a copy: edit it the way everything else is edited.
    case ordinary
    /// Inside a copy, and the original exposes a knob for exactly this fact.
    case knob(ComponentPiece, ComponentProperty)
    /// Inside a copy with nowhere for the edit to land.
    case refused(ComponentPieceRefusal)

    /// The copy involved, for anything that wants to point at it.
    public var piece: ComponentPiece? {
        switch self {
        case .ordinary: return nil
        case .knob(let piece, _): return piece
        case .refused(let refusal): return refusal.piece
        }
    }
}

extension PhotonzDocument {

    /// The copy a layer is a piece of, nil for everything else.
    ///
    /// The copy that OWNS the piece is the innermost one above it: that is the
    /// one whose sync rebuilds it. `isNested` says whether there is another
    /// above that, because then the inner copy is itself rebuilt and its own
    /// answers are rewritten with it.
    public func componentPiece(of id: UUID) -> ComponentPiece? {
        guard let path = path(of: id), path.count > 1 else { return nil }
        var list = layers
        var owner: Layer?
        var depth = 0
        for index in path.dropLast() {
            guard list.indices.contains(index) else { return nil }
            let layer = list[index]
            if layer.isComponentInstance {
                owner = layer
                depth += 1
            }
            list = layer.children
        }
        guard let owner, let componentID = owner.instanceOf,
              let source = sourceOfPiece(id, instance: owner.id, componentID: componentID)
        else { return nil }
        return ComponentPiece(layer: id, instance: owner.id, componentID: componentID,
                              source: source, isNested: depth > 1)
    }

    /// The layer inside the original that a piece is a picture of.
    ///
    /// Ids inside a copy are derived from the copy and the layer they came
    /// from, and that derivation is one-way, so the match is made by deriving
    /// the original's layers forward and looking for this one.
    private func sourceOfPiece(_ id: UUID, instance: UUID, componentID: UUID) -> UUID? {
        guard let main = mainComponent(componentID: componentID) else { return nil }
        return main.selfAndDescendants
            .first { ComponentIdentity.derived(instance: instance, source: $0.id) == id }?.id
    }

    /// What the piece is called, which is the original's name for it.
    public func componentPieceName(of piece: ComponentPiece) -> String {
        layer(id: piece.source)?.name ?? layer(id: piece.layer)?.name ?? "This piece"
    }

    /// The words of a COPY under a canvas point, nil when the point is not on
    /// a copy's words.
    ///
    /// The ordinary hit test stops at a copy on purpose: its contents belong
    /// to its original, so a click picks the whole copy and there is nothing
    /// inside to select. Typing is the one thing that reaches in, because a
    /// wording knob is a fact about one piece and the way anybody would set it
    /// is to double click the words and type.
    public func textPiece(at point: CGPoint, zoom: CGFloat = 1) -> UUID? {
        func search(_ list: [Layer], _ point: CGPoint, insideCopy: Bool) -> UUID? {
            for layer in list.reversed() {
                guard layer.isVisible, !layer.isLocked else { continue }
                if layer.isGroup {
                    if layer.clipsToFrame, !layer.localBounds.contains(point) { continue }
                    let local = CGPoint(x: point.x - layer.frame.origin.x,
                                        y: point.y - layer.frame.origin.y)
                    if let found = search(layer.children, local,
                                          insideCopy: insideCopy || layer.isComponentInstance) {
                        return found
                    }
                } else if insideCopy, layer.text != nil, layer.contains(canvasPoint: point, zoom: zoom) {
                    return layer.id
                }
            }
            return nil
        }
        return search(layers, point, insideCopy: false)
    }

    // MARK: - Wording

    /// What typing over `id` means: nothing special, a knob to land on, or a
    /// refusal with a way forward.
    public func wordingEdit(of id: UUID) -> ComponentPieceEdit {
        guard let piece = componentPiece(of: id) else { return .ordinary }
        if layer(id: piece.instance)?.isLocked == true {
            return .refused(refusal(for: piece, remedy: .unlock))
        }
        if !piece.isNested,
           let property = componentProperties(of: piece.componentID)
            .first(where: { $0.kind == .text && $0.target == piece.source }) {
            return .knob(piece, property)
        }
        let canExpose = !piece.isNested
            && canAddComponentProperty(componentID: piece.componentID, target: piece.source, kind: .text)
        return .refused(refusal(for: piece, remedy: canExpose ? .exposeWording : .detach))
    }

    private func refusal(for piece: ComponentPiece, remedy: ComponentPieceRemedy)
    -> ComponentPieceRefusal {
        ComponentPieceRefusal(piece: piece,
                              component: mainComponent(componentID: piece.componentID)?.name
                                ?? layer(id: piece.instance)?.name ?? "the original",
                              pieceName: componentPieceName(of: piece),
                              remedy: remedy)
    }

    /// Lands words typed over a piece on the copy's own answer. False when
    /// there is no knob to land on, which is the caller's cue to say why.
    @discardableResult
    public mutating func setPieceWording(of id: UUID, to string: String) -> Bool {
        guard case .knob(let piece, let property) = wordingEdit(of: id) else { return false }
        return setInstanceOverride(instance: piece.instance, property: property.id,
                                   value: .text(string))
    }

    /// Puts a piece back to saying whatever the original says.
    ///
    /// This is what emptying the field means. A piece of a copy cannot be
    /// deleted — the next sync would put it straight back — so an empty commit
    /// follows the original again instead, which is the one answer that is
    /// both undoable and visible.
    @discardableResult
    public mutating func clearPieceWording(of id: UUID) -> Bool {
        guard case .knob(let piece, let property) = wordingEdit(of: id) else { return false }
        clearInstanceOverride(instance: piece.instance, property: property.id)
        return true
    }

    /// Whether the original could be given a wording knob for this piece,
    /// which is the difference between offering to make it adjustable and
    /// offering only to detach.
    public func canExposePieceWording(of id: UUID) -> Bool {
        guard let piece = componentPiece(of: id), !piece.isNested else { return false }
        return canAddComponentProperty(componentID: piece.componentID, target: piece.source,
                                       kind: .text)
    }

    /// Makes a piece's wording adjustable, from the copy rather than from the
    /// original: the knob is added to the original, so every copy gets it, and
    /// the copy you were looking at can answer it straight away.
    @discardableResult
    public mutating func exposePieceWording(of id: UUID) -> UUID? {
        guard let piece = componentPiece(of: id), canExposePieceWording(of: id) else { return nil }
        return addComponentProperty(componentID: piece.componentID, target: piece.source,
                                    kind: .text)
    }
}
