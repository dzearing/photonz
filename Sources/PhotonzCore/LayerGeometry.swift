import CoreGraphics
import Foundation

/// One typed geometry number in the inspector: where a layer sits, how big it
/// is, and what angle it was turned to. Labelled the way every design tool
/// labels them, so nobody has to learn a new vocabulary to make two buttons
/// the same width.
public enum LayerGeometryField: String, CaseIterable, Hashable, Sendable {
    case x
    case y
    case width
    case height
    /// The angle, in degrees. Not part of the frame at all: it lives on the
    /// layer's transform, which is why the two write paths differ (see
    /// `LayerGeometrySelection.turning(to:)`). Everything else about it — the
    /// Mixed rule, the read-only look, the click that explains itself, the
    /// arrow-key stepping — is the same field the other four are, which is why
    /// it is one of them rather than a control of its own invention.
    case rotation

    /// The one- or two-letter label beside the field.
    public var label: String {
        switch self {
        case .x: "X"
        case .y: "Y"
        case .width: "W"
        case .height: "H"
        case .rotation: "A"
        }
    }

    /// The same field in words, for the hover tip: a letter says which box to
    /// type in, not what the number means.
    public var title: String {
        switch self {
        case .x: "Distance from the left edge of the canvas"
        case .y: "Distance from the top edge of the canvas"
        case .width: "Width"
        case .height: "Height"
        case .rotation: "Angle, in degrees, turning clockwise"
        }
    }

    /// The mark that goes after the number in this field. Lengths carry none,
    /// because a panel of numbers all in the same unit says it once in the
    /// caption; the angle carries its degree sign, because it is the one
    /// number in the section that is not a length and a bare 45 beside a
    /// W of 296 reads as another length.
    public var displaySuffix: String {
        self == .rotation ? LayerAngle.unitSuffix : ""
    }

    /// Whether this field changes the layer's size (rather than its position).
    public var isSize: Bool { self == .width || self == .height }

    /// Whether this field is one of the four read off the layer's box. The
    /// angle is not: it is on the transform, and every function here that
    /// takes a `CGRect` is about the other four.
    public var isFrameNumber: Bool { self != .rotation }

    /// The noun a sentence about this size uses, so "Smallest width" in a
    /// reason is spelled the way the Layout section's row spells it.
    var sizeNoun: String { self == .height ? "height" : "width" }

    /// The direction words a sentence about a floor and a ceiling needs: a
    /// width goes narrower and wider, a height shorter and taller.
    var smallerWord: String { self == .height ? "shorter" : "narrower" }
    var largerWord: String { self == .height ? "taller" : "wider" }
}

/// Reading and writing a layer's frame as four typed numbers.
///
/// Everything here is in document points, the same units the measure readouts
/// call "px", so a number measured with the caliper can be typed straight into
/// a field. The document model's origin is top left, so X grows right and Y
/// grows down, and a typed size grows to the right and downward — the same
/// direction the canvas size fields grow.
public enum LayerGeometry {

    /// The unit word beside the numbers. The app's one word for a document
    /// length, so no two surfaces disagree about what a number means: see
    /// `DocumentUnit`.
    public static var unitSuffix: String { DocumentUnit.word }

    /// The smallest a typed width or height may make a layer: below one point
    /// there is nothing left to see or grab. Some layers stop sooner than this
    /// — a text box floors where its drag does — which is
    /// `LayerGeometryEditing.minimum(for:)`.
    public static let minimumSide: CGFloat = 1

    /// A ceiling on a typed size, so a slipped keystroke ("29600000") cannot
    /// ask the renderer for a surface no machine can allocate.
    public static let maximumSide: CGFloat = 100_000

    /// What one arrow-key press changes the number by. The same 1 and 10 the
    /// canvas nudges a layer by (`Nudge`), so a field and the canvas answer an
    /// arrow key the same way.
    public static let step: CGFloat = 1

    /// What Shift plus an arrow key changes it by.
    public static let coarseStep: CGFloat = 10

    /// The exact number behind a field.
    ///
    /// A box has no angle, so A reads 0 here and is read from the layer's
    /// transform instead (`LayerGeometrySelection.Member.angle`). Every
    /// function in this type that takes a `CGRect` is about the other four.
    public static func value(_ field: LayerGeometryField, of frame: CGRect) -> CGFloat {
        switch field {
        case .x: frame.minX
        case .y: frame.minY
        case .width: frame.width
        case .height: frame.height
        case .rotation: 0
        }
    }

