import CoreGraphics
import Foundation

// How the words of a caption show: how many at a time, and what the word
// being said does (`CaptionLook`, `docs/design/mocks/pages/video-captions.html`).
//
// The user, 2026-09-25: "maybe I want to have a sentence at a time, or 3 words
// at a time, or 1... maybe the current word should have a soft grow animation
// with a bounce to make it more obvious. There could be styles to the caption.
// Maybe glow on the overall text vs the active word. I want it to be easy to
// tweak." CapCut, Submagic and Premiere all answer it the same way, and so
// does this:
//
// - **Show regroups the captions.** Picking 3 words re-splits the transcript
//   into captions of three, and the timeline shows the new bars, the way
//   CapCut's words-per-caption and Premiere's single/double lines do. Every
//   word keeps its moment and every word somebody fixed by hand stays fixed.
// - **The current word is its own thing**: a colour, a pill behind it, its own
//   glow, stroke and shadow, a size, and a motion (grow, a soft spring, a pop,
//   an underline) at a speed. None of it is stored per frame: the frame drawn
//   at a moment works out where the motion is (`CaptionWordPaint`), so the
//   canvas and the film written out draw exactly the same picture.
// - **Words said and words to come** each keep full colour, dim, or (said)
//   light up like karaoke, or (to come) wait off screen until they are said.

// MARK: - How many words at a time

/// How many words a caption holds.
public enum CaptionGrouping: String, Hashable, Codable, Sendable, CaseIterable {
    case sentence, line, threeWords, twoWords, oneWord

    public var title: String {
        switch self {
        case .sentence: "Sentence"
        case .line: "Line"
        case .threeWords: "3 words"
        case .twoWords: "2 words"
        case .oneWord: "1 word"
        }
    }

    /// The most words a caption holds, or nil where the width decides.
    public var wordCap: Int? {
        switch self {
        case .sentence, .line: nil
        case .threeWords: 3
        case .twoWords: 2
        case .oneWord: 1
        }
    }

    /// Whether Lines means anything: a few words are never more than one.
    public var usesLines: Bool { wordCap == nil }
}

extension CaptionCueRule {

    /// Captions of a few words: up only until the next arrives, never a flash
    /// shorter than a beat.
    static let fewWords = CaptionCueRule(maxCharacters: 400, maxLengthMS: 6_000, breakGapMS: 700,
                                         minLengthMS: 300, holdMS: 400)
}

extension CaptionCues {

    /// The captions a run of words breaks into when they show `showing` at a
    /// time, in captions at most `lines` lines of `charactersPerLine` long.
    ///
    /// - A **line** fills the width, and also ends where a sentence does or
    ///   the speaker stops, which is how captions have always been written.
    /// - A **sentence** ends only where the sentence does (or a long silence),
    ///   so a thought is never cut in two by a breath, but never runs to more
    ///   lines than it is allowed.
    /// - **A few words** at a time ends every few words, and at every full
    ///   stop and pause, the way social captions read.
    public static func cues(from words: [TranscribedWord], showing: CaptionGrouping,
                            lines: Int, charactersPerLine: Int) -> [CaptionCue] {
        let lines = max(1, min(2, lines))
        let width = max(8, charactersPerLine) * lines
        switch showing {
        case .line:
            return cues(from: words, rule: CaptionCueRule(maxCharacters: width))
        case .sentence:
            return cues(from: words, rule: CaptionCueRule(maxCharacters: width, maxLengthMS: 15_000,
                                                          breakGapMS: 1_500))
        case .threeWords, .twoWords, .oneWord:
            return cues(from: words, rule: .fewWords, maxWords: showing.wordCap ?? 1)
        }
    }

