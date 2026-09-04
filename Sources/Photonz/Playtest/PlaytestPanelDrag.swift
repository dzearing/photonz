// Picking things up in the right hand panel, for a scripted walk.
//
// AppKit will not start a drag from a synthesized mouse press: a real drag
// session begins inside the window server, from an event that came from a real
// device. So a walk could drive the canvas and nothing else, and every drag
// that lives in the dock — a tile off the Library, a row in the layers list —
// was a hand path an unmanned run had to take on trust.
//
// What a drag actually IS, to the view being dropped on, is a small handful of
// calls carrying a pasteboard and a point. That is what this makes: a dragging
// info the harness hands straight to the destination, so `draggingEntered`,
// `draggingUpdated` and `performDragOperation` run exactly as they do under a
// real pointer, and everything they draw while the drag is in the air — the
// landing outline on the canvas, the line in the layers list that says what
// will happen — is on screen to be photographed.
//
// It does NOT synthesize the picture that follows the pointer, which lives in
// the window server and belongs to the session we cannot start. That is the one
// part of a panel drag a walk still cannot see.
#if PHOTONZ_PLAYTEST
import AppKit
import UniformTypeIdentifiers

/// A drag in the air, as the view being dropped on sees it. The conformance is
/// isolated to the main actor because everything it touches — the pasteboard,
/// the window — already is, and only the main thread ever makes one.
@MainActor final class PlaytestDraggingInfo: NSObject, @MainActor NSDraggingInfo {
    let draggingPasteboard: NSPasteboard
    var draggingLocation: NSPoint
    var draggingDestinationWindow: NSWindow?
    var draggingSourceOperationMask: NSDragOperation = [.copy, .move, .generic]
    let draggingSequenceNumber = Int.random(in: 1...(Int.max / 2))
    var draggingSource: Any? { nil }
    var draggingFormation: NSDraggingFormation = .default
    var animatesToDestination: Bool = false
    var numberOfValidItemsForDrop: Int = 1
    var springLoadingHighlight: NSSpringLoadingHighlight { .none }

    init(pasteboard: NSPasteboard, location: NSPoint, window: NSWindow?) {
        self.draggingPasteboard = pasteboard
        self.draggingLocation = location
        self.draggingDestinationWindow = window
    }

    var draggedImageLocation: NSPoint { draggingLocation }
    var draggedImage: NSImage? { nil }

    func slideDraggedImage(to screenPoint: NSPoint) {}

    func resetSpringLoading() {}

    func enumerateDraggingItems(options: NSDraggingItemEnumerationOptions,
                                for view: NSView?,
                                classes: [AnyClass],
                                searchOptions: [NSPasteboard.ReadingOptionKey: Any],
                                using block: @escaping (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void) {
        for (index, item) in (draggingPasteboard.pasteboardItems ?? []).enumerated() {
            let dragged = NSDraggingItem(pasteboardWriter: item)
            dragged.draggingFrame = NSRect(origin: draggingLocation, size: CGSize(width: 1, height: 1))
            var stop: ObjCBool = false
            block(dragged, index, &stop)
            if stop.boolValue { return }
        }
    }
}

/// Everything the harness needs to hand one thing in the panel to something
/// that accepts drops.
enum PlaytestPanelDrag {
    /// The pasteboard a provider would put on the drag, built by asking it for
    /// every type it offers. This is the payload the pointer carries, read out
    /// of the very closure the view's own `onDrag` uses.
    static func pasteboard(from provider: NSItemProvider, named name: String) async throws -> NSPasteboard {
        let board = NSPasteboard(name: NSPasteboard.Name("photonz.playtest.\(name)"))
        board.clearContents()
        let item = NSPasteboardItem()
        var wrote: [String] = []
        for identifier in provider.registeredTypeIdentifiers {
            guard let data = try? await provider.loadData(forTypeIdentifier: identifier) else { continue }
            item.setData(data, forType: NSPasteboard.PasteboardType(identifier))
            wrote.append(identifier)
            // A file URL is written as a URL as well, because that is the type
            // a destination registers for and the plain data is not read as one.
            if identifier == UTType.fileURL.identifier,
               let text = String(data: data, encoding: .utf8), let url = URL(string: text) {
                item.setString(url.absoluteString, forType: .fileURL)
            }
        }
        guard !wrote.isEmpty else {
            throw PlaytestDragFailure(description: "\"\(name)\" offered nothing to carry; it cannot be picked up")
        }
        board.writeObjects([item])
        return board
    }

    /// The innermost view under a point in the window that takes drops. The
    /// smallest match wins, so a row is chosen over the list that holds it.
    static func destination(at windowPoint: CGPoint, in content: NSView) -> NSView? {
        var found: [NSView] = []
        func walk(_ view: NSView) {
            if !view.isHidden, !view.registeredDraggedTypes.isEmpty,
               view.convert(view.bounds, to: nil).contains(windowPoint) {
                found.append(view)
            }
            for sub in view.subviews { walk(sub) }
        }
        walk(content)
        return found.min { $0.bounds.width * $0.bounds.height < $1.bounds.width * $1.bounds.height }
    }
}

struct PlaytestDragFailure: Error, CustomStringConvertible {
    let description: String
}

private extension NSItemProvider {
    /// `loadDataRepresentation` as something a step can await.
    func loadData(forTypeIdentifier identifier: String) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            _ = loadDataRepresentation(forTypeIdentifier: identifier) { data, error in
                if let data {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: error ?? PlaytestDragFailure(description: "no data for \(identifier)"))
                }
            }
        }
    }
}
#endif
