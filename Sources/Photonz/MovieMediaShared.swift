import CoreGraphics
import PhotonzCore
import PhotonzMedia
import PhotonzRender

// The app's one `MovieLibrary` and one `MovieDecoder` (`PhotonzMedia`), wired
// to each other, to the sounds and to the gradient blending.

extension MovieLibrary {
    @MainActor static let shared: MovieLibrary = makeSharedMovieLibrary()
}

@MainActor private func makeSharedMovieLibrary() -> MovieLibrary {
    let library = MovieLibrary()
    library.linkSound = { SoundLibrary.shared.link($0, to: $1) }
    library.soundsMoved = { SoundLibrary.shared.relocate(from: $0, to: $1) }
    library.letGo = { id in Task { await MovieDecoder.shared.forget(id) } }
    library.fileFiled = { MovieFileWatch.shared.watch($0) }
    return library
}

extension MovieDecoder {
    static let shared = MovieDecoder(finish: { image, movie in smoothed(image, of: movie) ?? image })

    /// A decoded frame with the steps of its soft gradients blended
    /// (`RecordingSmoothing`), when the switch is on; as decoded otherwise.
    static func smoothed(_ image: CGImage?, of movie: MovieRef) -> CGImage? {
        guard let image, RecordingSmoothing.isOn else { return image }
        let scale = CGFloat(image.width) / max(1, movie.pixelSize.width)
        return RecordingSmoothing.smoothedPicture(image, reach: RecordingSmoothing.reach(readAt: scale)) ?? image
    }
}