    /// The number the field actually shows: whole points. A frame that came
    /// from a drag carries fractions nobody typed, and showing 296 while
    /// holding 295.5 would make the next arrow-key press look broken, so the
    /// display, the stepping and the typing all agree on the rounded value.
    public static func displayValue(_ field: LayerGeometryField, of frame: CGRect) -> CGFloat {
        value(field, of: frame).rounded()
    }

    /// The frame after `value` is typed into `field`.
    ///
    /// Position is free to go negative (a layer may hang off the canvas the
    /// same way a drag can put it there). Size is clamped into a range that
    /// still renders. A value that is not a real number leaves the frame
    /// untouched, so a half-typed "-" or "1e" never moves anything.
    ///
    /// `notBelow` is the layer's own floor, for the layers that stop before
    /// one point: pass `LayerGeometryEditing.minimum(for:)` and a typed width
    /// stops exactly where dragging that layer's edge stops. Nil means the
    /// ordinary floor. `notAbove` is the other end, for a group told the
    /// largest it may get: pass `LayerGeometryEditing.maximum(for:)` and a
    /// typed width stops where the group's own flow would have stopped it, so
    /// the panel lands the number the layer was going to keep anyway.
    public static func applying(_ value: CGFloat, to field: LayerGeometryField,
                                of frame: CGRect, notBelow floor: CGFloat? = nil,
                                notAbove ceiling: CGFloat? = nil) -> CGRect {
        guard value.isFinite else { return frame }
        var result = frame
        switch field {
        case .x: result.origin.x = value
        case .y: result.origin.y = value
        case .width: result.size.width = clampedSide(value, notBelow: floor, notAbove: ceiling)
        case .height: result.size.height = clampedSide(value, notBelow: floor, notAbove: ceiling)
        case .rotation: break // not a number about the box
        }
        return result
    }

    /// The number one arrow-key press produces: whole steps from the whole
    /// number on screen, so holding the key walks 296, 297, 298 rather than
    /// drifting on a fraction the field never showed.
    public static func stepped(_ value: CGFloat, direction: Int, coarse: Bool) -> CGFloat {
        guard value.isFinite, direction != 0 else { return value }
        let amount = coarse ? coarseStep : step
        return value.rounded() + CGFloat(direction.signum()) * amount
    }

    /// The number in a field's text, or nil when there is no number in it.
    ///
    /// Forgiving about the things a person actually does — spaces around the
    /// number, a leading plus, a pasted unit word ("296 px"), the minus sign a
    /// word processor substitutes — and strict about everything else. A field
    /// holding anything that is not plainly one number changes nothing and
    /// snaps back to what the layer really is, which beats guessing what a
    /// comma in "1,296" was supposed to mean.
    public static func parse(_ text: String) -> CGFloat? {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        // The units a person might have pasted or typed back in. The degree
        // sign is here because the A field SHOWS one: select the number, type
        // over it and the mark goes with it, but click to the end of "45°"
        // and add a digit and the box still has to read 455 rather than
        // snapping back as if you had typed a word.
        for unit in [unitSuffix, LayerAngle.unitSuffix, "degrees", "deg"]
        where cleaned.hasSuffix(unit) {
            cleaned = String(cleaned.dropLast(unit.count))
                .trimmingCharacters(in: .whitespaces)
            break
        }
        cleaned = cleaned.replacingOccurrences(of: "\u{2212}", with: "-") // a typographic minus
        if cleaned.hasPrefix("+") { cleaned = String(cleaned.dropFirst()) }
        guard !cleaned.isEmpty else { return nil }
        // Digits, at most one dot, an optional leading minus. Nothing else, so
        // "1e9", "296,5" and "wide" all read as no number at all.
        var body = Substring(cleaned)
        if body.hasPrefix("-") { body = body.dropFirst() }
        guard !body.isEmpty, body.allSatisfy({ $0.isNumber || $0 == "." }),
              body.filter({ $0 == "." }).count <= 1, body.contains(where: \.isNumber) else {
            return nil
        }
        guard let value = Double(cleaned), value.isFinite else { return nil }
        return CGFloat(value)
    }

