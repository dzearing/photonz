import Foundation

/// What the Component section shows when several copies are picked at once
/// (`docs/design/mocks/shared/UX-PATTERNS.md` §4, "What a control DOES for
/// several picked things").
///
/// Picking a second copy used to take the whole section off the panel, so
/// setting five buttons meant setting them one at a time. The rule says
/// disappearing is only ever the answer for "none of the picked things has this
/// property at all": both copies have knobs, the panel reaches both, so it stays
/// and speaks for them.
///
/// It is deliberately the same shape as `ColorStyleSelection`: the reading, the
/// count it reaches and the count that was picked all live in one value, so a
/// row can say what it reaches and a caption can say what it left out without
/// either of them working it out again.

/// What one knob row shows for the copies it speaks for.
public enum ComponentKnobReading: Hashable, Sendable {
    /// There is nothing to show: no copy this row reaches has an answer.
    case none
    /// Every copy it reaches shows this.
    case agreed(ComponentPropertyValue)
    /// They differ, so the row says `Mixed` in the value's own place.
    case mixed

    /// Whether the copies disagree, which is what puts the word in the control.
    public var isMixed: Bool { self == .mixed }

    /// The answer they share, when they share one.
    public var value: ComponentPropertyValue? {
        if case .agreed(let value) = self { return value }
        return nil
    }

    /// The words they share. Nil when they differ, and when the knob is not a
    /// wording knob at all.
    public var textValue: String? { value?.textValue }

    /// Whether they all show it. Nil when they differ.
    public var boolValue: Bool? { value?.boolValue }

    /// The one shape they all show. Nil when they differ.
    public var optionValue: UUID? { value?.optionValue }
}

/// The copies one Component section speaks for, and what each knob reads
/// across them.
public struct ComponentKnobSelection: Hashable, Sendable {

    /// The one original every picked copy follows. Nil when the picked copies
    /// come from more than one original, and when nothing picked is a copy.
    public let componentID: UUID?
    /// What that original is called, which is the heading the section wears.
    public let componentName: String
    /// The picked copies this section actually sets, in the order they were
    /// given. A locked copy is not one of them: a command aimed at the copies
    /// beside it must not reach in.
    public let instances: [UUID]
    /// How many layers are picked altogether, so the section can say what it
    /// does and does not reach.
    public let selectionCount: Int
    /// How many picked layers are copies of this original at all, locked ones
    /// counted.
    public let capableCount: Int
    /// The knobs the original exposes, in the order it lists them.
    public let properties: [ComponentProperty]
    /// The knobs at least one picked copy has answered for itself, which is
    /// what puts the way back on a row.
    public let overriddenProperties: Set<UUID>
    /// Whether the picked copies come from more than one original. Then there
    /// is no knob they share, and the section says so rather than going blank.
    public let hasDifferentComponents: Bool
    /// Every version the component holds, which is the menu on the Version row.
    /// One version is not a choice, so the row is only worth showing while this
    /// has two or more in it (`ComponentVersions`).
    public let versions: [ComponentVersion]
    /// The version every picked copy is showing. Nil when they show different
    /// ones, which is what puts Mixed in the Version row.
    public let version: UUID?

    private let readings: [UUID: ComponentKnobReading]

    public init(componentID: UUID?, componentName: String, instances: [UUID],
                selectionCount: Int, capableCount: Int, properties: [ComponentProperty],
                overriddenProperties: Set<UUID>, hasDifferentComponents: Bool,
                readings: [UUID: ComponentKnobReading],
                versions: [ComponentVersion] = [], version: UUID? = nil) {
        self.versions = versions
        self.version = version
        self.componentID = componentID
        self.componentName = componentName
        self.instances = instances
        self.selectionCount = selectionCount
        self.capableCount = capableCount
        self.properties = properties
        self.overriddenProperties = overriddenProperties
        self.hasDifferentComponents = hasDifferentComponents
        self.readings = readings
    }

    /// The empty answer: nothing picked is a copy, so there is no section.
    public static let none = ComponentKnobSelection(
        componentID: nil, componentName: "", instances: [], selectionCount: 0,
        capableCount: 0, properties: [], overriddenProperties: [],
        hasDifferentComponents: false, readings: [:])

    public var count: Int { instances.count }

    public var isEmpty: Bool { instances.isEmpty }

    /// Whether the section belongs on the panel at all: something picked is a
    /// copy, even when the picked copies have no knob in common.
    public var isPresent: Bool { !isEmpty || hasDifferentComponents }

    /// What one knob reads across the copies.
    public func reading(_ propertyID: UUID) -> ComponentKnobReading {
        readings[propertyID] ?? .none
    }

    /// Whether the Version row belongs on the panel: the component holds more
    /// than one drawing of itself, so which one this copy shows is a choice.
    public var hasVersions: Bool { versions.count > 1 }

    /// Whether the picked copies show different versions, which is what puts
    /// Mixed in the Version row.
    public var hasMixedVersions: Bool { hasVersions && version == nil }

