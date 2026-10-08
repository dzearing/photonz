import AppKit
import Foundation
import PhotonzCore
import SwiftUI

// Premiere's keys on the timeline (`TimelineKeys.swift` decides what a press
// means; this does it).
//
// The timeline has the keyboard from the moment it shows up (a recording
// opening, a clip dropped into a picture) and after any press in the dock, and
// loses it to a press anywhere else, Premiere's own panel focus. While it does, J/K/L
// shuttle, I and O mark, X marks the clip under the playhead, ⇧I and ⇧O go
// to the marks, ' and ; extract and lift what they mark, Q and W
// ripple trim the clip under the playhead up to it, S switches snapping, the
// arrows step frames and edit points, ⌘← and ⌘→ nudge the picked clips a
// frame (`EditorState+ClipNudge`), ⇧M goes to the next marker, and V, B and
// the zoom keys pick the timeline's tools, where the same letters on the canvas
// are Photoshop's tools. `TimelineKeyRouter` gets a press here before the
// toolbar or the menu bar can take it.
extension EditorState {

    /// The timeline showed up, or a press in the dock: it has the keyboard now.
    func takeTimelineKeyboard() {
        guard documentHasTime, !timelineHasKeyboard else { return }
        timelineHasKeyboard = true
    }

    /// A press anywhere else in the window: the canvas has it back. Not in
    /// View mode, where the picture has no tools to hand the letters to, and
    /// J, K and L have to keep working after a click on it.
    func releaseTimelineKeyboard() {
        guard timelineHasKeyboard, !isWatching else { return }
        timelineHasKeyboard = false
        isShuttleKHeld = false
    }

    /// A key went down. True when the timeline did something with it, which
    /// is what keeps the toolbar and the menu bar from acting on it too.
    func timelineKeyDown(_ press: TimelineKeyPress) -> Bool {
        guard documentHasTime else { return false }
        let focused = timelineHasKeyboard
        if focused, press.key == .letter("k"), press.modifiers.isEmpty {
            isShuttleKHeld = true
        }
        guard let command = TimelineKeys.command(for: press, timelineFocused: focused,
                                                 kHeld: isShuttleKHeld && press.key != .letter("k")) else {
            // View mode has no tool bar, so nothing else holds the tools'
            // letters: T for a title or R for a box picks the tool here, and
            // picking it brings the editor (`ViewEditMode`).
            if isWatching, press.modifiers.isEmpty, !press.isRepeat, case .letter(let letter) = press.key,
               let tool = Tool.allCases.first(where: { $0.shortcutKey == letter }),
               ViewEditMode.pickingStartsAnEdit(tool) {
                setTool(tool)
                return true
            }
            // A held K repeats: that is K still being down, not a new Stop.
            return focused && press.key == .letter("k") && press.modifiers.isEmpty && press.isRepeat
        }
        return perform(timelineCommand: command)
    }

    /// A key came up. Only K's matters: it stops J and L creeping.
    func timelineKeyUp(_ press: TimelineKeyPress) {
        if press.key == .letter("k") { isShuttleKHeld = false }
    }

    /// Do what a key asks. False where there was nothing for it to do, so the
    /// press carries on to whatever would have had it.
    ///
    /// A command that starts an edit switches View to Edit to show it; one
    /// that found nothing to do leaves the window as it was.
    @discardableResult
    func perform(timelineCommand command: TimelineKeyCommand) -> Bool {
        let took = carryOut(timelineCommand: command)
        if took, command.startsAnEdit { switchToEditForAnEdit() }
        return took
    }

