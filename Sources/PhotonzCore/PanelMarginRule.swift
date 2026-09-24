import CoreGraphics

/// Every row and control in the right hand panel keeps the panel's side margin.
///
/// UX-PATTERNS §3: a section's rows begin on the panel's margin and end on it,
/// and only a subsection steps further in. On 2026-09-23 the user found four
/// video sections drawn with no inset at all, their values running into both
/// edges of the panel, and nothing had ever compared a section against the
/// margin every other section keeps. A walk measures the live panel with this
/// (`panelMargins`), so a section written next month without the inset fails
/// the day it lands rather than the day somebody looks.
public enum PanelMarginRule {
    /// The margin on both sides of the panel's content.
    public static let margin: CGFloat = EditorChromeLayout.panelEdgeInset

    /// A point either way is how a centred glyph rounds and how a text box
    /// reports its bezel to accessibility, not a breach.
    public static let tolerance: CGFloat = 1

    /// One labelled row or control, where it was drawn, in the same
    /// coordinates as the panel's own frame.
    public struct Item: Equatable, Sendable {
        public let name: String
        public let frame: CGRect

        public init(name: String, frame: CGRect) {
            self.name = name
            self.frame = frame
        }
    }

    public enum Side: String, Equatable, Sendable {
        case leading, trailing
    }

    /// A row that came closer to an edge than the margin allows.
    public struct Breach: Equatable, Sendable {
        public let name: String
        public let side: Side
        /// How far in from that edge it actually is. Negative when it runs
        /// past the edge and out of the panel.
        public let inset: CGFloat

        public init(name: String, side: Side, inset: CGFloat) {
            self.name = name
            self.side = side
            self.inset = inset
        }

        /// What a person with a ruler would say about it.
        public var sentence: String {
            let edge = side == .leading ? "left" : "right"
            if inset < 0 {
                return "\"\(name)\" runs \(Self.points(-inset)) past the panel's \(edge) edge"
            }
            let verb = side == .leading ? "starts" : "ends"
            return "\"\(name)\" \(verb) \(Self.points(inset)) from the panel's \(edge) edge, "
                + "not \(Self.points(PanelMarginRule.margin))"
        }

        static func points(_ value: CGFloat) -> String {
            let rounded = (Double(value) * 10).rounded() / 10
            return rounded == rounded.rounded() ? "\(Int(rounded))pt" : "\(rounded)pt"
        }
    }

    /// Every side of every item that is closer to the panel's edge than the
    /// margin, leading before trailing, in the order the items came.
    ///
    /// Something with no size (not laid out, or folded away) is not measured,
    /// and neither is anything that does not overlap the panel at all: a
    /// sheet's buttons and the Settings window carry the same markers.
    public static func breaches(of items: [Item], in panel: CGRect) -> [Breach] {
        items.flatMap { item -> [Breach] in
            guard item.frame.width > 0, item.frame.height > 0,
                  item.frame.intersects(panel) else { return [] }
            let leading = item.frame.minX - panel.minX
            let trailing = panel.maxX - item.frame.maxX
            var found: [Breach] = []
            if leading < margin - tolerance {
                found.append(Breach(name: item.name, side: .leading, inset: leading))
            }
            if trailing < margin - tolerance {
                found.append(Breach(name: item.name, side: .trailing, inset: trailing))
            }
            return found
        }
    }

    /// How much wider than its dock the panel came out, or nil when it fits.
    ///
    /// The dock gives the panel a fixed width, and SwiftUI CENTRES a child
    /// that will not fit, so one row that cannot shrink (a segmented control,
    /// a label that will not wrap) pushes every section out past both sides:
    /// the dividers run over the canvas and the right margin shrinks. Every row
    /// then measures as if it kept its margin, because it does keep it, from a
    /// panel that is no longer where the dock is.
    public static func overflow(panelWidth: CGFloat, dockWidth: CGFloat) -> CGFloat? {
        let over = panelWidth - dockWidth
        return over > tolerance ? over : nil
    }

    public static func overflowSentence(_ over: CGFloat, dockWidth: CGFloat) -> String {
        "the panel is \(Breach.points(over)) wider than its \(Breach.points(dockWidth)) dock: "
            + "a section in it is too wide to fit, so the panel spills over the canvas and off the window"
    }
}