    private static func clampedSide(_ value: CGFloat, notBelow floor: CGFloat? = nil,
                                    notAbove ceiling: CGFloat? = nil) -> CGFloat {
        // The floor wins where the two cross, the same way `GroupLayout.held`
        // settles it, because somebody typing 96 over a 9 passes through that
        // state on the way and it has to mean something sensible.
        let most = min(ceiling ?? maximumSide, maximumSide)
        return max(min(value, most), max(floor ?? minimumSide, minimumSide))
    }
}

/// What decides how far a typed size may go, when something with a name does.
///
/// Two answers, because there are two: a group's own Smallest and Largest rows
/// in the Layout section, and a text layer's own words. A floor nobody set —
/// the one point every layer has — is not one of these, so a sentence is never
/// written about it.
public enum LayerSizeRule: Hashable, Sendable {
    /// The Smallest and Largest rows in the Layout section.
    case layoutSection
    /// The words in a text layer, which no box may be smaller than.
    case words
}

/// How far a size may go, and what holds it there. A limit with a name, so the
/// panel can say WHY a typed number sprang back instead of only showing the
/// number it kept.
public struct LayerSizeHold: Hashable, Sendable {
    public let limit: CGFloat
    public let rule: LayerSizeRule

    public init(limit: CGFloat, rule: LayerSizeRule) {
        self.limit = limit
        self.rule = rule
    }
}

/// Which of a layer's four numbers accept typing, and why the others do not.
///
/// The rule is that a field is typeable exactly where the canvas already lets
/// you drag the same thing. Every layer can be moved, so X and Y are open
/// unless the layer is locked. Size is another matter: an arrow's box is
/// padding around a shaft rather than the shape you drew, and a measurement is
/// edited by its feet, so neither takes a typed width — a number that never
/// matched what is on screen is worse than no number at all. Text takes a
/// width, which is its wrap width, but its height follows the re-wrap.
///
/// A field that takes nothing is not always a field with nothing to say:
/// `shows(_:)` is the second question, and it is how a wrapped paragraph
/// reports the height it turned out to be.
public struct LayerGeometryEditing: Hashable, Sendable {

    /// Why a piece inside a group that closes around its contents has no typed
    /// position: the room around it is the group's Padding.
    public static let huggedReason = "The group this is in is as big as what is inside it, so the room around this is the group's Padding in the Layout section."

    /// Why nothing on a locked layer can be typed. All three of the things
    /// this section holds are named, because it is also the caption for a
    /// locked selection and a sentence that stopped at size would be the panel
    /// promising less than unlocking gives back.
    public static let lockedReason = "This layer is locked. Unlock it in the Layers list to change its position, size or angle."

    /// The same, for a locked layer whose position was never its own anyway:
    /// a stack, a grid, or a group that closes around what is inside it
    /// already decides where its contents sit.
    ///
    /// Two reasons land on the same field here, and naming only the lock is
    /// the one that misleads: it promises that unlocking hands the position
    /// back, and the container would take it again on the very next pass. So
    /// the sentence says both, and says which half unlocking actually returns.
    public static func lockedInsideReason(_ kind: GroupLayoutKind?) -> String {
        let noun = kind?.title.lowercased() ?? "group"
        return "This layer is locked, and the \(noun) it is in decides where it sits. "
            + "Unlocking it in the Layers list gives back its size and angle, not its position."
    }

    /// Why a typed size sprang back to the smallest this group is allowed to
    /// be. The Layout section's own row is the owner, named the way that row
    /// names itself, and changing it there is the one thing to do.
    public static func smallestReason(for field: LayerGeometryField,
                                      _ limit: CGFloat) -> String {
        "Smallest \(field.sizeNoun) in the Layout section holds this at "
            + "\(whole(limit)) \(LayerGeometry.unitSuffix). "
            + "Change Smallest there to go \(field.smallerWord)."
    }

    /// The same at the other end.
    public static func largestReason(for field: LayerGeometryField,
                                     _ limit: CGFloat) -> String {
        "Largest \(field.sizeNoun) in the Layout section holds this at "
            + "\(whole(limit)) \(LayerGeometry.unitSuffix). "
            + "Change Largest there to go \(field.largerWord)."
    }

    /// Why a typed size sprang back to what the words themselves need. Not a
    /// rule anybody set: it is the text, so the Text section is where to go.
    public static func wordsReason(for field: LayerGeometryField,
                                   _ limit: CGFloat) -> String {
        let unit = LayerGeometry.unitSuffix
        return field == .height
            ? "The words need \(whole(limit)) \(unit) to sit in, so the box stops there. "
                + "Change the width to re-wrap them, or the font size in the Text section."
            : "The words need \(whole(limit)) \(unit) to stay readable, so the box stops "
                + "there. Change the font size in the Text section to go narrower."
    }

