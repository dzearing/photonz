import AppKit
import PhotonzCore
import SwiftUI

// **Pictures along a clip on the timeline** (`ClipFilmstrip.swift`).
//
// At Fit a clip is the coloured bar the mock draws. Opened out far enough for
// one small picture to stand for a short stretch of the recording, the frames
// of what is in the clip fade in along it, so a moment in a five minute
// recording is found by looking rather than by playing. The layout and when
// the pictures show are `ClipFilmstrip`'s; this reads the frames and draws
// them.

/// The small pictures the timeline has read, and the reading of more.
///
/// **Bounded, and never in the way.** A picture is a couple of hundred pixels
/// across, so a few hundred of them is a few tens of megabytes; the ones
/// looked at longest ago go first. Reads run a few at a time off the main
/// actor, newest asked first, and a read nobody on screen is waiting for any
/// more is never started: a hand flinging the timeline along leaves no queue
/// of pictures it has already passed between it and the ones it stopped on.
@MainActor
final class ClipFilmstripFrames {
    static let shared = ClipFilmstripFrames()

    /// The most a picture is read at, either way. A tile is about forty five
    /// points wide on a Retina screen, stretched up to half as much again by
    /// the ladder (`ClipFilmstrip.tileMS`), so this is sharp at every rung.
    static let pictureSize = CGSize(width: 192, height: 192)
    /// How many pictures are kept. About forty megabytes at the most.
    static let budget = 400
    /// How many reads run at once: enough to keep both of the decoder's
    /// picture lanes busy.
    static let running = MovieDecoder.pictureLanes * 2

    struct Key: Hashable, Sendable {
        let movie: UUID
        let sourceMS: Int
    }

    private var images: [Key: CGImage] = [:]
    private var lastUse: [Key: Int] = [:]
    private var clock = 0

    private struct Wanted {
        let movie: MovieRef
        let url: URL
    }
    /// What each key is being waited for by, and how to read it.
    private var waiters: [Key: [Int: CheckedContinuation<CGImage?, Never>]] = [:]
    private var wanted: [Key: Wanted] = [:]
    /// Keys waiting to be read, newest last: the newest is read first.
    private var queue: [Key] = []
    private var inFlight = Set<Key>()
    private var nextWaiter = 0

    /// A picture already read, straight away. Never starts a read, so a tile
    /// can ask it while it draws.
    func cached(_ key: Key) -> CGImage? {
        guard let image = images[key] else { return nil }
        clock += 1
        lastUse[key] = clock
        return image
    }

    /// The picture for `key`, read if it has to be. Nil when the file will not
    /// give it up, or when the tile asking stopped waiting.
    func picture(of movie: MovieRef, atSourceMS sourceMS: Int) async -> CGImage? {
        let key = Key(movie: movie.id, sourceMS: sourceMS)
        if let image = cached(key) { return image }
        guard let url = MovieLibrary.shared.url(for: movie) else { return nil }
        nextWaiter += 1
        let id = nextWaiter
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                if Task.isCancelled {
                    continuation.resume(returning: nil)
                    return
                }
                waiters[key, default: [:]][id] = continuation
                wanted[key] = Wanted(movie: movie, url: url)
                if !inFlight.contains(key) {
                    queue.removeAll { $0 == key }
                    queue.append(key)
                }
                startReads()
            }
        } onCancel: {
            Task { @MainActor in ClipFilmstripFrames.shared.stopWaiting(id, for: key) }
        }
    }

    private func stopWaiting(_ id: Int, for key: Key) {
        guard let continuation = waiters[key]?.removeValue(forKey: id) else { return }
        continuation.resume(returning: nil)
        if waiters[key]?.isEmpty == true {
            waiters[key] = nil
            if !inFlight.contains(key) {
                wanted[key] = nil
                queue.removeAll { $0 == key }
            }
        }
    }

    private func startReads() {
        while inFlight.count < Self.running, let key = queue.popLast() {
            guard waiters[key]?.isEmpty == false, let read = wanted[key] else {
                wanted[key] = nil
                continue
            }
            inFlight.insert(key)
            Task { [weak self] in
                let image = await MovieDecoder.shared.picture(of: read.movie, at: read.url,
                                                              sourceMS: key.sourceMS,
                                                              size: Self.pictureSize)
                self?.finish(key, image)
            }
        }
    }

    private func finish(_ key: Key, _ image: CGImage?) {
        inFlight.remove(key)
        wanted[key] = nil
        if let image { file(image, for: key) }
        for continuation in (waiters.removeValue(forKey: key) ?? [:]).values {
            continuation.resume(returning: image)
        }
        startReads()
    }

    private func file(_ image: CGImage, for key: Key) {
        clock += 1
        images[key] = image
        lastUse[key] = clock
        guard images.count > Self.budget else { return }
        // Let the oldest go in one sweep, a tenth of the budget at a time, so
        // a long scroll does not sort the whole lot on every picture landing.
        let spare = images.count - Self.budget + Self.budget / 10
        for (old, _) in lastUse.sorted(by: { $0.value < $1.value }).prefix(spare) {
            images[old] = nil
            lastUse[old] = nil
        }
    }
}

