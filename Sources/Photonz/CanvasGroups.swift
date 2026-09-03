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
            return document.hitTest(point, zoom: zoom).map { ($0.id, nil) }
        }
        return document.selectionTarget(at: point, zoom: zoom, inside: groupContext)
    }

    /// The layer a ⇧-click adds to the selection, or drops from it. Nil when
    /// the click cannot join the selection where you already are — nothing
    /// under the pointer, or the canvas outside the group you are inside.
    func groupAwareExtend(at point: CGPoint, zoom: CGFloat) -> UUID? {
        guard let document else { return nil }
        guard groupSelectionEnabled else { return document.hitTest(point, zoom: zoom)?.id }
        return document.extendTarget(at: point, zoom: zoom, inside: groupContext)
    }

    /// The layer a DOUBLE click selects: one level deeper than a plain click.
    /// Nil when there is nothing left to go into, which is when a double click
    /// keeps meaning what it always meant — opening a text layer to type, or an
    /// arrow's caption.
    func groupAwareDescent(at point: CGPoint, zoom: CGFloat) -> (id: UUID, context: UUID)? {
        guard groupSelectionEnabled, let document else { return nil }
        return document.descendTarget(at: point, zoom: zoom, inside: groupContext)
    }

    /// Whether the selected layer offers the rotate knob. A group never does:
    /// groups translate and nothing else, so a knob that turned one would be a
    /// control with nothing behind it.
    func offersRotation(_ layer: Layer) -> Bool {
        !layer.hasEndpointHandles && !layer.isGroup
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
    func refreshGroupContextOutline() {
        guard let viewport, let document, let context = groupContext,
              document.layer(id: context)?.isFrame != true,
              let bounds = document.canvasBounds(of: context), bounds.width > 0, bounds.height > 0
        else {
            groupContextLayer.isHidden = true
            return
        }
        let origin = viewport.viewPoint(fromDocument: bounds.origin)
        let rect = CGRect(x: origin.x, y: origin.y,
                          width: bounds.width * viewport.zoom,
                          height: bounds.height * viewport.zoom)
        groupContextLayer.path = CGPath(rect: rect.insetBy(dx: -3, dy: -3), transform: nil)
        groupContextLayer.isHidden = false
    }
}
