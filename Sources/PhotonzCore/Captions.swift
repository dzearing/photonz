import CoreGraphics
import Foundation

// Captions: the words somebody said, on the timeline
// (`docs/design/mocks/pages/video-captions.html`).
//
// **Captions are not a mode that replaces the app. They are what the Title /
// Text tool does when the document has time.** So there is no caption object,
// no caption track and no caption editor here. A caption is the same thing a
// title already is — a `Layer` with `content: .text` and a `LayerTime` — with
// one extra thing written on it: the words the machine heard, and when it
// heard each one.
//
// That one extra thing is why it is worth carrying rather than throwing away
// after the cues are cut:
//
// - A cue can be re-cut at a word rather than at a guess.
// - The whole track can be nudged when the machine was late, and each word
//   moves with it, so a second pass still knows where the words were.
// - Subtitles written out later carry the timings the words really had, not
//   the timings the boxes happen to have after somebody dragged one.
//
// Correcting the WORDS never touches any of it: the string on the text layer
// is the string on the text layer, and editing it is editing text. That is the
// whole of "a correction does not throw the timing away".
//
// Nothing in this file listens to anything. Hearing is `PhotonzMedia`'s job
// (`SpeechTranscription.swift`); everything here is arithmetic on what came
// back, which is what makes the hard parts — where the pieces join, where the
// lines break, where the boxes sit — testable without a microphone.

// MARK: - What was heard

/// One word, and the stretch of the recording it was said in.
///
/// Times are milliseconds from the start of the RECORDING, never from the
/// start of the piece it happened to be heard in. Every piece is put back onto
/// the recording's own clock the moment it lands (`TranscriptSeam`), because an
/// offset error is invisible at the start and enormous at the end.
public struct TranscribedWord: Hashable, Codable, Sendable {

    /// The word as it was heard, carrying whatever punctuation came with it.
    public var text: String
    public var startMS: Int
    public var endMS: Int
    /// How sure the machine was, nought to one, or nil where it did not say.
    public var confidence: Double?

    public init(_ text: String, startMS: Int, endMS: Int, confidence: Double? = nil) {
        self.text = text
        self.startMS = max(0, startMS)
        self.endMS = max(self.startMS, endMS)
        self.confidence = confidence
    }

    public var lengthMS: Int { endMS - startMS }

    /// Whether this word is one the machine was not sure of, and should be
    /// marked as heard-badly rather than passed off as heard.
    public var isUncertain: Bool {
        guard let confidence else { return false }
        return confidence < Captions.sureEnough
    }

    /// The word with nothing on it that decides whether two pieces heard the
    /// same thing: no case, no punctuation, no spaces.
    public var spine: String { Captions.spine(of: text) }

    /// The same word said somewhere else in the recording.
    public func shifted(byMS ms: Int) -> TranscribedWord {
        TranscribedWord(text, startMS: startMS + ms, endMS: endMS + ms, confidence: confidence)
    }
}

/// The numbers and words shared by everything that deals in captions.
public enum Captions {

    /// Below this, a word is marked rather than presented as heard.
    ///
    /// The point of the mark is not accuracy — every automatic caption is
    /// wrong somewhere — it is honesty: a word the machine half-heard should
    /// LOOK half-heard, so the eye goes to it first when you are correcting.
    public static let sureEnough = 0.35

    /// What is said where nothing was heard at all, rather than leaving an
    /// empty track and letting somebody think it is still working.
    public static let heardNothing = "There is nothing to caption: no words were heard in this recording."

    /// ...and where there was no sound to listen to in the first place.
    public static let nothingToHear = "There is no sound in this document to make captions from."

    /// Strip a word down to what decides whether two pieces heard the same
    /// thing. `"Recordings,"` and `"recordings"` are the same word said twice.
    public static func spine(of text: String) -> String {
        text.lowercased().unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .reduce(into: "") { $0.unicodeScalars.append($1) }
    }
}

// MARK: - Where the pieces join

