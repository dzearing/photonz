import Foundation

/// **Why a track turns a clip away.** A clip carried onto a track that cannot
/// take it is refused for one of three reasons, and the readout under the hand
/// says which, so an editor told "no room" goes looking for a clip in the way
/// only when there is one.
public struct ClipPlacementRefusal: Hashable, Sendable {

    public enum Reason: Hashable, Sendable {
        /// Picture onto sound, sound onto picture, anything but words onto
        /// captions (`DocumentTrack.Kind.accepts`).
        case wrongKind
        /// The track is locked: nothing lands on it and nothing leaves it.
        case locked
        /// Something already there at that time.
        case noRoom
    }

    public let reason: Reason
    /// The track that says no: the one aimed at, or for a locked track a clip
    /// is leaving, that one.
    public let track: DocumentTrack

    public init(reason: Reason, track: DocumentTrack) {
        self.reason = reason
        self.track = track
    }

    /// `Audio takes sound only`, `V2 is locked`, `no room on V2`: what the
    /// capsule under the hand adds while the clip is held there.
    public var reading: String {
        switch reason {
        case .wrongKind: "\(track.name) takes \(Self.what(track.kind)) only"
        case .locked: "\(track.name) is locked"
        case .noRoom: "no room on \(track.name)"
        }
    }

    static func what(_ kind: DocumentTrack.Kind) -> String {
        switch kind {
        case .video: "picture"
        case .audio: "sound"
        case .captions: "captions"
        }
    }
}

extension PhotonzDocument {

    /// Why the clip may not be put on a track, landing at `atInMS` (or where it
    /// already starts), or nil where nothing stands in its way. The wrong kind
    /// is said before a lock, since unlocking the track would not help.
    public func placementRefusal(_ clipID: UUID, onTrack trackID: UUID,
                                 atInMS: Int? = nil) -> ClipPlacementRefusal? {
        guard let clip = layers.first(where: { $0.id == clipID }),
              let target = track(id: trackID) else { return nil }
        guard target.kind.accepts(clip.clipTrackKind) else {
            return ClipPlacementRefusal(reason: .wrongKind, track: target)
        }
        if target.isLocked { return ClipPlacementRefusal(reason: .locked, track: target) }
        if let home = lockRefusal(ofClip: clipID) { return home }
        let span = clipSpan(clip, movedTo: atInMS)
        let blocked = clipIDs(onTrack: trackID).contains { other in
            guard other != clipID, let layer = layers.first(where: { $0.id == other }) else { return false }
            let theirs = clipSpan(layer, movedTo: nil)
            return span.lowerBound < theirs.upperBound && theirs.lowerBound < span.upperBound
        }
        return blocked ? ClipPlacementRefusal(reason: .noRoom, track: target) : nil
    }

    /// The lock that keeps a clip where it is: its own track's, when that is
    /// locked.
    public func lockRefusal(ofClip id: UUID) -> ClipPlacementRefusal? {
        guard let home = trackID(ofClip: id).flatMap({ track(id: $0) }), home.isLocked else { return nil }
        return ClipPlacementRefusal(reason: .locked, track: home)
    }
}
