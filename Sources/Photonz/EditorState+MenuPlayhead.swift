import Foundation
import Observation
import PhotonzCore

// MARK: What the menu bar knows about the playhead
//
// A person watching a video play saw the menu bar flicker on every frame and
// stop the moment they paused (2026-10-11). The menu bar's commands body read
// the playhead, so the playhead moving on re-ran it thirty times a second, and
// every pass had SwiftUI hand the whole bar back to AppKit: it put View back in
// its own place and `MenuBarArranger` moved it before Window again, which is
// the flicker. Measured with `the-menu-bar-stays-still-while-playing-walk`:
// 179 passes and 716 menus taken off the bar and put back in six seconds of
// playback, and the main thread busy for half of it.
//
// Most of the menu reads the playhead without saying so: Split, Delete, Freeze
// Frame, the transition and speed rows all act on "the clip picked, else the
// one under the playhead" (`clipInHandID`), and that is decided by where the
// playhead is. The answers only change when the playhead crosses something,
// though: into a clip, onto a cut, past a key, a marker or a click. So:
//
// - while the commands body is built, reading the playhead is not watched
//   (`readingForTheMenu`), so the clock moving on never re-runs it by itself;
// - the body reads `menuPlayhead` instead, the answers that depend on the
//   playhead, worked out again whenever anything they read changes and
//   written only when one of them is different. Crossing a boundary re-runs
//   the body, which then reads the live playhead for every row.
//
// A row that reads the playhead through something left out of `MenuPlayhead`
// is not wrong for long: it is brought up to date by the next pass, which any
// boundary, pick or edit makes. The walk guards the other side, that playing
// never re-runs the body.

/// The playhead-dependent answers the menu bar shows, as one value that is
/// equal for as long as none of them changes.
struct MenuPlayhead: Equatable {
    var clipInHand: UUID?
    var pieceInHand: Int?
    var cutInHand: DocumentCut?
    var canSplitClip = false
    var canSplitEverything = false
    var canHoldFrame = false
    var canMarkClip = false
    var canRippleTrimStart = false
    var canRippleTrimEnd = false
    var canRollCut = false
    var canApplyDefaultTransition = false
    var canGoToPreviousEdit = false
    var canGoToNextEdit = false
    var canGoToPreviousKey = false
    var canGoToNextKey = false
    var canGoToPreviousMarker = false
    var canGoToNextMarker = false
    var canKey = false
    var canRemoveKey = false
    var canPunchIn = false
    var markerAtPlayhead: UUID?
    var clickAtPlayhead: ClickMark?
    var nextClickMS: Int?
    var clipToAddClickTo: UUID?
    var clipToAddZoom: UUID?
    var captionWordInHand: CaptionWordRef?
    var curvedStretchInHand: Int?
    var betweenKeysCurve: EasingCurve?
    var placedLayerCanStart = false
    var placedLayerCanEnd = false
}

#if PHOTONZ_PLAYTEST
extension MenuPlayhead {
    /// The answers that differ, by name, for a walk's log line.
    static func differences(_ old: MenuPlayhead, _ new: MenuPlayhead) -> [String] {
        zip(Mirror(reflecting: old).children, Mirror(reflecting: new).children).compactMap { was, now in
            String(describing: was.value) == String(describing: now.value) ? nil : was.label
        }
    }
}
#endif

// MARK: What the menu bar knows about the document
//
// The same goes for the document, a pass late rather than on a boundary.
// Every edit re-ran the commands body in the edit's own pass, and SwiftUI
// handed the whole bar back to AppKit with it: about 7 ms of the pass after
// Command Return finished a typed title on a video, and 10 ms of a click on
// the Cross dissolve tile (`an-editing-session-walk`, Time Profiler,
// 2026-10-18). Nobody is looking at the menu bar in that frame. So while the
// body is built, the document and the undo history are read as they are but
// not watched, and the body watches `menuDocumentRevision` instead, which
// moves on in the pass after the document does (`NextRunLoopPass`): the edit is
// drawn in one frame and the bar catches up in the next. Several edits in one
// turn are one catch-up.

extension EditorState {
    /// True while the menu bar's commands body is being built: reading the
    /// playhead then is not watched (`documentTimeMS`).
    @MainActor static var readingForTheMenu = false

