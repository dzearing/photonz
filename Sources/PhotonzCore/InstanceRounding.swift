import CoreGraphics
import Foundation

/// How round a COPY is, and which control says so.
///
/// A copy of a Save button showed the number twice and the two disagreed:
/// Appearance read Corner Radius 0 with its slider at the far left while the
/// Component section under it read Corner radius 18, and the button on the
/// canvas was plainly round (found 2026-09-09).
///
/// Both numbers were true, of different layers. Appearance was reading the
/// copy's OWN outer mask; the knob turns the rounded rectangle inside it. The
/// outer mask is the one nobody can see: a component that keeps any room inside
/// its edges holds everything it draws in off them, so a curve cut at the
/// copy's own boundary passes through empty space. A row reading nought over a
/// round button is the panel denying the picture beside it, which is the very
/// thing the one Corner Radius row was built to stop
/// (`CornerRadiusSelection.swift`).
///
/// So the rule is the one the Layout section already follows: the panel leaves
/// out whatever the Component section under it already hands over
/// (`numberKnobsOnTheCopyItself`). A copy whose original exposes a rounding is
/// rounded by that knob, in the words its author chose, and Appearance says so
/// once instead of offering a second number.
///
/// A copy whose original exposes NO rounding keeps the ordinary row: then the
/// outer mask is the only rounding on offer and nothing else is claiming the
/// number.
extension PhotonzDocument {

    /// The knobs that decide how round this copy is: the rounding knobs its
    /// original exposes, named as the author named them, in the order the
    /// original lists them.
    ///
    /// Empty for anything that is not a copy. A rounding knob always reaches a
    /// piece INSIDE the original, never its outermost layer, because rounding
    /// is not on the short list a component may offer on its own edges
    /// (`ComponentNumberSlot.onTheComponentItself`).
    public func roundingKnobNames(instance: UUID) -> [String] {
        instanceProperties(instance: instance)
            .filter { $0.kind == .number && $0.numberSlot == .cornerRadius }
            .map(\.name)
    }

    /// Whether a Corner Radius row over this layer would be a SECOND number for
    /// a roundness the Component section already hands over.
    public func roundingIsAKnob(layerID: UUID) -> Bool {
        !roundingKnobNames(instance: layerID).isEmpty
    }

    /// The one line the panel says where the row would have been, or nil when
    /// nothing was left out.
    ///
    /// A row that simply vanishes is a hole: somebody who rounded a copy
    /// yesterday comes back for the slider and finds nothing where it was. So
    /// the section names the control that owns the number and where to find it,
    /// the way the Layout section names Edit Original.
    public func instanceRoundingNote(layerIDs: [UUID]) -> String? {
        let skipped = layerIDs.filter { roundingIsAKnob(layerID: $0) }
        guard let first = skipped.first else { return nil }
        let names = roundingKnobNames(instance: first)
        let sameEverywhere = skipped.dropFirst()
            .allSatisfy { roundingKnobNames(instance: $0) == names }
        let ending = "in the Component section below."
        guard sameEverywhere else {
            // Copies of different components, each with a rounding of its own
            // name. Naming all of them would be a list nobody reads, and naming
            // one would be a claim about the others.
            return "These copies are rounded by knobs their originals set up, \(ending)"
        }
        let knob = names.count == 1 ? "knob" : "knobs"
        let listed = ComponentVersionApply.list(names)
        return skipped.count == 1
            ? "This copy is rounded by its \(listed) \(knob), \(ending)"
            : "These copies are rounded by their \(listed) \(knob), \(ending)"
    }
}