    private func carryOut(timelineCommand command: TimelineKeyCommand) -> Bool {
        switch command {
        case .playPause:
            toggleDocumentPlayback()
        case .playInToOut:
            return playInToOut()
        case .shuttle(let key):
            shuttle(key)
        case .stepFrames(let frames):
            stepDocument(byFrames: frames)
        case .nudgeClips(let frames):
            // Nothing picked: the press is not the timeline's. Picked but
            // already against an edge, it still is, and nothing moves.
            guard canNudgeClips else { return false }
            nudgeClips(byFrames: frames)
        case .editPoint(let forward):
            goToEditPoint(forward: forward)
        case .marker(let forward):
            // At the last marker, or the first, nothing moves; the press is
            // still the timeline's, so ⇧M never falls through to the canvas's
            // selection cycle.
            goToMarker(forward: forward)
        case .goToStart:
            goToDocumentStart()
        case .goToEnd:
            goToDocumentEnd()
        case .markIn:
            setMarkIn(atMS: documentTimeMS)
        case .markOut:
            setMarkOut(atMS: documentTimeMS)
        case .markClip:
            // Nothing under the playhead: still the timeline's press, so X
            // never swaps the fill colours behind a person's back.
            markClipAtPlayhead()
        case .goToIn:
            goToMark(in: true)
        case .goToOut:
            goToMark(in: false)
        case .clearIn:
            clearMarkIn()
        case .clearOut:
            clearMarkOut()
        case .clearMarks:
            // Nothing marked, or the tracks out of sight in View: Escape
            // carries on to the canvas, which lets go of a pick.
            guard canClearMarkInOut, !isWatching, !isHoldingATimelineDrag else { return false }
            clearMarkInOut()
        case .addMarker:
            addMarker(atMS: documentTimeMS)
        case .splitAtPlayhead:
            splitClipAtPlayhead()
        case .lift:
            // A range just drawn on the ruler is what is in hand when it is
            // (`EditorState+RulerRange`): ⌫ lifts it.
            if rulerRangeHeld != nil { return liftMarkedStretch() }
            // ...and a range on some tracks, or pieces a box picked
            // (`EditorState+TrackRange`).
            if trackRangeHeld != nil || timelinePicksHeld != nil { return liftTrackThing() }
            // ...and a gap a click picked: Delete closes it, as in Premiere.
            if timelineGapHeld != nil {
                closeGapInHand()
                return true
            }
            return liftInHand()
        case .rippleDelete:
            guard canRippleDeleteInHand else { return false }
            rippleDeleteInHand()
        case .extractMarked:
            return extractMarkedStretch()
        case .liftMarked:
            return liftMarkedStretch()
        case .rippleTrimToPlayhead(let end):
            return rippleTrimToPlayhead(end)
        case .applyDefaultTransition:
            return applyDefaultTransition()
        case .openClipSpeed:
            return openClipSpeed()
        case .toggleSnapping:
            toggleTimelineSnapping()
        case .selectTool:
            // Premiere's V and Photoshop's V are the same arrow, so the
            // timeline puts its tool down and the press carries on to the
            // toolbar, which picks Select on the canvas as it always has.
            timelineTool = .select
            return false
        case .bladeTool:
            isTimelineBlade = true
        case .trackSelectForwardTool:
            // Premiere's A: a press on a clip picks it and everything after
            // it, and the drag carries the lot (`TrackSelectForward.swift`).
            timelineTool = .trackSelectForward
        case .rangeTool:
            // Final Cut's R: a drag on the tracks picks a stretch of time on
            // the tracks it crosses (`EditorState+TrackRange`).
            timelineTool = .range
        case .zoomIn:
            guard canOpenOutTheTimeline else { return false }
            zoomTimelineIn()
        case .zoomOut:
            guard canOpenOutTheTimeline else { return false }
            zoomTimelineOut()
        case .showMode(let mode):
            setViewEditMode(mode)
        case .toggleViewEdit:
            toggleViewEditMode()
        case .zoomToFit:
            guard canOpenOutTheTimeline else { return false }
            fitTimeline()
        }
        return true
    }

    // MARK: J, K and L

    /// A press of J, K or L. Each press of the way it is already going is
    /// faster; the other way starts again at normal speed; K stops.
    func shuttle(_ key: ShuttleKey) {
        // Space or the Play button may have started it: the ladder climbs
        // from whatever it is really doing.
        if isDocumentPlaying {
            timelineShuttle.playing(at: documentPlaybackRate)
        } else {
            timelineShuttle.stopped()
        }
        let rate = timelineShuttle.press(key)
        if rate == 0 {
            pauseDocument()
            return
        }
        playDocument(rate: rate)
        // Backwards from the first frame there is nowhere to go.
        if !isDocumentPlaying { timelineShuttle.stopped() }
    }

    /// What the transport reads while a shuttle is running: `2x`, `-1x`.
    /// Nil at normal speed, which needs no saying.
    var shuttleReading: String? {
        guard isDocumentPlaying, documentPlaybackRate != 1 else { return nil }
        let speed = abs(documentPlaybackRate)
        let number = speed == speed.rounded() ? "\(Int(speed))" : String(format: "%.1f", speed)
        return (documentPlaybackRate < 0 ? "-" : "") + number + "x"
    }

    // MARK: Edit points

    func canGoToEditPoint(forward: Bool) -> Bool {
        guard documentHasTime, let document else { return false }
        guard let moment = document.neighbourEditPoint(from: documentTimeMS, forward: forward) else { return false }
        return min(moment, lastDocumentTimeMS) != documentTimeMS
    }

    /// ↑ and ↓: the playhead to where something comes in or goes out, or to a
    /// cut, before or after it.
    func goToEditPoint(forward: Bool) {
        guard documentHasTime, let document,
              let moment = document.neighbourEditPoint(from: documentTimeMS, forward: forward) else { return }
        pauseDocument()
        scrubDocument(toMS: moment)
    }

    // MARK: Markers

    func canGoToMarker(forward: Bool) -> Bool {
        guard documentHasTime, let document,
              let moment = document.neighbourMarker(from: documentTimeMS, forward: forward) else { return false }
        return min(moment, lastDocumentTimeMS) != documentTimeMS
    }

    /// ⇧M and ⌘⇧M, Premiere's: the playhead to the next marker, or the one
    /// before it.
    func goToMarker(forward: Bool) {
        guard canGoToMarker(forward: forward), let document,
              let moment = document.neighbourMarker(from: documentTimeMS, forward: forward) else { return }
        pauseDocument()
        scrubDocument(toMS: moment)
    }

