import CoreGraphics
import Foundation

// The recordings and sounds on the Library's Media shelf (`video.html`, the
// Library group, scope Media: intro.mov 0:06, b-roll.mov 0:04, music.wav 0:14).
//
// The shelf is the document's own media pool, the one Premiere calls a bin:
// what this file has been GIVEN, not only what its timeline uses right now. So
// a file is remembered the moment it is brought in, and cutting its last clip
// away does not take it off the shelf. A picture needs no such memory, because
// a picture with no layer drawing it is not something a person expects back;
// a clip you trimmed out of the cut and want again is exactly that.

/// One file a document has been given: a recording or a piece of sound, under
/// the name it had on disk.
public struct DocumentMediaSource: Hashable, Codable, Sendable, Identifiable {

    /// What the file is. A recording's own sound shares its id, so the two are
    /// one entry.
    public enum Media: Hashable, Codable, Sendable {
        case recording(MovieRef)
        case sound(SoundRef)
    }

    public let media: Media
    /// The file's own name, extension and all, which is what the tile says.
    public let name: String

    public init(media: Media, name: String) {
        self.media = media
        self.name = name
    }

    public var id: UUID {
        switch media {
        case .recording(let movie): movie.id
        case .sound(let sound): sound.id
        }
    }
}

extension PhotonzDocument {

    /// Remembers a file this document has been given, once. Bringing the same
    /// file in again keeps the name it arrived with first, so a tile is never
    /// renamed under the hand that is reaching for it.
    public mutating func rememberMedia(_ media: DocumentMediaSource.Media, named name: String) {
        let source = DocumentMediaSource(media: media, name: name)
        guard !self.media.contains(where: { $0.id == source.id }) else { return }
        self.media.append(source)
    }
}

/// One recording or sound on the shelf.
public struct DocumentClipItem: Identifiable, Hashable, Sendable {
    public let media: DocumentMediaSource.Media
    /// The file's name when the document remembers it, else the name of the
    /// clip that plays it first.
    public let name: String
    /// How many layers on the timeline play it.
    public let uses: Int

    public init(media: DocumentMediaSource.Media, name: String, uses: Int) {
        self.media = media
        self.name = name
        self.uses = uses
    }

    public var id: UUID { DocumentMediaSource(media: media, name: name).id }

    public var movie: MovieRef? {
        if case .recording(let movie) = media { return movie }
        return nil
    }

    public var sound: SoundRef? {
        if case .sound(let sound) = media { return sound }
        return nil
    }

    public var isSound: Bool { movie == nil }

    public var durationMS: Int { movie?.durationMS ?? sound?.durationMS ?? 0 }

    /// How long it runs, the way the tile's corner says it: `0:04`.
    public var length: String { CaptionProgress.clock(durationMS) }

    /// The second line search reads and the help says: how long it is, and
    /// how much of it the timeline uses.
    public var detail: String {
        let used = switch uses {
        case 0: "not on the timeline"
        case 1: "used once"
        default: "used \(uses) times"
        }
        return "\(length), \(used)"
    }
}

extension DocumentMedia {

    /// Every recording and sound on the shelf: the files the document was
    /// given, in the order they came in, then any the timeline plays that it
    /// was never told about (a document written before the shelf held clips),
    /// oldest first.
    public static func clips(in document: PhotonzDocument) -> [DocumentClipItem] {
        var uses: [UUID: Int] = [:]
        var found: [UUID: (media: DocumentMediaSource.Media, name: String, inMS: Int)] = [:]
        var foundOrder: [UUID] = []
        // Bottom up, so what was put down first is met first.
        for layer in document.allLayersTopDown.reversed() {
            guard let media = media(of: layer) else { continue }
            let id = DocumentMediaSource(media: media, name: "").id
            let inMS = layer.time?.inMS ?? 0
            uses[id, default: 0] += 1
            guard let met = found[id] else {
                found[id] = (media, layer.name, inMS)
                foundOrder.append(id)
                continue
            }
            switch (met.media, media) {
            case (.sound, .recording):
                // The recording's picture outranks its own sound taken off it:
                // the tile is the whole file.
                found[id] = (media, layer.name, inMS)
            case (.recording, .sound):
                break
            default:
                // Cut in two, the piece that plays first names the tile, so
                // the second half of a cut ("b-roll 2") never renames it.
                if inMS < met.inMS { found[id] = (media, layer.name, inMS) }
            }
        }
        var items: [DocumentClipItem] = []
        var listed: Set<UUID> = []
        for source in document.media where listed.insert(source.id).inserted {
            // A remembered recording whose sound alone is on the timeline is
            // still the recording.
            items.append(DocumentClipItem(media: source.media, name: source.name,
                                          uses: uses[source.id] ?? 0))
        }
        for id in foundOrder where listed.insert(id).inserted {
            guard let met = found[id] else { continue }
            items.append(DocumentClipItem(media: met.media, name: met.name, uses: uses[id] ?? 0))
        }
        return items
    }

    /// The recordings and sounds as Library entries, which is what search
    /// reads.
    public static func clipEntries(in document: PhotonzDocument) -> [LibraryEntry] {
        clipEntriesOf(clips(in: document))
    }

    public static func clipEntriesOf(_ clips: [DocumentClipItem]) -> [LibraryEntry] {
        clips.map {
            LibraryEntry(id: $0.id.uuidString, scope: .media, name: $0.name, detail: $0.detail)
        }
    }

    /// The recording or sound a tile was picked by, nil for anything else.
    public static func clip(id: String, in document: PhotonzDocument) -> DocumentClipItem? {
        guard let uuid = UUID(uuidString: id) else { return nil }
        return clips(in: document).first { $0.id == uuid }
    }

    /// What file one layer plays, if any: a clip's recording, or a layer that
    /// is nothing but sound.
    private static func media(of layer: Layer) -> DocumentMediaSource.Media? {
        if let movie = layer.movie { return .recording(movie) }
        if case .sound(let sound) = layer.content { return .sound(sound) }
        return nil
    }
}