    /// Whether a knob is one at least one picked copy has answered for itself.
    public func isOverridden(_ propertyID: UUID) -> Bool {
        overriddenProperties.contains(propertyID)
    }

    /// The line under the section when it speaks for fewer than the layers that
    /// are picked: how many it reaches, in words. Nil when it reaches them all,
    /// which is the ordinary case and needs no small print.
    public var reachNote: String? {
        guard !instances.isEmpty, instances.count < selectionCount else { return nil }
        let are = count == 1 ? "is a copy" : "are copies"
        let those = count == 1 ? "that one" : "those"
        return "\(count) of the \(selectionCount) selected layers \(are) of \(componentName). "
            + "The knobs below change \(those)."
    }

    /// What the section says when the picked copies come from different
    /// originals. Two knobs that merely share a name are two knobs, so a row
    /// averaging them would be inventing a control neither original has.
    public static let differentComponentsNote =
        "These copies come from different components. "
        + "Pick copies of one component to set their knobs together."
}

extension PhotonzDocument {

    /// What the Component section shows for the layers picked: the copies it
    /// speaks for, the knobs their original exposes, and what each knob reads
    /// across them.
    ///
    /// Layers that are not copies at all are not copies that disagree, so they
    /// are counted and otherwise left alone: a rectangle picked beside two
    /// buttons does not empty the section, it only makes it say it is speaking
    /// for two of the three.
    public func componentKnobSelection(layerIDs: [UUID]) -> ComponentKnobSelection {
        let copies = layerIDs.filter { layer(id: $0)?.instanceOf != nil }
        var origins: [UUID] = []
        for id in copies {
            guard let componentID = layer(id: id)?.instanceOf else { continue }
            if !origins.contains(componentID) { origins.append(componentID) }
        }
        guard let componentID = origins.first else { return .none }
        guard origins.count == 1 else {
            return ComponentKnobSelection(
                componentID: nil, componentName: "", instances: [],
                selectionCount: layerIDs.count, capableCount: copies.count, properties: [],
                overriddenProperties: [], hasDifferentComponents: true, readings: [:])
        }
        let instances = copies.filter { layer(id: $0)?.isLocked == false }
        let versions = componentVersions(of: componentID)
        // The version they all show, or none when they differ.
        let shown = Set(instances.compactMap { instanceVersion(of: $0) })
        let version = shown.count == 1 ? shown.first : nil
        // The knobs of the version they are showing. Copies on DIFFERENT
        // versions keep only the knobs every one of those versions has, so a
        // row on this panel is never a row one of the picked copies has no
        // answer for.
        // In the component's own order, so a panel speaking for copies on two
        // versions lists the same rows in the same order every time.
        let ordered = versions.map(\.id).filter { shown.contains($0) }
        var properties = componentProperties(of: componentID, version: version ?? ordered.first)
        if version == nil, ordered.count > 1 {
            for other in ordered.dropFirst() {
                let ids = Set(componentProperties(of: componentID, version: other).map(\.id))
                properties.removeAll { !ids.contains($0.id) }
            }
        }
        var readings: [UUID: ComponentKnobReading] = [:]
        var overridden: Set<UUID> = []
        for property in properties {
            readings[property.id] = knobReading(property, over: instances)
            if instances.contains(where: {
                instanceOverrides(instance: $0).contains(property.id)
            }) {
                overridden.insert(property.id)
            }
        }
        return ComponentKnobSelection(
            componentID: componentID,
            componentName: mainComponent(componentID: componentID)?.name ?? "",
            instances: instances, selectionCount: layerIDs.count, capableCount: copies.count,
            properties: properties, overriddenProperties: overridden,
            hasDifferentComponents: false, readings: readings,
            versions: versions, version: version)
    }

    /// What one knob reads over the copies: the answer they share, or Mixed.
    private func knobReading(_ property: ComponentProperty,
                             over instances: [UUID]) -> ComponentKnobReading {
        var shared: ComponentPropertyValue?
        for id in instances {
            guard let value = instanceValue(instance: id, property: property.id) else { continue }
            guard let seen = shared else { shared = value; continue }
            if seen != value { return .mixed }
        }
        return shared.map { .agreed($0) } ?? .none
    }

    /// Sets one knob on every copy given, in one step. Returns how many took
    /// it, so a caller can tell a no-op from an edit and a caption can say how
    /// far the set reached.
    @discardableResult
    public mutating func setInstanceOverride(instances: [UUID], property propertyID: UUID,
                                             value: ComponentPropertyValue) -> Int {
        var count = 0
        for id in instances
        where setInstanceOverride(instance: id, property: propertyID, value: value) {
            count += 1
        }
        return count
    }

    /// Puts one knob back to following the original on every copy given, in one
    /// step. Returns how many had something to put back.
    @discardableResult
    public mutating func clearInstanceOverride(instances: [UUID],
                                               property propertyID: UUID) -> Int {
        var count = 0
        for id in instances where instanceOverrides(instance: id).contains(propertyID) {
            clearInstanceOverride(instance: id, property: propertyID)
            count += 1
        }
        return count
    }
}
