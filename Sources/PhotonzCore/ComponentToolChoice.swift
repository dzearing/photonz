import Foundation

/// Which component a click with the Component insert tool places
/// (`Tool.component`).
///
/// A click always places something when there is anything to place: the tool
/// never answers a click with a question. The tool's capsule shows the answer
/// before you click and swaps it, so what lands is never a surprise.
public enum ComponentToolChoice {

    /// The component a click places, out of the ones `offered` (the Library's
    /// components, in the Library's order).
    ///
    /// The one picked in the Library wins, because picking a tile and then
    /// clicking where it goes is the shortest way to say both. With nothing
    /// picked, the one the tool placed last, so a row of buttons is a row of
    /// clicks. First time, the first on offer. A pick or a memory naming
    /// something that is no longer on offer (deleted, or a document that never
    /// had it) is passed over rather than placing nothing.
    public static func component(libraryPick: UUID?, remembered: UUID?,
                                 offered: [UUID]) -> UUID? {
        if let libraryPick, offered.contains(libraryPick) { return libraryPick }
        if let remembered, offered.contains(remembered) { return remembered }
        return offered.first
    }
}