    // MARK: Marks

    var canMarkClipAtPlayhead: Bool {
        guard documentHasTime, let document else { return false }
        return document.markClipRangeMS(pickedLayerID: selectedLayerID, atMS: documentTimeMS) != nil
    }

    /// X, Premiere's Mark Clip: the In and the Out round the piece of the clip
    /// under the playhead, in one undo step. The playhead stays where it is.
    func markClipAtPlayhead() {
        guard documentHasTime, var trial = document,
              trial.markClip(pickedLayerID: selectedLayerID, atMS: documentTimeMS) else { return }
        let picked = selectedLayerID, at = documentTimeMS
        perform { $0.markClip(pickedLayerID: picked, atMS: at) }
    }

    /// ⇧I and ⇧O, Premiere's Go to In and Go to Out. With no mark set
    /// nothing moves and nothing is said.
    func goToMark(in isIn: Bool) {
        guard documentHasTime, let mark = isIn ? document?.markInMS : document?.markOutMS else { return }
        pauseDocument()
        scrubDocument(toMS: mark)
    }

    func clearMarkIn() {
        guard documentHasTime, document?.markInMS != nil else { return }
        perform { $0.clearMarkIn() }
    }

    func clearMarkOut() {
        guard documentHasTime, document?.markOutMS != nil else { return }
        perform { $0.clearMarkOut() }
    }

    // MARK: Lift

    /// Premiere's Delete: what is picked goes and nothing else moves. Keys
    /// picked on a lane first, because they are the smaller and more recent
    /// thing in hand; then tracks picked on their headers; then a picked piece
    /// of a clip; then the picked layers.
    func liftInHand() -> Bool {
        if selectedZoom != nil {
            removeZoomInHand()
            return true
        }
        if canDeletePickedKeys { return deletePickedKeys() }
        // Tracks picked on their headers, with nothing else picked: they go,
        // and everything on them (`EditorState+Tracks`).
        if !tracksInHand.isEmpty {
            deleteTracksInHand()
            return true
        }
        if canDeleteClipPieceInHand {
            deleteClipPieceInHand()
            return true
        }
        guard canDeleteSelectedLayers else { return false }
        deleteSelectedLayers()
        return true
    }
}

/// Gets a key press to the timeline before anything else in the window can.
///
/// The toolbar's single letters are key equivalents, and those are offered
/// before a key ever reaches the view that has the keyboard, so the timeline
/// could never win them from inside a view. An application event monitor sees
/// every press first. A walk's `key` step hands its press here the same way
/// (`PlaytestHarness.press`), because a synthesized press never passes a
/// monitor.
@MainActor
enum TimelineKeyRouter {
    private struct Route {
        weak var window: NSWindow?
        weak var editor: EditorState?
    }

    private static var routes: [ObjectIdentifier: Route] = [:]
    private static var monitor: Any?

    static func register(_ editor: EditorState, in window: NSWindow) {
        routes = routes.filter { $0.value.window != nil && $0.value.editor != nil }
        routes[ObjectIdentifier(window)] = Route(window: window, editor: editor)
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { event in
            guard let window = event.window else { return event }
            return offer(event, in: window) ? nil : event
        }
    }

    static func unregister(_ window: NSWindow) {
        routes[ObjectIdentifier(window)] = nil
    }

    /// Offer a press to the timeline in `window`. True when it took it.
    static func offer(_ event: NSEvent, in window: NSWindow) -> Bool {
        // A list open over the panel is being typed into: it has every key
        // first (`PanelPopoverKeyRouter`).
        if PanelPopoverKeyRouter.offer(event, in: window) { return true }
        guard let route = routes[ObjectIdentifier(window)], let editor = route.editor else { return false }
        // A field being typed in keeps every key: that is typing, never a
        // shortcut. So does a sheet up over the window.
        if window.firstResponder is NSText || window.attachedSheet != nil { return false }
        // A dropdown a person has tabbed to opens on Space, as every macOS
        // pop-up button does; Space plays only when nothing like that has
        // the keyboard.
        if window.firstResponder is VideoKit.DropdownButton, event.keyCode == 49 { return false }
        guard let press = TimelineKeyPress(event) else { return false }
        switch event.type {
        case .keyDown: return editor.timelineKeyDown(press)
        case .keyUp:
            editor.timelineKeyUp(press)
            return false
        default: return false
        }
    }
}

extension TimelineKeyPress {
    init?(_ event: NSEvent) {
        var modifiers: TimelineKeyModifiers = []
        let flags = event.modifierFlags
        if flags.contains(.command) { modifiers.insert(.command) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.control) { modifiers.insert(.control) }
        self.init(characters: event.charactersIgnoringModifiers ?? "", keyCode: event.keyCode,
                  modifiers: modifiers, isRepeat: event.type == .keyDown && event.isARepeat)
    }
}
