import AVFoundation
import CoreGraphics
import Foundation
import PhotonzCore

/// Which file each recording in a document is, for the length of this run.
///
/// A `MovieRef` is an identity, not a path, exactly as an `ImageRef` is. This
/// is the one place that identity is turned back into a file, and it is app
/// state rather than document state: a document that travels to another machine
/// travels with its media beside it, which is `video-share`'s problem and not
/// this one's.
@MainActor
public final class MovieLibrary {

    public init() {}

    /// Told of a recording's own sound as it is filed, and of one moved.
    public var linkSound: ((SoundRef, URL) -> Void)?
    public var soundsMoved: ((URL, URL) -> Void)?
    /// Told when every reader open on a recording is to be let go.
    public var letGo: ((UUID) -> Void)?

    /// Told of every file a recording is played from, as it is filed: the app
    /// watches them for a change.
    public var fileFiled: ((URL) -> Void)?

    private var urls: [UUID: URL] = [:]
    /// What each recording's file was when it was read, so one replaced on
    /// disk since is seen (`changedOnDisk`).
    private var stamps: [UUID: MediaFileStamp] = [:]
    private var identities = MediaIdentities<MovieRef>()
    /// Recordings of a project saved before it kept stamps, whose facts have
    /// not been checked against the file yet.
    private var unchecked: Set<UUID> = []
    /// Where the pointer went in each recording, read from beside its file
    /// when the recording is opened (`PointerTrack.swift`). Absent for a
    /// recording made before Photonz kept it, or brought in from elsewhere.
    private var pointerTracks: [UUID: PointerTrack] = [:]

    /// Read a recording's size and length off the file and hand back the
    /// reference a document can hold. The same file asked for twice is the same
    /// reference, so re-opening a recording re-uses whatever frames of it are
    /// already decoded. A file that has been written over or replaced since is
    /// ANOTHER recording, however much its path is the same: it gets a new
    /// reference, read afresh, so nothing kept for the old one (frames, the
    /// timeline's pictures, the waveform) can be shown for it.
    ///
    /// `id` is the identity to read it under, for a recording that was opened
    /// before its file landed and already has one (`ClosingRecording`).
    public func movie(at url: URL, as id: UUID? = nil) async -> MovieRef? {
        let standardized = url.standardizedFileURL
        let stamp = MediaFileStamp.of(standardized)
        if let known = identities.known(at: standardized, stamp: stamp), id == nil || known.id == id,
           !unchecked.contains(known.id) { return known }
        guard let read = await Self.read(standardized) else { return nil }
        // Somebody else asked at the same time and got there first.
        if let known = identities.known(at: standardized, stamp: read.stamp), id == nil || known.id == id {
            if !unchecked.contains(known.id) { return known }
            if read.facts.agree(with: known) {
                unchecked.remove(known.id)
                return known
            }
        }
        if let before = identities.filed(at: standardized) { letGo?(before.id) }
        let ref = MovieRef(id: id ?? UUID(), pixelSize: read.facts.pixelSize,
                           durationMS: read.facts.durationMS, hasSound: read.facts.hasSound)
        file(ref, at: standardized, stamp: read.stamp)
        return ref
    }

    private struct Facts {
        let pixelSize: CGSize
        let durationMS: Int
        let hasSound: Bool

        /// Whether a saved project's facts are these, give or take the few
        /// milliseconds two readings of one file can differ by.
        func agree(with movie: MovieRef) -> Bool {
            movie.pixelSize == pixelSize && movie.hasSound == hasSound
                && abs(movie.durationMS - durationMS) <= 100
        }
    }

    /// The file's facts and the stamp they were read under. Read again where
    /// it changed while being read, so the two are always of one file.
    private static func read(_ url: URL) async -> (facts: Facts, stamp: MediaFileStamp?)? {
        var stamp = MediaFileStamp.of(url)
        for _ in 0..<3 {
            let facts = await facts(of: url)
            let after = MediaFileStamp.of(url)
            if after == stamp { return facts.map { ($0, stamp) } }
            stamp = after
        }
        return await facts(of: url).map { ($0, stamp) }
    }

    private static func facts(of url: URL) async -> Facts? {
        let asset = AVURLAsset(url: url)
        guard let duration = try? await asset.load(.duration),
              let track = try? await asset.loadTracks(withMediaType: .video).first,
              let size = try? await track.load(.naturalSize),
              let transform = try? await track.load(.preferredTransform)
        else { return nil }
        // A recording made in portrait carries its rotation on the track, and
        // the picture the canvas gets is the rotated one, so the document's
        // canvas has to be that size too.
        let shown = size.applying(transform)
        // Whether it has a sound track decides whether the app offers to take
        // the sound off it, so it is read once, here, with everything else
        // about the file (`SoundClip.swift`).
        let hasSound = (try? await asset.loadTracks(withMediaType: .audio))?.isEmpty == false
        return Facts(pixelSize: CGSize(width: abs(shown.width), height: abs(shown.height)),
                     durationMS: Int((duration.seconds * 1000).rounded()), hasSound: hasSound)
    }

    private func file(_ ref: MovieRef, at url: URL, stamp: MediaFileStamp?) {
        urls[ref.id] = url
        stamps[ref.id] = stamp
        identities.file(ref, at: url, stamp: stamp)
        pointerTracks[ref.id] = PointerTrackSidecar.load(for: url)
        // A recording's sound is the same file as its picture, so the sound
        // library can answer for it from the moment the recording is opened.
        if let sound = ref.soundRef { linkSound?(sound, url) }
        fileFiled?(url)
    }