    /// Whole points, the spelling every number in a reason uses.
    private static func whole(_ value: CGFloat) -> String { String(Int(value.rounded())) }

    /// Why a screen has no angle to read or type. A screen is the surface you
    /// build on, and it sits in a column with its name printed above it, so a
    /// screen on a slant would tilt the room rather than the furniture. The
    /// rotate knob is not offered on one either, so the field says the same
    /// thing the canvas says by leaving the knob off
    /// (`EditorState.offersRotation`).
    public static let screenTurnReason = "A screen holds still, so everything you build on it lines up. Group what is on the screen and turn the group."

    /// Why a shape drawn end to end has no angle: it already points wherever
    /// its two ends are, so an angle typed here would be a second answer to a
    /// question the ends have already answered.
    public static let endpointTurnReason = "This shape points wherever its two ends are. Drag either end on the canvas to aim it."

    /// The same for a measurement, which points at the thing it measures.
    public static let measurementTurnReason = "A measurement lies along what it measures. Drag either end on the canvas to change it."

    /// Why a shape drawn end to end has no typeable size.
    public static let endpointReason = "Drag this shape's ends on the canvas to change its size."

    /// Why a measurement has no typeable size.
    public static let measurementReason = "Drag this measurement's ends on the canvas to change what it measures."

    /// Why text has no typeable height where there is nowhere to spend one.
    public static let textHeightReason = "Height follows the text. Change the width to re-wrap it, or the font size in the Text section."

    /// Why a piece stretched down the thing holding it has no typed height: the
    /// container works that number out, so one typed here would be put straight
    /// back. The tip points at the two controls that do change it.
    ///
    /// True of any piece, and of a piece of TEXT for a second reason on top:
    /// its height stopped being the words' answer the moment the container took
    /// it over.
    public static let filledHeightReason = "This is stretched to fill the height of what holds it. Change that container's height, or pick a different Vertical in the Layout section."

    /// The same across. A row in a column stack, a title spanning a bar and the
    /// surface behind a button are all as wide as the box holding them, so the
    /// width is the container's number rather than the piece's.
    public static let filledWidthReason = "This is stretched to fill the width of what holds it. Change that container's width, or pick a different Horizontal in the Layout section."

    /// Why a piece taking the room its stack has left over has no typed size
    /// along the way that stack runs: the stack works that number out from
    /// whatever the others left, so one typed here would be put straight back
    /// before you saw it. Points at the two controls that do change it.
    public static let fillingReason = "This takes the room its stack has left over, so the stack works this number out. Change the group's size in the Layout section, or set this row back from filling."

    /// Why a layer in a stack has no typeable position: the stack decides it,
    /// and a typed number would be put straight back. Says what to do instead.
    public static let stackedReason = "The stack this is in decides where it sits. Change the group's Gap or Direction in the Layout section, or drag this past its neighbours to reorder them."

    /// A piece stretched the way its stack runs is not in the line at all: it
    /// spans the group and is painted to its edges, so the group's own size is
    /// the number that moves it.
    public static let spanningReason = "This spans the group it is in and is painted to the group's own edges, so the group's size decides where it sits. Change the group's size in the Layout section, or set this piece's Stretch back and it lines up with the others."

    /// The same for a grid.
    public static let griddedReason = "The grid this is in decides where it sits. Change the group's Columns or gaps in the Layout section, or drag this past its neighbours to reorder them."

    public let canMove: Bool
    public let canSetWidth: Bool
    public let canSetHeight: Bool

    /// Whether a typed angle turns this layer. The rule is the canvas's:
    /// a field is typeable exactly where the knob is offered, so a group, a
    /// line, an arrow, a caliper and a locked layer all take none.
    public let canRotate: Bool

    /// Whether turning is a thing this layer does AT ALL, lock or no lock.
    /// A locked layer that was turned to 30 still has 30 worth reading, the
    /// same way its X is still worth reading; a group has no angle to show in
    /// the first place, so its A is a dash rather than a 0 that means nothing.
    private let turnsAtAll: Bool

