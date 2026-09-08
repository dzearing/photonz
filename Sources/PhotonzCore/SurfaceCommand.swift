import CoreGraphics
import Foundation

/// One row's reading of "be the surface behind the rest"
/// (`docs/design/ui-building.md`, "Stretch inside a hugging container means
/// surface").
///
/// A piece stretched BOTH ways inside a group that arranges its contents steps
/// out of the arrangement: it is painted to the group's own edges and the rest
/// are laid out on top of it, which is what a button's fill is. Getting there
/// used to mean stretching the piece one way and then the other, and only the
/// second of those two picks said what it was about to do. Inside a STACK it
/// could not be done at all from the panel: a stack owns the direction it runs,
/// so the menu for that direction is not a menu, and the second Stretch was
/// never on offer.
///
/// So it is one named answer instead, in the Layout section and in the Layer
/// menu. The reading lives here rather than in either of them so the two cannot
/// drift apart, and so the one question a menu row cannot answer for itself —
/// why it is dead — is a sentence somebody wrote rather than silence.
public struct SurfaceCommand: Hashable, Sendable {

    /// What the Layer menu row is called: the app's one name for a surface, in
    /// the case a menu wears. The panel row says the same words in a sentence's
    /// case, so a person reading either recognises the other.
    public static let menuTitle = "Surface Behind the Rest"

    /// Why the row is dead where the picked pieces are not being arranged at
    /// all: loose on the canvas, or in a group that holds things wherever they
    /// were put. There is no arrangement to step out of, so Stretch there
    /// already means exactly what it says.
    public static let notArrangedReason =
        "Only a piece inside a stack or a grid can be the surface behind the rest. Pick the "
        + "group it is in and set Arrangement in the Layout section."

    /// Why the row is ticked and dead at once: the GROUP tells everything
    /// inside it to stretch both ways, so this piece is the surface because of
    /// a rule set somewhere else, and clearing its own rule cannot change it.
    public static let setByTheGroupReason =
        "This group tells everything inside it to stretch both ways, so the surface is set "
        + "there rather than here. Pick the group and change its Horizontal and Vertical rows."

    /// What pressing it gives you, for the hover line on a live row. A menu row
    /// is a name and nothing else, so this is the only place it can say.
    public static let makesSurfaceReason =
        "Paint this piece to the group's own edges instead of giving it a place in the line, "
        + "and the others are arranged on top of it. Set it back and it is one of them again."

    /// The pieces the row would reach: every picked layer that has a place in
    /// the one container they share. Empty where there is nothing to act on.
    public let layers: [UUID]
    /// Whether the tick is there: every piece it reaches already is the
    /// surface. One piece that is not unticks it, so a mixed selection is one
    /// press away from all of them being it.
    public let isOn: Bool
    /// Whether the picked pieces are all stretched along the way their stack
    /// runs without being the surface: painted right across the group, but not
    /// behind everything in it. Not an answer on offer, a state to read back,
    /// and picking either answer takes them out of it.
    public var isSpanning: Bool = false
    /// Whether the picked pieces disagree: one is the surface and the next is
    /// not. The panel row says Mixed rather than picking one of them to be
    /// wrong about, the way every other row in the dock does.
    public var isMixed: Bool = false
    /// Whether the row is live.
    public let isEnabled: Bool
    /// Why it could not be pressed, in plain words, or nil where it can.
    public let reason: String?

    /// The sentence the row shows on hover: why it is dead where it is, and
    /// what pressing it does where it is not.
    public var help: String { reason ?? Self.makesSurfaceReason }

    public init(layers: [UUID], isOn: Bool, isMixed: Bool = false, isSpanning: Bool = false,
                isEnabled: Bool, reason: String?) {
        self.layers = layers
        self.isOn = isOn
        self.isMixed = isMixed
        self.isSpanning = isSpanning
        self.isEnabled = isEnabled
        self.reason = reason
    }

    /// Nothing picked: a dead row with nothing to explain, like every other row
    /// in the menu at that moment.
    public static let none = SurfaceCommand(layers: [], isOn: false, isEnabled: false,
                                            reason: nil)
}

extension PhotonzDocument {

    /// What the surface row reads for the layers picked, for the Layout section
    /// and the Layer menu alike.
    public func surfaceCommand(layerIDs: [UUID]) -> SurfaceCommand {
        guard !layerIDs.isEmpty else { return .none }
        let selection = placementSelection(layerIDs: layerIDs)
        guard !selection.hasDifferentContainers else {
            return SurfaceCommand(layers: [], isOn: false, isEnabled: false,
                                  reason: PlacementSelection.differentContainersNote)
        }
        guard let containerID = selection.containerID, let container = layer(id: containerID),
              !selection.layers.isEmpty else {
            return SurfaceCommand(layers: [], isOn: false, isEnabled: false,
                                  reason: SurfaceCommand.notArrangedReason)
        }
        let surfaces = selection.layers.map {
            layer(id: $0)?.resolvedPlacement(in: container).isSurface == true
        }
        let isOn = surfaces.allSatisfy { $0 }
        let isMixed = !isOn && surfaces.contains(true)
        guard container.group?.layout?.arranges == true else {
            // Off an arrangement the row has nothing to say, even about a piece
            // that happens to be stretched both ways: with nothing being
            // arranged, stretching both ways is stretching both ways.
            return SurfaceCommand(layers: selection.layers, isOn: false, isEnabled: false,
                                  reason: SurfaceCommand.notArrangedReason)
        }
        // A group that tells everything inside it to stretch both ways makes
        // every piece the surface from outside, and taking a piece's own rule
        // off cannot undo that. The row says where the answer really is rather
        // than being a switch that flips back on its own.
        guard !container.contentPlacementDefault.isSurface else {
            return SurfaceCommand(layers: selection.layers, isOn: true, isEnabled: false,
                                  reason: SurfaceCommand.setByTheGroupReason)
        }
        // Stretched the way the stack runs and not the surface: the row says
        // that instead of calling it one of the pieces, which is the one thing
        // the line under the rows says it is not.
        let spans = !isOn && !isMixed && selection.layers.allSatisfy {
            layer(id: $0)?.resolvedPlacement(in: container)
                .stepsOutOfTheFlow(of: container.group?.layout) == true
        }
        return SurfaceCommand(layers: selection.layers, isOn: isOn, isMixed: isMixed,
                              isSpanning: spans, isEnabled: true, reason: nil)
    }

    /// Make every picked piece the surface behind the rest, or hand it back to
    /// the arrangement, in ONE step that one undo puts back.
    ///
    /// Both directions at once, because the surface IS both directions: set one
    /// at a time and the piece spends a moment being something else, which is
    /// two undo steps and one wrong-looking canvas. Turning it off hands both
    /// directions back to the group rather than inventing a rule nobody asked
    /// for: the piece goes back to doing whatever its neighbours do.
    ///
    /// A piece taking the room its stack has left over stops first. The two
    /// cannot both be true — something painted to the box's own edges is not
    /// waiting for what the flow has spare — and stopping first is what hands
    /// it back the size it had before it started filling, so turning the
    /// surface off later leaves it the size it was drawn at.
    public mutating func setSurface(ids: [UUID], _ isSurface: Bool) {
        for id in ids where layer(id: id) != nil {
            if isSurface, layer(id: id)?.fillsTheFlow == true {
                setFillsTheFlow(id: id, false)
            }
            setPlacement(id: id, horizontal: isSurface ? .stretch : nil)
            setPlacement(id: id, vertical: isSurface ? .stretch : nil)
        }
    }
}
