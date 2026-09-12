import AppKit
import PhotonzCore

/// What a click on the canvas means once layers can hold layers
/// (Next flag `next-layer-groups`).
///
/// The rule, in one line: **a click picks the outermost thing you are not
/// already inside.** Click a grouped card and you get the card, not the label
/// you happened to land on; double click and you go one level in; Escape brings
/// you back out. Everything below is that rule, plus the fallback that keeps a
/// document with no groups (and the Current release) behaving exactly as it
/// always has. See `docs/design/ui-building.md`, "The two canvas gestures".
extension CanvasNSView {

    /// Whether clicks resolve through the group walk at all.
    var groupSelectionEnabled: Bool { Experiments.shared.layerGroupsEnabled }

    /// The layer a plain click selects, and the group it resolved inside.
    /// With the flag off (or no groups in the document) this is the plain
    /// hit test the canvas has always run.
    func groupAwarePick(at point: CGPoint, zoom: CGFloat) -> (id: UUID, context: UUID?)? {
        guard let document else { return nil }
        guard groupSelectionEnabled else {
            return document.hitTest(point, zoom: zoom,
                                    captionPillSize: Self.captionPillSizing)
                .map { ($0.id, nil) }
        }
        return document.selectionTarget(at: point, zoom: zoom, inside: groupContext,
                                        captionPillSize: Self.captionPillSizing)
    }

    /// How a click sizes an arrow's label: the measured pill, so the only
    /// picture that picks the arrow up is the picture the label covers. The
    /// document model's own estimate reserves room far past a sentence's far
    /// edge, which used to mean a click on the button underneath grabbed the
    /// arrow instead. See `CaptionPillSizing` and `CaptionPillSizing.swift`.
    static let captionPillSizing: CaptionPillSizing = { $0.measuredCaptionPillSize }

    /// The layer a ⇧-click adds to the selection, or drops from it. Nil when
    /// the click cannot join the selection where you already are — nothing
    /// under the pointer, or the canvas outside the group you are inside.
    func groupAwareExtend(at point: CGPoint, zoom: CGFloat) -> UUID? {
        guard let document else { return nil }
        guard groupSelectionEnabled else {
            return document.hitTest(point, zoom: zoom,
                                    captionPillSize: Self.captionPillSizing)?.id
        }
        return document.extendTarget(at: point, zoom: zoom, inside: groupContext,
                                     captionPillSize: Self.captionPillSizing)
    }

    /// The layer a DOUBLE click selects: one level deeper than a plain click.
    /// Nil when there is nothing left to go into, which is when a double click
    /// keeps meaning what it always meant — opening a text layer to type, or an
    /// arrow's caption.
    func groupAwareDescent(at point: CGPoint, zoom: CGFloat) -> (id: UUID, context: UUID)? {
        guard groupSelectionEnabled, let document else { return nil }
        return document.descendTarget(at: point, zoom: zoom, inside: groupContext,
                                      captionPillSize: Self.captionPillSizing)
    }

    /// The copy a layer is a piece of, nil for everything that is not inside
    /// one. A piece owns nothing: its size, its place and its look all come
    /// from the original and are written back over on the next redraw.
    func componentPiece(of id: UUID?) -> ComponentPiece? {
        guard componentsEnabled, let id, let document else { return nil }
        return document.componentPiece(of: id)
    }

    /// Whether a layer offers handles of its own. A piece inside a copy does
    /// not: dragging one of its corners would resize something the next sync
    /// puts straight back, so there is nothing to grab. Dragging the piece
    /// itself moves the whole copy instead, which is what the person meant.
    ///
    /// Neither does a piece inside a card that has been TURNED. Its place and
    /// its size are stated in the card's upright space, so a handle pulled
    /// sideways would send it off at an angle to the pointer. Its outline
    /// still draws on it, so you can see what you have picked and restyle it;
    /// to move or resize it, straighten the card, which the A field puts back
    /// to the degree.
    func offersOwnHandles(_ layer: Layer) -> Bool {
        layer.offersHandles && componentPiece(of: layer.id) == nil
            && inheritedTurn(of: layer.id).isIdentity
    }

    /// How the containers above a layer have turned it, in canvas space.
    /// Identity for everything at the top level, and for every layer in a
    /// document where no group has been turned.
    func inheritedTurn(of id: UUID) -> CGAffineTransform {
        document?.inheritedTurn(of: id) ?? .identity
    }

