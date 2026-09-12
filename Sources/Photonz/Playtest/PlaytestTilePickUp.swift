// Proving a tile really does come away in your hand.
//
// `PlaytestPanelDrag` covers everything that happens once something is in the
// air: it builds the tile's own payload and hands it to the view being dropped
// on. What it never covered is the first half of the gesture — pressing a tile
// and pulling, and a drag being what comes of it. Three features shipped on
// 2026-09-09 rest on that half, and all three audits said the same thing: no
// walk can prove it, please check by hand.
//
// This settles it. A press and a pull are posted at the tile, and the moment
// AppKit is asked to start a drag session is caught on its way past, with the
// payload it was asked to carry. That is the question the audits asked: does
// this tile have a handle, and does pulling on it put the right thing in the
// air.
//
// The session itself is then not allowed to start. A real one takes the main
// thread hostage in a loop of its own that only a mouse coming up on a real
// desk can end, and a walk has no desk. So the ask is caught, written down,
// and refused: what a walk proves is that the tile was picked up, not that the
// window server then drew a picture under the pointer, which is AppKit's
// business rather than this app's. Refusing also keeps the step from changing
// the document, because nothing is ever let go of.
//
// ONE PICK UP PER RUN OF THE APP. After a refused session SwiftUI will not
// start another, and nothing tried so far puts it back: a plain click in
// between, ending the session by hand through its source, giving every posted
// event its own number, even letting the real session run. The first tile in a
// walk comes away and every tile after it, the same tile included, stays on the
// shelf. A walk that needs to prove two tiles is two walks. That is written
// down here and said out loud by the step, because for an afternoon it looked
// exactly like a broken text style tile.
//
// Probe builds only.
#if PHOTONZ_PLAYTEST
import AppKit
import ObjectiveC

/// One moment a view asked AppKit to start dragging something.
struct PlaytestDragAsk: Sendable {
    /// The class of the view the drag came off, for the log.
    let view: String
    /// How many things were picked up at once.
    let items: Int
    /// Every type the payload offers, which is what the drop side reads.
    let types: [String]
}

/// Catches the moment a drag session is asked for, and refuses to let it start.
@MainActor
enum PlaytestDragWatch {
    private static var installed = false
    private(set) static var asks: [PlaytestDragAsk] = []
    /// True only between `start()` and `stop()`, so the app drags normally for
    /// the person using it and only a walk ever sees a session refused.
    private(set) static var isWatching = false
    /// Whether anything has been caught at all since the app started. A pick up
    /// that catches nothing means one of two very different things, and this is
    /// how the step tells them apart: the FIRST one catching nothing is a tile
    /// with no handle, and a later one catching nothing is the one-per-run
    /// limit at the top of this file.
    private(set) static var hasCaughtAnything = false

    /// Begin watching. Everything caught from here until `stop()` is returned
    /// by it.
    static func start() {
        install()
        asks = []
        isWatching = true
    }

    /// Stop watching and hand back everything caught.
    static func stop() -> [PlaytestDragAsk] {
        isWatching = false
        let caught = asks
        asks = []
        return caught
    }

    static func record(view: NSView, items: [NSDraggingItem]) {
        var types: [String] = []
        for item in items {
            if let board = item.item as? NSPasteboardWriting {
                types += board.writableTypes(for: NSPasteboard.general).map(\.rawValue)
            } else if let provider = item.item as? NSItemProvider {
                types += provider.registeredTypeIdentifiers
            }
        }
        hasCaughtAnything = true
        asks.append(PlaytestDragAsk(
            view: String(describing: type(of: view)),
            items: items.count,
            types: NSOrderedSet(array: types).compactMap { $0 as? String }))
    }

    private static func install() {
        guard !installed else { return }
        installed = true
        let original = #selector(NSView.beginDraggingSession(with:event:source:))
        let replacement = Selector("photonzPlaytestBeginDraggingSessionWithItems:event:source:")
        guard let from = class_getInstanceMethod(NSView.self, original),
              let to = class_getInstanceMethod(NSView.self, replacement) else { return }
        method_exchangeImplementations(from, to)
    }
}

extension NSView {
    /// Stands in for `beginDraggingSession(with:event:source:)` while a walk is
    /// watching. After the swap, calling this name calls the real one.
    @objc(photonzPlaytestBeginDraggingSessionWithItems:event:source:)
    func photonzPlaytestBeginDraggingSession(with items: [NSDraggingItem], event: NSEvent,
                                             source: NSDraggingSource) -> NSDraggingSession {
        guard MainActor.assumeIsolated({ PlaytestDragWatch.isWatching }) else {
            return photonzPlaytestBeginDraggingSession(with: items, event: event, source: source)
        }
        MainActor.assumeIsolated { PlaytestDragWatch.record(view: self, items: items) }
        // The ask is the answer, so the real call is never made. The empty
        // session handed back in its place is dropped on the floor by
        // everything that asks for one.
        return NSDraggingSession()
    }
}
#endif