/// Putting two pieces of a long recording back together.
///
/// A recogniser given an hour of audio in one breath is a recogniser you
/// cannot show progress for, cannot stop, and cannot restart when it gives up
/// half way. So a long recording is heard in pieces — and the pieces are where
/// a naive chunker fails, because a cut on a fixed clock lands in the middle of
/// a word and the word is lost twice over: once from the end of one piece and
/// once from the start of the next.
///
/// Two rules fix it, and they are both here:
///
/// 1. **Pieces overlap.** The next piece starts a few seconds BEFORE the last
///    one ended, so every word is wholly inside at least one piece.
/// 2. **They are stitched by what was said, not by the clock.** The overlap is
///    heard twice, so the join is made where the two pieces agree, and the
///    words in the overlap are kept exactly once.
public enum TranscriptSeam {

    /// How many words have to agree before the overlap is believed.
    ///
    /// One word is not evidence — "the" appears everywhere — and a run of
    /// three in the same order at roughly the same moment is not a coincidence
    /// in speech.
    public static let agreementRun = 3

    /// Join words already accepted with words from the next, overlapping piece.
    ///
    /// Both runs are on the recording's own clock. The answer holds every word
    /// once, in order: nothing in the overlap is lost and nothing is doubled.
    public static func joined(_ kept: [TranscribedWord],
                              with next: [TranscribedWord]) -> [TranscribedWord] {
        guard !kept.isEmpty else { return next }
        guard !next.isEmpty else { return kept }

        // Where the two pieces could be talking about the same words at all.
        let overlapFromMS = next[0].startMS
        let tail = kept.filter { $0.endMS > overlapFromMS }
        guard !tail.isEmpty else {
            // No overlap in time: the pieces simply meet, and a word that
            // straddled the meeting point is gone either way. Keep both runs.
            return kept + next
        }

        if let cut = agreementCut(tail: tail, next: next) {
            return kept + Array(next[cut...])
        }

        // The two pieces did not agree on anything in the overlap. Trust the
        // clock rather than inventing: take from the next piece only what
        // starts after everything already accepted, which loses nothing and
        // doubles nothing even though it may leave a gap where a word fell in
        // the disagreement.
        let lastEnd = kept[kept.count - 1].endMS
        return kept + next.filter { $0.startMS >= lastEnd }
    }

    /// Where the next piece should be cut so its words carry on from the
    /// accepted ones, found by matching what was said in the overlap.
    private static func agreementCut(tail: [TranscribedWord],
                                     next: [TranscribedWord]) -> Int? {
        let tailSpines = tail.map(\.spine)
        let nextSpines = next.map(\.spine)
        // Longest run of the tail that is also the head of the next piece,
        // longest first so a repeated phrase does not join at the wrong copy.
        var run = min(tailSpines.count, nextSpines.count)
        while run >= 1 {
            if Array(tailSpines.suffix(run)) == Array(nextSpines.prefix(run)),
               run >= agreementRun || run == tailSpines.count {
                return run
            }
            run -= 1
        }
        return nil
    }
}

// MARK: - Cutting a recording into pieces

/// One piece of a recording to be listened to on its own.
public struct AudioChunk: Hashable, Sendable {
    /// Where this piece starts in the recording. Everything heard inside it
    /// comes back relative to HERE and is put back on the recording's clock by
    /// adding it (`shifted(byMS:)`).
    public var startMS: Int
    public var endMS: Int

    public init(startMS: Int, endMS: Int) {
        self.startMS = max(0, startMS)
        self.endMS = max(self.startMS, endMS)
    }

    public var lengthMS: Int { endMS - startMS }
}

/// How long the pieces are and how far they lean into each other.
public struct ChunkWindow: Hashable, Sendable {

    /// How much audio to hand over at once.
    ///
    /// Two minutes, which is a compromise between two real costs. Longer and a
    /// stop takes longer to answer and a failure throws away more work. Shorter
    /// and there are more joins to get right, and a recogniser that gets the
    /// whole sentence tends to get the words in it right, so every extra cut
    /// costs a little accuracy at it.
    public var targetMS: Int
    /// How far either side of the target a quiet moment is worth moving the cut
    /// to. Cutting in a silence means there is no word at the join to lose.
    public var slackMS: Int
    /// How far the next piece leans back into the last when the cut had to be
    /// made in the middle of speech, so a word at the join is wholly inside one
    /// of them and the two have something to agree about.
    public var overlapMS: Int

    public init(targetMS: Int = 120_000, slackMS: Int = 15_000, overlapMS: Int = 4_000) {
        self.targetMS = max(1_000, targetMS)
        self.slackMS = max(0, slackMS)
        self.overlapMS = max(0, overlapMS)
    }
}