    /// The same breaking, with a cap on how many words a caption holds.
    static func cues(from words: [TranscribedWord], rule: CaptionCueRule, maxWords: Int) -> [CaptionCue] {
        var chunks: [[TranscribedWord]] = []
        var line: [TranscribedWord] = []
        for word in words {
            if let last = line.last,
               line.count >= maxWords || word.startMS - last.endMS >= rule.breakGapMS
                || ".?!。？！".contains(last.text.last ?? " ") {
                chunks.append(line)
                line = []
            }
            line.append(word)
        }
        if !line.isEmpty { chunks.append(line) }
        var cues: [CaptionCue] = []
        for (index, chunk) in chunks.enumerated() {
            guard let first = chunk.first, let last = chunk.last else { continue }
            let next = index + 1 < chunks.count ? chunks[index + 1].first?.startMS : nil
            // Up until the next caption arrives, when the speaker has not
            // stopped: a gap between two words is not a blank screen. Never
            // into the next one.
            var out = max(last.endMS + rule.holdMS, first.startMS + rule.minLengthMS)
            if let next {
                if next - last.endMS < rule.breakGapMS { out = next }
                out = max(min(out, next), first.startMS + LayerTime.shortestMS)
            }
            cues.append(CaptionCue(words: chunk, inMS: first.startMS, outMS: out))
        }
        return cues
    }
}

extension CaptionLayers {

    /// About how many characters of type this size sit across a box this wide:
    /// never more than the subtitling convention's forty two, so a wide box
    /// does not turn a caption into a paragraph, and fewer on a narrow
    /// picture, so a portrait video's captions do not run to three lines.
    public static func charactersPerLine(boxWidth: CGFloat, fontSize: CGFloat) -> Int {
        guard fontSize > 0 else { return 42 }
        return max(8, min(42, Int(boxWidth / (fontSize * 0.52))))
    }

    /// Every word of a Captions layer's captions, in the order they are said,
    /// as shown now: under a bar somebody moved, and with the words somebody
    /// retyped. A caption retyped into a different number of words shares its
    /// time out between the new words evenly.
    static func words(of cues: [Layer]) -> [TranscribedWord] {
        let ordered = cues.filter(\.isCaption).sorted { ($0.time?.inMS ?? 0) < ($1.time?.inMS ?? 0) }
        return ordered.flatMap(wordsAsShown)
    }

    /// One caption's words as shown now.
    private static func wordsAsShown(_ cue: Layer) -> [TranscribedWord] {
        guard let heard = cue.captionWords, let time = cue.time,
              case .text(let content) = cue.content else { return [] }
        let fitted = CaptionCue.words(heard, fittedTo: time)
        let typed: [String] = content.string.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !typed.isEmpty else { return [] }
        guard typed.count == fitted.count else {
            let start: Int = fitted.first?.startMS ?? time.inMS
            let end: Int = max(start + 1, fitted.last?.endMS ?? time.outMS)
            return PhotonzDocument.spread(typed, over: start...end)
        }
        var words: [TranscribedWord] = []
        for (word, text) in zip(fitted, typed) {
            guard word.text != text else { words.append(word); continue }
            var fixed = word
            fixed.heardAs = word.heardAs ?? word.text
            fixed.text = text
            words.append(fixed)
        }
        return words
    }
}

extension PhotonzDocument {

    /// Split one Captions layer's words into captions again, the way its look
    /// says they show. The layer stays where it is, the same layer; only its
    /// captions change, and every word keeps its moment.
    mutating func regroupCaptions(_ id: UUID) {
        guard let layer = layer(id: id), let look = layer.captionsLook else { return }
        let words = CaptionLayers.words(of: layer.children)
        guard !words.isEmpty else { return }
        let size = canvasSize
        let perLine = CaptionLayers.charactersPerLine(boxWidth: layer.frame.width,
                                                      fontSize: look.resolvedFontSize(in: size))
        let end = hasTime ? documentDurationMS : Int.max
        let cues = CaptionCues.cues(from: words, showing: look.show, lines: look.lines,
                                    charactersPerLine: perLine)
            .compactMap { cue -> CaptionCue? in
                guard cue.inMS < end - LayerTime.shortestMS else { return nil }
                return CaptionCue(words: cue.words, inMS: cue.inMS, outMS: min(cue.outMS, end))
            }
        guard !cues.isEmpty else { return }
        let children = CaptionLayers.layers(for: cues, in: size, look: look, box: layer.frame.size)
        updateLayer(id: id) { $0.children = children }
    }
}

// MARK: - Words said, and words to come

/// How a word that is not being said right now is drawn.
public enum CaptionWordShade: String, Hashable, Codable, Sendable, CaseIterable {
    /// In the caption's own colour.
    case full
    /// Faded, so the word being said stands out.
    case dim
    /// In the current word's colour: karaoke, every word sung stays lit.
    case lit
    /// Not drawn yet: words appear as they are said.
    case hidden

