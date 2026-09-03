import CoreGraphics
import Foundation

/// What letting go of a moved layer over the canvas does to what holds it.
///
/// Drawing a shape on a screen puts the shape on that screen, and so does
/// dropping a copy on it from the Library. Dragging something that is already
/// on the canvas has to mean the same thing, or a screen is a picture of a
/// boundary rather than a thing that holds anything: move the screen and the
/// button you dragged onto it stays behind.
///
/// The rule is the one every other way in already follows: the screen that
/// holds the layer's CENTRE (`addLayerOnFrame`). Something dropped mostly on a
/// screen joins it; something dropped mostly off it does not.
public enum FrameAdoption: Hashable, Sendable {
    /// Nothing changes: it stays in whatever holds it now.
    case stays
    /// It joins this screen, keeping the spot on canvas it was dropped on.
    case joins(UUID)
    /// It comes out of the screen it was in, onto bare canvas.
    case leaves
}

extension PhotonzDocument {

    /// What a drop would do to a layer's parent, read from where the layer is
    /// now — or, mid-drag, from the box `landingIn` says it is heading for.
    ///
    /// Only a DRAG asks this. An arrow-key nudge does not: a layer quietly
    /// changing hands one point at a time is a surprise nobody can see coming,
    /// and there is no pointer over a screen to say it is about to happen.
    public func frameAdoption(of id: UUID, landingIn landing: CGRect? = nil) -> FrameAdoption {
        guard let moved = layer(id: id), !moved.isLocked else { return .stays }
        // A screen is never swallowed by another screen — the same rule that
        // makes pasting a copied screen put it BESIDE the one it came from.
        guard !moved.isFrame else { return .stays }
        guard let box = landing ?? canvasBounds(of: id) else { return .stays }
        let now = frameID(containing: id)
        let host = frameID(under: CGPoint(x: box.midX, y: box.midY))
        guard host != now else { return .stays }
        guard let host else { return .leaves }
        return canAdopt(id, into: host) ? .joins(host) : .stays
    }

    /// The one screen a whole drag is promising to join, nil when the drag
    /// would change nothing — what the canvas outlines while the pointer is
    /// still down, so the drop is never a surprise.
    ///
    /// A selection spread across two screens promises nothing: there is no one
    /// box to draw, and a drag that means two different things at once is
    /// better left unannounced than half described.
    public func frameAdoptionHost(moving landings: [UUID: CGRect]) -> UUID? {
        var host: UUID?
        for (id, landing) in landings {
            switch frameAdoption(of: id, landingIn: landing) {
            case .stays: continue
            case .leaves: continue
            case .joins(let frame):
                if let host, host != frame { return nil }
                host = frame
            }
        }
        return host
    }

    /// After a drag has landed, put everything it carried in the screen it now
    /// sits on, and take out anything that left one. Returns the layers whose
    /// parent changed, empty when the drop changed no hands at all.
    ///
    /// Nothing moves on screen: each layer's position is rewritten into its new
    /// parent's space. Run inside the same mutation as the move itself, so one
    /// undo puts the layer back where it was AND back in what held it.
    @discardableResult
    public mutating func adoptMovedLayers(ids: [UUID]) -> [UUID] {
        guard hasFrames else { return [] }
        // Every answer is worked out against the document as the drop left it,
        // before any of them is applied: reparenting the first layer must not
        // change what the second one was promised.
        let plan = ids.compactMap { id -> (UUID, UUID?)? in
            switch frameAdoption(of: id) {
            case .stays: return nil
            case .joins(let host): return (id, host)
            case .leaves: return (id, nil)
            }
        }
        var changed: [UUID] = []
        for (id, host) in plan where moveLayer(id: id, toGroup: host) {
            changed.append(id)
        }
        return changed
    }

    /// Whether a subtree may go inside a screen without something ending up
    /// holding itself. The interface never offers a drop this refuses, so a
    /// gesture cannot make one by accident.
    func canAdopt(_ id: UUID, into host: UUID) -> Bool {
        guard let target = layer(id: host), !target.isLocked,
              // `isOpenableGroup`: a copy of a component is not a container you
              // can put anything in, because its contents are its original's.
              target.isOpenableGroup else { return false }
        // A group can never be dropped inside something it is carrying.
        guard let mine = path(of: id), let theirs = path(of: host),
              !(theirs.count > mine.count && Array(theirs.prefix(mine.count)) == mine) else { return false }
        return canMoveSubtree(id, intoGroup: host)
    }
}
