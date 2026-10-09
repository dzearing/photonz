import CoreGraphics
import Foundation

/// What letting go of a component in Edit Original's space would do.
///
/// The space holds only the component being edited, and Done folds whatever
/// is on its page into that component. So a drop there has three answers, not
/// the canvas's usual "inside a screen, or loose": it joins the drawing it was
/// let go on, it is refused because the component would end up holding itself,
/// or it is refused because it would sit loose on the bare page, where Done
/// would have quietly grown the original round it. Found on 2026-10-09, when a
/// Button and a Card dropped beside the Button's original turned every copy in
/// the document into a big box holding a Card and a copy of itself.
public enum EditingSpaceDrop: Equatable, Sendable {
    /// It lands inside a drawing: drop it with this group as the context.
    case into(UUID)
    /// It would put the component inside itself, directly or through
    /// something it holds.
    case holdsItself
    /// It would land loose on the page, outside every drawing.
    case beside

    /// What the canvas says under the pointer while the drag is in the air,
    /// nil for a drop that lands. `component` names the original the space is
    /// open on. Short, because it rides under the pointer.
    public func note(component: String?) -> String? {
        switch self {
        case .into: return nil
        case .holdsItself: return "Cannot go inside itself"
        case .beside:
            guard let component, !component.isEmpty else { return "Drop it onto the drawing" }
            return "Drop it onto \(component)"
        }
    }
}

extension PhotonzDocument {

    /// What letting go of `componentID` at a point in this editing space would
    /// do, while `editing` is the component the space is open on.
    ///
    /// `context` is the group you have stepped inside, as on the canvas: let
    /// go inside it and that is where the piece goes. Otherwise the drawing
    /// under the point takes it, the way dropping onto a component in Figma
    /// puts the piece inside it. `arriving` is the drawing of a component off
    /// the shared shelf that is not in this document yet.
    ///
    /// Asked by the drag in the air and by the drop itself, so the no-entry
    /// pointer and what happens agree.
    public func editingSpaceDrop(of componentID: UUID, at point: CGPoint,
                                 editing: UUID, inside context: UUID? = nil,
                                 arriving: Layer? = nil) -> EditingSpaceDrop {
        if componentID == editing { return .holdsItself }
        let used = mainComponent(componentID: componentID).map { componentsUsed(by: $0) }
            ?? arriving.map { componentsUsed(by: $0) } ?? []
        if used.contains(editing) { return .holdsItself }
        guard let group = spaceDropGroup(at: point, inside: context) else { return .beside }
        switch componentDropTarget(of: componentID, at: point, inside: group, arriving: arriving) {
        case .refused: return .holdsItself
        case .canvas: return .beside
        case .inside: return .into(group)
        }
    }

    /// The group a drop at `point` joins in an editing space: the one you have
    /// stepped inside when the point is in it, else the topmost drawing under
    /// the point. Nil on the bare page.
    private func spaceDropGroup(at point: CGPoint, inside context: UUID?) -> UUID? {
        if let context, let host = dropHostID(under: point, inside: context),
           let top = topLevelAncestor(of: host), layer(id: top)?.isMainComponent == true {
            return context
        }
        return layers.last { drawing in
            drawing.isMainComponent && drawing.isVisible
                && (canvasBounds(of: drawing.id)?.contains(point) ?? false)
        }?.id
    }

    /// The layer at the top of the tree that `id` sits in, itself when it is
    /// at the top.
    private func topLevelAncestor(of id: UUID) -> UUID? {
        guard layer(id: id) != nil else { return nil }
        var current = id
        while let parent = parentID(of: current) { current = parent }
        return current
    }
}