    /// Whether the group holding this layer is what decides where it sits, so
    /// no lock and no unlock changes that. The panel needs it apart from the
    /// reason strings because a caption speaking for several locked layers has
    /// to say the same thing in the plural.
    public let containerOwnsPosition: Bool

    /// Whether a lock is what is stopping this layer. It is the one state that
    /// takes all four numbers away at once and for a single reason, which is
    /// why the panel can say it in one line under the fields instead of making
    /// you hover a dead box to find out.
    public let isLocked: Bool

    /// Whether the layer's box is the thing you see. It is for nearly
    /// everything, and it is not for a line, an arrow or a caliper: those are
    /// drawn between two points and their box is padding around the stroke, so
    /// its width was never a number about the shape.
    private let frameIsTheShape: Bool

    /// The narrowest a typed width may make this layer, and the shortest a
    /// typed height may. A text box stops at the width its drag stops at, so
    /// the two ways of setting a width land in the same place; everything else
    /// stops at one point, which is where its drag stops. A group told a
    /// Smallest in the Layout section stops there too.
    public let minimumWidth: CGFloat
    public let minimumHeight: CGFloat

    /// The limits that have a NAME, kept apart from the numbers above because
    /// only a named one may be turned into a sentence. Every layer has a floor
    /// of one point and nobody set it, so "Smallest width holds this at 1 px"
    /// would be inventing a rule that is not in the Layout section.
    ///
    /// The ceilings are only here: nothing holds a size from above unless a
    /// group was told a Largest.
    private let widthFloor: LayerSizeHold?
    private let widthCeiling: LayerSizeHold?
    private let heightFloor: LayerSizeHold?
    private let heightCeiling: LayerSizeHold?

    private let widthReason: String?
    private let heightReason: String?
    private let moveReason: String?
    private let rotationReason: String?

