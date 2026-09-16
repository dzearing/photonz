import Foundation

/// What a right click on the picture is about, and what it has to pick before
/// the menu opens.
///
/// The layers list and the canvas ask the same question — "what does this menu
/// touch?" — and they must not answer it differently, or the same command run
/// from two places does two things. The list's answer is
/// `EditorState.rowMenuTargets`: the row you aimed at, or the whole selection
/// when that row is part of it. This is the same rule with one addition the
/// canvas needs and the list does not.
///
/// **A right click on a layer nobody has picked picks it first.** A row in a
/// list is a NAME you aimed at, and the menu that drops out of it is plainly
/// about that name. A shape on the canvas is a PICTURE you are looking at, and
/// the only thing on screen saying what the app thinks you mean is the
/// selection outline. Without the pick, right clicking one box while another
/// wears the handles opens a menu about the box with no handles on it, and
/// every command in it lands somewhere nobody pointed. Every editor that puts a
/// menu on a canvas picks first for this reason.
///
/// Once the pick has landed the two rules are the same rule, which is the
/// property `CanvasMenuAimTests` holds them to.
public enum CanvasMenuAim: Hashable, Sendable {
    /// The pointer was over no layer at all, so the menu is about the picture
    /// as a whole rather than about anything in it.
    case canvas
    /// The pointer was over `id`. `acts` is every layer the menu's commands
    /// touch; `picks` is the selection the right click must install first, nil
    /// when the selection already covers it and must be left alone.
    case layer(id: UUID, acts: Set<UUID>, picks: Set<UUID>?)

    /// The selection this right click installs before the menu opens, nil when
    /// it leaves the selection exactly as it found it.
    public var picks: Set<UUID>? {
        switch self {
        case .canvas: nil
        case .layer(_, _, let picks): picks
        }
    }

    /// Every layer the menu's commands act on. Empty on bare canvas.
    public var acts: Set<UUID> {
        switch self {
        case .canvas: []
        case .layer(_, let acts, _): acts
        }
    }

    /// The layer the pointer was over, nil on bare canvas.
    public var id: UUID? {
        switch self {
        case .canvas: nil
        case .layer(let id, _, _): id
        }
    }

    /// Work out both answers from what is under the pointer and what is picked
    /// right now.
    public static func aim(at hit: UUID?, picked: Set<UUID>) -> CanvasMenuAim {
        guard let hit else { return .canvas }
        if picked.contains(hit) { return .layer(id: hit, acts: picked, picks: nil) }
        return .layer(id: hit, acts: [hit], picks: [hit])
    }
}
