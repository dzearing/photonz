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

    /// The narrowest the WORDS in a text box go. Below this a caption is a
    /// sliver of a column many lines tall rather than something you can read,
    /// so the canvas drag stops here — and so, through `LayerGeometryEditing`,
    /// does the width you type into the W field. It is stated on the words
    /// because that is the number both of those surfaces show: a floor of 80
    /// that left 76 on screen would make the field's own "will not go below
    /// 80" a lie.
    public static let minimumContentWidth: CGFloat = 80

    /// The narrowest a text box is STORED at: the words' floor plus the room
    /// the renderer draws them in. Everything that floors a frame rather than
    /// a reading uses this (the renderer's `TextRasterizer.minimumTextWidth`
    /// is this), so the two ways of setting a width cannot disagree.
    public static let minimumWidth: CGFloat = minimumContentWidth + slack

    /// The slack a measured box carries around its glyphs, so rounding and
    /// antialiased edges never clip at the boundary. Matches the renderer's
    /// `frameInset` on each side.
    public static let slack: CGFloat = 4

    /// The narrowest a box can be and still break these words BETWEEN them:
    /// the width of the widest single word in it.
    ///
    /// Narrower than this there is nothing left to break, so the letters come
    /// apart in the middle of a word — "But" over "ton" — which is never what
    /// a ceiling on a button meant. A container narrows a label to its room or
    /// to this, whichever is wider, so a word too long for the room overhangs
    /// it exactly as it did before any of this wrapped anything.
    ///
    /// The widest word is measured rather than guessed from letter counts,
    /// because a proportional face makes "WWW" wider than "illili". Only the
    /// longest handful are measured: this is a floor, not a layout number, and
    /// a wall of text is not a label that hugs its words in the first place.
    public static func widestWord(in text: TextContent) -> CGFloat {
        let words = Set(text.string.split(whereSeparator: { $0 == " " || $0 == "\n" })
            .map(String.init))
        // Longest first, and ties broken by the words themselves, so the
        // handful that gets measured is the same handful every run.
        let longest = words.sorted {
            $0.count == $1.count ? $0 < $1 : $0.count > $1.count
        }.prefix(wordsMeasuredForAFloor)
        return longest.reduce(CGFloat(0)) { widest, word in
            var one = text
            one.string = word
            return Swift.max(widest, size(of: one).width)
        }
    }

    /// How many words a floor costs at most. Twelve covers every label anybody
    /// puts in a button, a chip or a title.
    private static let wordsMeasuredForAFloor = 12

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

    /// The room this layer's stored box carries beyond the box a person can
    /// SEE. Nothing for every kind of layer but text, where it is the slack a
    /// measurement leaves for antialiased glyph edges, sitting entirely on the
    /// far edges because the words are drawn flush to the near corner.
    public var boxSlack: CGSize {
        text == nil ? .zero : CGSize(width: TextMeasurement.slack, height: TextMeasurement.slack)
    }

    /// `box` as it LOOKS: this layer's slack taken off its far edges.
    ///
    /// Everything a person reads a box off goes through here — the selection
    /// outline and its handles, the W and H fields, the magnets a drag lines
    /// itself up with, the band you sweep round something. Leave the slack in
    /// and a label's outline floats clear of its own last letter, its width
    /// reads four points more than the words are, and it lines up by an edge
    /// nobody can see.
    public func withoutSlack(_ box: CGRect) -> CGRect {
        let slack = boxSlack
        guard slack != .zero else { return box }
        let standard = box.standardized
        return CGRect(x: standard.minX, y: standard.minY,
                      width: max(0, standard.width - slack.width),
                      height: max(0, standard.height - slack.height))
    }

    /// The other direction: a box as it looks, turned back into the box to
    /// STORE. What the canvas and the fields hand back has to gain the slack
    /// again or the words would lose the room they are drawn in and re-wrap.
    public func withSlack(_ box: CGRect) -> CGRect {
        let slack = boxSlack
        guard slack != .zero else { return box }
        let standard = box.standardized
        return CGRect(x: standard.minX, y: standard.minY,
                      width: standard.width + slack.width,
                      height: standard.height + slack.height)
    }

    /// The box this layer's CONTENT fills, which is its own box for everything
    /// but text.
    ///
    /// A container closing around its contents has to close around the WORDS:
    /// leave the slack in and a centred label sits two points left of the
    /// middle of the button it is in, which is exactly the kind of wrongness
    /// nobody can name but everyone can see.
    public var contentBounds: CGRect { withoutSlack(localBounds) }

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
        // A box the CONTAINER narrowed is still a box nobody chose a width
        // for: the flow works that width out again every pass, so re-wording
        // one goes back to the words and gets wrapped afresh.
        if wrappedByItsContainer == true { return true }
        return frame.standardized.width + 0.5 >= TextMeasurement.size(of: content).width
    }

    /// Whether the container around this layer may decide how wide it is: it is
    /// text, and its width is not a width somebody chose. A paragraph dragged
    /// narrower by hand is not — that width is an answer, and a box that only
    /// happens to sit inside something narrow must not lose it.
    var wrapsToItsContainer: Bool {
        guard case .text = content else { return false }
        return textHugsItsWords
    }

    /// This text box narrowed to the room its container has for it, with the
    /// words re-wrapped and the box as tall as they now need.
    ///
    /// `room` is room a person can SEE, the same as everything else the flow
    /// hands about, so the slack a measured box carries is added back here.
    /// Words that already fit change nothing at all: the same layer comes
    /// straight back, unmarked, so a label inside a roomy container is byte for
    /// byte the layer it was before any of this existed.
    func textWrapped(inRoom room: CGFloat) -> Layer {
        guard case .text(let content) = self.content else { return self }
        // Never narrower than a single word needs. Below that the words break
        // in the middle of themselves, which is worse than the overhang this
        // set out to fix.
        let allowed = max(max(1, room + boxSlack.width), TextMeasurement.widestWord(in: content))
        guard TextMeasurement.size(of: content).width > allowed else { return self }
        let box = frame.standardized
        let height = TextMeasurement.size(of: content, wrappingAt: allowed).height
        var out = self
        out.frame = CGRect(x: box.minX, y: box.minY, width: allowed, height: height)
        out.wrappedByItsContainer = true
        return out
    }

    /// The same box back at the width its WORDS want, undoing whatever a
    /// container decided last time. Every flow pass starts here, so the room a
    /// label is allowed is worked out from the words rather than from the
    /// answer the last pass gave — otherwise a wrapped label measures as if it
    /// fitted, the ceiling stops biting, and the two answers take turns for
    /// ever.
    var textUnwrapped: Layer {
        guard wrappedByItsContainer == true,
              case .text(let content) = self.content else { return self }
        let box = frame.standardized
        var out = self
        out.frame = CGRect(origin: box.origin, size: TextMeasurement.size(of: content))
        out.wrappedByItsContainer = nil
        return out
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