    public var title: String {
        switch self {
        case .full: "Full"
        case .dim: "Dim"
        case .lit: "Lit"
        case .hidden: "Hidden"
        }
    }

    /// What a word already said can do.
    public static let saidChoices: [CaptionWordShade] = [.full, .dim, .lit]
    /// What a word still to come can do.
    public static let comingChoices: [CaptionWordShade] = [.full, .dim, .hidden]

    /// How much of the word shows.
    public var opacity: CGFloat {
        switch self {
        case .full, .lit: 1
        case .dim: 0.45
        case .hidden: 0
        }
    }
}

// MARK: - The word being said

/// What the word being said does as it arrives.
public enum CaptionWordMotion: String, Hashable, Codable, Sendable, CaseIterable {
    case none, grow, growBounce, pop, underline

    public var title: String {
        switch self {
        case .none: "None"
        case .grow: "Grow"
        case .growBounce: "Grow with bounce"
        case .pop: "Pop"
        case .underline: "Underline sweep"
        }
    }

    /// Whether the word gets bigger, so a size of 100% would show nothing.
    public var grows: Bool { self == .grow || self == .growBounce }
}

/// How a caption shadows its words.
public enum CaptionShadow: String, Hashable, Codable, Sendable, CaseIterable {
    /// The small readable shadow, only where there is no plate behind.
    case auto
    case none
    case soft
    case deep

    public var title: String {
        switch self {
        case .auto: "Auto"
        case .none: "None"
        case .soft: "Soft"
        case .deep: "Deep"
        }
    }
}

/// The word being said: its own colour, pill, glow, stroke, shadow, size and
/// motion, separate from the rest of the text.
public struct CaptionWordLook: Hashable, Codable, Sendable {
    /// Its colour, or nil for the caption's own.
    public var colorHex: String?
    /// A rounded pill behind it, or nil for none.
    public var pillHex: String?
    public var glowHex: String?
    public var strokeHex: String?
    public var shadow: Bool
    /// How big it is next to the rest, 1 for the same size.
    public var scale: CGFloat
    public var motion: CaptionWordMotion
    /// How long the motion takes to arrive.
    public var speedMS: Int

    public static let scaleRange: ClosedRange<CGFloat> = 1...1.6
    public static let speedRange: ClosedRange<Int> = 80...600
    public static let standardSpeedMS = 220

    public init(colorHex: String? = nil, pillHex: String? = nil, glowHex: String? = nil,
                strokeHex: String? = nil, shadow: Bool = false, scale: CGFloat = 1,
                motion: CaptionWordMotion = .none, speedMS: Int = CaptionWordLook.standardSpeedMS) {
        self.colorHex = colorHex
        self.pillHex = pillHex
        self.glowHex = glowHex
        self.strokeHex = strokeHex
        self.shadow = shadow
        self.scale = scale
        self.motion = motion
        self.speedMS = speedMS
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        colorHex = try c.decodeIfPresent(String.self, forKey: .colorHex)
        pillHex = try c.decodeIfPresent(String.self, forKey: .pillHex)
        glowHex = try c.decodeIfPresent(String.self, forKey: .glowHex)
        strokeHex = try c.decodeIfPresent(String.self, forKey: .strokeHex)
        shadow = try c.decodeIfPresent(Bool.self, forKey: .shadow) ?? false
        scale = try c.decodeIfPresent(CGFloat.self, forKey: .scale) ?? 1
        motion = try c.decodeIfPresent(CaptionWordMotion.self, forKey: .motion) ?? .none
        speedMS = try c.decodeIfPresent(Int.self, forKey: .speedMS) ?? CaptionWordLook.standardSpeedMS
    }

    /// Pick a motion. A grow picked while the word is at full size gets
    /// somewhere to grow to, or picking it would change nothing you could see.
    public mutating func pick(_ motion: CaptionWordMotion) {
        self.motion = motion
        if motion.grows, scale < 1.05 { scale = 1.2 }
    }