public enum TranscriptChunks {

    /// The piece that starts here, or nil where the recording is already
    /// finished.
    ///
    /// `quietMS` is the moments the recording has been MEASURED to go quiet in,
    /// which the thing doing the listening learns as it goes rather than in a
    /// pass of its own. A cut lands on the quiet moment nearest the target
    /// where there is one within the slack, and in the middle of speech
    /// otherwise — and only then does the next piece need to overlap, because
    /// a cut in a silence has no word at it to lose.
    public static func next(startingAt start: Int, durationMS: Int, quietMS: [Int] = [],
                            window: ChunkWindow = ChunkWindow()) -> AudioChunk? {
        guard start < durationMS else { return nil }
        let target = start + window.targetMS
        guard target < durationMS - window.slackMS else {
            return AudioChunk(startMS: start, endMS: durationMS)
        }
        let silence = nearestQuiet(to: target, in: quietMS.sorted(),
                                   within: window.slackMS, after: start + window.targetMS / 2)
        return AudioChunk(startMS: start, endMS: silence ?? target)
    }

    /// Where the piece AFTER this one begins.
    ///
    /// A piece cut in a silence is followed straight on, because no word
    /// straddles the cut. A piece cut in the middle of speech is followed by
    /// one that leans back into it, so the word at the cut is wholly inside
    /// the next piece and the two have something to agree about
    /// (`TranscriptSeam`).
    public static func start(after chunk: AudioChunk, cutInSilence: Bool,
                             window: ChunkWindow = ChunkWindow()) -> Int {
        cutInSilence ? chunk.endMS : max(chunk.startMS + 1, chunk.endMS - window.overlapMS)
    }

    /// Every piece a recording of this length is heard in, worked out up front.
    ///
    /// What the driver actually walks is `next(startingAt:)`, one piece at a
    /// time, because it learns where the silences are as it listens. This is
    /// the same walk done in advance: it is what says how many pieces there
    /// will be before any of them have been heard.
    public static func plan(durationMS: Int, quietMS: [Int] = [],
                            window: ChunkWindow = ChunkWindow()) -> [AudioChunk] {
        guard durationMS > 0 else { return [] }
        var chunks: [AudioChunk] = []
        var start = 0
        while let chunk = next(startingAt: start, durationMS: durationMS,
                               quietMS: quietMS, window: window) {
            chunks.append(chunk)
            guard chunk.endMS < durationMS else { break }
            start = self.start(after: chunk, cutInSilence: quietMS.contains(chunk.endMS),
                               window: window)
        }
        return chunks
    }

    private static func nearestQuiet(to target: Int, in quiet: [Int],
                                     within slack: Int, after floor: Int) -> Int? {
        var best: Int?
        for moment in quiet where moment > floor && abs(moment - target) <= slack {
            if best == nil || abs(moment - target) < abs(best! - target) { best = moment }
        }
        return best
    }
}

// MARK: - Lines

/// One line of caption: the words in it, and when it is on screen.
public struct CaptionCue: Hashable, Codable, Sendable {

    public var words: [TranscribedWord]
    public var inMS: Int
    public var outMS: Int

    public init(words: [TranscribedWord], inMS: Int, outMS: Int) {
        self.words = words
        self.inMS = inMS
        self.outMS = max(inMS + LayerTime.shortestMS, outMS)
    }

    /// What is on screen.
    public var text: String { words.map(\.text).joined(separator: " ") }

    /// Whether any word in this line was one the machine was unsure of.
    public var isUncertain: Bool { words.contains { $0.isUncertain } }

    public var lengthMS: Int { outMS - inMS }
}

/// Where a line of caption ends and the next begins.
public struct CaptionCueRule: Hashable, Sendable {

    /// How many characters a line may run to before it is broken.
    ///
    /// Forty two is the subtitling convention and it is a convention for a
    /// reason: a line wider than that takes a sweep of the eye to read rather
    /// than a glance, and a caption is read out of the corner of the eye while
    /// watching something else.
    public var maxCharacters: Int
    /// The longest a single line stays up, however few words are in it.
    public var maxLengthMS: Int
    /// A silence at least this long ends the line: somebody stopped talking,
    /// and carrying the next sentence into the same box reads as one thought.
    public var breakGapMS: Int
    /// The shortest a line stays up, so a one-word line is not a flash.
    public var minLengthMS: Int
    /// How long the words linger after the last one was finished, so a line
    /// does not vanish on the final syllable.
    public var holdMS: Int

