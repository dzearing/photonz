import Foundation
import PhotonzCore

// MARK: - The Library's Catalog in a video (Next)

// A video's Library has two pivots, Media and Catalog (`LibraryScope.scopes`),
// and the catalog files everything made for video under what it is
// (`VideoCatalog`, mock `docs/design/mocks/pages/video-library.html`). This is
// the app's side: what fills it for the open document, which pivot and kind
// are remembered for which kind of document, and what a double click on a
// background or a picture in it does.
extension EditorState {

    /// The pivot a video's Library was left on. Its own setting, so a picture
    /// left on Styles does not open the next video on a pivot it has not got.
    static let videoLibraryScopeKey = "library.scope.video"
    /// The kind the catalog was last showing, "" for All.
    static let catalogCategoryKey = "library.catalog.category"
    /// Whether the catalog keeps only what was made for video (on until a
    /// person turns it off).
    static let catalogBuiltForVideoKey = "library.catalog.builtForVideo"

    /// The setting that holds the pivot for the kind of document that is open.
    var libraryScopeKey: String {
        documentHasTime ? Self.videoLibraryScopeKey : LibraryPanel.scopeKey
    }

    /// The pivot the Library is showing for the open document, read from its
    /// kind's own setting and fallen to the nearest one it offers.
    var libraryPivot: LibraryScope {
        let stored = UserDefaults.standard.string(forKey: libraryScopeKey).flatMap(LibraryScope.init(rawValue:))
        return LibraryScope.resolved(stored ?? .media, hasTime: documentHasTime,
                                     brushes: libraryOffersBrushes)
    }

    /// Puts the Library on `scope`, in the open document's kind's own
    /// setting. Components asked for in a video is its catalog.
    func setLibraryScope(_ scope: LibraryScope) {
        UserDefaults.standard.set(scope.rawValue, forKey: libraryScopeKey)
    }

    /// Puts the Library on its components: the Components pivot in a
    /// picture; in a video, the catalog's Components with the Built for video
    /// filter off, since that filter is what keeps them out of sight. Making
    /// a component, a guide about one and a walk asking for the shelf all
    /// mean this.
    func showComponentsInLibrary() {
        guard documentHasTime else {
            setLibraryScope(.components)
            return
        }
        setLibraryScope(.catalog)
        UserDefaults.standard.set(false, forKey: Self.catalogBuiltForVideoKey)
        UserDefaults.standard.set(VideoCatalogCategory.components.rawValue, forKey: Self.catalogCategoryKey)
    }

    /// Everything the catalog holds for this document: its title presets, the
    /// moving backgrounds, the transitions, the pictures it holds and the
    /// components it could take.
    var videoCatalog: VideoCatalog {
        guard documentHasTime else { return VideoCatalog(items: []) }
        let experiments = Experiments.shared
        return VideoCatalog.assemble(
            titles: titleShelf,
            backgrounds: experiments.titleBackgroundsEnabled ? LiveLook.allCases : [],
            transitions: experiments.transitionsAtACutEnabled ? ClipTransitionKind.allCases : [],
            pictures: timelineTakesPictures ? DocumentMedia.entriesOf(documentMediaItems) : [],
            components: componentEntries)
    }

    /// The moving background the picked tile is, nil for any other tile.
    var selectedCatalogBackground: LiveLook? {
        selectedLibraryItemID.flatMap(VideoCatalog.background(id:))
    }

    /// ...and the one the dock's section describes, the way
    /// `titlePresetInPanel` follows the pick.
    var catalogBackgroundInPanel: LiveLook? {
        panelLibraryItemID.flatMap(VideoCatalog.background(id:)) ?? selectedCatalogBackground
    }

    /// A moving background at the playhead, the whole frame, for five
    /// seconds on a track of its own: one step to undo, picked, with its
    /// track picked, and the canvas saying where it went.
    func insertCatalogBackground(_ look: LiveLook) {
        guard documentHasTime, let document else { return }
        let landing = document.backgroundLanding(atMS: documentTimeMS, over: nil)
        guard landing.allowed else { return }
        pauseDocument()
        var landed: UUID?
        perform { landed = $0.landBackground(look, at: landing) }
        guard let landed else { return }
        selectLayer(landed)
        if let track = self.document?.trackID(ofClip: landed) { selectedTrackIDs = [track] }
        documentMomentChanged()
        raiseCanvasNotice(.landedOnTrack(name: look.title, track: landing.trackName,
                                         atMS: landing.startMS, isSound: false))
    }

    /// A picture off the catalog at the playhead, on a Gfx track, for a
    /// still's five seconds: the same landing a tile let go on the timeline
    /// makes, at the playhead instead of under the pointer.
    func placePictureAtPlayhead(_ item: DocumentMediaItem) {
        guard timelineTakesPictures, let document else { return }
        let landing = document.pictureLanding(atMS: documentTimeMS, over: nil)
        guard landing.allowed else { return }
        let name = PlacedImageNaming.layerName(named: item.layerName,
                                               taken: Set(document.allLayers.map(\.name)))
        pauseDocument()
        var landed: UUID?
        perform { landed = $0.landPicture(item.image, named: name, at: landing) }
        guard let landed else { return }
        selectLayer(landed)
        if let track = self.document?.trackID(ofClip: landed) { selectedTrackIDs = [track] }
        documentMomentChanged()
        raiseCanvasNotice(.landedOnTrack(name: name, track: landing.trackName,
                                         atMS: landing.startMS, isSound: false))
    }

    // MARK: A background dragged onto the timeline

    /// A background tile has arrived over the timeline, or moved across it:
    /// the ghost a picture draws, saying it is a background, its track and
    /// its time.
    func moveBackgroundHover(_ look: LiveLook, to point: CGPoint) {
        guard documentHasTime else { return }
        timelineBackgroundInAir = look
        if timelineDropRoomMS != VideoCatalog.backgroundLengthMS { timelineDropRoomMS = VideoCatalog.backgroundLengthMS }
        guard let landing = timelineOverlayLanding(lengthMS: VideoCatalog.backgroundLengthMS, at: point,
                                                   newTrackNamed: DocumentTrack.graphicsTrackName) else {
            if timelineFileHover != nil { timelineFileHover = nil }
            return
        }
        let next = TimelineFileHover(name: look.title, landing: landing,
                                     verb: VideoCatalogCategory.backgrounds.singular)
        if timelineFileHover != next { timelineFileHover = next }
    }

    /// The tile has left the timeline without landing.
    func endBackgroundHover() {
        timelineBackgroundInAir = nil
        backgroundTileLifted = nil
        endTimelineFileHover()
    }

    /// Let go over the timeline: the background lands where the ghost said,
    /// as one step to undo, picked, with its track picked.
    @discardableResult
    func dropBackgroundOnTimeline(_ look: LiveLook, at point: CGPoint) -> Bool {
        // Read before the room made for it goes, since taking the room away
        // moves the lane under the pointer.
        let landing = timelineOverlayLanding(lengthMS: VideoCatalog.backgroundLengthMS, at: point,
                                             newTrackNamed: DocumentTrack.graphicsTrackName)
        endBackgroundHover()
        guard documentHasTime, let landing, landing.allowed else { return false }
        pauseDocument()
        var landed: UUID?
        perform { landed = $0.landBackground(look, at: landing) }
        guard let landed else { return false }
        selectLayer(landed)
        if let track = self.document?.trackID(ofClip: landed) { selectedTrackIDs = [track] }
        documentMomentChanged()
        raiseCanvasNotice(.landedOnTrack(name: look.title, track: landing.trackName,
                                         atMS: landing.startMS, isSound: false))
        return true
    }
}
