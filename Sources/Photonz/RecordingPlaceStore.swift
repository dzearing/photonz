import AVFoundation
import Foundation
import PhotonzCore
import UniformTypeIdentifiers

/// The recording kinds a file-picking box offers.
///
/// Deliberately NARROWER than `UTType.movie`: that conforms to formats the app
/// cannot open, so a panel offering it would let somebody pick an .avi and then
/// fail to open it, which is the empty window this whole change exists to stop.
/// These are exactly `CaptureLibrary.videoExtensions`, which is what
/// `RecordingFiles.isRecording` answers for.
enum RecordingContentTypes {
    static let all: [UTType] = CaptureLibrary.videoExtensions
        .sorted()
        .compactMap { UTType(filenameExtension: $0) }
}

/// Where you were in each recording, kept between launches.
///
/// The rules for what is worth remembering are in `RecordingPlaces`
/// (PhotonzCore, pure and tested); this is the settings key behind it and the
/// file fingerprint it is keyed on. A recording saved since (a trim written
/// into the file) has a different fingerprint, so it opens at the top instead
/// of at a moment that may no longer be in it.
@MainActor
final class RecordingPlaceStore {
    static let shared = RecordingPlaceStore()
    static let defaultsKey = "recording.places"

    private var places: RecordingPlaces

    private init() {
        places = Self.stored()
    }

    /// Reads the memory back off disk. Only a scripted walk asking to forget it
    /// needs this: it wipes the setting after the app has already read it.
    func reload() { places = Self.stored() }

    /// Note where the playhead is in this recording. Cheap enough to call on
    /// every pause and every close; a moment not worth keeping forgets the
    /// recording instead of storing a useless one.
    func remember(url: URL, momentMS: Int, durationMS: Int) {
        let path = url.standardizedFileURL.path
        places.remember(path: path, momentMS: momentMS, durationMS: durationMS,
                        stamp: Self.stamp(of: url))
        persist()
    }

    /// Where to put the playhead when this recording opens, or nil to start at
    /// the beginning.
    func moment(for url: URL, durationMS: Int) -> Int? {
        places.moment(forPath: url.standardizedFileURL.path,
                      stamp: Self.stamp(of: url), durationMS: durationMS)
    }

    func forget(url: URL) {
        places.forget(path: url.standardizedFileURL.path)
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(places) else { return }
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }

    private static func stored() -> RecordingPlaces {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode(RecordingPlaces.self, from: data)
        else { return RecordingPlaces() }
        return decoded
    }

    /// What the file looked like when a moment was noted: its size and its
    /// modification time. Same shape as `CaptureStore`'s media stamp, and for
    /// the same reason.
    static func stamp(of url: URL) -> String {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) else {
            return "none"
        }
        let mtime = (attrs[.modificationDate] as? Date)?.timeIntervalSinceReferenceDate ?? 0
        let size = (attrs[.size] as? Int) ?? 0
        return "\(mtime)-\(size)"
    }
}

/// Reading the three facts the door needs off a real file.
///
/// The length is asked for first because it is the only question that matters
/// in the ordinary case, and a local recording answers it in milliseconds. The
/// second size sample is only ever taken when the length could not be read, so
/// opening a recording that plays never waits for it.
enum RecordingFileReader {
    static func facts(for url: URL) async -> RecordingFileFacts {
        let manager = FileManager.default
        guard manager.fileExists(atPath: url.path) else {
            return RecordingFileFacts(exists: false)
        }
        let size = byteCount(of: url)
        let durationMS = await durationMS(of: url)
        guard durationMS == nil || durationMS == 0 else {
            return RecordingFileFacts(exists: true, byteCount: size, durationMS: durationMS)
        }
        // Nothing playable yet. Is the file still landing? One more look, a
        // moment later: a writer that is still going will have written
        // something in between.
        try? await Task.sleep(for: .seconds(RecordingDoor.growthSampleSeconds))
        guard manager.fileExists(atPath: url.path) else {
            return RecordingFileFacts(exists: false)
        }
        let after = byteCount(of: url)
        return RecordingFileFacts(exists: true, byteCount: after, isGrowing: after != size,
                                  durationMS: durationMS)
    }

    private static func byteCount(of url: URL) -> Int {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attrs?[.size] as? Int) ?? 0
    }

    private static func durationMS(of url: URL) async -> Int? {
        let asset = AVURLAsset(url: url)
        guard let duration = try? await asset.load(.duration), duration.seconds.isFinite,
              let tracks = try? await asset.loadTracks(withMediaType: .video), !tracks.isEmpty
        else { return nil }
        return Int((duration.seconds * 1000).rounded())
    }
}