    public init(maxCharacters: Int = 42, maxLengthMS: Int = 6_000, breakGapMS: Int = 700,
                minLengthMS: Int = 1_200, holdMS: Int = 300) {
        self.maxCharacters = max(8, maxCharacters)
        self.maxLengthMS = max(500, maxLengthMS)
        self.breakGapMS = max(0, breakGapMS)
        self.minLengthMS = max(0, minLengthMS)
        self.holdMS = max(0, holdMS)
    }
}

public enum CaptionCues {

    /// The lines a run of words breaks into.
    ///
    /// Four things end a line, and they are in the order a person would use
    /// them: a full stop, a silence, a line that has got long enough to read,
    /// and a line that has been up long enough. Nothing here is clever: the
    /// bar is not that the breaks are perfect, it is that fixing one is a drag
    /// of a bar end rather than a retype.
    public static func cues(from words: [TranscribedWord],
                            rule: CaptionCueRule = CaptionCueRule()) -> [CaptionCue] {
        guard !words.isEmpty else { return [] }
        var cues: [CaptionCue] = []
        var line: [TranscribedWord] = []

        func close() {
            guard let first = line.first, let last = line.last else { return }
            cues.append(CaptionCue(words: line, inMS: first.startMS, outMS: last.endMS + rule.holdMS))
            line = []
        }

        for word in words {
            if let last = line.last {
                let gap = word.startMS - last.endMS
                let wouldRead = line.map(\.text).joined(separator: " ").count + 1 + word.text.count
                let wouldRun = word.endMS - (line.first?.startMS ?? word.startMS)
                if gap >= rule.breakGapMS || wouldRead > rule.maxCharacters
                    || wouldRun > rule.maxLengthMS || endsASentence(last.text) {
                    close()
                }
            }
            line.append(word)
        }
        close()
        return fitted(cues, rule: rule)
    }

    /// Whether this word finishes a thought, so the next one starts a line.
    private static func endsASentence(_ text: String) -> Bool {
        guard let last = text.last else { return false }
        return ".?!。？！".contains(last)
    }

    /// Every line held long enough to read and never a millisecond into the
    /// next one.
    ///
    /// Two captions on screen at once is worse than one that went early, and it
    /// is what both of the adjustments here would otherwise cause. The lingering
    /// after the last word is the commoner offender: in continuous speech the
    /// next line starts the instant this one's last word ends, so a line that
    /// hangs on for another three hundred milliseconds hangs over the line
    /// after it. Found by the walk on 2026-09-21, on real speech, at 2160ms.
    private static func fitted(_ cues: [CaptionCue], rule: CaptionCueRule) -> [CaptionCue] {
        var out = cues
        for index in out.indices {
            let wanted = max(out[index].outMS, out[index].inMS + rule.minLengthMS)
            guard index + 1 < out.count else {
                out[index] = CaptionCue(words: out[index].words, inMS: out[index].inMS,
                                        outMS: wanted)
                continue
            }
            // Never past where the next one arrives, and never so short that
            // the model would refuse it.
            let ceiling = max(out[index + 1].inMS, out[index].inMS + LayerTime.shortestMS)
            out[index] = CaptionCue(words: out[index].words, inMS: out[index].inMS,
                                    outMS: min(wanted, ceiling))
        }
        return out
    }
}

// MARK: - From the file's clock to the document's

/// Putting words heard in a FILE where they are heard in the DOCUMENT.
///
/// The recogniser listens to a file and answers in the file's own time. The
/// timeline is not the file: a recording gets trimmed, cut into pieces, sped
/// up, slowed down and rearranged, and a piece thrown away takes the words in
/// it with it. Captioning the file and dropping the words straight onto the
/// timeline puts every word after the first cut in the wrong place, and the
/// error grows for the rest of the film.
///
/// The map from one to the other already exists and is the same one playback
/// and export use: `PhotonzDocument.audioMix()`, which says for every stretch
/// of sound WHERE it lands and WHICH part of the file it reads. So this is the
/// arithmetic and nothing else, and a caption cannot drift from what you hear.
public enum CaptionTiming {

