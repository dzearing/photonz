import CoreGraphics
import Dispatch
import Foundation
import ImageIO
import Synchronization
import UniformTypeIdentifiers

/// A copied picture on its way to the clipboard.
///
/// Copy puts the clipboard item up the instant it is pressed and promises the
/// picture's types; the PNG, which is nearly all of a copy's cost (about 70 ms
/// for a 3456x2234 screenshot and 250 ms for a 12 megapixel photo on an M
/// series Mac), is made here, off the caller's thread, starting at once. A
/// paste that asks before it is done waits for it, so it gets the new picture,
/// never the clipboard from before and never an empty one.
///
/// Only the PNG is kept. The bitmap is let go of as soon as the PNG is made,
/// and the rarer TIFF is written from the PNG when somebody asks for it, so a
/// picture nobody pastes holds a compressed copy and no more.
public final class ClipboardPicture: Sendable {

    private struct State {
        var done = false
        var png: Data?
    }

    private let state = Mutex(State())
    private let finished = DispatchGroup()

    /// Starts making the PNG of `image` straight away.
    public convenience init(_ image: CGImage) {
        self.init(making: { image })
    }

    /// Starts making the picture, then its PNG, straight away and off this
    /// thread. `making` may be slow (a render, or a file read back from disk);
    /// nil means there is no picture, and every reader is told so.
    public init(making: @escaping @Sendable () -> CGImage?) {
        finished.enter()
        // Holds itself until the PNG is made, which is the point: a copy
        // nobody keeps a hand on still finishes for the paste that asks.
        DispatchQueue.global(qos: .userInitiated).async {
            let png = making().flatMap { ImageCodec.encode($0, format: .png) }
            self.state.withLock {
                $0.png = png
                $0.done = true
            }
            self.finished.leave()
        }
    }

    /// Whether the PNG is made, so a read would not wait.
    public var isReady: Bool { state.withLock { $0.done } }

    /// The PNG, waiting for it when it is still being made.
    public var png: Data? {
        finished.wait()
        return state.withLock { $0.png }
    }

    /// The same picture as a TIFF, for the apps that ask for nothing else.
    public func tiff() -> Data? {
        guard let png, let image = ImageCodec.decode(png) else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data, UTType.tiff.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}

/// One type a copy promised the clipboard: made once, by whoever asks first
/// (the copy getting it ready in the background, or a paste that came
/// sooner), and let go of the moment it is handed over. Everything the maker
/// held on to (a picture, a layer) goes with it, so once the system clipboard
/// has a copy's data, Photonz holds none of it.
public final class PromisedData: Sendable {

    private struct State {
        var make: (@Sendable () -> Data?)?
        var made: Data?
    }

    private let state: Mutex<State>

    public init(_ make: @escaping @Sendable () -> Data?) {
        state = Mutex(State(make: make))
    }

    /// Makes it now, on this thread, unless it is made already. A second
    /// asker waits for the first.
    public func prepare() {
        state.withLock { state in
            guard let make = state.make else { return }
            state.made = make()
            state.make = nil
        }
    }

    /// The data, made here if nobody has yet, and forgotten as it is handed
    /// over: a second take answers nil.
    public func take() -> Data? {
        prepare()
        return state.withLock { state in
            defer { state.made = nil }
            return state.made
        }
    }
}
