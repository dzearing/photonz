import CoreGraphics
import Foundation

/// The words the app has read off the pictures in a document, kept WITH the
/// document (Next, `next-a-separated-row-says-its-words`).
///
/// Separate into Layers hands back a hundred and forty pieces of a screenshot
/// called Text 1 to Text 142, and the words are in the pixels rather than in
/// the document, so the app reads them in the background and the layers list
/// says them (`Layer.displayName(readWords:)`). Until this existed that reading
/// lived for as long as the window did and no longer, which cost two things:
///
/// - **The same work, every open.** A file holding a hundred and forty
///   separated runs was read again from nothing every time it was opened, for
///   an answer that had already been worked out and thrown away.
/// - **A second reading that need not agree with the first.** The bitmaps in a
///   saved package are HEIC, so the pixels a reopened document hands the reader
///   are not byte for byte the pixels the first reading saw. A row that said
///   its words on Monday was free to say something slightly different on
///   Tuesday, with nothing on screen to explain why.
///
/// So what a reading found is written down. What is written is words and the
/// bitmap they were read off, nothing else: no pixels, which the document model
/// is not allowed to carry, and not the face the words are set in, which the
/// study behind `docs/design/separate-reads-the-words.md` measured as the
/// unreliable half and which nothing asks for.
///
/// Three rules keep it honest:
///
/// - **Keyed by the BITMAP, never by the layer.** Two layers cut from one
///   picture agree, and undoing a separation and running it again finds the
///   reading already there.
/// - **It is not an edit.** A reading is filed through
///   `History.applyOutsideHistory`, so it spends no undo step, and the editor
///   moves its saved baseline with it, so a file does not become "edited"
///   because the app read something in the background. The reading rides along
///   with the next save the person actually makes.
/// - **An empty answer is an answer.** A picture with nothing readable in it —
///   an icon, a switch — is written down as having no words, which is what
///   stops it being asked about again on every open forever.
public struct ReadWords: Hashable, Sendable {
    /// What was read, against the bitmap it was read off.
    public private(set) var byPicture: [ImageRef: String]

    public init(_ byPicture: [ImageRef: String] = [:]) {
        self.byPicture = byPicture
    }

    public var isEmpty: Bool { byPicture.isEmpty }
    public var count: Int { byPicture.count }

    /// What was read off this bitmap, or nil where it has never been asked.
    /// An empty string is a real answer and is not nil: this picture holds no
    /// words, and asking again would cost a Vision pass for the same nothing.
    public subscript(ref: ImageRef) -> String? { byPicture[ref] }

    /// Whether this bitmap has been read, however it came back.
    public func hasBeenRead(_ ref: ImageRef) -> Bool { byPicture[ref] != nil }

    /// Files what a reading came back with.
    public mutating func remember(_ words: String, for ref: ImageRef) {
        byPicture[ref] = words
    }

    /// The same for a batch, which is how the background pass hands them over.
    public mutating func remember(_ found: [(ImageRef, String)]) {
        for (ref, words) in found { byPicture[ref] = words }
    }
}

extension ReadWords: Codable {
    /// One reading, written out. An array rather than a map because the key is
    /// a bitmap rather than a string, and sorted by that bitmap's id so a
    /// document saved twice with the same readings is the same bytes twice.
    private struct Entry: Codable {
        var image: ImageRef
        var words: String
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(byPicture
            .map { Entry(image: $0.key, words: $0.value) }
            .sorted { $0.image.id.uuidString < $1.image.id.uuidString })
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        var found: [ImageRef: String] = [:]
        for entry in try c.decode([Entry].self) { found[entry.image] = entry.words }
        self.init(found)
    }
}