    /// The words of one sound file, placed on the document's timeline.
    ///
    /// A word in a piece somebody cut out does not come back: it is not said in
    /// this film. A word in a piece played at half speed is stretched to the
    /// length it now takes. A word in a held frame is dropped, because a held
    /// frame plays no sound at all.
    public static func onTheTimeline(_ words: [TranscribedWord], of sound: SoundRef,
                                     in mix: [AudioMixSegment]) -> [TranscribedWord] {
        let stretches = mix.filter { $0.sound.id == sound.id && $0.speedPercent > 0 }
        guard !stretches.isEmpty else { return [] }
        var placed: [TranscribedWord] = []
        for word in words {
            for stretch in stretches {
                guard word.startMS < stretch.sourceOutMS, word.endMS > stretch.sourceInMS else {
                    continue
                }
                let start = at(word.startMS, in: stretch)
                let end = max(start + 1, at(word.endMS, in: stretch))
                placed.append(TranscribedWord(word.text, startMS: start, endMS: end,
                                              confidence: word.confidence))
                break
            }
        }
        return placed.sorted { $0.startMS < $1.startMS }
    }

    /// Where a moment of the file lands on the timeline, inside this stretch.
    private static func at(_ sourceMS: Int, in stretch: AudioMixSegment) -> Int {
        let into = min(max(0, sourceMS - stretch.sourceInMS), stretch.sourceLengthMS)
        let played = into * 100 / max(1, stretch.speedPercent)
        return stretch.startMS + min(played, stretch.lengthMS)
    }
}

// MARK: - Cues as layers

extension Layer {

    /// The words the machine heard in this caption, and when it heard each one.
    ///
    /// Nil for everything that is not a caption, which is every layer in every
    /// document written before captions existed. Set, and this layer IS a
    /// caption: it is still an ordinary text layer with an in and an out, and
    /// this is simply the record of where its words came from.
    public var captionWords: [TranscribedWord]? {
        get { captionWordsStorage }
        set { captionWordsStorage = (newValue?.isEmpty ?? true) ? nil : newValue }
    }

    /// Whether this layer is a caption the machine wrote.
    public var isCaption: Bool { captionWordsStorage != nil }
}

/// Turning cues into the layers that carry them.
public enum CaptionLayers {

    /// What the group holding a recording's captions is called.
    public static let groupName = "Captions"

    /// The share of the picture's height the words sit above, the
    /// broadcast title-safe inset the clickthrough asks for. Words below this
    /// are the first thing a crop, a rounded corner or a player's own chrome
    /// eats.
    public static let titleSafeInset: CGFloat = 0.10

    /// The band a caption's box occupies: the full width inside the title-safe
    /// inset, sitting on the title-safe floor.
    ///
    /// Top-left origin, like everything else in the document model.
    public static func band(in size: CGSize, lines: Int = 2, fontSize: CGFloat) -> CGRect {
        let inset = size.width * titleSafeInset
        let lineHeight = fontSize * 1.3
        let height = lineHeight * CGFloat(max(1, lines))
        let floor = size.height * (1 - titleSafeInset)
        return CGRect(x: inset, y: floor - height,
                      width: max(1, size.width - inset * 2), height: max(1, height))
    }

    /// How big the words are on a picture this size.
    ///
    /// A share of the height rather than a number of points, because a caption
    /// on a phone-sized recording and a caption on a 4K one should read the
    /// same size to the eye. Four and a half per cent is about what a
    /// broadcaster uses.
    public static func fontSize(in size: CGSize) -> CGFloat {
        max(12, (size.height * 0.045).rounded())
    }

    /// The look a caption comes out in: the app's own text, centred, with the
    /// same auto-contrast shadow every text layer gets so it stays readable
    /// over a picture nobody chose.
    public static func content(_ text: String, in size: CGSize) -> TextContent {
        var content = TextContent(string: text, fontSize: fontSize(in: size),
                                  colorHex: "#FFFFFF", weight: .semibold,
                                  alignment: .center, verticalAlignment: .bottom)
        content.staysOnOneLine = false
        return content
    }

