import Foundation

/// What a picture is called once it lands in a document as a layer.
///
/// A picture arrives three ways — picked in the Library, dragged in from the
/// Finder, or pasted — and until now all three produced a layer called
/// "Pasted Image", so a stack of them read as one repeated word. The layer now
/// takes the name of the file behind it, and falls back to "Pasted Image" only
/// when there is no file, which is exactly the clipboard case.
///
/// Captures the app named itself are the one exception. Their file names are
/// all shared prefix and date ("Screenshot 2026-06-21 at 10.30.45"), which is
/// about 220pt of text in a panel that is 220pt wide including its thumbnails
/// and buttons, so every one of them would truncate to the identical
/// "Screenshot 2026-06-21 a…". The clock time is the part that tells two of
/// them apart, so that is the part the layer keeps. The Library tiles solve
/// the same problem the same way (`LibraryNaming.caption`), with a relative
/// time instead — which reads well on a tile but would go stale on a layer.
public enum PlacedImageNaming {

    /// The name for a picture that arrived with no file behind it.
    public static let clipboardName = "Pasted Image"

    /// The layer name for a picture that came from `fileName`, which may be a
    /// bare name or a whole path, with or without an extension. Pass nil for
    /// the clipboard.
    public static func layerName(fileName: String?) -> String {
        let stem = stem(of: fileName)
        guard !stem.isEmpty else { return clipboardName }
        return shortenedCaptureName(stem) ?? stem
    }

    /// The layer name for a picture from `fileName`, given every name already
    /// spoken for in the document.
    ///
    /// Two copies of one file used to land as two rows carrying the identical
    /// word, and the only way to tell which was which was to rename one by
    /// hand. The second one takes the next free number instead, exactly as a
    /// second drawn rectangle does (`LayerNaming`). Nothing is numbered until
    /// there is something to tell apart, so the first copy keeps the plain
    /// file name; and it is always the picture ARRIVING that steps aside, so a
    /// layer somebody named themselves is never renumbered behind their back.
    public static func layerName(fileName: String?, taken: Set<String>) -> String {
        LayerNaming.firstFree(base: layerName(fileName: fileName), taken: taken)
    }

    /// The file's own name, without its folders and without its extension.
    private static func stem(of fileName: String?) -> String {
        guard let fileName else { return "" }
        let path = fileName.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = path.split(separator: "/").last.map(String.init) ?? path
        var stem = base
        // A leading dot is a hidden file, not an extension, so only a dot with
        // something in front of it ends the name.
        if let dot = base.lastIndex(of: "."), dot != base.startIndex {
            stem = String(base[base.startIndex..<dot])
        }
        return stem.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// "Screenshot 2026-06-21 at 10.30.45" → "Screenshot 10.30.45", and nil
    /// for a name a person chose, which is already short and already means
    /// something. The date has to look like a date, so "Screenshot of the cat
    /// at night" stays whole.
    private static func shortenedCaptureName(_ stem: String) -> String? {
        for prefix in LibraryNaming.timestampedPrefixes where stem.hasPrefix("\(prefix) ") {
            let rest = stem.dropFirst(prefix.count + 1)
            guard let at = rest.range(of: " at ") else { continue }
            guard isDatePart(rest[rest.startIndex..<at.lowerBound]) else { continue }
            let time = rest[at.upperBound...].trimmingCharacters(in: .whitespaces)
            guard !time.isEmpty else { continue }
            return "\(prefix) \(time)"
        }
        return nil
    }

    /// True for "2026-06-21": three runs of digits joined by dashes.
    private static func isDatePart(_ text: Substring) -> Bool {
        let parts = text.split(separator: "-", omittingEmptySubsequences: false)
        return parts.count == 3 && parts.allSatisfy { !$0.isEmpty && $0.allSatisfy(\.isNumber) }
    }
}
