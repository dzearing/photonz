import CoreGraphics
import Foundation

/// Pointing a copy already on the canvas at a DIFFERENT component.
///
/// Building a screen means trying things: this row wants a Primary Button
/// here and a Secondary one there. Before this, a copy was stuck being a copy
/// of the component it was made from, so changing your mind cost the copy —
/// delete it, drag the other one out of the Library, and type back every knob,
/// every size and every bit of room you had set. On a screen carrying twenty
/// copies nobody does that, so the layout stops being something you explore and
/// becomes something you commit to by accident.
///
/// Chosen by the user on 2026-09-20 answering "You put a Button on a screen and
/// set it up. Should you be able to point it at a different component without
/// starting over?" with **"A row in the panel that says which one it is"**: the
/// line in the Component section that already names the original becomes the
/// control that changes it.
///
/// ## What a copy keeps
///
/// One rule, everywhere: **a copy keeps what is its own and follows the new
/// original for everything else.** That is not a new rule invented for the
/// swap, it is the rule a copy already lives by, which is why the answer to
/// "what happened to my settings" is the same sentence before and after.
///
/// - Where it sits: its own. Kept.
/// - A size it was GIVEN by hand (`InstanceSize`): its own. Kept.
/// - A size it never set: the original's. It becomes the new original's — the
///   copy is refilled from that drawing and takes its box — so a badge does not
///   arrive stretched to the width of the button it replaced.
/// - A look it set for itself: its own. Kept, part by part, because
///   `followedStyle` still records what the old original looked like and
///   `LayerStyle.following` reads the difference (`syncComponentInstances`).
/// - A knob the new component also offers, matched by the name on the panel:
///   kept, with the value typed into it.
/// - A knob the new component does not offer: dropped, and SAID OUT LOUD by
///   name rather than lost quietly.
/// - The type it set for its own words (`ComponentPieceTextStyle`): dropped,
///   because those words belonged to pieces of the old original.
/// - Its name: the new component's, unless somebody named the copy themselves,
///   in which case the name they chose stands.

/// What one swap did, so the app can say it out loud.
public struct ComponentSwapReport: Hashable, Sendable {
    /// How many copies were pointed somewhere else.
    public var copies: Int
    /// What they follow now, so a notice can name it.
    public var component: String?
    /// How many typed-in knob answers carried over.
    public var keptKnobs: Int
    /// The knobs that did not, by the name they wore on the panel. Named
    /// rather than counted: "Label did not carry over" is something a person
    /// can act on, "1 setting was dropped" is something they have to go and
    /// find.
    public var droppedKnobs: [String]
    /// Whether the copy was also holding a type of its own for its words,
    /// which cannot follow it to a different drawing.
    public var droppedOwnType: Bool

    public init(copies: Int = 0, component: String? = nil, keptKnobs: Int = 0,
                droppedKnobs: [String] = [], droppedOwnType: Bool = false) {
        self.copies = copies
        self.component = component
        self.keptKnobs = keptKnobs
        self.droppedKnobs = droppedKnobs
        self.droppedOwnType = droppedOwnType
    }
}

/// One row of the menu the Component section's name opens: a component this
/// copy could be pointed at.
public struct ComponentSwapChoice: Hashable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    /// The one it follows now, which wears the tick and does nothing.
    public var isCurrent: Bool
    /// Whether picking it would work. False for a component that would end up
    /// holding itself — a copy of the Card living inside the Card draws
    /// forever — which is dimmed rather than hidden, so the list of components
    /// is the same list everywhere.
    public var canTake: Bool

    public init(id: UUID, name: String, isCurrent: Bool, canTake: Bool) {
        self.id = id
        self.name = name
        self.isCurrent = isCurrent
        self.canTake = canTake
    }
}

/// A knob as a person meets it: what it is called and what it sets. Two knobs
/// with this much in common are the same knob as far as a swap is concerned,
/// whichever component they belong to.
private struct ComponentKnobKey: Hashable {
    var name: String
    var kind: ComponentPropertyKind
    var slot: ColorSlot?
    var numberSlot: ComponentNumberSlot?

    init(_ property: ComponentProperty) {
        self.name = property.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.kind = property.kind
        self.slot = property.slot
        self.numberSlot = property.numberSlot
    }
}

extension PhotonzDocument {

    // MARK: - What the row offers