    /// One layer per cue, each a text layer with an in and an out and nothing
    /// else special about it.
    public static func layers(for cues: [CaptionCue], in size: CGSize) -> [Layer] {
        let font = fontSize(in: size)
        return cues.map { cue in
            var layer = Layer(name: name(for: cue),
                              content: .text(content(cue.text, in: size)),
                              frame: band(in: size, fontSize: font))
            layer.style.shadow = TextBuilder.autoContrastShadow(forColorHex: "#FFFFFF")
            layer.time = LayerTime(inMS: cue.inMS, outMS: cue.outMS)
            layer.captionWords = cue.words
            return layer
        }
    }

    /// What a caption is called in the layers list: the words themselves, cut
    /// short. A list of forty rows called "Caption 12" is a list nobody can
    /// find anything in.
    public static func name(for cue: CaptionCue) -> String {
        let text = cue.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count > 32 else { return text.isEmpty ? "Caption" : text }
        return String(text.prefix(31)) + "…"
    }
}

// MARK: - Captions in a document

extension PhotonzDocument {

    /// Every caption in this document, top-level or inside the group they
    /// landed in, oldest moment first.
    public var captionLayers: [Layer] {
        var found: [Layer] = []
        forEachLayer { if $0.isCaption { found.append($0) } }
        return found.sorted { ($0.time?.inMS ?? 0) < ($1.time?.inMS ?? 0) }
    }

    public var hasCaptions: Bool { layers.contains { $0.containsSelfOrDescendant(where: \.isCaption) } }

    /// How long captions are on screen, in seconds, added up across every
    /// cue: what the Export sheet counts when it says what a film with its
    /// captions burned in will weigh (`RecordingExport.Source.captionedSeconds`).
    public var captionedSeconds: TimeInterval {
        captionLayers.reduce(0) { total, layer in
            guard let time = layer.time else { return total }
            return total + Double(max(0, time.outMS - time.inMS)) / 1000
        }
    }

    /// The cues this document's captions are, read back off the layers.
    ///
    /// The layer's own in and out win over the words', because a person
    /// dragging a bar end is saying something the recogniser was not asked.
    public var captionCues: [CaptionCue] {
        captionLayers.compactMap(captionCue(of:))
    }

    /// The cue one caption layer is, read back off it: its own in and out, and
    /// the words it says now with the timings they were heard at.
    public func captionCue(of layer: Layer) -> CaptionCue? {
        guard let time = layer.time, let words = layer.captionWords else { return nil }
        var cue = CaptionCue(words: words, inMS: time.inMS, outMS: time.outMS)
        if case .text(let content) = layer.content {
            cue = CaptionCue(words: wordsSaying(content.string, heard: words),
                             inMS: time.inMS, outMS: time.outMS)
        }
        return cue
    }

    /// The words a corrected line is made of, keeping the timings the machine
    /// found wherever it can.
    ///
    /// The commonest correction by far is fixing one word in a line — a name,
    /// a piece of jargon — and that must not cost the line its timings. So the
    /// corrected words are matched against the heard ones one for one where
    /// the count still agrees, and where it does not, the line's own span is
    /// spread across them. Either way something sensible comes out and nothing
    /// throws an error at somebody who was only typing.
    private func wordsSaying(_ string: String, heard: [TranscribedWord]) -> [TranscribedWord] {
        let pieces = string.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !pieces.isEmpty else { return heard }
        if pieces.count == heard.count {
            // Nobody retyped it: the words are the ones heard, and there is no
            // matching to do. The common case, asked for every cue each time
            // the document changes.
            if zip(pieces, heard).allSatisfy({ $0 == $1.text }) {
                return heard.map {
                    TranscribedWord($0.text, startMS: $0.startMS, endMS: $0.endMS, confidence: $0.confidence)
                }
            }
            return zip(pieces, heard).map {
                TranscribedWord($0, startMS: $1.startMS, endMS: $1.endMS,
                                confidence: Captions.spine(of: $0) == $1.spine ? $1.confidence : nil)
            }
        }
        let start = heard.first?.startMS ?? 0
        let end = heard.last?.endMS ?? start
        let step = max(1, (end - start) / pieces.count)
        return pieces.enumerated().map { index, word in
            TranscribedWord(word, startMS: start + index * step,
                            endMS: min(end, start + (index + 1) * step))
        }
    }

