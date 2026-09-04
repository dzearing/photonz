import CoreGraphics
import Foundation

/// Setting a colour knob on copies, and reading what a row over several of them
/// should say (`docs/design/ui-building.md`, step C6).
///
/// Everything here is a thin layer over the knob model in
/// `ComponentProperties.swift` and the colour model in `ColorStyles.swift`. It
/// exists so a colour row on a copy's panel is answered by exactly the same
/// type a colour row on the canvas is answered by: `ColorStyleSelection` does
/// the agreeing, the naming and the Mixed, so the two can never say a colour
/// differs in one place and agrees in the other.

extension PhotonzDocument {

    /// The colour knob behind an id, when that is what it is.
    func colorKnob(instance: UUID, property propertyID: UUID) -> (componentID: UUID,
                                                                  property: ComponentProperty,
                                                                  slot: ColorSlot)? {
        guard let componentID = layer(id: instance)?.instanceOf,
              let property = componentProperty(componentID: componentID, propertyID: propertyID),
              property.kind == .color, let slot = property.slot else { return nil }
        return (componentID, property, slot)
    }

    /// Which colour a knob paints, for a panel that has to say so.
    public func componentColorSlot(instance: UUID, property propertyID: UUID) -> ColorSlot? {
        colorKnob(instance: instance, property: propertyID)?.slot
    }

    /// What a copy shows for a colour knob, with a saved colour resolved to
    /// what it paints today. Nil when the knob is not a colour, or the original
    /// has no colour there any more.
    public func instanceColor(instance: UUID,
                              property propertyID: UUID) -> ComponentColorAnswer? {
        guard let knob = colorKnob(instance: instance, property: propertyID),
              let answer = instanceValue(instance: instance, property: propertyID)?.colorValue
        else { return nil }
        return resolvedColorAnswer(answer, slot: knob.slot)
    }

    /// What one colour row on a copy's panel shows, however many copies it
    /// speaks for.
    ///
    /// It is a `ColorStyleSelection`, the same value the Fill row over a canvas
    /// selection is, so the agreeing, the naming of a saved colour and the word
    /// Mixed are all decided in one place. Copies keep the order they are given,
    /// which is the order the panel lists them.
    public func componentColorSelection(instances: [UUID],
                                        property propertyID: UUID) -> ColorStyleSelection {
        guard let first = instances.first,
              let knob = colorKnob(instance: first, property: propertyID) else {
            return ColorStyleSelection(slot: .fill, members: [],
                                       selectionCount: instances.count, capableCount: 0)
        }
        let members = instances.compactMap { id -> ColorStyleSelection.Member? in
            guard let copy = layer(id: id), !copy.isLocked,
                  copy.instanceOf == knob.componentID,
                  let answer = instanceColor(instance: id, property: propertyID) else { return nil }
            return ColorStyleSelection.Member(id: id, paint: answer.paint, styleID: answer.styleID)
        }
        // A copy of a DIFFERENT component has no such knob at all, so it is not
        // a copy this row left out; one that is locked is.
        let capable = instances.filter { layer(id: $0)?.instanceOf == knob.componentID }
        return ColorStyleSelection(slot: knob.slot, members: members,
                                   selectionCount: instances.count, capableCount: capable.count)
    }

    /// Gives copies a colour of their own. Returns how many took it, so a
    /// caller can tell a no-op from an edit.
    @discardableResult
    public mutating func setInstanceColor(instances: [UUID], property propertyID: UUID,
                                          answer: ComponentColorAnswer) -> Int {
        var count = 0
        for id in instances
        where setInstanceOverride(instance: id, property: propertyID, value: .color(answer)) {
            count += 1
        }
        return count
    }

    /// Points copies' knob at a saved colour, so editing that colour later
    /// moves every one of them. Returns how many took it.
    ///
    /// The colour is written alongside the name for the same reason a layer
    /// writes it: nothing downstream has to know what a style is, and the day
    /// the name is deleted the copy is already wearing the right colour.
    @discardableResult
    public mutating func setInstanceColorStyle(instances: [UUID], property propertyID: UUID,
                                               styleID: UUID) -> Int {
        guard let first = instances.first,
              let knob = colorKnob(instance: first, property: propertyID),
              let style = colorStyle(id: styleID) else { return 0 }
        return setInstanceColor(instances: instances, property: propertyID,
                                answer: ComponentColorAnswer(paint: style.paint(for: knob.slot),
                                                             styleID: styleID))
    }

    /// Lets copies' knob go back to being a colour of its own, keeping exactly
    /// the colour it is wearing. The way out of a saved name that does NOT put
    /// the copy back on the original, which is what Revert is for.
    @discardableResult
    public mutating func unlinkInstanceColorStyle(instances: [UUID],
                                                  property propertyID: UUID) -> Int {
        var count = 0
        for id in instances {
            guard let answer = instanceColor(instance: id, property: propertyID),
                  answer.styleID != nil else { continue }
            if setInstanceOverride(instance: id, property: propertyID,
                                   value: .color(ComponentColorAnswer(paint: answer.paint))) {
                count += 1
            }
        }
        return count
    }

    /// Every colour knob in the document, by id, with the part it paints. The
    /// answers on a copy know only the knob's id, so this is how a style edit
    /// works out which paint each answer should be given.
    var componentColorKnobSlots: [UUID: ColorSlot] {
        var slots: [UUID: ColorSlot] = [:]
        for main in mainComponents {
            for property in main.componentProperties where property.kind == .color {
                if let slot = property.slot { slots[property.id] = slot }
            }
        }
        return slots
    }
}

extension Layer {

    /// Runs every colour answer this layer holds through a change, and keeps
    /// the ones it hands back. Nothing else about the layer is touched, and a
    /// layer holding no answers costs one check.
    mutating func updateColorAnswers(
        _ change: (UUID, ComponentColorAnswer) -> ComponentColorAnswer?
    ) {
        guard var content = group, !content.overrides.isEmpty else { return }
        var changed = false
        for index in content.overrides.indices {
            guard case .color(let answer) = content.overrides[index].value,
                  let next = change(content.overrides[index].property, answer),
                  next != answer else { continue }
            content.overrides[index].value = .color(next)
            changed = true
        }
        if changed { self.content = .group(content) }
    }
}
