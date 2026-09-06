import CoreGraphics
import Foundation

/// Where a piece sits when the thing holding it is resized.
///
/// A container says how its contents line up by default, and any one piece
/// inside may say something different for itself. That is the whole model, and
/// it is what makes a button survive being dragged wider: the button says
/// "centre everything", its background says "stretch", so the label stays in
/// the middle while the fill grows.
/// See `docs/design/ui-building.md`, "Resizing places the pieces".
///
/// Nothing is set anywhere until somebody sets it, and nothing set means
/// `scale` — the proportional multiply this app did before any of this
/// existed — so a document saved yesterday resizes exactly as it did yesterday.
public enum HorizontalPlacement: String, CaseIterable, Hashable, Codable, Sendable {
    /// Position and width both multiplied by how much the container grew. The
    /// rule every document used before placement existed.
    case scale
    /// Keeps its distance from the container's left edge, and its own width.
    case left
    /// Keeps its offset from the container's middle, and its own width. A
    /// piece that was centred stays centred at any width.
    case center
    /// Keeps its distance from the container's right edge, and its own width.
    case right
    /// Keeps BOTH distances, so its width grows and shrinks with the container.
    /// A background inset by nothing fills the new width exactly.
    case stretch

    public var title: String {
        switch self {
        case .scale: "Scale"
        case .left: "Left"
        case .center: "Center"
        case .right: "Right"
        case .stretch: "Stretch"
        }
    }
}

/// The same four choices up and down, plus the proportional default.
public enum VerticalPlacement: String, CaseIterable, Hashable, Codable, Sendable {
    case scale
    case top
    case center
    case bottom
    case stretch

    public var title: String {
        switch self {
        case .scale: "Scale"
        case .top: "Top"
        case .center: "Middle"
        case .bottom: "Bottom"
        case .stretch: "Stretch"
        }
    }
}

/// A placement setting, one axis at a time.
///
/// Each axis is separately optional so a piece can override just one of them:
/// a divider along the bottom of a bar is `stretch` across and `bottom` down,
/// while a label may want to stretch across and keep whatever the container
/// says about down. On a LAYER, nil means "follow the container"; on a
/// CONTAINER (`GroupContent.contentPlacement`) it means "no default of my own",
/// which resolves to `scale`.
public struct LayerPlacement: Hashable, Codable, Sendable {
    public var horizontal: HorizontalPlacement?
    public var vertical: VerticalPlacement?

    public init(horizontal: HorizontalPlacement? = nil, vertical: VerticalPlacement? = nil) {
        self.horizontal = horizontal
        self.vertical = vertical
    }

    /// True when neither axis says anything, which is the same as not being
    /// there at all. Setting an axis back to "follow" collapses to nil through
    /// this, so a layer never carries an empty setting around.
    public var isEmpty: Bool { horizontal == nil && vertical == nil }

    /// Both axes stretched: the setting a background wants, so it fills
    /// whatever box its container ends up with.
    public static let fill = LayerPlacement(horizontal: .stretch, vertical: .stretch)

    /// The setting, or nil when it says nothing — what a stored property wants
    /// so that "follow on both axes" writes no key at all.
    public var normalized: LayerPlacement? { isEmpty ? nil : self }
}

/// A piece told to take the room its stack has left over.
///
/// Filling is about the FLOW, not about an axis. It says "take whatever this
/// stack has left along the way it runs", so a row that is flipped to a column
/// goes on meaning the same thing, and it never collides with the Stretch that
/// makes a piece the surface behind everything else: something painted to the
/// box's own edges cannot also be one of the pieces sharing the box out.
///
/// The size it had BEFORE is kept here because nothing else could keep it. The
/// flow writes the size it worked out straight into the piece, so a button
/// tried at Fill for a second would otherwise be stuck at whatever the room
/// made it, with nobody left who remembers what it was.
public struct FlowFill: Hashable, Codable, Sendable {
    /// The size this piece was before it started filling, so turning Fill off
    /// hands it back.
    public var sizeBefore: CGSize

    public init(sizeBefore: CGSize) {
        self.sizeBefore = sizeBefore
    }
}

