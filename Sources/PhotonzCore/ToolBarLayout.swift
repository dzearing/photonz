import Foundation

/// A family of tools that shares ONE slot in the tool bar, the way a pro
/// editor has always folded its marquees or its shapes into a single button.
///
/// The slot shows the member you used last, a click picks that member up, and
/// press-and-hold lists the family. Each member keeps whatever letter it has,
/// and shift plus any member's letter walks the family so a keyboard user
/// never needs the list.
public enum ToolGroup: String, CaseIterable, Hashable, Codable, Sendable {
    /// The region selectors: rectangle, ellipse, magic wand (Photoshop's M
    /// and W).
    case selection
    /// The plain drawing shapes: line, rectangle, ellipse. Arrow is NOT here:
    /// it is the redline tool people reach for most and never hides.
    case shapes

    /// The members, in cycle order. The first is the default.
    public var tools: [Tool] {
        switch self {
        case .selection: [.rectSelect, .ellipseSelect, .wand]
        case .shapes: [.line, .rectangle, .ellipse]
        }
    }

    /// The family's name, for its menu and its tooltip.
    public var title: String {
        switch self {
        case .selection: "Selection"
        case .shapes: "Shapes"
        }
    }

    /// A letter that belongs to the family rather than to any member: it
    /// picks the remembered member up. The marquee pair has no letters of its
    /// own, so M stands for the pair; the shapes each keep their own.
    public var groupKey: Character? {
        switch self {
        case .selection: "m"
        case .shapes: nil
        }
    }

    /// Every letter that, with shift held, walks the family: the group key
    /// first, then each member's own key. Deduplicated, in that order.
    public var cycleKeys: [Character] {
        var keys: [Character] = []
        if let groupKey { keys.append(groupKey) }
        for tool in tools {
            if let key = tool.shortcutKey, !keys.contains(key) { keys.append(key) }
        }
        return keys
    }

    /// The member after `tool`, wrapping. A tool from outside the family
    /// starts the walk at the first member.
    public func next(after tool: Tool) -> Tool {
        let members = tools
        guard let index = members.firstIndex(of: tool) else { return members[0] }
        return members[(index + 1) % members.count]
    }

    /// The member a stored raw value names, or the first member when the
    /// value is missing, stale, or names a tool outside the family.
    public func member(from raw: String?) -> Tool {
        guard let raw, let tool = Tool(rawValue: raw), tools.contains(tool) else { return tools[0] }
        return tool
    }

    /// The family holding `tool`, nil for a tool that stands alone.
    public static func containing(_ tool: Tool) -> ToolGroup? {
        allCases.first { $0.tools.contains(tool) }
    }
}

/// The tool bar's order: families of slots, each slot a lone tool or a
/// group. Pure data, so the order is a tested product decision rather than
/// whatever the view happened to list.
///
/// The families read left to right as what you do to a picture: pick and cut
/// and measure it, draw on it, paint it. Photoshop's principle (families, one
/// slot per family, last member remembered) rather than its literal sequence,
/// because it has no arrow, highlight or zoom callout to place.
public struct ToolBarLayout: Hashable, Sendable {
    public enum Entry: Hashable, Sendable {
        case tool(Tool)
        case group(ToolGroup)
    }

    public let families: [[Entry]]

    public init(families: [[Entry]]) {
        self.families = families
    }

    /// Every slot in bar order, families flattened.
    public var entries: [Entry] { families.flatMap { $0 } }

    /// The slot that stands for `tool`: its group's, or its own.
    public func entry(for tool: Tool) -> Entry? {
        let wanted: Entry = ToolGroup.containing(tool).map { .group($0) } ?? .tool(tool)
        return entries.contains(wanted) ? wanted : nil
    }

    /// The grouped bar. Resize Image is not a tool and is not listed: it rides
    /// at the foot of the Crop flyout, the same family (change the picture's
    /// bounds), and in the Image menu.
    public static let families = ToolBarLayout(families: [
        [.tool(.select), .group(.selection), .tool(.crop), .tool(.measure)],
        [.tool(.arrow), .group(.shapes), .tool(.highlight), .tool(.text), .tool(.zoomCallout)],
        [.tool(.fill)],
    ])
}
