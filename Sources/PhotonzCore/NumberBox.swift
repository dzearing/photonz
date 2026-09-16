import CoreGraphics
import Foundation

/// The rules of the one number box, wherever a number is typed into a panel.
///
/// `NumberFieldEntry` next door says what each KEY means. This says what the
/// box does with what is in it, which is the part every panel used to work out
/// on its own: three boxes were written before this one and each learned a
/// different lesson the hard way, so a fourth panel needing a number inherits
/// the answers here instead of rediscovering them.
///
/// The four questions, and the answers that are now the same everywhere:
///
/// - **The thing can refuse part of what you typed.** A text box will not go
///   below its words, a start time will not go below zero. The box shows what
///   was TAKEN, not what was asked for, or the next arrow key steps from a
///   number nothing has. That is why landing hands a value back rather than
///   just doing something.
/// - **Several things can disagree.** Then the box stands in with the word
///   Mixed, drawn where its value goes, at the one strength every other Mixed
///   in the dock uses. A stand-in that names a real state instead ("Spread",
///   or the four sides written out) is a value and is drawn like one.
/// - **Emptying it means different things.** A limit cleared is no limit; a
///   gap cleared is not a thing. Which one it is, is a property of the box the
///   panel sets once, and clearing never happens while the box is only
///   standing in for values that disagree, because there is no one value there
///   to take away.
/// - **The arrow keys.** One, or ten with Shift, from the WHOLE number that is
///   on screen, so holding the key walks 296, 297, 298 rather than drifting on
///   a fraction the box never showed.
public enum NumberBox {

    /// What the box has in it when nobody is typing.
    ///
    /// The difference between an empty box and a box standing in for several
    /// values that disagree is load bearing: they look similar and they answer
    /// Return, an arrow key and an empty draft differently.
    public enum Showing: Equatable, Sendable {
        /// One number, already spelled the way this panel spells it, unit mark
        /// and all.
        case number(String)
        /// No one number to show, and a word or a list standing in its place.
        case standIn(String)
        /// No number and nothing standing in for one: room to type in.
        case nothing

        /// What is actually drawn in the box.
        public var text: String {
            switch self {
            case .number(let text), .standIn(let text): text
            case .nothing: ""
            }
        }

        public var isStandIn: Bool {
            if case .standIn = self { return true }
            return false
        }

        /// Whether this is the quieter word rather than a value. Read off the
        /// stand-in itself, so there is no second flag that can disagree with
        /// what is on screen.
        public var isMixed: Bool {
            if case .standIn(let text) = self { return text == MixedValue.text }
            return false
        }

        /// Whether what stands in is made of numbers — four sides written out
        /// rather than a word. A box holding those has to be wide enough for
        /// them.
        public var standsInForNumbers: Bool {
            guard case .standIn(let text) = self else { return false }
            return text.contains(where: \.isNumber)
        }
    }

    /// One whole number, or the words standing in for several that disagree.
    ///
    /// The shape most panels are in: they hold a number they may not have, and
    /// a word for the times they do not. An empty stand-in means the box is
    /// simply empty, which is a different thing from standing in for values
    /// that disagree.
    public static func showing(_ value: CGFloat?, standingIn standIn: String) -> Showing {
        if let value { return .number(String(Int(value.rounded()))) }
        return standIn.isEmpty ? .nothing : .standIn(standIn)
    }

    /// What happens when the draft in the box is finished with.
    public enum Landing: Equatable, Sendable {
        /// This number reaches the thing the box speaks for.
        case land(CGFloat)
        /// The box was emptied and emptying it means something here.
        case clear
        /// Nothing reaches anything, and the box goes back to what the thing
        /// really says.
        case putBack
    }

    /// The draft, finished with.
    ///
    /// - Parameters:
    ///   - draft: what is in the box right now.
    ///   - showing: what the box holds when nobody is typing.
    ///   - canClear: whether emptying this box means something.
    ///   - floor: the smallest number this box may hold, or nil where it may
    ///     go as low as it likes (a position may hang off the canvas).
    ///   - ceiling: the largest, for the numbers that have a top — a strength
    ///     that means nothing past 100.
    ///   - wholeNumbers: whether this box counts in whole numbers.
    public static func landing(draft: String, showing: Showing, canClear: Bool,
                               floor: CGFloat?, ceiling: CGFloat? = nil,
                               wholeNumbers: Bool) -> Landing {
        if draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // Clearing takes a value away, so there has to be one. A box only
            // standing in for several values that disagree has none, and a box
            // left blank reads as a row that failed to draw rather than as a
            // limit somebody lifted.
            guard canClear, case .number = showing else { return .putBack }
            return .clear
        }
        guard let typed = LayerGeometry.parse(draft) else { return .putBack }
        return .land(held(wholeNumbers ? typed.rounded() : typed, floor: floor, ceiling: ceiling))
    }

    /// What one press of an arrow key does.
    public enum Stepping: Equatable, Sendable {
        /// The box has a number: this is the next one.
        case to(CGFloat)
        /// The box has no one number, and the panel can step every thing it
        /// speaks for from its own value, so a spread-out row moves together
        /// and stays spread out.
        case each(direction: Int, coarse: Bool)
        /// Nothing to step from and nothing to step. Inventing a nought here
        /// would flatten values that disagree into one nobody typed.
        case nothing
    }

    /// One press of an arrow key.
    ///
    /// It steps what is IN THE BOX, which is the whole point: a half-typed 50
    /// steps to 51 rather than back to the width the layer still has, and a
    /// layer whose frame carries 295.5 off a drag steps 296, 297, 298, because
    /// 296 is the number the box is showing. Stepping the value behind the box
    /// instead is what used to drift on a fraction nobody had seen.
    ///
    /// A box that counts in whole numbers rounds the result, so 12.6 pasted in
    /// and stepped up lands on 14 rather than 13.6. A box that does not keeps
    /// the fraction, because 12.5 degrees stepping to 13.5 is what the person
    /// pressing the key meant.
    public static func stepping(draft: String, direction: Int, coarse: Bool,
                                floor: CGFloat?, ceiling: CGFloat? = nil,
                                wholeNumbers: Bool = false,
                                stepsEach: Bool) -> Stepping {
        guard let base = LayerGeometry.parse(draft), direction != 0 else {
            return stepsEach ? .each(direction: direction, coarse: coarse) : .nothing
        }
        let amount = coarse ? LayerGeometry.coarseStep : LayerGeometry.step
        var next = base + CGFloat(direction.signum()) * amount
        if wholeNumbers { next = next.rounded() }
        return .to(held(next, floor: floor, ceiling: ceiling))
    }

    /// Whether this number is the one the box is ALREADY showing.
    ///
    /// Landing it again would be an undo step that changes nothing you can
    /// see, which is what a down arrow held at a floor used to produce: the
    /// number stops moving and the undo stack goes on growing.
    public static func alreadyShowing(_ value: CGFloat, showing: Showing) -> Bool {
        guard case .number(let text) = showing,
              let current = LayerGeometry.parse(text) else { return false }
        return current == value
    }

    /// A number kept inside the ends this box has, if it has any.
    private static func held(_ value: CGFloat, floor: CGFloat?, ceiling: CGFloat?) -> CGFloat {
        var held = value
        if let floor { held = max(floor, held) }
        if let ceiling { held = min(ceiling, held) }
        return held
    }
}
