import CoreGraphics
import Foundation

/// What the layers list says under a row about auto layout
/// (`ui-autolayout.html`, the Layers rows' `.lmeta`): a group that arranges
/// itself says row, column or grid, and a piece inside a stack says how it is
/// sized along the way the stack runs, hug, fill or fixed. One quiet word, so
/// the layout can be read down the list without picking each thing.
///
/// Nil on everything nobody stacked, which is nearly every row: a plain group
/// and a loose layer read exactly as they always did.
public struct StackRowNote: Hashable, Sendable {

    /// What a group that arranges itself does with what it holds.
    public enum Arrangement: String, CaseIterable, Hashable, Sendable {
        case row, column, grid
    }

    /// How a piece of a stack is sized along the way that stack runs.
    public enum Sizing: String, CaseIterable, Hashable, Sendable {
        /// As big as its own contents: words sized by their words, a group
        /// closed around what it holds.
        case hug
        /// Takes the room the stack has left (Fill the Row, Fill the Stack).
        case fill
        /// Keeps the size it was drawn or given.
        case fixed
    }

    /// The group's own arrangement, or nil on a row that is not one.
    public let arrangement: Arrangement?
    /// How the stack around this row sizes it, or nil outside a stack.
    public let sizing: Sizing?
    /// Whether the stack this piece sits in runs left to right, so the hover
    /// says width rather than height.
    public let across: Bool

    /// Nil when there is nothing to say.
    public init?(arrangement: Arrangement?, sizing: Sizing?, across: Bool) {
        guard arrangement != nil || sizing != nil else { return nil }
        self.arrangement = arrangement
        self.sizing = sizing
        self.across = across
    }

    /// The row's second line. The mock's own lower-case words, the group's
    /// arrangement first when a stack sits inside another: "column · hug".
    public var text: String {
        [arrangement?.rawValue, sizing?.rawValue].compactMap { $0 }.joined(separator: " \u{00B7} ")
    }

    /// The same, in words, for the hover.
    public var help: String {
        [arrangement.map(Self.help), sizing.map { help($0) }]
            .compactMap { $0 }.joined(separator: ". ")
    }

    private static func help(_ arrangement: Arrangement) -> String {
        switch arrangement {
        case .row: "Lays out what is inside it left to right"
        case .column: "Lays out what is inside it top to bottom"
        case .grid: "Lays out what is inside it in equal cells"
        }
    }

    private func help(_ sizing: Sizing) -> String {
        switch sizing {
        case .hug: across ? "As wide as what is in it" : "As tall as what is in it"
        case .fill: across ? "Takes the room the row has left" : "Takes the room the stack has left"
        case .fixed: across ? "Keeps the width it was given" : "Keeps the height it was given"
        }
    }

    /// What `layer`'s row says, sitting in `container` (nil at the top of the
    /// tree).
    public static func forRow(_ layer: Layer, in container: Layer?) -> StackRowNote? {
        let layout = container?.group?.layout
        let across = layout?.flowsHorizontally ?? true
        return StackRowNote(arrangement: layer.group?.layout.flatMap(Self.arrangement),
                            sizing: layer.sizingInStack(container),
                            across: across)
    }

    private static func arrangement(_ layout: GroupLayout) -> Arrangement? {
        switch layout.kind {
        case .stack: layout.direction == .row ? .row : .column
        case .grid: .grid
        case nil: nil
        }
    }
}

extension Layer {
    /// How the stack `container` sizes this piece along the way it runs, or nil
    /// where `container` is not a stack or this piece is not one of the pieces
    /// it lines up (the surface behind a button, a piece floated in front, a
    /// piece stretched to the stack's own edges). A grid hands out cells, so
    /// its pieces have no answer here either.
    func sizingInStack(_ container: Layer?) -> StackRowNote.Sizing? {
        guard let layout = container?.group?.layout, layout.kind == .stack else { return nil }
        if resolvedPlacement(in: container).stepsOutOfTheFlow(of: layout) { return nil }
        let across = layout.flowsHorizontally
        // Only where it takes something: Fill with no room left over does
        // nothing, and the row should say what the piece actually does.
        if fillsTheFlow, canFillTheFlow(in: container) { return .fill }
        if text != nil {
            // Words a container wraps still hug: the flow works that width out
            // from the words every pass. Down the page they are as tall as
            // their lines unless somebody gave them more room.
            let hugs = across ? textHugsItsWords : heightChosenByHand == nil
            return hugs ? .hug : .fixed
        }
        if let group {
            // A group nobody gave a size closes around what it holds; a screen
            // is the size it was drawn unless somebody picked Hug.
            guard let own = group.layout else { return group.isFrame ? .fixed : .hug }
            return own.hugs(onAScreen: group.isFrame, horizontal: across) ? .hug : .fixed
        }
        return .fixed
    }
}
