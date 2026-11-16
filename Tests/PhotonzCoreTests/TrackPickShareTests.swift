import Foundation
import PhotonzCore
import Testing

@Suite("A track's share of the pick")
struct TrackPickShareTests {
    let v1 = UUID(), v2 = UUID(), a1 = UUID()
    let take1 = UUID(), take2 = UUID(), broll = UUID(), music = UUID()

    func share(_ track: UUID, clips: [UUID], linked: [UUID] = [], primary: UUID? = nil, multi: Set<UUID> = [],
               pickedTracks: Set<UUID> = [], inHand: Set<UUID> = []) -> TrackPickShare {
        TrackPickShare(track: track, clips: clips, linked: linked, primary: primary, multi: multi,
                       pickedTracks: pickedTracks, tracksInHand: inHand)
    }

    @Test("Nothing picked is nothing on any track")
    func nothingPicked() {
        let s = share(v1, clips: [take1, take2])
        #expect(s == .none)
        #expect(!s.isPicked)
        #expect(!s.isHeld)
    }

    @Test("A clip picked is that track's alone: every other track's share stays as it was")
    func aPickTouchesOnlyItsTrack() {
        let before = [share(v1, clips: [take1, take2]), share(v2, clips: [broll]), share(a1, clips: [music])]
        let after = [share(v1, clips: [take1, take2], primary: take2), share(v2, clips: [broll], primary: take2),
                     share(a1, clips: [music], primary: take2)]
        #expect(after[0] != before[0])
        #expect(after[0].picked == [take2])
        #expect(after[0].primary == take2)
        #expect(after[0].isPicked)
        #expect(after[1] == before[1])
        #expect(after[2] == before[2])
    }

    @Test("Moving the pick between two clips on one track changes only that track")
    func movingThePickAlongATrack() {
        let a = share(v1, clips: [take1, take2], primary: take1)
        let b = share(v1, clips: [take1, take2], primary: take2)
        #expect(a != b)
        #expect(share(v2, clips: [broll], primary: take1) == share(v2, clips: [broll], primary: take2))
    }

    @Test("A clip's own sound counts as picked on the track it sits on, and a box pick counts every clip it caught")
    func soundsAndBoxPicks() {
        let s = share(a1, clips: [], linked: [take1], multi: [take1, broll])
        #expect(s.picked == [take1])
        // Only the single pick is the primary one.
        #expect(s.primary == nil)
        #expect(s.isPicked)
    }

    @Test("The layer a key would go on is named only by the track it sits on")
    func theKeyLayer() {
        let on = TrackPickShare(track: v1, clips: [take1, take2], linked: [], primary: take2, multi: [],
                                pickedTracks: [], tracksInHand: [], keyLayer: take2)
        let off = TrackPickShare(track: v2, clips: [broll], linked: [], primary: take2, multi: [],
                                 pickedTracks: [], tracksInHand: [], keyLayer: take2)
        #expect(on.key == take2)
        #expect(off.key == nil)
        #expect(off == .none)
    }

    @Test("A track picked on its header, and in hand, says so")
    func pickedOnItsHeader() {
        let s = share(v1, clips: [take1], pickedTracks: [v1], inHand: [v1])
        #expect(s.isTrackPicked)
        #expect(s.isHeld)
        #expect(s.isPicked)
        #expect(share(v2, clips: [broll], pickedTracks: [v1], inHand: [v1]) == .none)
    }
}
