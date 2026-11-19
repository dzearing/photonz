/// When the canvas asks for a picture while a hand drags the playhead.
///
/// A hand sends moves faster than a screen shows pictures, so the first move
/// in each display refresh is asked for at once and any more in the same
/// refresh wait for the next one, drawn as one picture of the last of them.
///
/// A frame landing from the decoder while the hand is on the playhead waits
/// for a refresh too, and while a picture is still on its way it waits for
/// that picture as well. Asking at the refresh anyway drew the same picture a
/// second time (the next one asked for is drawn from every frame in hand, the
/// landed one included), and the main thread spent the refresh's first 1.5 ms
/// working out the document for it, exactly while the picture already drawn
/// was waiting to go up: on the 6 minute reference edit that is most of why a
/// dragged picture trailed the hand by two refreshes rather than one
/// (`a-long-edit-with-transitions-plays-scrubs-and-ed`, pass 17).
///
/// Every picture asked for is numbered (`asked()`), and the canvas says which
/// one it put up (`shown(_:)`); pictures skipped on the way (a render queue
/// that draws only the newest) count as shown once a later one arrives.
public struct ScrubPictureAsks: Sendable, Equatable {
    /// The number of the newest picture asked for.
    public private(set) var lastAsked = 0
    /// The number of the newest picture put up.
    public private(set) var lastShown = 0
    /// The refresh the newest move was asked for at once in.
    public private(set) var askedAtRefresh = -1
    /// A move left for the next refresh.
    public private(set) var moveWaiting = false
    /// A frame landed that no picture asked for since has been drawn with.
    public private(set) var landingWaiting = false

    public init() {}

    /// A picture asked for has not been put up yet.
    public var pictureOnItsWay: Bool { lastShown < lastAsked }

    /// A picture is being asked for, whatever asked: its number. Every ask
    /// draws from every frame in hand, so nothing is left waiting after it.
    public mutating func asked() -> Int {
        lastAsked += 1
        moveWaiting = false
        landingWaiting = false
        return lastAsked
    }

    /// The canvas put up picture `number`.
    public mutating func shown(_ number: Int) {
        lastShown = max(lastShown, number)
    }

    /// The hand moved during refresh `refresh` (the display's own count): true
    /// when this move is to be asked for at once, false when it waits for the
    /// next refresh.
    public mutating func handMoved(atRefresh refresh: Int) -> Bool {
        if refresh > askedAtRefresh {
            askedAtRefresh = refresh
            return true
        }
        moveWaiting = true
        return false
    }

    /// A frame landed from the decoder.
    public mutating func frameLanded() {
        landingWaiting = true
    }

    /// The display refreshed: true when a picture is to be asked for now.
    public mutating func refreshed() -> Bool {
        guard moveWaiting || (landingWaiting && !pictureOnItsWay) else { return false }
        moveWaiting = false
        landingWaiting = false
        return true
    }

    /// The hand let go: true when something is still waiting to be drawn.
    public mutating func lettingGo() -> Bool {
        let waiting = moveWaiting || landingWaiting
        moveWaiting = false
        landingWaiting = false
        return waiting
    }
}