    /// Whether the word needs drawing on its own: anything beyond a colour.
    var isDrawnAlone: Bool {
        pillHex != nil || glowHex != nil || strokeHex != nil || shadow || abs(scale - 1) > 0.001
            || motion != .none
    }

    /// How long the motion runs before it has settled.
    public var settleMS: Int {
        motion == .growBounce ? speedMS * 5 / 2 : speedMS
    }

    /// How big the word is drawn, `ms` after it started being said.
    public func drawnScale(msIntoWord ms: Int) -> CGFloat {
        let t = Double(max(0, ms)) / Double(max(1, speedMS))
        let target = Double(scale)
        let eased = 1 - pow(1 - min(t, 1), 3)
        switch motion {
        case .none, .underline:
            return scale
        case .grow:
            return CGFloat(1 + (target - 1) * eased)
        case .growBounce:
            // A soft spring: past the size by a sixth of the way, and back.
            guard ms < settleMS else { return scale }
            let spring = 1 - exp(-3 * t) * cos(2 * Double.pi * 0.8 * t)
            return CGFloat(1 + (target - 1) * spring)
        case .pop:
            // In from small, a little past, and down onto its size.
            let u = min(t, 1)
            let back = 1 + 2.7 * pow(u - 1, 3) + 1.7 * pow(u - 1, 2)
            return CGFloat(target * (0.55 + 0.45 * back))
        }
    }

    /// How far an underline has swept across the word, or nil for a motion
    /// with no underline.
    public func drawnUnderline(msIntoWord ms: Int) -> CGFloat? {
        guard motion == .underline else { return nil }
        let t = min(1, Double(max(0, ms)) / Double(max(1, speedMS)))
        return CGFloat(1 - pow(1 - t, 3))
    }
}

/// Everything about how a caption's words are drawn at one moment: which word
/// is being said, where its motion is, and how the words either side of it
/// are shaded. Set on the frame drawn at a moment and never saved, exactly
/// like the lit word before it.
public struct CaptionWordPaint: Hashable, Codable, Sendable {
    /// The word being said, in UTF-16 units.
    public var word: CaptionActiveWord.Span
    public var said: CaptionWordShade
    public var coming: CaptionWordShade
    /// What the word being said, and karaoke's sung words, are drawn in.
    public var colorHex: String?
    public var pillHex: String?
    public var glowHex: String?
    public var strokeHex: String?
    public var shadow: Bool
    /// How big the word is drawn at this moment.
    public var scale: CGFloat
    /// How far its underline has swept, 0 to 1, or nil for none.
    public var underline: CGFloat?
    /// Whether the word is drawn on its own, over the rest.
    public var drawnAlone: Bool

    public init(word: CaptionActiveWord.Span, said: CaptionWordShade = .full,
                coming: CaptionWordShade = .full, colorHex: String? = nil, pillHex: String? = nil,
                glowHex: String? = nil, strokeHex: String? = nil, shadow: Bool = false,
                scale: CGFloat = 1, underline: CGFloat? = nil, drawnAlone: Bool = false) {
        self.word = word
        self.said = said
        self.coming = coming
        self.colorHex = colorHex
        self.pillHex = pillHex
        self.glowHex = glowHex
        self.strokeHex = strokeHex
        self.shadow = shadow
        self.scale = scale
        self.underline = underline
        self.drawnAlone = drawnAlone
    }
}

extension CaptionActiveWord {

    /// The word being said at `ms` and the moment it started, or nil before
    /// the first word.
    public static func current(in string: String, words: [TranscribedWord], cue: LayerTime,
                               atMS ms: Int) -> (span: Span, index: Int, startMS: Int)? {
        let words = CaptionCue.words(words, fittedTo: cue)
        let tokens = tokenSpans(in: string)
        guard let first = words.first, let last = words.last, !tokens.isEmpty,
              ms >= first.startMS else { return nil }
        if tokens.count == words.count {
            let index = words.lastIndex { $0.startMS <= ms } ?? 0
            return (tokens[index], index, words[index].startMS)
        }
        let length = max(1, last.endMS - first.startMS)
        let share = Double(ms - first.startMS) / Double(length)
        let index = min(tokens.count - 1, max(0, Int(share * Double(tokens.count))))
        return (tokens[index], index, first.startMS + length * index / tokens.count)
    }
}

