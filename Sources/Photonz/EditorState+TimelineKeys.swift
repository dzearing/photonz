import AppKit
import Foundation
import PhotonzCore

// Premiere's keys on the timeline (`TimelineKeys.swift` decides what a press
// means; this does it).
//
// The timeline has the keyboard from the moment it shows up (a recording
// opening, a clip dropped into a picture) and after any press in the dock, and
// loses it to a press anywhere else, Premiere's own panel focus. While it does, J/K/L
// shuttle, I and O mark, ' and ; extract and lift what they mark, Q and W
// ripple trim the clip under the playhead up to it, the arrows step frames and
// edit points, and V, B and
// the zoom keys pick the timeline's tools, where the same letters on the canvas
// are Photoshop's tools. `TimelineKeyRouter` gets a press here before the
// toolbar or the menu bar can take it.
extension EditorState {

    /// The timeline showed up, or a press in the dock: it has the keyboard now.
    func takeTimelineKeyboard() {
        guard documentHasTime, !timelineHasKeyboard else { return }
        timelineHasKeyboard = true
    }

    /// A press anywhere else in the window: the canvas has it back.
    func releaseTimelineKeyboard() {
        guard timelineHasKeyboard else { return }
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
    @discardableResult
    func perform(timelineCommand command: TimelineKeyCommand) -> Bool {
        switch command {
        case .playPause:
            toggleDocumentPlayback()
        case .shuttle(let key):
            shuttle(key)
        case .stepFrames(let frames):
            stepDocument(byFrames: frames)
        case .editPoint(let forward):
            goToEditPoint(forward: forward)
        case .goToStart:
            goToDocumentStart()
        case .goToEnd:
            goToDocumentEnd()
        case .markIn:
            setMarkIn(atMS: documentTimeMS)
        case .markOut:
            setMarkOut(atMS: documentTimeMS)
        case .clearIn:
            clearMarkIn()
        case .clearOut:
            clearMarkOut()
        case .addMarker:
            addMarker(atMS: documentTimeMS)
        case .splitAtPlayhead:
            splitClipAtPlayhead()
        case .lift:
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
        case .selectTool:
            // Premiere's V and Photoshop's V are the same arrow, so the
            // timeline puts the Blade down and the press carries on to the
            // toolbar, which picks Select on the canvas as it always has.
            isTimelineBlade = false
            return false
        case .bladeTool:
            isTimelineBlade = true
        case .trackSelectForwardTool:
            // Not yet: a pick that takes everything after a clip is only worth
            // having once the lot can be carried as one. Until then A stays
            // the Arrow tool.
            return false
        case .zoomIn:
            guard canOpenOutTheTimeline else { return false }
            zoomTimelineIn()
        case .zoomOut:
            guard canOpenOutTheTimeline else { return false }
            zoomTimelineOut()
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

    // MARK: Marks

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
    /// thing in hand; then a picked piece of a clip; then the picked layers.
    func liftInHand() -> Bool {
        if canDeletePickedKeys { return deletePickedKeys() }
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
        guard let route = routes[ObjectIdentifier(window)], let editor = route.editor else { return false }
        // A field being typed in keeps every key: that is typing, never a
        // shortcut. So does a sheet up over the window.
        if window.firstResponder is NSText || window.attachedSheet != nil { return false }
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
