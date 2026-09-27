import CoreGraphics
import Foundation

/// The one quiet line a video window's title bar carries: which edit this is,
/// how big its picture is, how long it runs, and whether closing it would lose
/// anything. The video mocks draw it as
/// `launch-teaser · 1920 x 1080 · 0:15 · saved`, the name in bold and the rest
/// faint (`docs/design/mocks/pages/video.html`, `data-shell`).
///
/// Pure words: the app decides where and how it is drawn.
public struct WindowTitleLine: Sendable, Equatable {
    /// Saved or edited, the last word on the line.
    public enum SaveState: String, Sendable, Equatable {
        case saved, edited
    }

    /// The document's name without its extension: `launch-teaser`.
    public let name: String
    /// Size and length, joined by the same dot the line uses:
    /// `1920 x 1080 · 0:15`. Empty while neither is known.
    public let details: String
    /// Nil while the window is still reading its recording, when there is
    /// nothing yet to be saved or edited.
    public let state: SaveState?

    public static let separator = " · "

    /// - Parameters:
    ///   - fileName: the file this window is showing, with its extension.
    ///   - pictureSize: the document's canvas, when there is one.
    ///   - lengthMS: how long the document runs; zero or nil leaves it out.
    ///   - affordance: what Save means right now. The line says edited exactly
    ///     when closing would stop and ask, so the two can never disagree.
    ///   - hasFile: false for a document never written anywhere (a new empty
    ///     video). Unchanged, it is not "saved", since nothing was: the line
    ///     says neither word until there is a file or an edit.
    public init(fileName: String, pictureSize: CGSize?, lengthMS: Int?,
                affordance: SaveAffordance, hasFile: Bool = true) {
        let stem = (fileName as NSString).deletingPathExtension
        name = stem.isEmpty ? fileName : stem
        var parts: [String] = []
        if let pictureSize, pictureSize.width > 0, pictureSize.height > 0 {
            parts.append("\(Int(pictureSize.width.rounded())) x \(Int(pictureSize.height.rounded()))")
        }
        if let lengthMS, lengthMS > 0 {
            parts.append(Self.clock(lengthMS))
        }
        details = parts.joined(separator: Self.separator)
        switch affordance {
        case .nothingToSave: state = nil
        case .upToDate: state = hasFile ? .saved : nil
        case .unsavedChanges, .unsavedRecording, .saving: state = .edited
        }
    }

    /// The whole line as one string, for a walk to read and for accessibility.
    public var text: String {
        ([name, details, state?.rawValue ?? ""])
            .filter { !$0.isEmpty }
            .joined(separator: Self.separator)
    }

    /// `0:15`, or `1:02:03` once there are hours: whole seconds rounded down,
    /// the way the transport's end reads, so the two lengths always agree.
    public static func clock(_ ms: Int) -> String {
        let total = max(0, ms) / 1000
        let seconds = total % 60
        let minutes = (total / 60) % 60
        let hours = total / 3600
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, seconds) }
        return String(format: "%d:%02d", minutes, seconds)
    }
}