/// What a piece actually does, once the container's default and the piece's own
/// override have been put together — and, for each axis, which of the two
/// answered. The inspector needs the second half to say whether a row is
/// following the container or overriding it.
public struct ResolvedPlacement: Hashable, Sendable {
    public var horizontal: HorizontalPlacement
    public var vertical: VerticalPlacement
    /// True when the horizontal answer came from the container, not the piece.
    public var followsHorizontal: Bool
    public var followsVertical: Bool

    public init(horizontal: HorizontalPlacement, vertical: VerticalPlacement,
                followsHorizontal: Bool, followsVertical: Bool) {
        self.horizontal = horizontal
        self.vertical = vertical
        self.followsHorizontal = followsHorizontal
        self.followsVertical = followsVertical
    }
}

extension LayerPlacement {
    /// The piece's own setting first, the container's default behind it, and
    /// the proportional multiply behind that.
    public static func resolving(child: LayerPlacement?,
                                 container: LayerPlacement?) -> ResolvedPlacement {
        ResolvedPlacement(horizontal: child?.horizontal ?? container?.horizontal ?? .scale,
                          vertical: child?.vertical ?? container?.vertical ?? .scale,
                          followsHorizontal: child?.horizontal == nil,
                          followsVertical: child?.vertical == nil)
    }
}

extension ResolvedPlacement {
    /// Whether this piece is the SURFACE behind everything else rather than one
    /// of the things being arranged.
    ///
    /// Stretching both ways is the one rule that cannot mean "be a row in this
    /// stack" or "be one of the pieces this box closes around": it says be the
    /// size of the box, and something that is the size of the box cannot also
    /// be the thing that decides how big the box is. So it steps out of the
    /// arrangement, is measured by nobody, and is painted to the container's
    /// own edges — which is exactly what a button's fill is.
    public var isSurface: Bool { horizontal == .stretch && vertical == .stretch }

    /// The same answer as a SCREEN honours it. Dragging a frame's edge moves
    /// where it clips rather than magnifying what is on it, so nothing on a
    /// screen ever scales: a piece nobody gave a rule to holds still, which in
    /// a frame's own space is pinning to the top left.
    public var onAScreen: ResolvedPlacement {
        var out = self
        if out.horizontal == .scale { out.horizontal = .left }
        if out.vertical == .scale { out.vertical = .top }
        return out
    }
}

extension Layer {
    /// Whether this container PLACES what it holds rather than magnifying it.
    ///
    /// True of a screen, whose handle moves where it clips, and true of a group
    /// that arranges itself, whose flow puts every piece somewhere. In both,
    /// the proportional Scale a layer starts on means nothing, so it is neither
    /// offered nor reported: what an unset piece really does is hold to the
    /// leading edge.
    public var placesItsContents: Bool { isFrame || group?.layout?.arranges == true }

    /// How this layer behaves when the group holding it is resized, resolved
    /// against that group's default.
    public func resolvedPlacement(in container: Layer?) -> ResolvedPlacement {
        let resolved = LayerPlacement.resolving(child: placement,
                                                container: container?.group?.contentPlacement)
        return container?.placesItsContents == true ? resolved.onAScreen : resolved
    }

    /// What this container's contents do by default, in the words the
    /// inspector shows. A screen's unset default is the top left it actually
    /// honours, not the Scale a group would do, and so is a stack's.
    public var contentPlacementDefault: ResolvedPlacement {
        let placement = group?.contentPlacement
        let resolved = ResolvedPlacement(horizontal: placement?.horizontal ?? .scale,
                                         vertical: placement?.vertical ?? .scale,
                                         followsHorizontal: placement?.horizontal == nil,
                                         followsVertical: placement?.vertical == nil)
        return placesItsContents ? resolved.onAScreen : resolved
    }

    /// The choices worth offering for something in this container. Scale is not
    /// one of them on a screen, which never magnifies what is on it, nor in a
    /// stack or a grid, which place their contents instead.
    public var horizontalPlacementChoices: [HorizontalPlacement] {
        placesItsContents ? HorizontalPlacement.allCases.filter { $0 != .scale }
                          : HorizontalPlacement.allCases
    }

