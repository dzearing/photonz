import Foundation

// Where a saved project's recordings and sounds are (`docs/design/video.md`).
//
// A document holds a `MovieRef` or a `SoundRef`, which is an identity and never
// a path, the bargain `ImageRef` strikes with `ImageStore`. A picture keeps that
// bargain on disk by writing its pixels into the package. A recording cannot:
// an hour of screen recording copied into every project would be the wrong
// trade, and a Premiere editor expects the project to point at the footage
// where it sits. So the package carries a small table beside the document, one
// row per file, saying where each one was when the project was saved, both as a
// full path and relative to the project, so a folder moved to another disk with
// its footage in it still opens whole.

/// One recording or sound a saved project plays, and where it was.
public struct ProjectMediaFile: Hashable, Codable, Sendable {

    public enum Kind: String, Hashable, Codable, Sendable {
        case recording
        case sound
    }

    /// The document's own id for the file: a `MovieRef`'s or a `SoundRef`'s.
    public let id: UUID
    public let kind: Kind
    /// The file's name, which is what a person is told when it cannot be found.
    public let name: String
    /// Where it was, in full, when the project was saved.
    public let path: String
    /// Where it was measured from the folder the project sits in, so a folder
    /// moved whole still finds its footage. Nil where the two share no root.
    public let relativePath: String?

    public init(id: UUID, kind: Kind, name: String, path: String, relativePath: String?) {
        self.id = id
        self.kind = kind
        self.name = name
        self.path = path
        self.relativePath = relativePath
    }
}

public enum ProjectMedia {

    /// Every recording and sound the document plays or holds on its shelf, once
    /// each, in the order first met. A recording's own sound shares its id and
    /// is the recording, so the recording is what is listed.
    public static func references(in document: PhotonzDocument) -> [DocumentMediaSource.Media] {
        var order: [UUID] = []
        var found: [UUID: DocumentMediaSource.Media] = [:]
        func meet(_ media: DocumentMediaSource.Media) {
            let id = DocumentMediaSource(media: media, name: "").id
            guard let met = found[id] else {
                found[id] = media
                order.append(id)
                return
            }
            if case .sound = met, case .recording = media { found[id] = media }
        }
        for source in document.media { meet(source.media) }
        document.forEachLayer { layer in
            if let movie = layer.movie { meet(.recording(movie)) }
            if case .sound(let sound) = layer.content { meet(.sound(sound)) }
        }
        return order.compactMap { found[$0] }
    }

    /// The table a project is saved with. `locate` answers where each file is
    /// in this run of the app; a file it cannot answer for is left out, and
    /// opens as missing, rather than stopping the save.
    public static func table(for document: PhotonzDocument, project: URL,
                             locate: (UUID) -> URL?) -> [ProjectMediaFile] {
        let folder = project.deletingLastPathComponent().standardizedFileURL
        return references(in: document).compactMap { media in
            let id = DocumentMediaSource(media: media, name: "").id
            guard let url = locate(id)?.standardizedFileURL else { return nil }
            let kind: ProjectMediaFile.Kind
            switch media {
            case .recording: kind = .recording
            case .sound: kind = .sound
            }
            return ProjectMediaFile(id: id, kind: kind, name: url.lastPathComponent,
                                    path: url.path,
                                    relativePath: relativePath(of: url, from: folder))
        }
    }

    /// What opening a project found.
    public struct Resolution: Sendable, Equatable {
        /// Every file that is where the project says, or beside it where it
        /// says relative to the project.
        public var located: [UUID: URL] = [:]
        /// Every file that is in neither place, in the table's order.
        public var missing: [ProjectMediaFile] = []
    }

    /// Where each file is now: first where it was saved, then the same place
    /// relative to wherever the project is now.
    public static func resolve(_ table: [ProjectMediaFile], project: URL,
                               exists: (URL) -> Bool) -> Resolution {
        let folder = project.deletingLastPathComponent().standardizedFileURL
        var result = Resolution()
        for entry in table {
            let saved = URL(fileURLWithPath: entry.path)
            if exists(saved) {
                result.located[entry.id] = saved
            } else if let relative = entry.relativePath,
                      case let beside = folder.appendingPathComponent(relative).standardizedFileURL,
                      exists(beside) {
                result.located[entry.id] = beside
            } else {
                result.missing.append(entry)
            }
        }
        return result
    }

    /// What a person is told when a project opens without some of its files,
    /// or nil when nothing is missing.
    public static func missingMessage(names: [String]) -> String? {
        guard !names.isEmpty else { return nil }
        let quoted = names.map { "“\($0)”" }
        let list: String
        if quoted.count == 1 {
            list = quoted[0]
        } else {
            list = quoted.dropLast().joined(separator: ", ") + " and " + (quoted.last ?? "")
        }
        let tail = names.count == 1
            ? "It was moved or deleted since this project was saved."
            : "They were moved or deleted since this project was saved."
        return "Can’t find \(list). \(tail)"
    }

    /// The line under that message: what the window is doing without them,
    /// and how to get them back.
    public static func missingAdvice(count: Int) -> String {
        count == 1
            ? "The project is open without it. Put the file back where it was, or beside the project, and open the project again."
            : "The project is open without them. Put the files back where they were, or beside the project, and open the project again."
    }

    /// `url` as a path from `folder`, climbing with `..` as far as it has to.
    /// Nil when the two share nothing but the root, where a relative path
    /// would only ever be a longer way of writing the full one.
    static func relativePath(of url: URL, from folder: URL) -> String? {
        let target = url.standardizedFileURL.pathComponents
        let base = folder.standardizedFileURL.pathComponents
        var shared = 0
        while shared < min(target.count, base.count), target[shared] == base[shared] {
            shared += 1
        }
        guard shared > 1 else { return nil }
        let up = Array(repeating: "..", count: base.count - shared)
        return (up + target[shared...]).joined(separator: "/")
    }
}
