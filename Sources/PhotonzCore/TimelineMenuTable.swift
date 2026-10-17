import Foundation

/// **What a right click on each kind of thing on the timeline offers.** One
/// table, so the app's menus, its tests and the design note
/// (`docs/design/timeline-right-click.md`) say the same thing.
///
/// The user, 2026-10-17: "I right click on a clip, and i get this enormous
/// right click menu which makes nearly no sense to me. It is as if we didn't
/// consider what these things meant in a particular context." A video clip
/// offered 21 rows in five groups, and a gap offered the whole track header.
///
/// So each kind gets its own short menu: about ten rows in at most four
/// groups, what you do at the playhead first, the clipboard and the deletes
/// last, and the long tail one level down under More (on empty space and in a
/// gap, under Track: the header's own menu). A row that cannot act on this
/// thing here is left OUT by the app, never greyed: the table says where a
/// row goes when it applies, not that it always shows.
public enum TimelineMenuThing: String, CaseIterable, Sendable {
    /// A recording or a video: it has a picture, and maybe a sound.
    case videoClip
    /// A video's sound, drawn on the track under it and still linked to it.
    case linkedSound
    /// A sound of its own: music, a voice-over, a detached sound.
    case soundClip
    /// A title page or a name card built from a design.
    case title
    /// A picture, a shape, clip art: something placed in time that is not a title.
    case picture
    /// One line on the Captions track.
    case caption
    /// A zoom's bar on the lane under a recording.
    case zoom
    /// A cut: a join inside one clip, or the edit point between two.
    case join
    /// Empty time between two clips on one track.
    case gap
    /// Track space with nothing in it.
    case emptySpace
}

/// One row a timeline right-click menu can carry. The app draws each one
/// (`EditorState+TimelineMenus`); some open a submenu, and a few stand for a
/// list the app already has (`captionsTrack`, `trackRows`).
public enum TimelineMenuRow: String, CaseIterable, Sendable {
    // At the playhead
    case split, freezeFrame, speed, startAtPlayhead, endAtPlayhead
    // What a clip does
    case addTransition, detachAudio, audio, normalize, cleanNoise, resetGain, animateIn, animateOut
    // The clipboard and the deletes
    case cut, copy, delete, rippleDelete
    // One level down
    case more, track
    case showPicture, rippleTrimStart, rippleTrimEnd, fadeIn, fadeOut, punchIn, addZoom, suggestZooms, addClick
    case animate, addKey, pasteKeys, breakApart, replayTitle, saveAsPreset, addCaptions
    case selectForward, duplicate, rename, revealInFinder
    // A caption
    case editWords, joinWithNextLine, startHere, captionsTrack
    // A zoom
    case followCursor, zoomAmount, deleteZoom
    // A cut
    case applyDefaultTransition, transitionLength, transitionCurve, removeTransition
    case copyTransition, pasteTransition, rollEdit, joinThroughEdit
    // Space on a track
    case closeGap, addTitlePage, addNameCard, addText, addRectangle, putLayerHere, pasteHere
    case zoomToFit, compactTracks, trackRows
}

public enum TimelineMenuTable {

    /// The most rows a kind's top level may offer, More counted.
    public static let mostTopLevelRows = 11
    /// The most groups, separators between them, a kind's top level may have.
    public static let mostGroups = 4

    /// The top level of `thing`'s menu, group by group.
    public static func groups(for thing: TimelineMenuThing) -> [[TimelineMenuRow]] {
        switch thing {
        case .videoClip:
            [[.split, .freezeFrame, .speed],
             [.addTransition, .detachAudio, .audio],
             [.cut, .copy, .delete, .rippleDelete],
             [.more]]
        case .linkedSound, .soundClip:
            [[.split, .speed],
             [.detachAudio, .normalize, .cleanNoise, .resetGain],
             [.cut, .copy, .delete, .rippleDelete],
             [.more]]
        case .title, .picture:
            [[.split, .startAtPlayhead, .endAtPlayhead],
             [.animateIn, .animateOut, .addTransition],
             [.cut, .copy, .delete, .rippleDelete],
             [.more]]
        case .caption:
            [[.editWords, .joinWithNextLine, .startHere],
             [.delete],
             [.more]]
        case .zoom:
            [[.followCursor, .zoomAmount],
             [.deleteZoom]]
        case .join:
            [[.applyDefaultTransition, .addTransition, .transitionLength, .transitionCurve, .removeTransition],
             [.copyTransition, .pasteTransition],
             [.rollEdit, .joinThroughEdit]]
        case .gap:
            [[.closeGap],
             [.pasteHere],
             [.zoomToFit, .compactTracks],
             [.track]]
        case .emptySpace:
            [[.addTitlePage, .addNameCard, .addText, .addRectangle, .putLayerHere],
             [.captionsTrack, .pasteHere],
             [.zoomToFit, .compactTracks],
             [.track]]
        }
    }

    /// What is one level down, under `moreRow(for:)`, group by group.
    public static func moreGroups(for thing: TimelineMenuThing) -> [[TimelineMenuRow]] {
        switch thing {
        case .videoClip:
            [[.showPicture, .rippleTrimStart, .rippleTrimEnd],
             [.fadeIn, .fadeOut, .punchIn, .addZoom, .suggestZooms, .addClick],
             [.animate, .addKey, .pasteKeys],
             [.breakApart, .selectForward, .duplicate, .rename, .revealInFinder]]
        case .linkedSound, .soundClip:
            [[.rippleTrimStart, .rippleTrimEnd],
             [.addCaptions],
             [.breakApart, .selectForward, .duplicate, .rename, .revealInFinder]]
        case .title, .picture:
            [[.fadeIn, .fadeOut, .animate, .addKey, .pasteKeys],
             [.replayTitle, .saveAsPreset],
             [.selectForward, .duplicate, .rename]]
        case .caption:
            [[.captionsTrack]]
        case .zoom, .join:
            []
        case .gap, .emptySpace:
            [[.trackRows]]
        }
    }

    /// The row the long tail hangs from: More on a thing, Track on the track
    /// itself, whose header menu it is.
    public static func moreRow(for thing: TimelineMenuThing) -> TimelineMenuRow {
        switch thing {
        case .gap, .emptySpace: .track
        default: .more
        }
    }

    /// A row's words where the table decides them: the rows that act at the
    /// playhead say where it is, the way "Add Key at 0:02.00" does
    /// (`TimelinePointing.atPlayhead`). Nil where the app words the row from
    /// what it is acting on.
    public static func title(_ row: TimelineMenuRow, playheadMS ms: Int) -> String? {
        switch row {
        case .split: TimelinePointing.atPlayhead("Split", ms: ms)
        // It asks how long before it freezes, so it ends in an ellipsis.
        case .freezeFrame: TimelinePointing.atPlayhead("Freeze Frame", ms: ms) + "\u{2026}"
        case .startAtPlayhead: TimelinePointing.atPlayhead("Start", ms: ms)
        case .endAtPlayhead: TimelinePointing.atPlayhead("End", ms: ms)
        case .rollEdit: TimelinePointing.atPlayhead("Roll Edit", ms: ms).replacingOccurrences(of: " at ", with: " to ")
        case .cut: "Cut"
        case .copy: "Copy"
        case .more: "More"
        case .track: "Track"
        default: nil
        }
    }
}
