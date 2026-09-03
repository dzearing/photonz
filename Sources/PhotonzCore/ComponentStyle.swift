import CoreGraphics
import Foundation

/// A copy follows its original's LOOK, part by part
/// (`docs/design/ui-building.md`, "A copy follows the original's look").
///
/// Step C5 kept a copy's contents equal to the original's but left its own
/// fade, blur, rounded corners, border and shadow alone, because writing the
/// original's look over a copy would snap an Effects slider back the moment it
/// was let go. This is the honest version of that: the look follows the same
/// way a knob's answer does, and anything set on the copy stays set.
///
/// The trick is one fact stored on the copy: the original's look **as of the
/// last time the two were put in step** (`GroupContent.followedStyle`). Any
/// part the copy's own look differs from that by is a part somebody set on the
/// copy, so it stays; every other part is taken from the original again. No
/// command has to announce that it styled a copy, which matters because the
/// styling paths are many (sliders, steppers, colour wells) and one that forgot
/// would silently snap back.

// MARK: - The parts of a look

/// One part of a layer's look, in the words the Effects and Shadow controls
/// use. A copy follows or owns its look one of these at a time, so fading a
/// copy does not stop it taking the shadow the original gains afterwards.
public enum LayerStyleField: String, Hashable, Sendable, CaseIterable, Codable {
    case opacity
    case blur
    case cornerRadius
    case border
    case borderColor
    case shadow
    case blendMode

    /// What this part is called where a person meets it: the label on the
    /// control that sets it.
    public var label: String {
        switch self {
        case .opacity: return "Opacity"
        case .blur: return "Blur"
        case .cornerRadius: return "Corner Radius"
        case .border: return "Border"
        case .borderColor: return "Border color"
        case .shadow: return "Shadow"
        case .blendMode: return "Blending"
        }
    }

    /// The order the controls appear in the dock, so a list of what a copy owns
    /// reads down the panel rather than at random.
    public var order: Int {
        switch self {
        case .opacity: return 0
        case .blur: return 1
        case .cornerRadius: return 2
        case .border: return 3
        case .borderColor: return 4
        case .shadow: return 5
        case .blendMode: return 6
        }
    }
}

extension LayerStyle {

    /// The parts two looks differ in.
    public static func differences(_ a: LayerStyle, _ b: LayerStyle) -> Set<LayerStyleField> {
        var fields: Set<LayerStyleField> = []
        if a.opacity != b.opacity { fields.insert(.opacity) }
        if a.blurRadius != b.blurRadius { fields.insert(.blur) }
        if a.cornerRadius != b.cornerRadius { fields.insert(.cornerRadius) }
        if a.borderWidth != b.borderWidth { fields.insert(.border) }
        if a.borderColorHex != b.borderColorHex { fields.insert(.borderColor) }
        if a.shadow != b.shadow { fields.insert(.shadow) }
        if a.blendMode != b.blendMode { fields.insert(.blendMode) }
        return fields
    }

    /// This look with one part taken from another. A shadow is one part: its
    /// softness, distance, direction, colour and opacity are five controls for
    /// the one thing a person means by "the shadow".
    public func taking(_ field: LayerStyleField, from other: LayerStyle) -> LayerStyle {
        var style = self
        switch field {
        case .opacity: style.opacity = other.opacity
        case .blur: style.blurRadius = other.blurRadius
        case .cornerRadius: style.cornerRadius = other.cornerRadius
        case .border: style.borderWidth = other.borderWidth
        case .borderColor: style.borderColorHex = other.borderColorHex
        case .shadow: style.shadow = other.shadow
        case .blendMode: style.blendMode = other.blendMode
        }
        return style
    }

    /// A copy's look after the original's has been laid under it: every part
    /// the copy has not set itself comes from the original.
    ///
    /// With no memory of the original — a copy saved before the look followed —
    /// the copy keeps exactly what it is drawing. Nothing on screen moves when
    /// such a document is opened; the memory is adopted instead, so whatever
    /// the copy already differed by becomes its own from then on.
    static func following(_ original: LayerStyle, own: LayerStyle,
                          lastSeen: LayerStyle?) -> LayerStyle {
        guard let lastSeen else { return own }
        let owned = differences(own, lastSeen)
        var merged = own
        for field in LayerStyleField.allCases where !owned.contains(field) {
            merged = merged.taking(field, from: original)
        }
        return merged
    }
}

// MARK: - What a copy owns, and putting it back

extension Layer {

    /// Which parts of THIS copy's look are its own rather than the original's:
    /// everything its look differs from the original's last-seen look by.
    /// Empty for anything that is not a copy, and for a copy that has never met
    /// its original.
    public var ownStyleFields: Set<LayerStyleField> {
        guard isComponentInstance, let lastSeen = group?.followedStyle else { return [] }
        return LayerStyle.differences(style, lastSeen)
    }
}

extension PhotonzDocument {

    /// Which parts of a copy's look are its own rather than the original's.
    /// This is what puts the revert control on an Effects row.
    public func instanceStyleOverrides(instance: UUID) -> Set<LayerStyleField> {
        layer(id: instance)?.ownStyleFields ?? []
    }

    /// Whether one part of a copy's look is its own.
    public func isInstanceStyleOwn(instance: UUID, field: LayerStyleField) -> Bool {
        instanceStyleOverrides(instance: instance).contains(field)
    }

    /// The parts a copy owns, in the order their controls sit in the dock.
    public func instanceStyleOverrideLabels(instance: UUID) -> [String] {
        instanceStyleOverrides(instance: instance)
            .sorted { $0.order < $1.order }
            .map(\.label)
    }

    /// Puts one part of a copy's look back to following the original.
    public mutating func clearInstanceStyleOverride(instance: UUID, field: LayerStyleField) {
        guard let copy = layer(id: instance), let componentID = copy.instanceOf,
              !copy.isLocked, let main = mainComponent(componentID: componentID) else { return }
        updateLayer(id: instance) { layer in
            layer.style = layer.style.taking(field, from: main.style)
        }
    }

    /// Puts a copy's whole look back to the original's.
    public mutating func clearInstanceStyleOverrides(instance: UUID) {
        guard let copy = layer(id: instance), let componentID = copy.instanceOf,
              !copy.isLocked, let main = mainComponent(componentID: componentID) else { return }
        updateLayer(id: instance) { $0.style = main.style }
    }
}