    /// Move every caption in the document earlier or later together.
    ///
    /// The one correction that fixes a whole track at once, and the commonest
    /// one worth making: a recogniser that hears a fraction of a second late
    /// is late by the same amount everywhere, so nudging the track is a
    /// judgment made once rather than four hundred times. Nothing is allowed
    /// off the front of the recording, and a shift that would push the first
    /// caption before nought is held there.
    public mutating func shiftCaptions(byMS ms: Int) {
        guard ms != 0 else { return }
        let earliest = captionLayers.compactMap { $0.time?.inMS }.min() ?? 0
        let move = max(ms, -earliest)
        guard move != 0 else { return }
        for id in captionLayers.map(\.id) {
            updateLayer(id: id) { layer in
                guard let time = layer.time else { return }
                layer.time = LayerTime(inMS: time.inMS + move, outMS: time.outMS + move)
                layer.captionWords = layer.captionWords?.map { $0.shifted(byMS: move) }
            }
        }
    }

    /// Take every caption out, leaving everything else exactly as it was.
    public mutating func clearCaptions() {
        removeLayers(ids: Set(captionLayers.map(\.id)))
        // ...and the group they were put in, now that it is empty.
        let empty = allLayers.filter {
            $0.name == CaptionLayers.groupName && $0.group?.children.isEmpty == true
        }
        removeLayers(ids: Set(empty.map(\.id)))
    }
}

// MARK: - The way out that is not a picture

/// Captions as a subtitle file.
///
/// Burning the words into the picture is the default and it is free, because a
/// caption is an ordinary text layer and the exporter already draws those. This
/// is the other way out: a `.srt` beside the film, which every player, every
/// video site and every editor in the world reads, and which leaves the words
/// switchable-off and searchable rather than baked into the pixels.
public enum CaptionsSRT {

    public static let fileExtension = "srt"

    public static func text(_ cues: [CaptionCue]) -> String {
        cues.enumerated().map { index, cue in
            "\(index + 1)\n\(stamp(cue.inMS)) --> \(stamp(cue.outMS))\n\(cue.text)\n"
        }.joined(separator: "\n")
    }

    /// `00:01:23,456`, which is the only timestamp SubRip accepts.
    public static func stamp(_ ms: Int) -> String {
        let ms = max(0, ms)
        return String(format: "%02d:%02d:%02d,%03d",
                      ms / 3_600_000, (ms / 60_000) % 60, (ms / 1_000) % 60, ms % 1_000)
    }
}

// MARK: - What it says while it works

/// The words a transcription says about itself.
public enum CaptionProgress {

    /// `Listening · 4:10 of 41:20 · 612 words so far`.
    ///
    /// Two numbers and a count, because the question somebody staring at a
    /// progress bar actually has is "is it getting anywhere", and a count of
    /// words going up answers it in a way a percentage does not.
    public static func reading(doneMS: Int, ofMS: Int, words: Int) -> String {
        "Listening · \(clock(doneMS)) of \(clock(ofMS)) · \(count(words)) so far"
    }

    /// What it says when it has finished.
    public static func heard(words: Int, cues: Int, ofMS: Int) -> String {
        guard words > 0 else { return Captions.heardNothing }
        return "\(count(words)) in \(cues) caption\(cues == 1 ? "" : "s"), from \(clock(ofMS)) of sound"
    }

    /// ...and when somebody stopped it part way, which keeps what it had.
    public static func stopped(doneMS: Int, ofMS: Int, words: Int) -> String {
        guard words > 0 else { return "Stopped before anything was heard." }
        return "Stopped at \(clock(doneMS)) of \(clock(ofMS)). \(count(words)) kept."
    }

    public static func count(_ words: Int) -> String {
        "\(words) word\(words == 1 ? "" : "s")"
    }

    /// `41:20`, or `1:02:30` where it runs past an hour.
    public static func clock(_ ms: Int) -> String {
        let seconds = max(0, ms) / 1_000
        let h = seconds / 3600, m = (seconds / 60) % 60, s = seconds % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    /// How far through, nought to one, for a bar to draw.
    public static func share(doneMS: Int, ofMS: Int) -> Double {
        guard ofMS > 0 else { return 0 }
        return min(1, max(0, Double(doneMS) / Double(ofMS)))
    }
}
