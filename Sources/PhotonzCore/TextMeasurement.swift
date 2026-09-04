import CoreGraphics
import Foundation

/// How much room a piece of text needs — the one fact a box around words cannot
/// work out for itself here, because real wrapping is CoreText's answer and
/// `PhotonzCore` is pure.
///
/// The app installs the real thing once at launch (`TextMeasurement.use`, wired
/// to `TextRasterizer.naturalSize`). Everything else — every test, every tool
/// run without the app — gets an estimate that breaks on whole words at about
/// the right width. It is never what the app draws with; it is close enough
/// that "these words now need another line" is answered the same way.
public enum TextMeasurement {

    /// The size a box must be for `text` to lay out without clipping when it
    /// wraps at `maxWidth`. Pass `.greatestFiniteMagnitude` for "keep it on one
    /// line", which is the natural size of the words.
    public typealias Measure = @Sendable (_ text: TextContent, _ maxWidth: CGFloat) -> CGSize

    /// Installs the real measurement. Called once, from the app, before any
    /// document is opened.
    public static func use(_ measure: @escaping Measure) {
        installed.store(measure)
    }

    /// The size `text` needs, wrapped at `maxWidth`.
    public static func size(of text: TextContent,
                            wrappingAt maxWidth: CGFloat = .greatestFiniteMagnitude) -> CGSize {
        (installed.measure ?? estimated)(text, maxWidth)
    }

    /// The narrowest a text box goes. Below this a caption is a sliver of a
    /// column many lines tall rather than something you can read, so the
    /// canvas drag stops here — and so, through `LayerGeometryEditing`, does
    /// the width you type into the W field. One number, so the two ways of
    /// setting a width cannot disagree (the renderer's
    /// `TextRasterizer.minimumTextWidth` is this).
    public static let minimumWidth: CGFloat = 80

    /// The slack a measured box carries around its glyphs, so rounding and
    /// antialiased edges never clip at the boundary. Matches the renderer's
    /// `frameInset` on each side.
    public static let slack: CGFloat = 4

    /// About how big a piece of text is, without CoreText: whole-word wrapping
    /// against an average glyph width. Only used where the real thing has not
    /// been installed.
    public static func estimated(_ text: TextContent, _ maxWidth: CGFloat) -> CGSize {
        let perGlyph: CGFloat = text.weight == .regular ? 0.52 : 0.55
        let lineHeight = (text.fontSize * 1.22).rounded()
        func width(_ s: Substring) -> CGFloat { CGFloat(s.count) * text.fontSize * perGlyph }
        guard !text.string.isEmpty else {
            return CGSize(width: (text.fontSize / 2).rounded() + slack, height: lineHeight + slack)
        }
        let room = maxWidth.isFinite ? max(maxWidth - slack, 1) : .greatestFiniteMagnitude
        var lines: [Substring] = []
        for paragraph in text.string.split(separator: "\n", omittingEmptySubsequences: false) {
            var line = paragraph[paragraph.startIndex..<paragraph.startIndex]
            for word in paragraph.split(separator: " ", omittingEmptySubsequences: false) {
                let candidate = line.isEmpty ? word : paragraph[line.startIndex..<word.endIndex]
                if !line.isEmpty, width(candidate) > room {
                    lines.append(line)
                    line = word
                } else {
                    line = candidate
                }
            }
            lines.append(line)
        }
        let widest = lines.map(width).max() ?? 0
        return CGSize(width: min(ceil(widest), room) + slack,
                      height: lineHeight * CGFloat(lines.count) + slack)
    }

    /// The installed measurement, behind a lock. A closure is not `Hashable`
    /// and there is exactly one of these for the whole process, so the box is
    /// the smallest safe thing under Swift 6 strict concurrency — every read
    /// and write is serialized, and the stored value is itself `Sendable`.
    private final class Box: @unchecked Sendable {
        private let lock = NSLock()
        private var value: Measure?

        var measure: Measure? {
            lock.lock(); defer { lock.unlock() }
            return value
        }

        func store(_ measure: @escaping Measure) {
            lock.lock(); defer { lock.unlock() }
            value = measure
        }
    }

    private static let installed = Box()
}

extension Layer {

    /// Whether this box is as wide as its words want to be.
    ///
    /// A box nobody has narrowed hugs its words: re-wording it should stay on
    /// one line and simply be as wide as the new words. A box somebody HAS
    /// dragged narrower is a paragraph: re-wording it keeps that wrap width and
    /// only grows downward. Telling them apart is the difference between a
    /// button label that reads "Save changes" and one that reads "Save" over
    /// "changes".
    var textHugsItsWords: Bool {
        guard case .text(let content) = self.content else { return false }
        return frame.standardized.width + 0.5 >= TextMeasurement.size(of: content).width
    }

    /// This text box re-fitted to the words in it.
    ///
    /// A hugging box takes the natural size of the words; a wrapped one keeps
    /// its width and takes the height the wrap now needs. Either way the box
    /// grows from its top edge, and across the width it grows about whichever
    /// edge `anchor` pins, so a centred label stays centred and a title that
    /// starts at the left still starts there.
    func textRefitted(hugging: Bool, anchor: HorizontalPlacement) -> Layer {
        guard case .text(let content) = self.content else { return self }
        let box = frame.standardized
        let size = hugging ? TextMeasurement.size(of: content)
                           : TextMeasurement.size(of: content, wrappingAt: box.width)
        let width = hugging ? size.width : box.width
        guard width != box.width || size.height != box.height else { return self }
        let x: CGFloat
        switch anchor {
        case .center: x = (box.midX - width / 2).rounded()
        case .right: x = box.maxX - width
        case .scale, .left, .stretch: x = box.minX
        }
        var out = self
        out.frame = CGRect(x: x, y: box.minY, width: width, height: size.height)
        return out
    }
}
