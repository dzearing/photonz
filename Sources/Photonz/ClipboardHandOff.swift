import AppKit
import PhotonzCore
import PhotonzRender

/// One clipboard write that is on the clipboard the instant Copy is pressed.
///
/// A copy used to clear the clipboard FIRST and fill it once the PNG was made
/// on the main thread, so for the 80 ms of a Retina screenshot and the 260 ms of a 12 megapixel photo
/// a quick paste in another app got the clipboard from before, or nothing
/// (the user, 2026-10-31: "like im doing it too fast and clipboard fails to
/// update"). Now the item goes up at once: what is cheap is written as it is,
/// and the picture's types are PROMISED and made in the background
/// (`ClipboardPicture`). A paste that asks before they are made waits for
/// them, inside AppKit's own data provider call, and gets the new picture.
///
/// Nothing waits on a paste to be made, though: each promised type is made in
/// the background straight away and then handed to the system clipboard, one
/// short main thread pass per type, while the clipboard still holds this copy.
/// After that the clipboard holds the data itself, so a Photonz that crashes
/// or is force quit a second after a copy still leaves the picture to paste,
/// and Photonz keeps none of it (`PromisedData`). A quit before then is safe
/// as well: AppKit asks the provider for anything still owed.
///
/// A copy that asks is then read back (`ClipboardProof`): off the main thread,
/// and only once everything is handed over, so the answer comes from the system
/// clipboard rather than from a promise of ours. No picture there in two
/// seconds and `onMissed` is called, so a copy never fails in silence.
final class ClipboardHandOff: NSObject, NSPasteboardItemDataProvider, Sendable {

    /// What one type on the clipboard carries.
    enum Flavor: Sendable {
        /// Written as it is, now.
        case data(NSPasteboard.PasteboardType, Data)
        /// Written as it is, now.
        case string(NSPasteboard.PasteboardType, String)
        /// Promised now, made in the background and handed over as soon as it
        /// is, or made for a paste that asks first. `make` runs on any thread
        /// (a background one, or the main one a paste asks on) and may wait
        /// for a `ClipboardPicture`, so it never needs the main thread itself.
        case later(NSPasteboard.PasteboardType, @Sendable () -> Data?)
    }

    private let promised: [NSPasteboard.PasteboardType: PromisedData]

    private init(promised: [NSPasteboard.PasteboardType: PromisedData]) {
        self.promised = promised
    }

    /// Replaces what is on `pasteboard` with ONE item carrying `flavors`, in
    /// their order, so a reader that takes the first type it knows takes the
    /// one listed first. Clearing and writing happen together: the clipboard
    /// is never left empty while anything is made.
    @MainActor @discardableResult
    static func write(_ flavors: [Flavor], to pasteboard: NSPasteboard = .general,
                      onMissed: (@MainActor @Sendable () -> Void)? = nil) -> Bool {
        let item = NSPasteboardItem()
        var promised: [NSPasteboard.PasteboardType: PromisedData] = [:]
        var promisedOrder: [NSPasteboard.PasteboardType] = []
        var everyPromise: [(NSPasteboard.PasteboardType, PromisedData)] = []
        // An item lists its types in the order they were given, so each run of
        // promised types is handed over before the next type that is not.
        // AppKit keeps each provider until the clipboard moves on.
        func flushPromises() {
            guard !promisedOrder.isEmpty else { return }
            item.setDataProvider(ClipboardHandOff(promised: promised), forTypes: promisedOrder)
            promised = [:]
            promisedOrder = []
        }
        for flavor in flavors {
            switch flavor {
            case .data(let type, let data):
                flushPromises()
                item.setData(data, forType: type)
            case .string(let type, let string):
                flushPromises()
                item.setString(string, forType: type)
            case .later(let type, let make):
                let promise = PromisedData(make)
                promised[type] = promise
                promisedOrder.append(type)
                everyPromise.append((type, promise))
            }
        }
        flushPromises()
        pasteboard.clearContents()
        guard pasteboard.writeObjects([item]) else {
            if let onMissed { DispatchQueue.main.async { MainActor.assumeIsolated { onMissed() } } }
            return false
        }
        handOver(everyPromise, to: pasteboard, whileItHolds: pasteboard.changeCount, onMissed: onMissed)
        return true
    }

    /// Makes each promised type in the background, in the order it was
    /// listed, and gives it to the system clipboard the moment it is made by
    /// reading it back on the main thread, which is what makes AppKit call the
    /// provider and keep the answer. A clipboard that has moved on since (a
    /// newer copy, here or anywhere) is left alone.
    @MainActor
    private static func handOver(_ promises: [(NSPasteboard.PasteboardType, PromisedData)],
                                 to pasteboard: NSPasteboard, whileItHolds changeCount: Int,
                                 onMissed: (@MainActor @Sendable () -> Void)?) {
        guard !promises.isEmpty else { return }
        // Read on the main thread while handing over, and by `prove` once that
        // is finished, never both at once.
        nonisolated(unsafe) let board = pasteboard
        let wrote = Date()
        DispatchQueue.global(qos: .utility).async {
            for (type, promise) in promises {
                promise.prepare()
                DispatchQueue.main.async {
                    guard board.changeCount == changeCount else { return }
                    _ = board.data(forType: type)
                }
            }
            guard let onMissed else { return }
            // Behind every pass above on the main queue.
            DispatchQueue.main.async {
                DispatchQueue.global(qos: .utility).async {
                    prove(board, holds: changeCount, since: wrote, onMissed: onMissed)
                }
            }
        }
    }

    /// Looks for the picture on the clipboard until `ClipboardProof` has an
    /// answer. Runs on a background thread and holds it for two seconds at most.
    private nonisolated static func prove(_ board: NSPasteboard, holds changeCount: Int, since wrote: Date,
                                          onMissed: @escaping @MainActor @Sendable () -> Void) {
        while true {
            let now = board.changeCount
            let readable = now == changeCount && ClipboardPicture.isReadablePicture(board.data(forType: .png))
            switch ClipboardProof.verdict(wrote: changeCount, now: now, pictureReadable: readable,
                                          elapsed: Date().timeIntervalSince(wrote)) {
            case .held, .movedOn:
                return
            case .missed:
                NSLog("Copy check: no picture on the clipboard after \(ClipboardProof.limit) s")
                DispatchQueue.main.async { MainActor.assumeIsolated { onMissed() } }
                return
            case .keepWaiting:
                Thread.sleep(forTimeInterval: 0.05)
            }
        }
    }

    // MARK: NSPasteboardItemDataProvider

    func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem,
                    provideDataForType type: NSPasteboard.PasteboardType) {
        guard let data = promised[type]?.take() else { return }
        item.setData(data, forType: type)
    }

    func pasteboardFinishedWithDataProvider(_ pasteboard: NSPasteboard) {}
}

extension ClipboardHandOff.Flavor {
    /// The picture's PNG, waiting for it if it is still being made.
    static func png(_ picture: ClipboardPicture) -> Self {
        .later(.png) { picture.png }
    }

    /// The picture as a TIFF, for the long tail of AppKit apps that ask for
    /// nothing else; written from the PNG once that is made.
    static func tiff(_ picture: ClipboardPicture) -> Self {
        .later(.tiff) { picture.tiff() }
    }
}