    public var verticalPlacementChoices: [VerticalPlacement] {
        placesItsContents ? VerticalPlacement.allCases.filter { $0 != .scale }
                          : VerticalPlacement.allCases
    }

    /// Whether the container decides this layer's height by stretching it to
    /// fill its box, rather than the layer deciding it for itself.
    ///
    /// Only a container that HAS a height to share can: a column stack hands
    /// every row the height it already had, so a Stretch there fills nothing
    /// and the layer is still the size of what is in it.
    public func heightIsFilled(in container: Layer?) -> Bool {
        guard let container else { return false }
        if let layout = container.group?.layout, !layout.decidesHeight {
            // A column stack decides no heights at all, with one exception:
            // a piece told to take the room the column has left over is at a
            // height the column worked out, and its own field cannot change it.
            return fillsTheFlow && (container.isFrame || layout.hasRoomAlongTheFlow)
        }
        return resolvedPlacement(in: container).vertical == .stretch
    }

    /// Whether this piece takes the room its stack has left over along the way
    /// that stack runs, rather than keeping the size it was drawn at.
    public var fillsTheFlow: Bool { flowFill != nil }

    /// Whether Fill is worth offering for this piece inside this container:
    /// there has to be a flow that owns a direction, and room left over in it.
    public func canFillTheFlow(in container: Layer?) -> Bool {
        guard let container, let layout = container.group?.layout else { return false }
        return PlacementEditing(arrangement: layout,
                                placing: resolvedPlacement(in: container),
                                onAScreen: container.isFrame).canFill
    }

    /// This layer's own setting with one axis changed, collapsed back to
    /// nothing when both axes end up following the container again.
    public func settingPlacement(horizontal: HorizontalPlacement?) -> LayerPlacement? {
        LayerPlacement(horizontal: horizontal, vertical: placement?.vertical).normalized
    }

    public func settingPlacement(vertical: VerticalPlacement?) -> LayerPlacement? {
        LayerPlacement(horizontal: placement?.horizontal, vertical: vertical).normalized
    }
}

/// Which of the two placement questions are still worth asking inside a
/// container, and what to say where one is not.
///
/// A stack decides the axis it runs along: a column decides every Y, a row
/// decides every X. On that axis a placement menu is a live control that
/// changes nothing, which is worse than a line saying who owns it — so the
/// inspector shows the answer instead, both for the group's own contents and
/// for a single layer sitting inside it. A grid places into a cell and a plain
/// group places into its box, so both of those keep both menus.
///
/// The same shape as `LayerGeometryEditing`, which is what stops a layer in a
/// stack taking a typed X: same question, asked of a different control.
public struct PlacementEditing: Hashable, Sendable {

    /// What the row reads where the flow decides it.
    public static let rowTitle = "Set by the row"
    public static let stackTitle = "Set by the stack"

    /// The one other answer that row takes: take whatever room the stack has
    /// left along the way it runs.
    ///
    /// It names the flow rather than reading plain "Fill", because the panel
    /// already has a Fill: the colour inside a shape, three sections down. Two
    /// controls a thumb apart wearing the same word and meaning nothing like
    /// each other is how somebody ends up painting a rectangle when they
    /// wanted to widen it.
    public static func fillTitle(across: Bool) -> String {
        across ? "Fill the row" : "Fill the stack"
    }

    /// What picking it does, for the hover tip.
    public static func fillReason(_ noun: String) -> String {
        "Take the room \(noun) has left once the other pieces, the gaps and the room at its "
            + "edges have taken theirs. Two pieces set to fill share it equally."
    }

    /// Why, for the tip that comes up on the row, pointing at the control that
    /// owns it now.
    public static let rowReason = "The row this is in lays its contents out left to right, so it decides where each one sits across. Change the group's Gap or Direction in the Layout section."
    public static let stackReason = "The stack this is in lays its contents out top to bottom, so it decides where each one sits down the page. Change the group's Gap or Direction in the Layout section."

    /// Whether that axis is still a question the placement rules answer.
    public let canSetHorizontal: Bool
    public let canSetVertical: Bool

