import Foundation

/// Edit ▸ Tools: every tool on the bar as a menu row, each with its letter.
///
/// The placement contract's menu bar row holds every command, and picking a
/// tool is one: a person who has not found a tool on the bar, or whose window
/// is too narrow to show it, reads it here, and learns its key from the row.
///
/// A letter is printed on ONE row, the row a press of that letter would pick up
/// right now. M owns the marquee pair and swaps them when one is already in
/// hand, and C does the same for Crop and Trim, so printing M on both marquees
/// would print one key twice and promise the wrong tool on one of them. The row
/// does what the key does (`tool(forKey:)`), so a click and a press can never
/// disagree about which tool they hand you.
public enum ToolMenu {

    /// The tools the bar offers, in the bar's order, each family opened out
    /// into its members. `bounds` is what the crop slot holds in this document:
    /// Crop alone in a picture, Crop and Trim in something with time.
    public static func tools(_ layout: ToolBarLayout, bounds: [Tool]) -> [Tool] {
        var tools: [Tool] = []
        for entry in layout.entries {
            switch entry {
            case .tool(let tool) where ToolGroup.containing(tool) == .bounds:
                tools += bounds
            case .tool(let tool):
                tools.append(tool)
            case .group(let group):
                tools += group.tools
            case .blade:
                continue
            }
        }
        return tools
    }

    /// The letter printed beside `tool`: its key, when a plain press of that
    /// key would hand you this tool now. Nil on the rows of a family whose
    /// letter would hand you another member.
    public static func printedKey(for tool: Tool, among tools: [Tool], active: Tool,
                                  remembered: (ToolGroup) -> Tool) -> Character? {
        guard let key = tool.shortcutKey ?? ToolGroup.containing(tool)?.groupKey else { return nil }
        return self.tool(forKey: key, among: tools, active: active, remembered: remembered) == tool ? key : nil
    }

    /// The tool a plain press of `key` hands you, read live: the family rule
    /// for a family's letter, the one tool that owns it otherwise.
    public static func tool(forKey key: Character, among tools: [Tool], active: Tool,
                            remembered: (ToolGroup) -> Tool) -> Tool? {
        let owners = tools.filter { ($0.shortcutKey ?? ToolGroup.containing($0)?.groupKey) == key }
        guard let first = owners.first else { return nil }
        guard let group = ToolGroup.containing(first) else { return first }
        return group.tool(forKey: key, active: active, remembered: remembered(group), offered: Set(tools))
    }
}
