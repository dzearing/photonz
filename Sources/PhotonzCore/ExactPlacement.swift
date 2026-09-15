import CoreGraphics

/// Typing an exact position or size, as something you ASK for.
///
/// The four numbers used to be a section sitting open at the top of the right
/// hand panel for every layer, forever. Moving something is what the pointer is
/// for, and it was measured on 2026-09-15 that those boxes cost the dock 130 of
/// the 1052 points it was asking a 968 point panel for. So they left: the same
/// fields now open on a command, over the thing they are about, and close again
/// when the number has landed.
///
/// What is here is the part that is not a view: whose numbers the command is
/// about, what it calls itself, and where on the canvas the popover points. The
/// fields themselves are unchanged — same typing, same Mixed, same arrow keys,
/// same one undo step — because the complaint was never about the fields.
public enum ExactPlacement {

    /// The command, under one name everywhere it appears: the Layer menu, a
    /// right click on the layer's row, and the heading of what opens. The three
    /// dots are macOS's promise that pressing it asks you for something rather
    /// than doing it.
    public static let menuItem = "Position and Size\u{2026}"

    /// What the command says it is for, on the row and in the panel help.
    public static let help =
        "Type an exact position, size or angle for what you have picked. "
        + "Dragging and the arrow keys do the same job roughly; this is for when the number matters."

    /// The smallest box a popover may be hung off. A hairline at 5% zoom is
    /// under a point on screen, and a popover with nothing to point at lands
    /// wherever the window feels like.
    public static let smallestAnchor: CGFloat = 12

    /// Whose numbers the command is about, or nil when there is nothing to
    /// place and the command is off.
    public enum Subject: Equatable, Sendable {
        /// Everything picked, as ONE subject: type one width and all of them
        /// take it.
        case layers(Int)
        /// The marquee. While a selection tool has the arrow keys they walk the
        /// selection outline rather than the layer under it, so the numbers are
        /// the marquee's, exactly as they were in the section.
        case marquee
    }

    /// The same rule the arrow keys use, so the command and the keyboard can
    /// never disagree: a live marquee owns the numbers, else the picked layers
    /// do, else there is nothing to place.
    public static func subject(pickedLayers: Int, hasMarquee: Bool) -> Subject? {
        if hasMarquee { return .marquee }
        return pickedLayers > 0 ? .layers(pickedLayers) : nil
    }

    /// The heading of what opens. A marquee says so, because a surface that
    /// swaps subject silently is a surface telling a lie, and several layers
    /// say how many, because one typed width reaches all of them.
    public static func heading(for subject: Subject) -> String {
        switch subject {
        case .marquee: "Selection"
        case .layers(let count):
            count > 1 ? "Position and Size, \(count) layers" : "Position and Size"
        }
    }

    /// The one box several picked layers make between them, in whatever space
    /// the boxes were given in. Nil when nothing is picked.
    public static func box(around boxes: [CGRect]) -> CGRect? {
        guard var union = boxes.first else { return nil }
        for box in boxes.dropFirst() { union = union.union(box) }
        return union
    }

    /// Where the popover points, in view coordinates: the picked box as the
    /// camera has it, kept inside what is actually on screen.
    ///
    /// Three things can go wrong and all three end with an arrow pointing at
    /// nothing. A box can hang off the edge, in which case the part on screen
    /// is what gets pointed at; it can be scrolled out of view entirely, in
    /// which case the middle of the canvas is the honest answer; and it can be
    /// smaller than a popover's arrow at low zoom, in which case it is grown
    /// about its own middle rather than pointed at as a dot.
    public static func anchor(around box: CGRect, viewport: Viewport,
                              canvas visible: CGRect) -> CGRect {
        let inView = box.applying(viewport.documentToView)
        let onScreen = inView.intersection(visible)
        let landing = onScreen.isNull || onScreen.isEmpty
            ? CGRect(x: visible.midX, y: visible.midY, width: 0, height: 0)
            : onScreen
        return grown(landing, toAtLeast: smallestAnchor, inside: visible)
    }

    /// A box grown about its own middle until a popover has something to hang
    /// off, then slid back inside what is on screen rather than being allowed
    /// to grow out of the window.
    private static func grown(_ box: CGRect, toAtLeast minimum: CGFloat,
                              inside visible: CGRect) -> CGRect {
        let width = max(box.width, minimum)
        let height = max(box.height, minimum)
        var result = CGRect(x: box.midX - width / 2, y: box.midY - height / 2,
                            width: width, height: height)
        if result.minX < visible.minX { result.origin.x = visible.minX }
        if result.minY < visible.minY { result.origin.y = visible.minY }
        if result.maxX > visible.maxX { result.origin.x = max(visible.minX, visible.maxX - width) }
        if result.maxY > visible.maxY { result.origin.y = max(visible.minY, visible.maxY - height) }
        return result
    }
}