    /// Whether the row that says who owns the axis can also offer Fill. Only a
    /// stack with room to spare can: one that is the size of what is inside it
    /// has nothing left over, so the choice would be there and do nothing.
    public let canFill: Bool

    /// Why it cannot, said in the row's own caption rather than left as a dead
    /// menu item, or nil where filling is on offer or the flow owns no axis.
    public let noRoomToFill: String?

    /// What that answer is called here, or nil where the flow owns no axis.
    public let fillTitle: String?

    /// The words for the axis the flow decided, or nil where it decided
    /// neither. Only ever one axis, because a flow runs one way.
    public let setByTheFlow: String?
    public let reason: String?

    /// The flow named on its own, for a sentence that has to talk about it
    /// rather than label a row: "the row" or "the stack".
    public static let rowNoun = "the row"
    public static let stackNoun = "the stack"
    public let flowNoun: String?

    /// `arrangement` is the layout of the group these placements apply inside:
    /// the container's own layout when this is one layer's row, and the
    /// group's own layout when it is the row for everything inside it. Nil for
    /// a group that arranges nothing, so both axes stay live.
    /// The same question asked of ONE piece, which the flow may not be
    /// arranging at all.
    ///
    /// A piece stretched both ways is the surface behind the rest: it steps out
    /// of the flow, is measured by nobody and is painted to the container's own
    /// edges. So the flow decides neither of its directions, and both of its
    /// rows stay live — setting one of them to something else is exactly how it
    /// stops being the surface and becomes a piece being arranged again.
    ///
    /// `resolved` is that piece's answer once its own rule and the container's
    /// default are put together, or nil to ask about the flow on its own.
    public init(arrangement: GroupLayout?, placing resolved: ResolvedPlacement?,
                onAScreen: Bool = false) {
        self.init(arrangement: resolved?.isSurface == true ? nil : arrangement,
                  onAScreen: onAScreen)
    }

    /// `onAScreen` says the container is a screen, whose box is a size somebody
    /// drew rather than one worked out from its contents. A stack on one always
    /// has room to spare, so the app never has to ask the layout about it.
    public init(arrangement: GroupLayout?, onAScreen: Bool = false) {
        guard let arrangement, arrangement.kind == .stack else {
            canSetHorizontal = true
            canSetVertical = true
            setByTheFlow = nil
            reason = nil
            flowNoun = nil
            canFill = false
            noRoomToFill = nil
            fillTitle = nil
            return
        }
        let across = arrangement.flowsHorizontally
        canSetHorizontal = !across
        canSetVertical = across
        setByTheFlow = across ? Self.rowTitle : Self.stackTitle
        reason = across ? Self.rowReason : Self.stackReason
        flowNoun = across ? Self.rowNoun : Self.stackNoun
        canFill = onAScreen || arrangement.hasRoomAlongTheFlow
        noRoomToFill = canFill ? nil : Self.noRoomReason(across: across)
        fillTitle = Self.fillTitle(across: across)
    }

    /// The line under the row where a stack has nothing left over: what is
    /// missing, and the one number that would make the choice mean something.
    static func noRoomReason(across: Bool) -> String {
        "There is no room left over here: \(across ? rowNoun : stackNoun) is as big as what is "
            + "inside it. Give it a \(across ? "Width" : "Height") in the Layout section and a "
            + "piece can take what is left."
    }

    /// The rule this setting still carries on the axis the flow decides, in the
    /// words the menu used for it, or nil where there is nothing sitting there.
    ///
    /// A setting made before the group became a stack stays in the file: the
    /// flow only takes the axis over, it does not wipe what was there, because
    /// flipping a column to a row and back would then quietly lose it. So the
    /// row that says who owns the axis now also says what is still written on
    /// it, and offers to take it off, rather than letting it spring back to
    /// life the day somebody changes the direction.
    public func inertRule(in placement: LayerPlacement?) -> String? {
        guard let placement else { return nil }
        if !canSetHorizontal { return placement.horizontal?.title }
        if !canSetVertical { return placement.vertical?.title }
        return nil
    }
}

