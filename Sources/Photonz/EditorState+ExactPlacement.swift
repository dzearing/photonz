import CoreGraphics
import PhotonzCore

/// Typing an exact position or size, on demand (`ExactPlacement`).
///
/// The same four numbers the panel used to keep open for every layer, reached
/// now from the Layer menu and from a right click on the layer's own row, and
/// shown over the thing they are about instead of at the top of a column the
/// user never came to that column for.
@MainActor
extension EditorState {

    /// Whose numbers the command is about, or nil when there is nothing to
    /// place and the command is off. A live marquee wins, exactly as it does
    /// for the arrow keys and for the fields themselves.
    var exactPlacementSubject: ExactPlacement.Subject? {
        guard Experiments.shared.geometryFieldsEnabled else { return nil }
        return ExactPlacement.subject(pickedLayers: actionableLayerIDs.count,
                                      hasMarquee: regionGeometry != nil)
    }

    var canOpenExactPlacement: Bool { exactPlacementSubject != nil }

    /// The heading of the popover: "Selection" for a marquee, and how many
    /// layers when one typed width would reach several.
    var exactPlacementHeading: String {
        exactPlacementSubject.map(ExactPlacement.heading) ?? ExactPlacement.menuItem
    }

    /// Where the popover points, in the canvas view's own coordinates: the box
    /// the selection outline is drawn around, kept inside what is on screen.
    ///
    /// Zero-sized rather than nil when there is nothing to point at, because a
    /// popover with no anchor at all cannot be presented, and a command that
    /// silently did nothing would be worse than one that opens in the middle.
    var exactPlacementAnchor: CGRect {
        guard let viewport else { return .zero }
        let visible = CGRect(origin: .zero, size: viewport.viewSize)
        return ExactPlacement.anchor(around: exactPlacementBox ?? .zero,
                                     viewport: viewport, canvas: visible)
    }

    /// The box in canvas coordinates the numbers are about: the marquee, or
    /// everything picked taken together.
    private var exactPlacementBox: CGRect? {
        if let region = regionGeometry { return region.bounds }
        return ExactPlacement.box(around: actionableLayerIDs.compactMap { canvasFrame(of: $0) })
    }

    /// Open the numbers over what is picked. Does nothing when there is
    /// nothing to place, so the menu row and the key press agree with the
    /// row's own disabled state rather than opening an empty popover.
    func openExactPlacement() {
        guard canOpenExactPlacement else { return }
        isExactPlacementPresented = true
    }

    func closeExactPlacement() {
        isExactPlacementPresented = false
    }
}
