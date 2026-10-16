import CoreGraphics
import Foundation
import PhotonzCore

// A logo or a photo off the Library shelf, let go on the TIMELINE
// (`video-title-wt.html`, steps 6 to 8: the art sits on a Gfx track over the
// footage). It is laid over the picture the way a title is: on the track under
// the pointer when that track is free, on a new one of its own otherwise, for
// Premiere's five seconds (`PictureClip`). The ghost it draws is the one every
// drop on the timeline draws.
extension EditorState {

    /// Whether the timeline takes a picture tile at all.
    var timelineTakesPictures: Bool {
        Experiments.shared.droppingMedia && documentHasTime
    }

    /// Where a picture let go at `point` would land: as a title does, on a
    /// new track called Gfx when it gets one.
    func timelinePictureLanding(at point: CGPoint) -> ClipLanding? {
        timelineOverlayLanding(lengthMS: PictureClip.lengthMS, at: point,
                               newTrackNamed: DocumentTrack.graphicsTrackName)
    }

    /// A picture tile has arrived over the timeline, or moved across it.
    func movePictureHover(_ id: UUID, to point: CGPoint) {
        guard timelineTakesPictures, let item = documentMediaItems.first(where: { $0.id == id }) else {
            endPictureHover()
            return
        }
        timelinePictureInAir = id
        // Room past the end for it, so one let go after the last clip has a
        // lane to be drawn on.
        if timelineDropRoomMS != PictureClip.lengthMS { timelineDropRoomMS = PictureClip.lengthMS }
        guard let landing = timelinePictureLanding(at: point) else {
            if timelineFileHover != nil { timelineFileHover = nil }
            return
        }
        let next = TimelineFileHover(name: item.layerName, landing: landing, verb: "Picture")
        if timelineFileHover != next { timelineFileHover = next }
    }

    /// The tile has left the timeline without landing.
    func endPictureHover() {
        timelinePictureInAir = nil
        endTimelineFileHover()
    }

    /// Let go over the timeline: the picture lands where the ghost said, as
    /// one step to undo, picked, with its track picked.
    @discardableResult
    func dropPictureOnTimeline(_ id: UUID, at point: CGPoint) -> Bool {
        // Read before the room made for it goes, since taking the room away
        // moves the lane under the pointer.
        let landing = timelinePictureLanding(at: point)
        endPictureHover()
        guard timelineTakesPictures, let landing, landing.allowed, let document,
              let item = documentMediaItems.first(where: { $0.id == id }) else { return false }
        let name = PlacedImageNaming.layerName(named: item.layerName,
                                               taken: Set(document.allLayers.map(\.name)))
        pauseDocument()
        var landed: UUID?
        perform { landed = $0.landPicture(item.image, named: name, at: landing) }
        guard let landed else { return false }
        selectLayer(landed)
        if let track = self.document?.trackID(ofClip: landed) { selectedTrackIDs = [track] }
        documentMomentChanged()
        raiseCanvasNotice(.landedOnTrack(name: name, track: landing.trackName,
                                         atMS: landing.startMS, isSound: false))
        return true
    }

    // MARK: - A picture file from the Finder

    /// A PNG or an SVG carried from the Finder over the timeline. It is taken
    /// the way Premiere takes a file dropped on a sequence: into the bin (the
    /// Library shelf) and onto a track, landing where a tile would. True when
    /// the file is one.
    func beginPictureFileHover(_ url: URL) -> Bool {
        guard timelineTakesPictures, MediaFiles.isPicture(url) || MediaFiles.isVector(url) else { return false }
        if timelinePictureFileInAir != url {
            timelinePictureFileInAir = url
            if timelineDropRoomMS != PictureClip.lengthMS { timelineDropRoomMS = PictureClip.lengthMS }
        }
        refreshTimelineFileHover()
        return true
    }

    /// The ghost for a picture file in the air, when one is. True when it
    /// answered.
    func refreshPictureFileHover() -> Bool {
        guard let url = timelinePictureFileInAir else { return false }
        guard let pointer = timelineFilePointer, let landing = timelinePictureLanding(at: pointer.point) else {
            if timelineFileHover != nil { timelineFileHover = nil }
            return true
        }
        let name = PlacedImageNaming.layerName(fileName: url.lastPathComponent)
        let next = TimelineFileHover(name: name, landing: landing, verb: "Picture")
        if timelineFileHover != next { timelineFileHover = next }
        return true
    }

    /// Let go over the timeline: the file goes on the Library shelf and its
    /// picture lands where the ghost said, as one step to undo. False for a
    /// file that is not a picture, or one that will not read.
    @discardableResult
    func dropPictureFileOnTimeline(_ url: URL, at point: CGPoint) -> Bool {
        guard timelineTakesPictures, MediaFiles.isPicture(url) || MediaFiles.isVector(url) else { return false }
        let landing = timelinePictureLanding(at: point)
        endTimelineFileHover()
        guard let landing, landing.allowed, let document, let ref = importedPicture(at: url) else { return false }
        let name = PlacedImageNaming.layerName(named: PlacedImageNaming.layerName(fileName: url.lastPathComponent),
                                               taken: Set(document.allLayers.map(\.name)))
        let source = DocumentMediaSource(media: .picture(ref), name: url.lastPathComponent)
        pauseDocument()
        var landed: UUID?
        perform {
            $0.bringIntoLibrary([source])
            landed = $0.landPicture(ref, named: name, at: landing)
        }
        guard let landed else { return false }
        selectLayer(landed)
        if let track = self.document?.trackID(ofClip: landed) { selectedTrackIDs = [track] }
        documentMomentChanged()
        raiseCanvasNotice(.landedOnTrack(name: name, track: landing.trackName,
                                         atMS: landing.startMS, isSound: false))
        return true
    }
}