/// One piece inside a container that places itself rather than following what
/// the container says, named so the container can list it.
///
/// Set on the CHILD, read from the PARENT: a group's Layout section says what
/// everything inside it does, and this is how it also says who is not doing it.
/// Without it the only way to find an override is to click every piece in turn.
public struct PlacementOverride: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let name: String
    /// The axes this piece decides for itself. Nil means it still follows the
    /// container on that axis, so at least one of the two is always set.
    public let horizontal: HorizontalPlacement?
    public let vertical: VerticalPlacement?
    /// True where this piece is the surface behind everything the container
    /// arranges rather than one of the things being arranged.
    public let isSurface: Bool
    /// True where this piece takes the room the stack has left over along the
    /// way it runs, which is a rule of its own even with no placement set.
    public let fills: Bool

    public init(id: UUID, name: String,
                horizontal: HorizontalPlacement?, vertical: VerticalPlacement?,
                isSurface: Bool = false, fills: Bool = false) {
        self.id = id
        self.name = name
        self.horizontal = horizontal
        self.vertical = vertical
        self.isSurface = isSurface
        self.fills = fills
    }

    /// What this piece's own rule says, in a few words that fit beside its
    /// name. "Across" and "down" carry the axis so a single word like Stretch
    /// is never ambiguous about which direction it applies to.
    public var summary: String {
        // In a stack or a grid this is the ONE piece in the list that is not
        // being arranged, and summarising it by direction hid that: a surface
        // in a column stack read "Stretch across", word for word what a row
        // that fills the width reads. So it says what it is instead.
        if isSurface { return "Surface behind the rest" }
        if horizontal == .stretch, vertical == .stretch { return "Stretch both ways" }
        // Filling carries no direction word: it is about the way the stack
        // runs, so naming an axis for it would be naming the wrong thing the
        // day somebody flips the stack from a row to a column.
        let takes = fills ? "Takes the room left over" : nil
        let across = horizontal.map { "\($0.title) across" }
        let down = vertical.map { "\($0.title) down" }
        return [takes, across, down].compactMap { $0 }.joined(separator: ", ")
    }
}

extension Layer {
    /// The pieces directly inside this container that have a rule of their own,
    /// top-most first so the list reads the way the Layers list does.
    ///
    /// Direct children only: what a piece deeper down says is an argument with
    /// ITS container, and belongs in that container's Layout section, not here.
    /// A piece whose rule happens to match the container's answer is still in
    /// the list, because it stops matching the moment the container changes.
    ///
    /// A rule on the axis the flow decides is NOT in the list, and is not in
    /// the summary of a piece that is: a Bottom inside a column stack moves
    /// nothing, so naming it says somebody is out of line when nobody is.
    /// `arrangement` is this group's own layout, or nil for a group that
    /// arranges nothing, in which case every rule counts as it always did.
    public func contentsWithTheirOwnPlacement(arrangement: GroupLayout?) -> [PlacementOverride] {
        let arranges = arrangement?.arranges == true
        let container = group?.contentPlacement
        return children.reversed().compactMap { child in
            let placement = child.placement
            // What the piece really does, which decides whether the flow is
            // arranging it at all: a piece stretched both ways is the surface
            // and the flow owns neither of its directions, so a rule sitting
            // on the direction the flow would have owned still counts — it is
            // half of what makes this the surface.
            let resolved = LayerPlacement.resolving(child: placement, container: container)
            let flow = PlacementEditing(arrangement: arrangement, placing: resolved)
            let horizontal = flow.canSetHorizontal ? placement?.horizontal : nil
            let vertical = flow.canSetVertical ? placement?.vertical : nil
            // Taking the room left over is a rule of its own even where the
            // piece has no placement at all, and it only counts where a flow
            // actually runs: outside a stack there is nothing to fill.
            let fills = child.fillsTheFlow && flow.setByTheFlow != nil
            guard horizontal != nil || vertical != nil || fills else { return nil }
            return PlacementOverride(id: child.id, name: child.name,
                                     horizontal: horizontal, vertical: vertical,
                                     isSurface: arranges && resolved.isSurface,
                                     fills: fills)
        }
    }
}
