import AppKit
import Foundation
import PhotonzCore
import PhotonzMedia

// A sound or a video let go on the window (`MediaDrop`, `next-dropping-a-sound-
// or-a-video`).
//
// Dropping a picture in has always worked and is the app's whole promise said
// in one gesture: everything is a layer. Sound is a layer now and a recording
// is a document, so the same gesture has to answer for both, and where it
// genuinely cannot it has to say so rather than leaving the pointer to shrug.
//
// Every decision about WHAT happens is `MediaDrop.answer`, which the canvas
// also reads to draw its sentence while the file is still in the air. Nothing
// is decided twice, so the promise the pointer made and the thing that lands
// cannot disagree.
extension EditorState {

    /// What a sound or a recording let go on this window would do, in the words
    /// the canvas says under the pointer.
    ///
    /// Nil where the file is neither, which leaves every other drop exactly
    /// where it was.
    func mediaDropAnswer(for url: URL, atMS ms: Int? = nil) -> MediaDrop.Answer? {
        guard Experiments.shared.droppingMedia, let kind = MediaFiles.kind(of: url) else { return nil }
        return MediaDrop.answer(for: kind, named: url.lastPathComponent,
                                documentHasTime: document?.hasTime ?? false,
                                atMS: ms ?? documentTimeMS,
                                hasDocument: document != nil)
    }

    /// Takes the drop the answer promised.
    ///
    /// `point` is where it landed on the canvas, in canvas coordinates, when
    /// the drop came down on the picture itself. A clip uses it to work out the
    /// box it fills, the same way an incoming picture does. A piece of sound
    /// has nothing to draw, so it ignores it and lands at the playhead, which
    /// is where you are in time and is where Add Sound puts one.
    func dropMedia(at url: URL, droppedAt point: CGPoint? = nil) {
        guard let answer = mediaDropAnswer(for: url) else { return }
        switch answer.landing {
        case .refused:
            // The canvas already said this while the file was in the air and
            // the pointer already refused it, so nothing reaches here by that
            // route. A panel target that took the drop without tracking can,
            // and it owes the same sentence.
            raiseCanvasNotice(.mediaWouldNotOpen(name: url.lastPathComponent))
        case .openDocument:
            openRecordingInItsOwnWindow?(url)
        case .soundLayer:
            let at = documentTimeMS
            Task { [weak self] in
                guard let self else { return }
                if await self.addSound(from: url, atMS: at) == nil {
                    // `addSound` raises its own pill for a file with nothing in
                    // it, and it is about a mix that could not be written,
                    // which is not what happened. Said properly here instead.
                    self.raiseCanvasNotice(.mediaWouldNotOpen(name: url.lastPathComponent))
                }
            }
        case .clipLayer:
            Task { [weak self] in await self?.addClip(from: url, at: point) }
        }
    }

    /// Puts a second recording into a document that already runs in time: a
    /// clip over the picture, at the playhead, in the box the drag drew.
    ///
    /// Fitted and nudged wholly inside whatever it was let go on, exactly as an
    /// incoming picture is (`placementForIncomingImage`), so a 4K recording let
    /// go on a 720p document arrives at a size somebody can see rather than
    /// eight times off the edge.
    @discardableResult
    func addClip(from url: URL, at point: CGPoint?) async -> UUID? {
        guard let movie = await MovieLibrary.shared.movie(at: url), let document else {
            raiseCanvasNotice(.mediaWouldNotOpen(name: url.lastPathComponent))
            return nil
        }
        let frame = document.placementForIncomingImage(size: movie.pixelSize, at: point)
        guard !frame.isEmpty else { return nil }
        let name = url.deletingPathExtension().lastPathComponent
        let at = documentTimeMS
        var landed: UUID?
        pauseDocument()
        perform { landed = $0.addClip(movie, name: name, atMS: at, frame: frame) }
        if let landed { selectLayer(landed) }
        // Its own sound came with it: `MovieLibrary.movie(at:)` files a
        // recording's sound against the same file as it reads it, so the bar
        // can draw the shape of it and Detach Sound has something to take off.
        documentMomentChanged()
        raiseCanvasNotice(.clipAdded(name: name))
        return landed
    }
}
