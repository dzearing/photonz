import Foundation

/// A component has PROPERTIES, and the looks it holds are one of them
/// (asked for by the user on 2026-09-15: "Variant is a property of the
/// component").
///
/// The panel used to split one idea in two. An "Adjustable" list held the knobs
/// a copy may set, and a "Versions" list held the drawings a copy may show, so
/// somebody meeting a component was asked to learn two words this app invented
/// for two halves of the same thing. They are one list: **Properties**. A
/// property is anything a copy can be given its own answer for, and a
/// **variant** is the kind of property whose answer picks which drawing of the
/// component the copy shows.
///
/// ### Why this is a list
///
/// A real button wants a Type of primary or secondary AND a State of rest or
/// hovered before long, so nothing may assume a component has exactly one
/// look-changing property. Today it holds at most one — the drawings a
/// component has are a flat list, so there is one question to ask about them —
/// and everything that reads this reads a list, so a second one is an addition
/// rather than a rewrite.
///
/// When a second one arrives, the drawings stay a flat list and each one
/// carries an answer per variant property. A combination nobody drew falls back
/// to the nearest one that was, which is what keeps Type × State × Size from
/// meaning twenty-four drawings somebody has to make by hand.
///
/// The drawings themselves are still `ComponentVersion` in the code, and the
/// group still writes `versionID` and `versionName` to the file, because those
/// are what a document saved yesterday holds. **Version is the old spelling of
/// the word; nowhere a person can read it says version.**
public struct ComponentVariantProperty: Hashable, Sendable, Identifiable {
    /// Its identity. A component holds at most one of these today, so this is
    /// the component's own id; when a component can hold several this becomes
    /// the property's own.
    public var id: UUID
    /// What the row is called on the panel: "Variant" until the author calls it
    /// State, or Type, or Size.
    public var name: String
    /// The looks it chooses between, in the order the canvas holds them. Always
    /// two or more: one look is not a choice.
    public var options: [ComponentVersion]

    public init(id: UUID, name: String, options: [ComponentVersion]) {
        self.id = id
        self.name = name
        self.options = options
    }
}

extension Layer {

    /// What the variant property of this main's component is called, nil on a
    /// component nobody has renamed it on.
    public var componentVariantName: String? { group?.variantName }
}

// MARK: - Reading it

extension PhotonzDocument {

    /// The variant properties of a component: none while it holds one drawing,
    /// one the moment it holds two.
    ///
    /// A component with a single look has nothing to choose between, so there
    /// is no property and the panel shows none. That is what keeps a plain
    /// component's panel the panel it always was rather than a menu with one
    /// item in it.
    public func componentVariantProperties(of componentID: UUID) -> [ComponentVariantProperty] {
        let options = componentVersions(of: componentID)
        guard options.count > 1 else { return [] }
        return [ComponentVariantProperty(id: componentID,
                                         name: componentVariantName(of: componentID),
                                         options: options)]
    }

    /// What this component's variant property is called, falling back to the
    /// word the panel starts it at.
    ///
    /// Read off whichever drawing carries it, because every drawing carries the
    /// same answer and the one it was typed on may since have been deleted.
    public func componentVariantName(of componentID: UUID) -> String {
        for main in mainComponents where main.componentID == componentID {
            if let name = ComponentNaming.normalized(main.componentVariantName) { return name }
        }
        return ComponentNaming.defaultVariantPropertyName
    }

    // MARK: - Naming it

    /// Calls this component's variant property something else — State, Type,
    /// Size. Answers false, changing nothing, for a blank name or for a
    /// component that has no variant property to name.
    ///
    /// Written to EVERY drawing of the component, so the name outlives the
    /// drawing it was typed on.
    @discardableResult
    public mutating func renameComponentVariantProperty(of componentID: UUID,
                                                        to name: String) -> Bool {
        guard let chosen = ComponentNaming.normalized(name) else { return false }
        guard componentVersions(of: componentID).count > 1 else { return false }
        guard chosen != componentVariantName(of: componentID) else { return false }
        var changed = false
        for main in mainComponents where main.componentID == componentID {
            updateLayer(id: main.id) { layer in
                guard var group = layer.group else { return }
                group.variantName = chosen
                layer.content = .group(group)
                changed = true
            }
        }
        return changed
    }
}

// MARK: - What it is called before anybody names it

extension ComponentNaming {

    /// What the looks a component holds are asked about before the author says
    /// otherwise. One word, the one every design tool uses, and a noun for a
    /// thing rather than an adjective for a quality.
    public static let defaultVariantPropertyName = "Variant"
}
