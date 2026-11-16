import Foundation

/// What of the pick lands on one track of the timeline: whether the track is
/// picked on its header or in hand, which of its clips (and clips' sounds)
/// are picked, and the single pick when it is one of them.
///
/// The timeline hands each track row its share instead of letting the row
/// read the selection, because a row that reads the selection is built again
/// for every pick anywhere: on the 6 minute reference edit a click on one clip
/// built all five track rows and their lanes, and through them seven to nine
/// clip bars that had not changed
/// (`a-long-edit-with-transitions-plays-scrubs-and-ed`, pass 11). Handed its
/// share, a row is equal to what it was unless the pick reached it, so a pick
/// builds the track it left and the track it landed on and nothing else.
public struct TrackPickShare: Equatable, Sendable {
    /// Picked on its header, whatever else is picked.
    public var isTrackPicked = false
    /// The thing in hand: picked on its header with nothing else picked.
    public var isHeld = false
    /// Its clips, and clips' own sounds, that are picked.
    public var picked: Set<UUID> = []
    /// The single pick, when it is one of this track's clips.
    public var primary: UUID?
    /// The one picked layer the header's key diamond keys, when it is one of
    /// this track's clips.
    public var key: UUID?

    public static let none = TrackPickShare()

    public init() {}

    /// - Parameters:
    ///   - clips: the clips on the track.
    ///   - linked: the clips whose own sound is drawn on this track.
    ///   - primary: the single pick (`selectedLayerID`).
    ///   - multi: the clips a box or a shift click picked together.
    ///   - pickedTracks: the tracks picked on their headers.
    ///   - tracksInHand: the tracks that are the thing in hand.
    ///   - keyLayer: the one picked layer a key would be added to, if any.
    public init(track: UUID, clips: [UUID], linked: [UUID], primary: UUID?, multi: Set<UUID>,
                pickedTracks: Set<UUID>, tracksInHand: Set<UUID>, keyLayer: UUID? = nil) {
        isTrackPicked = pickedTracks.contains(track)
        isHeld = tracksInHand.contains(track)
        if primary != nil || !multi.isEmpty {
            for id in clips + linked where id == primary || multi.contains(id) { picked.insert(id) }
        }
        if let primary, clips.contains(primary) { self.primary = primary }
        if let keyLayer, clips.contains(keyLayer) { key = keyLayer }
    }

    /// Lit as picked: on its header, or for one of its clips.
    public var isPicked: Bool { isTrackPicked || !picked.isEmpty }
}
