import Foundation

/// **View mode and Edit mode**: what a window holding a document with time is
/// set up for.
///
/// View is a player, the way QuickTime opens a clip: the picture fitted to the
/// whole window, a slim transport under it, and nothing else. No tool bar, no
/// tracks, no panel, no handles. Edit is the whole editor, Final Cut's way: the
/// tool bar, the timeline with its tracks and the panel, exactly as this window
/// last had them. A segmented control at the right of the title bar switches,
/// and so do ⌘1, ⌘2 and E.
///
/// A recording opens in View, every time, whatever the last one was left in:
/// the user, 2026-09-28, "when I open a video, again, I don't want to see the
/// full edit experience by default. I want a minimized look to focus on the
/// video playback." Anything already worked on opens in Edit, because you are
/// coming back to an edit. Starting an edit from View (an edit key, a tool, a
/// right click's edit, media dropped in) switches to Edit by itself.
///
/// This replaced the tucked-away timeline of 2026-09-25, which folded only the
/// tracks and remembered the last choice by hand, so after one expand every
/// recording opened expanded.
///
/// A picture has no modes: it is always the editor.
public enum ViewEditMode: String, CaseIterable, Hashable, Codable, Sendable {
    case view, edit

    /// What the switch says.
    public var title: String {
        switch self {
        case .view: "View"
        case .edit: "Edit"
        }
    }

    /// What the View menu calls it, where "View" alone would read as the
    /// menu's own name.
    public var menuTitle: String {
        switch self {
        case .view: "View Mode"
        case .edit: "Edit Mode"
        }
    }

    /// The glyph beside the switch's words in a tooltip or a menu.
    public var symbol: String {
        switch self {
        case .view: "play.rectangle"
        case .edit: "slider.horizontal.below.rectangle"
        }
    }

    /// The digit that, with ⌘, picks this mode. V is the arrow, so View
    /// cannot have it; one and two are the switch's order, left to right.
    public var commandKey: Character {
        switch self {
        case .view: "1"
        case .edit: "2"
        }
    }

    /// The other one: what E switches to.
    public var toggled: ViewEditMode { self == .view ? .edit : .view }

    /// The plain letter that switches between the two while nothing is being
    /// typed. E is free: no tool here takes it.
    public static let toggleKey: Character = "e"

    /// How long the editing takes to come and go, in seconds. Quick enough to
    /// never be waited on, slow enough to be seen leaving.
    public static let transitionSeconds: Double = 0.25

    /// Whether `document` offers the two modes at all. Only a document with
    /// time: a picture is always the editor, and has no switch.
    public static func applies(to document: PhotonzDocument) -> Bool {
        document.hasTime
    }

    /// Which mode `document` opens in when its window first shows it.
    ///
    /// - Parameter forAGuide: the document is a guide's sample, whose cards
    ///   point at the tracks and the tools, so it opens in Edit.
    public static func opening(_ document: PhotonzDocument, forAGuide: Bool = false) -> ViewEditMode {
        guard applies(to: document), !forAGuide else { return .edit }
        // Something already done to it: you are coming back to an edit.
        return document.isUntouchedRecording ? .view : .edit
    }

    /// Whether picking `tool` starts an edit, and so switches View to Edit.
    /// The arrow is what View already has in hand, so picking it is not one.
    public static func pickingStartsAnEdit(_ tool: Tool) -> Bool {
        tool != .select
    }
}

extension PhotonzDocument {

    /// A recording exactly as it came off the disk: one clip, one piece, all
    /// of it in play. Anything more (a second layer, a cut, a trim) means
    /// somebody has worked on it.
    public var isUntouchedRecording: Bool {
        guard hasTime, layers.count == 1, let only = layers.first, only.isClip,
              only.clipPieces?.isOnePlainPiece == true else { return false }
        return only.time?.spareBeforeMS == 0 && only.time?.spareAfterMS == 0
    }
}

extension TimelineKeyCommand {

    /// Whether this key starts an edit, and so switches View to Edit. Watching
    /// keys (space, J/K/L, the arrows, Home and End) leave the mode alone,
    /// because watching is what View is for. V hands the press on to the
    /// canvas's arrow, so it is not one, and neither are the mode keys.
    public var startsAnEdit: Bool {
        switch self {
        case .playPause, .playInToOut, .shuttle, .stepFrames, .editPoint, .marker, .goToStart, .goToEnd,
             .selectTool, .showMode, .toggleViewEdit, .clearMarks:
            // Escape only clears marks the tracks show, so never from View.
            return false
        case .markIn, .markOut, .clearIn, .clearOut, .addMarker, .splitAtPlayhead, .lift,
             .rippleDelete, .extractMarked, .liftMarked, .rippleTrimToPlayhead,
             .applyDefaultTransition, .toggleSnapping, .bladeTool, .trackSelectForwardTool, .rangeTool,
             .zoomIn, .zoomOut, .zoomToFit:
            return true
        }
    }
}

/// **The timeline toggle** at the right of a recording's transport: the tracks
/// open and closed, the way the title bar's panel toggle does the panel.
///
/// Closing the tracks keeps the window in Edit, with its tool bar and panel,
/// because the person asked for the room under the picture and nothing else.
/// From View a press is a way into editing, so it lands in Edit with the tracks
/// up. Whether the tracks are closed is the window's, never remembered: the
/// timeline that folded by hand and stayed folded for every later recording is
/// what View and Edit replaced on 2026-09-28.
public enum TimelineToggle {

    /// Where a press on the toggle leaves the window.
    public static func pressed(mode: ViewEditMode,
                               tracksShown: Bool) -> (mode: ViewEditMode, tracksShown: Bool) {
        switch mode {
        case .view: return (.edit, true)
        case .edit: return (.edit, !tracksShown)
        }
    }

    /// Whether it is lit: the tracks are on screen.
    public static func isOn(mode: ViewEditMode, tracksShown: Bool) -> Bool {
        mode == .edit && tracksShown
    }

    /// What its tooltip says: what a press will do.
    public static func tooltip(isOn: Bool) -> String {
        isOn ? "Hide Timeline" : "Show Timeline"
    }

    /// The key that does the same, as the View menu shows it.
    public static let shortcut = "⌥⌘T"
}