    // MARK: A file that changes

    /// Which of these recordings' files are not the ones they were read from,
    /// and where. One that is missing is not changed: it may be on its way
    /// back, and what is in hand goes on showing.
    public func changedOnDisk(_ ids: some Sequence<UUID>) -> [UUID: URL] {
        var changed: [UUID: URL] = [:]
        for id in ids {
            guard let url = urls[id], let was = stamps[id], let now = MediaFileStamp.of(url), now != was
            else { continue }
            changed[id] = url
        }
        return changed
    }

    /// What the file of a project's recording says where it is not what the
    /// project holds, under the same id, or nil where the two agree or there
    /// is nothing to check (`adopt`).
    public func refreshed(_ movie: MovieRef) async -> MovieRef? {
        guard unchecked.contains(movie.id), let url = urls[movie.id], let read = await Self.read(url)
        else { return nil }
        unchecked.remove(movie.id)
        let agrees = read.facts.agree(with: movie)
        let ref = agrees ? movie : MovieRef(id: movie.id, pixelSize: read.facts.pixelSize,
                                            durationMS: read.facts.durationMS, hasSound: read.facts.hasSound)
        file(ref, at: url, stamp: read.stamp)
        return agrees ? nil : ref
    }

    public func url(for movie: MovieRef) -> URL? { urls[movie.id] }

    /// Where the pointer went and every click while this recording was made,
    /// or nil when nothing was kept.
    public func pointerTrack(for movie: MovieRef) -> PointerTrack? { pointerTracks[movie.id] }

    /// Gives a recording a pointer path as if the recorder had kept one, for a
    /// walk (`PlaytestZoom`).
    public func setPointerTrack(_ track: PointerTrack, for movie: MovieRef) {
        pointerTracks[movie.id] = track
    }

    /// File a reference a saved project already holds against the file its
    /// media table found for it (`ProjectMedia`), so the project's clips play
    /// under the ids they were saved with, and answer with the reference to
    /// hold. A file this run has opened under another reference keeps that one
    /// for anybody opening it afresh.
    ///
    /// Nothing is read off the file here: the project already knows its size
    /// and length. Where the file is not the one the project was saved with
    /// (`savedAs`), or not the one this run played under that id, the answer is
    /// a reference of a new id with the same facts, and `refreshed` reads the
    /// real ones; where there is no stamp to tell by, `refreshed` checks.
    public func adopt(_ movie: MovieRef, at url: URL, savedAs saved: MediaFileStamp?) -> MovieRef {
        let standardized = url.standardizedFileURL
        let now = MediaFileStamp.of(standardized)
        var held = movie
        if let now {
            let changedSinceSaved = saved.map { !$0.sameContents(as: now) } ?? false
            let changedThisRun = stamps[movie.id].map {
                urls[movie.id] == standardized ? $0 != now : !$0.sameContents(as: now)
            } ?? false
            if changedSinceSaved || changedThisRun { held = movie.underNewID() }
        }
        if held.id != movie.id || (saved == nil && stamps[movie.id] == nil) { unchecked.insert(held.id) }
        urls[held.id] = standardized
        stamps[held.id] = now
        if identities.known(at: standardized, stamp: now) == nil {
            identities.file(held, at: standardized, stamp: now)
        }
        pointerTracks[held.id] = PointerTrackSidecar.load(for: standardized)
        if let sound = held.soundRef { linkSound?(sound, standardized) }
        fileFiled?(standardized)
        return held
    }

    /// Every recording this run plays from `old`, played from `new` from now
    /// on: a save into history keeps the recording as it was made in the
    /// originals folder and is about to write the edit over the file the
    /// window opened (`HistoryVideoSave`). The two files are the same bytes
    /// when this runs, so nothing on screen changes, and the readers already
    /// open on the old path are let go so none of them reads the edit.
    public func relocate(from old: URL, to new: URL) {
        let from = old.standardizedFileURL
        let to = new.standardizedFileURL
        let moved = urls.filter { $0.value == from }.map(\.key)
        guard !moved.isEmpty else { return }
        let stamp = MediaFileStamp.of(to), fromNow = MediaFileStamp.of(from)
        for id in moved {
            urls[id] = to
            // One already read from an earlier file at that path stays changed.
            if fromNow == nil || stamps[id] == fromNow { stamps[id] = stamp }
            letGo?(id)
        }
        identities.relocate(from: from, to: to, stamp: stamp)
        // A recording's sound is the same file, filed under the same id.
        soundsMoved?(from, to)
        fileFiled?(to)
    }

    /// Whether any recording this run plays is the file at `url`.
    public func plays(_ url: URL, in document: PhotonzDocument) -> Bool {
        let file = url.standardizedFileURL
        return urls(in: document).values.contains(file)
    }

    /// The same question asked with an id on its own, which is what a
    /// recording's SOUND has: a clip's sound shares the recording's identity
    /// because it is the same file (`SoundClip.swift`).
    public func url(forID id: UUID) -> URL? { urls[id] }

    /// Which file every recording in a document is, taken once so a job that
    /// runs off the main actor — writing a video out — never has to come back
    /// here to ask (`EditorState+VideoExport`).
    public func urls(in document: PhotonzDocument) -> [UUID: URL] {
        var found: [UUID: URL] = [:]
        for layer in document.allLayers {
            guard let movie = layer.movie, found[movie.id] == nil,
                  let url = urls[movie.id] else { continue }
            found[movie.id] = url
        }
        return found
    }
}
