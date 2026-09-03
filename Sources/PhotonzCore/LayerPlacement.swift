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
    public var placesItsContents: Bool { isFrame || group?.layout != nil }

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

    /// This layer's own setting with one axis changed, collapsed back to
    /// nothing when both axes end up following the container again.
    public func settingPlacement(horizontal: HorizontalPlacement?) -> LayerPlacement? {
        LayerPlacement(horizontal: horizontal, vertical: placement?.vertical).normalized
    }

    public func settingPlacement(vertical: VerticalPlacement?) -> LayerPlacement? {
        LayerPlacement(horizontal: placement?.horizontal, vertical: vertical).normalized
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

    public init(id: UUID, name: String,
                horizontal: HorizontalPlacement?, vertical: VerticalPlacement?) {
        self.id = id
        self.name = name
        self.horizontal = horizontal
        self.vertical = vertical
    }

    /// What this piece's own rule says, in a few words that fit beside its
    /// name. "Across" and "down" carry the axis so a single word like Stretch
    /// is never ambiguous about which direction it applies to.
    public var summary: String {
        if horizontal == .stretch, vertical == .stretch { return "Stretch both ways" }
        let across = horizontal.map { "\($0.title) across" }
        let down = vertical.map { "\($0.title) down" }
        return [across, down].compactMap { $0 }.joined(separator: ", ")
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
    public var contentsWithTheirOwnPlacement: [PlacementOverride] {
        children.reversed().compactMap { child in
            guard let placement = child.placement, !placement.isEmpty else { return nil }
            return PlacementOverride(id: child.id, name: child.name,
                                     horizontal: placement.horizontal,
                                     vertical: placement.vertical)
        }
    }
}
