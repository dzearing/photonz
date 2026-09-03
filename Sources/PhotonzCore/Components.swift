import CoreGraphics
import Foundation

/// Components: a subtree you drew once, given a name, that the Library can
/// hand back to you (`docs/design/ui-building.md`, step C4).
///
/// This is the first rung. A **main** is an ordinary group with a component id
/// on it: it stays exactly where you drew it, draws exactly as it drew before,
/// and every operation a group already answers to (select, move, restack,
/// hide, undo, save) it still answers to. Nothing about the model forks. What
/// the id buys is identity: the shelf can list it, and the instances that come
/// next have something to point at.
///
/// Instances, exposed properties and detach are later steps and are not here.
extension Layer {

    /// This layer's component identity, set only on a main.
    public var componentID: UUID? { group?.componentID }

    /// Whether this layer is a main component: the original a Library tile
    /// stands for, and the thing every future instance follows.
    public var isMainComponent: Bool { componentID != nil }
}

extension PhotonzDocument {

    /// The name a promoted group takes when its own name says nothing.
    public static let componentNameBase = "Component"

    /// Every main in the document, in the order the tree holds them.
    public var mainComponents: [Layer] {
        allLayers.filter(\.isMainComponent)
    }

    /// The main a component id belongs to, wherever in the tree it sits.
    public func mainComponent(componentID: UUID) -> Layer? {
        mainComponents.first { $0.componentID == componentID }
    }

    /// Whether the layer, or anything under it, is a main.
    private func holdsMain(_ layer: Layer) -> Bool {
        layer.isMainComponent || layer.children.contains(where: holdsMain)
    }

    /// Whether any layer between `id` and the canvas is a main.
    private func isInsideMain(_ id: UUID) -> Bool {
        var parent = parentID(of: id)
        while let current = parent {
            if layer(id: current)?.isMainComponent == true { return true }
            parent = parentID(of: current)
        }
        return false
    }

    /// Whether Layer ▸ Make Component would do anything.
    ///
    /// One unlocked group, not already a main, with no main inside it and none
    /// above it. Components inside components are a nesting question this
    /// version has no answer for, so the row is dead rather than making one
    /// that later work would have to unpick.
    public func canMakeComponent(ids: Set<UUID>) -> Bool {
        guard ids.count == 1, let id = ids.first, let layer = layer(id: id),
              layer.isGroup, !layer.isLocked, !layer.isMainComponent,
              !holdsMain(layer), !isInsideMain(id)
        else { return false }
        return true
    }

    /// A component name nobody is using yet: "Component", then "Component 2",
    /// "Component 3"… so two made a minute apart are tellable apart on the
    /// shelf.
    public func freshComponentName(base: String = PhotonzDocument.componentNameBase) -> String {
        freshGroupName(base: base)
    }

    /// Layer ▸ Make Component (⌥⌘K): marks the group as a main and returns the
    /// component's id, or nil when the group could not be promoted.
    ///
    /// The group is not moved, not rewrapped and not re-parented — promoting is
    /// one flag going on, which is why nothing on the canvas shifts by a pixel
    /// when you press the key. A name given by the caller wins; otherwise the
    /// group keeps the name someone chose for it, and only the auto name the
    /// grouping command minted ("Group", "Group 2") is replaced, because it
    /// says nothing a shelf could be browsed by.
    @discardableResult
    public mutating func makeComponent(id: UUID, name: String? = nil) -> UUID? {
        guard canMakeComponent(ids: [id]), let existing = layer(id: id) else { return nil }
        let componentID = UUID()
        let chosen = ComponentNaming.normalized(name)
            ?? (ComponentNaming.isAutoGroupName(existing.name) ? freshComponentName() : existing.name)
        updateLayer(id: id) { layer in
            guard var group = layer.group else { return }
            group.componentID = componentID
            layer.content = .group(group)
            layer.name = chosen
        }
        return layer(id: id)?.componentID
    }

    /// Renames a component, which is the same act as renaming its layer: the
    /// name lives in one place, so the layers list, the canvas badge and the
    /// Library tile can never disagree. A blank name is refused rather than
    /// leaving a nameless tile on the shelf.
    public mutating func renameComponent(componentID: UUID, to name: String) {
        guard let main = mainComponent(componentID: componentID),
              let chosen = ComponentNaming.normalized(name) else { return }
        updateLayer(id: main.id) { $0.name = chosen }
    }

    /// What the Library's Components scope shows: one tile per main, named by
    /// its layer. The detail line says how many copies of it are out, which is
    /// the question a shelf raises the moment copies exist; a component nobody
    /// has placed yet says "main".
    public var componentLibraryEntries: [LibraryEntry] {
        mainComponents.compactMap { layer in
            guard let componentID = layer.componentID else { return nil }
            return LibraryEntry(id: componentID.uuidString, scope: .components,
                                name: layer.name,
                                detail: ComponentNaming.detail(instanceCount: instanceCount(of: componentID)))
        }
    }
}

/// Naming policy for components, kept apart from the document so the app and
/// its tests can ask the same questions the model asks.
public enum ComponentNaming {
    /// The word a main's tile and badge wear, so a component is never mistaken
    /// for an ordinary group.
    public static let mainDetail = "main"

    /// A name with its edges trimmed, or nil when there is nothing left — what
    /// every field that renames a component runs its text through.
    public static func normalized(_ name: String?) -> String? {
        guard let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }

    /// The same names, with repeats numbered so a list of them can be read.
    /// "Rectangle, Rectangle, Label" becomes "Rectangle, Rectangle 2, Label".
    /// Display only: no layer is renamed.
    public static func distinctLabels(_ names: [String]) -> [String] {
        var seen: [String: Int] = [:]
        return names.map { name in
            let count = (seen[name] ?? 0) + 1
            seen[name] = count
            return count == 1 ? name : "\(name) \(count)"
        }
    }

    /// True for the name the grouping command minted ("Group", "Group 2"),
    /// which is a placeholder rather than a name anyone chose.
    public static func isAutoGroupName(_ name: String) -> Bool {
        isAutoName(name, stem: "Group")
    }

    /// True for a name the APP wrote rather than a person: "Group", "Group 2",
    /// "Text", "Text 2". Anything named this way tells a reader nothing, so
    /// nothing that has to be readable later should borrow it.
    public static func isPlaceholderLayerName(_ name: String) -> Bool {
        isAutoGroupName(name) || isAutoName(name, stem: TextBuilder.defaultLayerName)
    }

    /// "Stem", "Stem 2", "Stem 17": the shape every automatic name takes.
    private static func isAutoName(_ name: String, stem: String) -> Bool {
        guard name.hasPrefix(stem) else { return false }
        let tail = name.dropFirst(stem.count).trimmingCharacters(in: .whitespaces)
        return tail.isEmpty || Int(tail) != nil
    }
}
