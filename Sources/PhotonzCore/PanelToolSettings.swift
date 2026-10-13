import Foundation

/// **A tool's settings are in the panel only while that tool is in hand.**
///
/// The panel answers one question: what is this thing I have picked, and what
/// can I set on it right now. A tool's own section (Measure Tool, Magic Wand,
/// the bucket, Crop, Zoom Callout, Lens) is part of that answer only while the
/// tool is the one in hand, and then it sits directly above the pick's own
/// sections, because it decides what the next drag or click does. With any
/// other tool in hand it is noise (the user, 2026-10-13: "You're clogging up
/// the right pane with useless non contextual crap").
///
/// Each condition that adds a tool section in the app already asks for its
/// tool; this is the one rule over all of them, so a section added later, or a
/// saved order that put a tool section somewhere odd, cannot break it. The
/// walk's `expectSections` reads `strays` on every claim.
///
/// Sections are named by their raw ids (`InspectorSectionID` in the app), so
/// the rule stays pure.
public enum PanelToolSettings {

    /// Each tool-settings section and the tool it belongs to.
    public static let sections: [String: Tool] = [
        "measureTool": .measure,
        "wandTool": .wand,
        "fillTool": .fill,
        "cropTool": .crop,
        "calloutTool": .zoomCallout,
        "lensTool": .lens,
    ]

    /// The tool a section is the settings of, or nil when it is not a tool's.
    public static func tool(ofSection id: String) -> Tool? { sections[id] }

    /// The tool sections in `shown` that belong to a tool NOT in hand: what a
    /// walk fails on.
    public static func strays(_ shown: [String], toolInHand: Tool) -> [String] {
        shown.filter { id in sections[id].map { $0 != toolInHand } ?? false }
    }

    /// The order the panel draws: every other tool's section gone, and the
    /// tool in hand's section moved to the top, under the Layers list when
    /// the dock leads with it, so it sits above the pick's own sections and
    /// above the other lists (Measurements, Library) whatever order the dock
    /// has saved. Everything else keeps the order it came in.
    public static func arrange(_ order: [String], toolInHand: Tool) -> [String] {
        var out = order.filter { sections[$0] == nil }
        guard let mine = order.first(where: { sections[$0] == toolInHand }) else { return out }
        out.insert(mine, at: out.first == "layers" ? 1 : 0)
        return out
    }
}