    /// Whether the selected layer offers the rotate knob. A group does: the
    /// knob turns the whole card and everything in it at once, about the
    /// middle of the box its contents make (`Layer.turnPivot`).
    ///
    /// A SCREEN does not. A screen is the surface you build on, printed with
    /// its name above its top left corner and sitting in a column with its
    /// neighbours, so a screen on a slant would tilt the room rather than the
    /// furniture. Neither does a shape held between two ends, which is aimed
    /// by its ends, nor a locked layer, which offers no handles of any kind
    /// (`Layer.offersHandles`). The Position and Size panel asks the same
    /// question in the same words (`LayerGeometryEditing`).
    func offersRotation(_ layer: Layer) -> Bool {
        offersOwnHandles(layer) && !layer.hasEndpointHandles && !layer.isFrame
    }
}

extension CanvasNSView {

    /// The faint box around the group you are inside, drawn behind whatever is
    /// selected within it. Without it, descending into a group is a mode with
    /// no sign of itself: the handles move to one piece and nothing on the
    /// canvas says why.
    ///
    /// A screen never draws it. The box means "you stepped in here", and you
    /// never step into a screen: clicking a button on one puts you inside it
    /// straight away, so the box would be on almost all the time and say
    /// nothing. A screen already shows where it is, with its surface and its
    /// name above it.
    /// While a band is being swept the box comes from the BAND, and it comes
    /// up out of its whisper for as long as the button is down.
    ///
    /// Both halves are the same point. The press that starts a sweep lets go
    /// of the selection, and letting go of the selection puts the canvas back
    /// at the top level, so reading `groupContext` here took the box down at
    /// the one moment it had something to say: the band that picks a button's
    /// own pieces looked exactly like the band that picks whole layers off the
    /// document. `marqueeContext` is the level the sweep was latched to at the
    /// press, so it is the honest answer for as long as the band is up. And a
    /// box drawn at the strength it rests at is a box nobody notices mid-drag,
    /// so the room you are picking in lights up while you sweep it and settles
    /// back the moment the band comes down.
    func refreshGroupContextOutline() {
        let sweeping = marquee != nil
        let context = sweeping ? marqueeContext : groupContext
        // A screen draws it only while a band is being swept on it. At rest
        // the box would be on almost all the time and say nothing, since
        // clicking a button on a screen puts you inside that screen straight
        // away; and a screen already shows where it is, with its surface and
        // its name above it. Mid-sweep it says the one thing nothing else on
        // screen says: this band is picking from what is on THIS screen, not
        // from the screens themselves. Same wall, same blue, as a group's.
        guard let viewport, let document, let context,
              sweeping || document.layer(id: context)?.isFrame != true,
              let bounds = document.canvasBounds(of: context), bounds.width > 0, bounds.height > 0
        else {
            groupContextLayer.isHidden = true
            return
        }
        applyGroupContextStyle(lit: sweeping)
        // The box follows the group's own turn, so stepping into a card on a
        // slant lights up the slanted room rather than an upright box the
        // contents hang out of on two corners.
        let turn = document.layer(id: context)?.transform ?? .identity
        let pivot = CGPoint(x: bounds.midX, y: bounds.midY)
        var toView = (turn.isIdentity ? CGAffineTransform.identity
                                      : turn.affineTransform(around: pivot))
            .concatenating(viewport.documentToView)
        let room = 3 / viewport.zoom
        groupContextLayer.path = CGPath(rect: bounds.insetBy(dx: -room, dy: -room),
                                        transform: &toView)
        groupContextLayer.isHidden = false
    }

    /// The two strengths the context box is drawn at: the room you are
    /// standing in, and the room you are sweeping.
    ///
    /// The lit one is SOLID, and that is the whole of how it keeps out of the
    /// band's way. Everything the band itself puts on screen is dashed — the
    /// ants round the band, the two point `[2, 4]` outlines round each layer
    /// it has caught — so a bright dashed box round the group read as one more
    /// thing the band had taken, which is the exact opposite of what it means.
    /// An unbroken hairline reads as a wall instead: the edge of the room you
    /// are picking in, not something picked. Same blue, same one point, same
    /// place as the box at rest, so it reads as that box firming up rather
    /// than as a second box arriving.
    func applyGroupContextStyle(lit: Bool) {
        groupContextLayer.strokeColor = NSColor.systemBlue
            .withAlphaComponent(lit ? 0.7 : 0.28).cgColor
        groupContextLayer.lineDashPattern = lit ? nil : [1, 3]
    }
}
