import CoreGraphics
import Foundation
import PhotonzCore
import PhotonzMedia

// A recording whose file was replaced on disk (`MovieFileWatch`,
// `PhotonzDocument.replaceRecording`).
//
// The window takes on the new file where it stands: the playhead stays, the
// edit stays, nothing is marked edited and no undo step is made, because
// nobody here did anything. The steps undo can reach are pointed at the new
// file too, so Command Z never brings the old one back.
extension EditorState {

    /// Every recording this window plays or has on its shelf.
    var playedRecordingIDs: Set<UUID> {
        guard let document else { return [] }
        var ids = Set<UUID>()
        for media in ProjectMedia.references(in: document) {
            if case .recording(let movie) = media { ids.insert(movie.id) }
        }
        return ids
    }

    /// The files of these recordings are `movie`'s from now on.
    ///
    /// The frames the playhead needs are read out of the new file first, so
    /// the canvas goes from the old picture to the new one: taken on and then
    /// read, it was blank for two display frames (2026-11-24).
    func recordingReplaced(_ old: [UUID], with movie: MovieRef) async {
        let update: (inout PhotonzDocument) -> Void = { document in
            for id in old { document.replaceRecording(id, with: movie) }
        }
        var ready: [(request: MovieFrameRequest, image: CGImage)] = []
        if var next = document, let url = MovieLibrary.shared.url(for: movie) {
            update(&next)
            let moment = min(documentTimeMS, max(0, next.documentDurationMS - 1))
            for request in next.movieFrames(atTimeMS: moment) where request.movie.id == movie.id {
                if let image = await MovieDecoder.shared.frame(of: movie, at: url, sourceMS: request.sourceMS) {
                    ready.append((request, image))
                }
            }
        }
        guard document != nil else { return }
        let moment = documentTimeMS
        let canvas = document?.canvasSize
        // A trim in hand is laid out for the old file.
        if trimSession != nil { cancelTrim() }
        pauseDocument()
        // From here on in one turn, so nothing is drawn part way.
        for id in old { movieFrames.forget(id) }
        for frame in ready { movieFrames.hold(frame.image, for: frame.request) }
        guard applyWithoutMarkingEdited(update) else { return }
        if var opened = recordingAsOpened {
            update(&opened)
            recordingAsOpened = opened
        }
        if let now = document?.canvasSize, now != canvas { fitCanvasToWindow() }
        documentTimeMS = max(0, min(moment, lastDocumentTimeMS))
        documentMomentChanged()
    }

    /// Reads what the files of a project say now, for the ones that are not
    /// what the project was saved with (`MovieLibrary.adopt`).
    func readChangedMedia() {
        guard let document else { return }
        for media in ProjectMedia.references(in: document) {
            guard case .recording(let movie) = media else { continue }
            Task { [weak self] in
                guard let read = await MovieLibrary.shared.refreshed(movie) else { return }
                await self?.recordingReplaced([movie.id], with: read)
            }
        }
    }

    /// Before an export is written over a file this window plays (the save box
    /// offers a recording's own name): keep that file, beside it in the hidden
    /// originals folder, and play the kept one. The window goes on being the
    /// edit it is, and opening the file again opens what was exported.
    func keepRecordingPlayed(from url: URL) {
        guard let document, MovieLibrary.shared.plays(url, in: document),
              FileManager.default.fileExists(atPath: url.path) else { return }
        // Under a name of its own: the plain one means "what this file was
        // before a save wrote over it", which an export is not.
        let kept = VideoOriginals.url(for: url).deletingLastPathComponent()
            .appendingPathComponent("\(UUID().uuidString)-\(url.lastPathComponent)")
        do {
            try FileManager.default.createDirectory(at: kept.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: url, to: kept)
        } catch {
            NSLog("Couldn't keep \(url.lastPathComponent) before writing over it: \(error)")
            return
        }
        MovieLibrary.shared.relocate(from: url, to: kept)
    }
}