    /// Called at the top of the commands body: from here to `endMenuRead`
    /// the playhead is read without being watched, and what the menu shows
    /// about it is watched through `menuPlayhead` instead.
    static func beginMenuRead(_ editor: EditorState?) {
        // Next's menu bar only (`next-a-pro-menu-bar`), where the flicker was:
        // with the flag off the menu reads the playhead as it always did.
        guard Experiments.shared.proMenuBarEnabled else { return }
        readingForTheMenu = true
        guard let editor else { return }
        _ = editor.menuPlayhead
        if !editor.watchesMenuPlayhead {
            // Never written while a body is being built: the first answers
            // land on the next turn of the run loop.
            DispatchQueue.main.async { MainActor.assumeIsolated { editor.watchMenuPlayhead() } }
        }
    }

    static func endMenuRead() {
        readingForTheMenu = false
    }

    /// The document changed: the menu bar hears about it in the next pass,
    /// once however many edits this one makes.
    func noteWhatTheMenuSees() {
        // Only where the menu reads unwatched (`beginMenuRead`).
        guard Experiments.shared.proMenuBarEnabled, !menuDocumentCatchUpAsked else { return }
        menuDocumentCatchUpAsked = true
        Task { @MainActor [weak self] in
            await NextRunLoopPass.start()
            guard let self else { return }
            self.menuDocumentCatchUpAsked = false
            self.menuDocumentRevision &+= 1
        }
    }

    /// Works the answers out, watching everything they read, and does it again
    /// the moment any of that changes. The value is written only when it is
    /// different, so a clock moving on inside one clip writes nothing.
    func watchMenuPlayhead() {
        watchesMenuPlayhead = true
        let answers = withObservationTracking { workOutMenuPlayhead() } onChange: { [weak self] in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.menuPlayheadChanged() } }
        }
        guard answers != menuPlayhead else { return }
        #if PHOTONZ_PLAYTEST
        ViewBuildMeter.shared.note("menu playhead at \(documentTimeMS)ms: "
            + MenuPlayhead.differences(menuPlayhead, answers).joined(separator: ","))
        #endif
        menuPlayhead = answers
    }

    /// Several changes in one turn of the run loop are one pass, not several.
    private func menuPlayheadChanged() {
        guard watchesMenuPlayhead else { return }
        watchMenuPlayhead()
    }

    func workOutMenuPlayhead() -> MenuPlayhead {
        guard documentHasTime else { return MenuPlayhead() }
        let placed = placedLayerInHand?.id
        return MenuPlayhead(
            clipInHand: clipInHandID,
            pieceInHand: clipPieceInHand,
            cutInHand: cutInHand,
            canSplitClip: canSplitClipAtPlayhead,
            canSplitEverything: canSplitEverythingAtPlayhead,
            canHoldFrame: canHoldFrameAtPlayhead,
            canMarkClip: canMarkClipAtPlayhead,
            canRippleTrimStart: canRippleTrimToPlayhead(.start),
            canRippleTrimEnd: canRippleTrimToPlayhead(.end),
            canRollCut: canRollCutInHand,
            canApplyDefaultTransition: canApplyDefaultTransition(),
            canGoToPreviousEdit: canGoToEditPoint(forward: false),
            canGoToNextEdit: canGoToEditPoint(forward: true),
            canGoToPreviousKey: canGoToKey(forward: false),
            canGoToNextKey: canGoToKey(forward: true),
            canGoToPreviousMarker: canGoToMarker(forward: false),
            canGoToNextMarker: canGoToMarker(forward: true),
            canKey: canKeyAtPlayhead,
            canRemoveKey: canRemoveKeyAtPlayhead,
            canPunchIn: canPunchIn,
            markerAtPlayhead: markerAtPlayhead,
            clickAtPlayhead: clickAtPlayhead?.mark,
            nextClickMS: nextClickMS,
            clipToAddClickTo: clipToAddClickTo,
            clipToAddZoom: clipToAddZoom(atMS: documentTimeMS),
            captionWordInHand: captionWordInHand,
            curvedStretchInHand: curvedStretchInHand,
            betweenKeysCurve: betweenKeysCurve,
            placedLayerCanStart: placed.map(canStartPlacedLayerHere) ?? false,
            placedLayerCanEnd: placed.map(canEndPlacedLayerHere) ?? false)
    }
}