    /// `container` is the group this layer sits in, when it has one. It only
    /// matters when that group arranges itself: a stack or a grid decides
    /// where its contents sit, so typing a position there would be undone
    /// before you saw it, and the field says who owns it instead.
    /// `textTakesAHeight` says whether a text box's Height field is a number
    /// you can type. It is, wherever there is somewhere to spend the room a
    /// height gives: the Down row of the Text section, which is part of the
    /// placement experiment. Without that row the field reads the height the
    /// words came out to and takes nothing, as it always did.
    public init(layer: Layer, in container: Layer? = nil, textTakesAHeight: Bool = false) {
        // A group told the smallest and the largest it may get keeps those
        // limits in its OWN flow, applied inside `LayerScaling.rearranging`
        // long after the panel has handed a number over. The panel has to know
        // them too, or the only way to find out a group will not go below 160
        // is to type 50 and watch the box spring back. Only the groups that
        // actually take that path: a copy is sized by its original and a screen
        // is its own frame, so neither is held here.
        let ownLimits: GroupLayout? = {
            guard let group = layer.group, group.instanceOf == nil, !group.isFrame,
                  let layout = group.layout, layout.limitsSize else { return nil }
            return layout
        }()
        // Text is the one content with a floor of its own: below it a caption
        // is an unreadable sliver, so the canvas refuses to drag one narrower
        // and the field refuses to type one.
        // Counted on the words, because the words are what the field shows.
        let textWidthFloor = layer.resizeWidthOnly ? TextMeasurement.minimumContentWidth : nil
        widthFloor = ownLimits?.usedMinWidth.map { LayerSizeHold(limit: $0, rule: .layoutSection) }
            ?? textWidthFloor.map { LayerSizeHold(limit: $0, rule: .words) }
        widthCeiling = ownLimits?.usedMaxWidth.map { LayerSizeHold(limit: $0, rule: .layoutSection) }
        minimumWidth = max(widthFloor?.limit ?? 0, LayerGeometry.minimumSide)
        // And a floor down the box for the same reason: a height typed here is
        // ROOM the words then sit in, so the shortest it can be is the words
        // themselves. Counted without the room the renderer draws them in,
        // because the field speaks the box a person sees.
        let textHeightFloor: CGFloat? = if case .text(let content) = layer.content {
            max(LayerGeometry.minimumSide,
                TextMeasurement.size(of: content, wrappingAt: layer.frame.standardized.width)
                    .height - layer.boxSlack.height)
        } else {
            nil
        }
        heightFloor = ownLimits?.usedMinHeight.map { LayerSizeHold(limit: $0, rule: .layoutSection) }
            ?? textHeightFloor.map { LayerSizeHold(limit: $0, rule: .words) }
        heightCeiling = ownLimits?.usedMaxHeight
            .map { LayerSizeHold(limit: $0, rule: .layoutSection) }
        minimumHeight = max(heightFloor?.limit ?? 0, LayerGeometry.minimumSide)
        frameIsTheShape = !layer.hasEndpointHandles
        isLocked = layer.isLocked
        // Turning, decided the same way the canvas decides whether to float
        // the knob above the outline (`EditorState.offersRotation`). A shape
        // held between two ends is aimed by its ends, and a screen is the
        // surface everything else is built on; both would be a field with
        // nothing behind it, so both get a dash and a sentence rather than a
        // live box. An ordinary group turns like anything else, about the
        // middle of the box its contents make (`Layer.turnPivot`).
        let cannotTurn: String? = if layer.isFrame {
            Self.screenTurnReason
        } else if layer.hasEndpointHandles {
            layer.measure != nil ? Self.measurementTurnReason : Self.endpointTurnReason
        } else {
            nil
        }
        turnsAtAll = cannotTurn == nil
        canRotate = turnsAtAll && !layer.isLocked
        rotationReason = cannotTurn ?? (layer.isLocked ? Self.lockedReason : nil)
        // A container that arranges its contents, or that closes around them,
        // owns where they sit; one that was given a size on both axes and
        // arranges nothing leaves them exactly where you put them.
        let owningLayout = (container?.group?.layout).flatMap {
            $0.arranges || $0.hugsWidth || $0.hugsHeight ? $0 : nil
        }
        containerOwnsPosition = owningLayout != nil
        if layer.isLocked {
            canMove = false
            canSetWidth = false
            canSetHeight = false
            // Size really does come back on unlocking, so those two fields
            // still name the lock and nothing else.
            widthReason = Self.lockedReason
            heightReason = Self.lockedReason
            moveReason = owningLayout.map { Self.lockedInsideReason($0.kind) } ?? Self.lockedReason
            return
        }
        if let owningLayout {
            canMove = false
            let spans = layer.resolvedPlacement(in: container).stepsOutOfTheFlow(of: owningLayout)
            moveReason = switch owningLayout.kind {
            case _ where spans: Self.spanningReason
            case .grid: Self.griddedReason
            case .stack: Self.stackedReason
            case nil: Self.huggedReason
            }
        } else {
            canMove = true
            moveReason = nil
        }
        // A size the container works out is a number to READ, on either axis
        // and however the container arrived at it: stretched to the box's own
        // edges, handed the width a column gives every row, or taking the room
        // a stack has left over. It is not a lock and unlocking gives it
        // nothing back, because the flow would put a typed number straight back
        // on its next pass. One question, asked once, so the three cases cannot
        // drift apart again (`Layer.sizeIsDecidedByItsContainer`).
        let filling = layer.fillsTheFlow && layer.canFillTheFlow(in: container)
        let alongTheFlow = container?.group?.layout?.flowsHorizontally
        // Which of the two controls the tip should name: Fill and Stretch are
        // different answers with different homes, so the sentence has to say
        // which one is holding this number.
        func decidedReason(across: Bool) -> String {
            filling && alongTheFlow == across ? Self.fillingReason
                : across ? Self.filledWidthReason : Self.filledHeightReason
        }
        let widthIsTheirs = layer.sizeIsDecidedByItsContainer(across: true, in: container)
        let heightIsTheirs = layer.sizeIsDecidedByItsContainer(across: false, in: container)
        if layer.allowsFrameResize {
            canSetWidth = !widthIsTheirs
            // Height takes a number on a text box too: it is how you give one
            // room for its words to sit in, and it stops at the words
            // (`docs/design/ui-building.md`, "Where the words sit in their
            // box").
            let hugsForever = layer.resizeWidthOnly && !textTakesAHeight
            canSetHeight = !hugsForever && !heightIsTheirs
            widthReason = widthIsTheirs ? decidedReason(across: true) : nil
            heightReason = if heightIsTheirs {
                decidedReason(across: false)
            } else if hugsForever {
                Self.textHeightReason
            } else {
                nil
            }
        } else {
            canSetWidth = false
            canSetHeight = false
            let reason = layer.measure != nil ? Self.measurementReason : Self.endpointReason
            widthReason = reason
            heightReason = reason
        }
    }