/// The row of pictures inside one piece of a video clip.
///
/// Drawn over the clip's colour and under its name, leaving a band of the
/// colour along the top so the clip still says what it is at a glance.
struct ClipFilmstripStrip: View {
    let layerID: UUID
    let pieceIndex: Int
    let movie: MovieRef
    let piece: ClipPiece
    /// The piece's whole width, most of which may be off screen.
    let pieceWidth: CGFloat
    /// The part of the piece that is drawn, in the piece's own points.
    let visibleFrom: CGFloat
    let visibleWidth: CGFloat
    let height: CGFloat
    let opacity: Double

    /// The clip's colour kept along the top edge of the pictures.
    static let band: CGFloat = 3

    var body: some View {
        let stripHeight = max(1, height - Self.band)
        let aspect = movie.pixelSize.height > 0 ? movie.pixelSize.width / movie.pixelSize.height : 16.0 / 9
        let nominal = ClipFilmstrip.tileWidth(height: stripHeight, aspect: aspect)
        let tiles = ClipFilmstrip.tiles(of: piece, pieceWidth: pieceWidth,
                                        visible: visibleFrom...(visibleFrom + visibleWidth),
                                        nominalWidth: nominal)
        ZStack(alignment: .topLeading) {
            ForEach(tiles, id: \.index) { tile in
                ClipFilmstripTile(movie: movie, sourceMS: tile.sourceMS)
                    .frame(width: tile.width, height: stripHeight)
                    .clipped()
                    .offset(x: tile.x - visibleFrom)
            }
        }
        .frame(width: visibleWidth, height: stripHeight, alignment: .topLeading)
        .clipped()
        .padding(.top, Self.band)
        .opacity(opacity)
        .allowsHitTesting(false)
        #if PHOTONZ_PLAYTEST
        .onAppear { report(tiles, opacity) }
        .onChange(of: tiles) { _, now in report(now, opacity) }
        .onChange(of: opacity) { _, now in report(tiles, now) }
        .onDisappear { DrawnFilmstrips.shared.gone(layerID, piece: pieceIndex) }
        #endif
    }
}

#if PHOTONZ_PLAYTEST
extension ClipFilmstripStrip {
    private func report(_ tiles: [ClipFilmstrip.Tile], _ opacity: Double) {
        DrawnFilmstrips.shared.showing(layerID, piece: pieceIndex,
                                       keys: tiles.map { .init(movie: movie.id, sourceMS: $0.sourceMS) },
                                       opacity: opacity)
    }
}
#endif

/// One picture, read in the background the first time and faded in when it
/// lands; straight away every time after.
private struct ClipFilmstripTile: View {
    let movie: MovieRef
    let sourceMS: Int

    @State private var landed: (sourceMS: Int, image: CGImage)?

    private var key: ClipFilmstripFrames.Key { .init(movie: movie.id, sourceMS: sourceMS) }

    var body: some View {
        let image = landed.flatMap { $0.sourceMS == sourceMS ? $0.image : nil }
            ?? ClipFilmstripFrames.shared.cached(key)
        ZStack {
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(.medium)
                    .aspectRatio(contentMode: .fill)
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .trailing) {
            // A hairline between pictures, so a row of near identical frames
            // still reads as a row.
            Rectangle().fill(Color.black.opacity(0.35)).frame(width: 0.5)
        }
        .task(id: sourceMS) {
            guard ClipFilmstripFrames.shared.cached(key) == nil else { return }
            let asked = sourceMS
            guard let image = await ClipFilmstripFrames.shared.picture(of: movie, atSourceMS: asked),
                  !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) { landed = (asked, image) }
        }
    }
}