extension CaptionLook {

    /// Whether this look draws anything about its words beyond a lit colour.
    var paintsWords: Bool {
        word.isDrawnAlone || said != .full || coming != .full
    }

    /// The paint for a caption saying `string` at `ms`, or nil where nothing
    /// is drawn beyond the plain lit colour.
    func wordPaint(for string: String, words: [TranscribedWord], cue: LayerTime,
                   atMS ms: Int) -> CaptionWordPaint? {
        guard paintsWords else { return nil }
        // Before the first word nothing is being said, and every word is
        // still to come: a look whose words wait shows none of them yet. The
        // paint is there all the same, so the words sit exactly where they
        // will once the first one arrives.
        guard let now = CaptionActiveWord.current(in: string, words: words, cue: cue, atMS: ms) else {
            return CaptionWordPaint(word: CaptionActiveWord.Span(location: 0, length: 0), said: said,
                                    coming: coming, drawnAlone: word.isDrawnAlone)
        }
        let into = ms - now.startMS
        return CaptionWordPaint(word: now.span, said: said, coming: coming,
                                colorHex: word.colorHex, pillHex: word.pillHex,
                                glowHex: word.glowHex, strokeHex: word.strokeHex,
                                shadow: word.shadow, scale: word.drawnScale(msIntoWord: into),
                                underline: word.drawnUnderline(msIntoWord: into),
                                drawnAlone: word.isDrawnAlone)
    }
}

// MARK: - A style, played on a tile

extension CaptionLook {

    /// What a style tile says, over and over, with a moment for every word.
    public static let previewWords: [TranscribedWord] = [
        TranscribedWord("Say", startMS: 0, endMS: 360),
        TranscribedWord("it", startMS: 360, endMS: 600),
        TranscribedWord("like", startMS: 600, endMS: 960),
        TranscribedWord("you", startMS: 960, endMS: 1_260),
        TranscribedWord("mean", startMS: 1_260, endMS: 1_700),
        TranscribedWord("it.", startMS: 1_700, endMS: 2_300),
    ]
    /// One lap of a tile's words, with a beat of rest at the end.
    public static let previewCycleMS = 2_900

    /// A style tile's caption `ms` into its lap, at `fontSize` in a box
    /// `width` wide: the caption exactly as a frame of the film would draw it
    /// in this look, word being said and all.
    public func previewText(atMS ms: Int, fontSize: CGFloat, width: CGFloat) -> TextContent? {
        var look = self
        look.fontSize = fontSize
        let perLine = CaptionLayers.charactersPerLine(boxWidth: width, fontSize: fontSize)
        let cues = CaptionCues.cues(from: Self.previewWords, showing: show, lines: 1,
                                    charactersPerLine: perLine)
        guard let cue = cues.last(where: { $0.inMS <= ms }) ?? cues.first else { return nil }
        let box = CGSize(width: width, height: fontSize * 2.6)
        guard let layer = CaptionLayers.layers(for: [cue], in: box, look: look, box: box).first,
              case .text(let content) = layer.withSpokenWordLit(atTimeMS: ms, look: look).content
        else { return nil }
        return content
    }
}

// MARK: - Styles of your own

/// A caption look somebody kept under a name, to use on any recording.
public struct SavedCaptionStyle: Hashable, Codable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var look: CaptionLook

    public init(id: UUID = UUID(), name: String, look: CaptionLook) {
        self.id = id
        self.name = name
        self.look = look
    }
}

/// The caption styles somebody has kept, in the order they kept them.
public struct CaptionStyleLibrary: Hashable, Codable, Sendable {
    public var styles: [SavedCaptionStyle]

    public init(styles: [SavedCaptionStyle] = []) {
        self.styles = styles
    }

    /// Keep `look` under the next free "My style" name.
    @discardableResult
    public mutating func save(_ look: CaptionLook) -> SavedCaptionStyle {
        let taken = Set(styles.map(\.name))
        var name = "My style"
        var number = 2
        while taken.contains(name) {
            name = "My style \(number)"
            number += 1
        }
        let style = SavedCaptionStyle(name: name, look: look)
        styles.append(style)
        return style
    }

    public mutating func remove(id: UUID) {
        styles.removeAll { $0.id == id }
    }
}