    /// Every component the picked copies could be pointed at, in the order a
    /// menu lists them.
    ///
    /// Empty unless the picked copies all follow ONE component: a row that
    /// says "which one is this" has no answer for a selection of several
    /// different ones, and the panel already says so in its own words.
    public func componentSwapChoices(instances: [UUID]) -> [ComponentSwapChoice] {
        let copies = instances.compactMap { layer(id: $0) }.filter { $0.isComponentInstance }
        guard copies.count == instances.count, !copies.isEmpty else { return [] }
        let following = Set(copies.compactMap(\.instanceOf))
        guard following.count == 1, let current = following.first else { return [] }

        let mains = mainComponents
        let names = Self.componentNames(from: mains)
        var seen: Set<UUID> = []
        var choices: [ComponentSwapChoice] = []
        for main in mains {
            guard let componentID = main.componentID, seen.insert(componentID).inserted else { continue }
            let name = names[componentID] ?? main.name
            choices.append(ComponentSwapChoice(
                id: componentID, name: name, isCurrent: componentID == current,
                canTake: componentID != current
                    && instances.allSatisfy { canSwapInstance($0, to: componentID) }))
        }
        return choices.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Whether one copy could be pointed at this component.
    ///
    /// The refusal that matters is the one that draws forever: a copy living
    /// inside the Card cannot become a copy of the Card. It is the same check
    /// a drop from the Library makes, asked about where the copy already sits,
    /// so the menu and the act can never disagree.
    public func canSwapInstance(_ id: UUID, to componentID: UUID) -> Bool {
        guard let copy = layer(id: id), let current = copy.instanceOf, !copy.isLocked,
              current != componentID, mainComponent(componentID: componentID) != nil
        else { return false }
        return canInsertInstance(of: componentID, intoGroup: parentID(of: id))
    }

    // MARK: - Doing it

    /// Points every picked copy at `componentID`, in one step, and says what
    /// carried over and what did not.
    ///
    /// Nil when nothing happened at all — nothing picked was a copy it could
    /// reach, or they already follow that component — so a caller can tell a
    /// refusal from an edit without comparing documents.
    @discardableResult
    public mutating func swapComponentInstances(ids: [UUID], to componentID: UUID)
        -> ComponentSwapReport? {
        guard let newMain = mainComponent(componentID: componentID) else { return nil }
        var report = ComponentSwapReport(component: newMain.name)
        for id in ids where canSwapInstance(id, to: componentID) {
            swapOne(id, to: componentID, into: &report)
        }
        guard report.copies > 0 else { return nil }
        // The drops are said once however many copies were carrying the same
        // knob, because "Label did not carry over" is one fact about the swap.
        var seen: Set<String> = []
        report.droppedKnobs = report.droppedKnobs.filter { seen.insert($0).inserted }
        syncComponentInstances()
        return report
    }

    private mutating func swapOne(_ id: UUID, to componentID: UUID,
                                  into report: inout ComponentSwapReport) {
        guard let copy = layer(id: id), let oldComponent = copy.instanceOf,
              let oldMain = mainComponent(componentID: oldComponent,
                                          version: copy.instanceVersionID),
              let newMain = mainComponent(componentID: componentID) else { return }

        // Worked out against the OLD original, before anything is rewritten.
        let carried = carriedKnobs(of: copy, from: oldMain, to: newMain)
        let hadOwnType = !(copy.group?.pieceTextStyles ?? []).isEmpty
        let wasNamedAfterItsOriginal = copy.name == oldMain.name

        updateLayer(id: id) { layer in
            guard var group = layer.group else { return }
            group.instanceOf = componentID
            group.instanceVersion = newMain.componentVersionID
            // Every answer is re-applied below against the new original, which
            // is the only thing that can say whether it fits.
            group.overrides = []
            // The type this copy set for its own words named pieces of the old
            // drawing, which are not in this one.
            group.pieceTextStyles = []
            // `followedStyle` is deliberately left holding the OLD original's
            // look: the next sync reads it to tell what this copy styled for
            // itself from what it was merely inheriting, and only the first of
            // those is the copy's to keep.
            group.children = layer.children
            layer.content = .group(group)
            // A copy nobody renamed is called after what it is, so it goes on
            // being called after what it is. A name somebody typed is theirs.
            if wasNamedAfterItsOriginal { layer.name = newMain.name }
        }

        for knob in carried {
            if setInstanceOverride(instance: id, property: knob.property, value: knob.value) {
                report.keptKnobs += 1
            } else {
                report.droppedKnobs.append(knob.name)
            }
        }
        report.copies += 1
        report.droppedOwnType = report.droppedOwnType || hadOwnType
    }

    /// One knob answer on its way across: where it lands on the new original,
    /// and what it was called on the old one so a drop can be named.
    private struct CarriedKnob {
        var property: UUID
        var value: ComponentPropertyValue
        var name: String
    }

    /// The copy's typed-in answers, matched onto the new original's knobs by
    /// the name on the panel.
    ///
    /// By NAME rather than by position or by the piece it reaches, because the
    /// name is the only thing the two components share: a Label on a Button and
    /// a Label on a Chip are different layers in different drawings, and the
    /// person who typed "Save" into one means "Save" in the other. Everything
    /// that does not match is returned as a drop, so nothing goes quietly.
    private func carriedKnobs(of copy: Layer, from oldMain: Layer,
                              to newMain: Layer) -> [CarriedKnob] {
        let newByKey = Dictionary(newMain.componentProperties.map { (ComponentKnobKey($0), $0) },
                                  uniquingKeysWith: { first, _ in first })
        var carried: [CarriedKnob] = []
        for override in copy.componentOverrides {
            guard let old = oldMain.componentProperties.first(where: { $0.id == override.property })
            else { continue }   // a knob the old original no longer has: already dead
            guard let new = newByKey[ComponentKnobKey(old)] else {
                carried.append(CarriedKnob(property: UUID(), value: override.value, name: old.name))
                continue
            }
            guard let value = value(override.value, from: old, on: oldMain,
                                    to: new, on: newMain) else {
                carried.append(CarriedKnob(property: UUID(), value: override.value, name: old.name))
                continue
            }
            carried.append(CarriedKnob(property: new.id, value: value, name: old.name))
        }
        return carried
    }

    /// One answer as the new knob would hold it.
    ///
    /// Everything but a choice travels as it is: words are words, a colour is a
    /// colour. A CHOICE is the id of one alternative inside the old drawing,
    /// which means nothing in the new one, so it travels by the alternative's
    /// name — "Filled" on one component becomes "Filled" on the other — and
    /// does not travel at all when there is no such alternative.
    private func value(_ value: ComponentPropertyValue,
                       from old: ComponentProperty, on oldMain: Layer,
                       to new: ComponentProperty, on newMain: Layer) -> ComponentPropertyValue? {
        guard case .variant(let option) = value else { return value }
        guard let chosen = oldMain.selfAndDescendants.first(where: { $0.id == old.target })?
            .children.first(where: { $0.id == option }),
              let match = newMain.selfAndDescendants.first(where: { $0.id == new.target })?
                .children.first(where: { $0.name == chosen.name })
        else { return nil }
        return .variant(match.id)
    }
}
