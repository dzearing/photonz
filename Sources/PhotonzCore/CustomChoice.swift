import Foundation

// A menu that says Custom lets you pick Custom
// (task `a-menu-that-says-custom-lets-you-get-back-to-cus`).
//
// Several menus offer a short list of named values and print "Custom" (or
// "Drawn") when the value is one of your own: Around on a turn, the Curve menus,
// and the size lists in New Frame, New Canvas and New Video. Until 2026-10-02
// none of them would let you pick that word: open Around to see what Top centre
// looks like, take it, and the point you had dragged was gone unless you
// dragged it again. A menu that prints a value has to let you choose it.
//
// The one answer, used by every one of those menus: the menu KEEPS the last
// value of your own it moved away from, and picking Custom puts it back.

/// The value of your own a menu of named values keeps, so its Custom row is a
/// choice rather than a word.
public struct CustomChoice<Value: Equatable & Sendable>: Equatable, Sendable {
    /// The last value of your own, or nil when there has not been one.
    public private(set) var kept: Value?

    public init(kept: Value? = nil) {
        self.kept = kept
    }

    /// Keeps `value` when it is your own. A named value is never kept: the
    /// list already has it.
    public mutating func keep(_ value: Value, isOwn: Bool) {
        if isOwn { kept = value }
    }

    /// The value moved from `old` to `new`. Whichever of them is your own is
    /// kept, the newer winning, so leaving your own value for a named one is
    /// exactly the moment it is remembered.
    public mutating func change(from old: Value, oldIsOwn: Bool, to new: Value, newIsOwn: Bool) {
        keep(old, isOwn: oldIsOwn)
        keep(new, isOwn: newIsOwn)
    }

    /// What picking Custom sets: the value showing, when it is already your
    /// own, else the one kept. Nil when there is nothing of your own to go back
    /// to, and then the menu has no Custom to offer.
    public func custom(current: Value, currentIsOwn: Bool) -> Value? {
        currentIsOwn ? current : kept
    }
}

extension CustomChoice: Hashable where Value: Hashable {}
extension CustomChoice: Codable where Value: Codable {}

extension MotionPivot {
    /// True where the pivot is somewhere of its own rather than on one of the
    /// spots the Around menu names.
    public var isOwn: Bool { named == nil }
}

extension LayerMotion {

    /// This motion after an edit, still keeping the pivot and the curve of
    /// your own it had before the edit (`CustomChoice`). Every edit to a
    /// motion passes through here, so whichever door changed the value (the
    /// menu, the crosshair, the two numbers, the curve editor) leaving your own
    /// value behind is never the end of it.
    public func keepingOwnValues(of before: LayerMotion) -> LayerMotion {
        var made = self
        var pivots = CustomChoice(kept: ownPivot ?? before.ownPivot)
        pivots.change(from: before.turnsAbout, oldIsOwn: before.turnsAbout.isOwn,
                      to: turnsAbout, newIsOwn: turnsAbout.isOwn)
        made.ownPivot = property == .rotation ? pivots.kept : nil
        var curves = CustomChoice(kept: ownCurve ?? before.ownCurve)
        curves.change(from: before.curve, oldIsOwn: before.curve.isDrawn,
                      to: curve, newIsOwn: curve.isDrawn)
        made.ownCurve = curves.kept
        return made
    }

    /// What the Around menu's Custom puts the pivot on, or nil when this turn
    /// has never been anywhere of its own.
    public var customPivot: MotionPivot? {
        CustomChoice(kept: ownPivot).custom(current: turnsAbout, currentIsOwn: turnsAbout.isOwn)
    }

    /// What the Curve menu's Drawn puts back, or nil when no curve has been
    /// drawn for this motion.
    public var customCurve: EasingCurve? {
        CustomChoice(kept: ownCurve).custom(current: curve, currentIsOwn: curve.isDrawn)
    }
}