    /// Whether this field takes a typed number.
    public func allows(_ field: LayerGeometryField) -> Bool {
        switch field {
        case .x, .y: canMove
        case .width: canSetWidth
        case .height: canSetHeight
        case .rotation: canRotate
        }
    }

    /// Whether this field's number is worth showing when it cannot be typed.
    ///
    /// A number you cannot change is still a number you may want to read: how
    /// tall a paragraph came out once it wrapped, where the stack put a row,
    /// how big the original a copy follows is. It is only worth showing when
    /// the box really is what you see, which is why a line, an arrow or a
    /// caliper still shows no size — its box is padding around a stroke, and a
    /// width that never matched the shape you drew is worse than a blank.
    public func shows(_ field: LayerGeometryField) -> Bool {
        switch field {
        case .x, .y: return true
        case .width, .height: return frameIsTheShape
        case .rotation: return turnsAtAll
        }
    }

    /// The floor this field stops at, or nil for a field with no floor: a
    /// position may go anywhere, including off the canvas.
    public func minimum(for field: LayerGeometryField) -> CGFloat? {
        switch field {
        case .x, .y, .rotation: nil
        case .width: minimumWidth
        case .height: minimumHeight
        }
    }

    /// The ceiling this field stops at, or nil where nothing holds it from
    /// above — which is nearly everything. Only a group told a Largest in the
    /// Layout section has one.
    public func maximum(for field: LayerGeometryField) -> CGFloat? {
        switch field {
        case .x, .y, .rotation: nil
        case .width: widthCeiling?.limit
        case .height: heightCeiling?.limit
        }
    }

    /// Why a number typed into this field would not be taken, in the wording
    /// law's two halves. Nil when the number is one this layer will take, and
    /// nil when the thing holding it has no name: the one point every layer
    /// has is nobody's rule, and a sentence about it would send a person
    /// looking for a control that does not exist.
    ///
    /// Worked out from the limits as they stand right now rather than from
    /// anything remembered, so taking the rule off takes the sentence with it
    /// instead of leaving it explaining a rule that is gone.
    public func limitReason(for field: LayerGeometryField, asking value: CGFloat) -> String? {
        guard field.isSize, value.isFinite else { return nil }
        let floor = field == .height ? heightFloor : widthFloor
        if let floor, value < floor.limit {
            return switch floor.rule {
            case .layoutSection: Self.smallestReason(for: field, floor.limit)
            case .words: Self.wordsReason(for: field, floor.limit)
            }
        }
        let ceiling = field == .height ? heightCeiling : widthCeiling
        if let ceiling, value > ceiling.limit, ceiling.rule == .layoutSection {
            return Self.largestReason(for: field, ceiling.limit)
        }
        return nil
    }

    /// A plain sentence explaining why a field does not take a number, for the
    /// hover tip. Nil when the field is editable.
    public func fixedReason(for field: LayerGeometryField) -> String? {
        guard !allows(field) else { return nil }
        switch field {
        case .x, .y: return moveReason
        case .width: return widthReason
        case .height: return heightReason
        case .rotation: return rotationReason
        }
    }
}

// MARK: - The two halves of a typed geometry number

public extension Layer {

    /// The box the Position & Size fields SHOW for this layer, in the space
    /// its numbers are read in.
    ///
    /// A group's stored frame is an anchor rather than a box, so what it shows
    /// is the box it actually occupies. Everything else shows the frame it has.
    /// (The slack a measured text box carries comes off on top of this, with
    /// `withoutSlack`, because that is a question about the words rather than
    /// about which rectangle to read.)
    var shownBox: CGRect { isGroup ? localBounds : frame }

    /// This layer with a typed geometry number landed on it.
    ///
    /// ONE call, so the panel and a test cannot disagree about what a commit
    /// does — which matters because what a commit does is now the only source
    /// of what the field shows afterwards. `resized(to:)` is where a layer gets
    /// to refuse: a flow with a smallest width keeps its width, a text box
    /// keeps its words, and neither of those is a floor the panel knows about
    /// in advance.
    func geometrySet(to frame: CGRect, canvas: CGSize?, byHand: Bool,
                     captionPillSize: CGSize? = nil) -> Layer {
        AnnotationBuilder.planningCaption(resized(to: frame, chosenByHand: byHand),
                                          canvas: canvas, captionPillSize: captionPillSize)
    }
}
