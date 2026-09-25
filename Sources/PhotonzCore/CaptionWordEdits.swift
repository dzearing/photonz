import CoreGraphics
import Foundation

// Fixing a caption one word at a time (`docs/design/mocks/pages/video-captions.html`,
// the Words lane).
//
// Every automatic caption is wrong somewhere, and it is almost always one word:
// a name, a piece of jargon, "alot". So the unit of correction is the word, not
// the line. A word can be retyped where it is, split in two, merged with the
// next, deleted or carried onto the next line, and on the Words lane it can be
// dragged earlier or later or stretched, the way Premiere and Descript let a
// word's timing be set by hand.
//
// Two promises hold for all of it:
//
// - **The rest of the line is left exactly as it was.** A word is swapped in
//   the caption's own string, character for character, so a line somebody
//   broke by hand stays broken there, and nothing about the caption's look or
//   box changes. Its words are written back matching its string one for one,
//   so the word being said is lit at its own time.
// - **Words never overlap.** Words carried earlier squeeze the word before
//   them down to a sliver rather than stopping at it, because spoken words sit
//   end to end; a word moved alone or stretched stops at its neighbours. A
//   line's words stop at the first word of the next line and the last of the
//   one before, and where two lines meet the boundary between them rolls to
//   let the words through.
//
// Everything here works on the words as they sit under the caption's bar NOW
// (`captionWordsAsShown`), which is what the Words lane draws: a bar somebody
// moved by hand carries its words with it.

/// One word of one caption.
public struct CaptionWordRef: Hashable, Sendable {
    public var cueID: UUID
    public var index: Int

    public init(cueID: UUID, index: Int) {
        self.cueID = cueID
        self.index = index
    }
}

/// What a hand has hold of on a word chip.
public enum CaptionWordGrab: Hashable, Sendable {
    /// The word, and every word after it in its line: the fix for a line that
    /// is right up to one word and late from there on. A plain drag.
    case carryRest
    /// The same, and every later line on the track too, Premiere's ripple.
    /// Shift-drag.
    case carryTrack
    /// The word alone, between its neighbours. Command-drag.
    case alone
    /// The word's leading or trailing edge, which resizes only that word.
    case start, end
}

public enum CaptionWordEdits {
    /// The shortest a word can be stretched down to: shorter than any word
    /// anybody says, long enough to still be a chip you can take hold of.
    public static let shortestWordMS = 40

    /// Each run of non-space characters in a caption, in UTF-16 units: the
    /// words as the string has them.
    static func tokens(in string: String) -> [NSRange] {
        CaptionActiveWord.tokenSpans(in: string).map { NSRange(location: $0.location, length: $0.length) }
    }

    /// `string` with tokens `first...last` swapped for `pieces`, joined by a
    /// space, and everything outside them untouched. No pieces deletes the
    /// tokens and one run of the space beside them.
    static func replacing(tokens first: Int, through last: Int, in string: String,
                          with pieces: [String]) -> String? {
        let spans = tokens(in: string)
        guard first >= 0, last < spans.count, first <= last else { return nil }
        let text = string as NSString
        var range = NSRange(location: spans[first].location,
                            length: spans[last].location + spans[last].length - spans[first].location)
        guard pieces.isEmpty else {
            return text.replacingCharacters(in: range, with: pieces.joined(separator: " "))
        }
        // Take the space after the word with it, or before it for the last
        // word, so no double space and no trailing one is left behind.
        if last + 1 < spans.count {
            range.length = spans[last + 1].location - range.location
        } else if first > 0 {
            let start = spans[first - 1].location + spans[first - 1].length
            range = NSRange(location: start, length: range.location + range.length - start)
        }
        return text.replacingCharacters(in: range, with: "")
    }
}

/// Which word of a caption a point on the picture is on.
public enum CaptionWordHit {
    /// The word whose box holds `point`, or failing that the nearest one on
    /// the same line within `slack`, so a click in the space between two
    /// words still lands on one of them. Nil off every word.
    public static func index(at point: CGPoint, in rects: [CGRect?], slack: CGFloat) -> Int? {
        if let inside = rects.firstIndex(where: { $0?.contains(point) ?? false }) { return inside }
        var best: (index: Int, distance: CGFloat)?
        for (index, rect) in rects.enumerated() {
            guard let rect, point.y >= rect.minY, point.y <= rect.maxY else { continue }
            let distance = point.x < rect.minX ? rect.minX - point.x : point.x - rect.maxX
            guard distance <= slack, distance < best?.distance ?? .infinity else { continue }
            best = (index, distance)
        }
        return best?.index
    }
}

/// Snapping a dragged word onto something worth landing on: the playhead, and
/// the edges of the words around it.
public enum CaptionWordSnap {
    /// `deltaMS`, pulled so the moving edge nearest a target lands on it, when
    /// one is within `withinMS`. Otherwise the delta as the hand has it.
    public static func snapped(deltaMS: Int, edges: [Int], targets: [Int], withinMS: Int) -> Int {
        var best: (distance: Int, delta: Int)?
        for edge in edges {
            for target in targets {
                let pull = target - (edge + deltaMS)
                guard abs(pull) <= withinMS else { continue }
                if best == nil || abs(pull) < best?.distance ?? .max {
                    best = (abs(pull), deltaMS + pull)
                }
            }
        }
        return best?.delta ?? deltaMS
    }
}

extension PhotonzDocument {

    // MARK: - The words as they sit now

    /// A caption's words as they sit under its bar now, one per word of its
    /// string: what the Words lane draws, and what every edit here starts from.
    public func captionWordsAsShown(of id: UUID) -> [TranscribedWord]? {
        guard let layer = layer(id: id), let time = layer.time, let cue = captionCue(of: layer) else {
            return nil
        }
        return CaptionCue.words(cue.words, fittedTo: time)
    }

    /// The word `step` words on from `ref`, running on into the next line and
    /// back into the one before: what Tab and Shift-Tab walk while typing.
    public func captionWord(from ref: CaptionWordRef, step: Int) -> CaptionWordRef? {
        let cues = captionLayers
        guard let at = cues.firstIndex(where: { $0.id == ref.cueID }) else { return nil }
        var cue = at
        var index = ref.index + step
        while true {
            guard cues.indices.contains(cue) else { return nil }
            let count = captionWordsAsShown(of: cues[cue].id)?.count ?? 0
            if index < 0 {
                cue -= 1
                guard cues.indices.contains(cue) else { return nil }
                index += captionWordsAsShown(of: cues[cue].id)?.count ?? 0
            } else if index >= count {
                index -= count
                cue += 1
            } else {
                return CaptionWordRef(cueID: cues[cue].id, index: index)
            }
        }
    }

    // MARK: - Retyping one word

    /// Retype one word where it is. It keeps its time; typed as two words it
    /// splits that time evenly between them, and typed as nothing it goes.
    @discardableResult
    public mutating func setCaptionWord(_ ref: CaptionWordRef, to typed: String) -> Bool {
        let pieces = typed.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !pieces.isEmpty else { return deleteCaptionWord(ref) }
        guard let (words, string) = captionWordParts(ref), pieces != [words[ref.index].text] else {
            return false
        }
        let old = words[ref.index]
        let heard = old.heardAs ?? old.text
        let replaced = Self.spread(pieces, over: old.startMS...old.endMS).map {
            TranscribedWord($0.text, startMS: $0.startMS, endMS: $0.endMS, confidence: nil,
                            heardAs: $0.text == heard ? nil : heard)
        }
        var next = words
        next.replaceSubrange(ref.index...ref.index, with: replaced)
        guard let rewritten = CaptionWordEdits.replacing(tokens: ref.index, through: ref.index,
                                                         in: string, with: pieces) else { return false }
        return writeCaption(ref.cueID, words: next, string: rewritten)
    }

    /// **Split Here.** One word becomes two, cut at `atMS` (or its middle),
    /// with its letters cut in the same proportion.
    @discardableResult
    public mutating func splitCaptionWord(_ ref: CaptionWordRef, atMS: Int?) -> Bool {
        guard let (words, string) = captionWordParts(ref) else { return false }
        let old = words[ref.index]
        let letters = Array(old.text)
        guard letters.count >= 2, old.lengthMS >= 2 else { return false }
        let cut = min(max(old.startMS + 1, atMS ?? (old.startMS + old.endMS) / 2), old.endMS - 1)
        let share = Double(cut - old.startMS) / Double(old.lengthMS)
        let at = min(max(1, Int((share * Double(letters.count)).rounded())), letters.count - 1)
        let halves = [String(letters[..<at]), String(letters[at...])]
        let heard = old.heardAs ?? old.text
        let replaced = [
            TranscribedWord(halves[0], startMS: old.startMS, endMS: cut, heardAs: heard),
            TranscribedWord(halves[1], startMS: cut, endMS: old.endMS, heardAs: heard),
        ]
        var next = words
        next.replaceSubrange(ref.index...ref.index, with: replaced)
        guard let rewritten = CaptionWordEdits.replacing(tokens: ref.index, through: ref.index,
                                                         in: string, with: halves) else { return false }
        return writeCaption(ref.cueID, words: next, string: rewritten)
    }

    /// **Merge with Next.** This word and the one after it become one word,
    /// their letters run together, over the time both had.
    @discardableResult
    public mutating func mergeCaptionWordWithNext(_ ref: CaptionWordRef) -> Bool {
        guard let (words, string) = captionWordParts(ref), ref.index + 1 < words.count else { return false }
        let a = words[ref.index], b = words[ref.index + 1]
        let text = a.text + b.text
        let heardA = a.heardAs ?? a.text, heardB = b.heardAs ?? b.text
        // Two halves of one split word were one heard word.
        let heard = heardA == heardB && a.heardAs != nil ? heardA : heardA + " " + heardB
        let merged = TranscribedWord(text, startMS: a.startMS, endMS: max(a.endMS, b.endMS),
                                     heardAs: Captions.spine(of: text) == Captions.spine(of: heard) ? nil : heard)
        var next = words
        next.replaceSubrange(ref.index...(ref.index + 1), with: [merged])
        guard let rewritten = CaptionWordEdits.replacing(tokens: ref.index, through: ref.index + 1,
                                                         in: string, with: [text]) else { return false }
        return writeCaption(ref.cueID, words: next, string: rewritten)
    }

    /// **Delete Word.** The word goes and the rest of the line keeps its
    /// timing. The only word of a line takes the line with it.
    @discardableResult
    public mutating func deleteCaptionWord(_ ref: CaptionWordRef) -> Bool {
        guard let (words, string) = captionWordParts(ref) else { return false }
        guard words.count > 1 else { return removeLayer(id: ref.cueID) != nil }
        var next = words
        next.remove(at: ref.index)
        guard let rewritten = CaptionWordEdits.replacing(tokens: ref.index, through: ref.index,
                                                         in: string, with: []) else { return false }
        return writeCaption(ref.cueID, words: next, string: rewritten)
    }

    /// **Move to Next Line.** This word and every word after it in its line go
    /// to the front of the next line, which starts where they do. On the last
    /// line they become a new line of their own. Moving the first word moves
    /// the whole line, which then goes.
    @discardableResult
    public mutating func moveCaptionWordsToNextCue(from ref: CaptionWordRef) -> Bool {
        guard let (words, string) = captionWordParts(ref), let layer = layer(id: ref.cueID),
              let time = layer.time else { return false }
        let moved = Array(words[ref.index...])
        let movedText = CaptionWordEdits.tokens(in: string)[ref.index...]
            .map { (string as NSString).substring(with: $0) }
        guard let first = moved.first, let last = moved.last else { return false }
        let cues = captionLayers
        let following = cues.firstIndex { $0.id == ref.cueID }.flatMap { at in
            cues.indices.contains(at + 1) ? cues[at + 1] : nil
        }
        if let following, let nextWords = captionWordsAsShown(of: following.id),
           case .text(let nextContent) = following.content, let nextTime = following.time {
            let joined = movedText.joined(separator: " ") + " " + nextContent.string
            writeCaption(following.id, words: moved + nextWords, string: joined,
                         time: LayerTime(inMS: min(nextTime.inMS, first.startMS), outMS: nextTime.outMS))
        } else {
            var line = layer.reidentified()
            let text = movedText.joined(separator: " ")
            if case .text(var content) = line.content {
                content.string = text
                line.content = .text(content)
            }
            line.name = CaptionLayers.name(for: text)
            line.captionWords = moved
            line.time = LayerTime(inMS: first.startMS, outMS: max(time.outMS, last.endMS))
            if let parent = parentID(of: ref.cueID) {
                addLayer(line, toGroup: parent)
            } else {
                addLayer(line)
            }
        }
        guard ref.index > 0 else {
            removeLayer(id: ref.cueID)
            return true
        }
        let kept = Array(words[..<ref.index])
        guard let rewritten = CaptionWordEdits.replacing(tokens: ref.index,
                                                         through: words.count - 1, in: string, with: [])
        else { return false }
        writeCaption(ref.cueID, words: kept, string: rewritten,
                     time: LayerTime(inMS: time.inMS, outMS: max(time.inMS + LayerTime.shortestMS,
                                                                 min(time.outMS, first.startMS))))
        return true
    }

    // MARK: - Dragging a word

    /// How far this word may be dragged with this grab, earlier (negative) to
    /// later, so that no word ever overlaps another.
    public func captionWordDragRange(_ ref: CaptionWordRef, grab: CaptionWordGrab) -> ClosedRange<Int>? {
        guard let context = captionWordDragContext(ref) else { return nil }
        let words = context.words
        let word = words[ref.index]
        let before = ref.index > 0 ? words[ref.index - 1].endMS : context.previousWordEnd
        let after = ref.index + 1 < words.count ? words[ref.index + 1].startMS : context.nextWordStart
        let lastEnd = words.last?.endMS ?? word.endMS
        // Carried earlier, the words squeeze the word before them rather
        // than stopping at it: spoken words sit end to end, so stopping would
        // mean a word could never be carried earlier at all. The word before
        // keeps a sliver, and a line's first word stops at the line before.
        let squeeze = ref.index > 0 ? words[ref.index - 1].startMS + CaptionWordEdits.shortestWordMS : before
        var low: Int, high: Int
        switch grab {
        case .carryRest:
            low = min(before, squeeze) - word.startMS
            high = context.nextWordStart - lastEnd
        case .carryTrack:
            low = min(before, squeeze) - word.startMS
            high = context.trackEnd - context.laterEnd
        case .alone:
            low = before - word.startMS
            high = after - word.endMS
        case .start:
            low = before - word.startMS
            high = word.endMS - CaptionWordEdits.shortestWordMS - word.startMS
        case .end:
            low = word.startMS + CaptionWordEdits.shortestWordMS - word.endMS
            high = after - word.endMS
        }
        // Words that already overlap (a line typed over by hand) are never
        // yanked apart by a drag that has not moved yet.
        low = min(0, low)
        high = max(0, high)
        return low...high
    }

    /// Drag one word by `byMS`, as far as it may go. Returns how far it went;
    /// nought changes nothing.
    @discardableResult
    public mutating func dragCaptionWord(_ ref: CaptionWordRef, grab: CaptionWordGrab, byMS: Int) -> Int {
        guard let range = captionWordDragRange(ref, grab: grab),
              let context = captionWordDragContext(ref),
              let time = layer(id: ref.cueID)?.time else { return 0 }
        let delta = min(max(byMS, range.lowerBound), range.upperBound)
        guard delta != 0 else { return 0 }
        var words = context.words
        let i = ref.index
        var inMS = time.inMS, outMS = time.outMS
        switch grab {
        case .carryRest, .carryTrack:
            for index in i..<words.count { words[index] = words[index].shifted(byMS: delta) }
            if i > 0, words[i - 1].endMS > words[i].startMS {
                words[i - 1] = words[i - 1].retimed(startMS: words[i - 1].startMS, endMS: words[i].startMS)
            }
            let lastEnd = words.last?.endMS ?? outMS
            // The line's tail moves with its last word, and its head with its
            // first, but never onto the next line's words or the last one's.
            let ceiling = grab == .carryTrack ? Int.max : context.nextWordStart
            outMS = max(lastEnd, min(outMS + delta, ceiling))
            if i == 0 { inMS = min(words[0].startMS, max(inMS + delta, context.previousWordEnd)) }
        case .alone:
            words[i] = words[i].shifted(byMS: delta)
        case .start:
            words[i] = words[i].retimed(startMS: words[i].startMS + delta, endMS: words[i].endMS)
        case .end:
            words[i] = words[i].retimed(startMS: words[i].startMS, endMS: words[i].endMS + delta)
        }
        inMS = min(inMS, words.first?.startMS ?? inMS)
        outMS = max(outMS, words.last?.endMS ?? outMS)
        writeCaption(ref.cueID, words: words, string: context.string,
                     time: LayerTime(inMS: inMS, outMS: outMS))
        // Later lines ride along on a ripple.
        if grab == .carryTrack {
            for later in context.laterCueIDs {
                updateLayer(id: later) { layer in
                    guard let time = layer.time else { return }
                    let fitted = layer.captionWords.map { CaptionCue.words($0, fittedTo: time) }
                    layer.time = LayerTime(inMS: time.inMS + delta, outMS: time.outMS + delta)
                    layer.captionWords = fitted?.map { $0.shifted(byMS: delta) }
                }
            }
        }
        // Where two lines meet, the boundary rolls rather than the lines
        // overlapping.
        if let previous = context.previousCueID {
            updateLayer(id: previous) { layer in
                guard let time = layer.time, time.outMS > inMS else { return }
                layer.time = LayerTime(inMS: time.inMS, outMS: max(time.inMS + LayerTime.shortestMS, inMS))
            }
        }
        if let following = context.nextCueID, grab != .carryTrack {
            updateLayer(id: following) { layer in
                guard let time = layer.time, time.inMS < outMS else { return }
                layer.time = LayerTime(inMS: min(outMS, time.outMS - LayerTime.shortestMS), outMS: time.outMS)
            }
        }
        return delta
    }

    // MARK: - Underneath

    private struct CaptionWordDragContext {
        var words: [TranscribedWord]
        var string: String
        /// The end of the last word of the line before, or the start of time.
        var previousWordEnd: Int
        /// The start of the first word of the line after, or the end of time.
        var nextWordStart: Int
        var previousCueID: UUID?
        var nextCueID: UUID?
        var laterCueIDs: [UUID]
        /// The latest any line from this one on ends, for a ripple.
        var laterEnd: Int
        /// As late as a ripple may push the last line.
        var trackEnd: Int
    }

    private func captionWordDragContext(_ ref: CaptionWordRef) -> CaptionWordDragContext? {
        guard let (words, string) = captionWordParts(ref) else { return nil }
        let cues = captionLayers
        guard let at = cues.firstIndex(where: { $0.id == ref.cueID }) else { return nil }
        let previous = at > 0 ? cues[at - 1] : nil
        let next = at + 1 < cues.count ? cues[at + 1] : nil
        let previousEnd = previous.flatMap { cue in
            captionWordsAsShown(of: cue.id)?.last?.endMS
                ?? cue.time.map { $0.inMS + LayerTime.shortestMS }
        } ?? 0
        let nextStart = next.flatMap { cue in
            captionWordsAsShown(of: cue.id)?.first?.startMS
                ?? cue.time.map { $0.outMS - LayerTime.shortestMS }
        } ?? (hasTime ? documentDurationMS : Int.max / 4)
        let later = Array(cues[(at + 1)...])
        let laterEnd = ([words.last?.endMS ?? 0, cues[at].time?.outMS ?? 0]
            + later.compactMap { $0.time?.outMS }).max() ?? 0
        return CaptionWordDragContext(words: words, string: string,
                                      previousWordEnd: previousEnd, nextWordStart: nextStart,
                                      previousCueID: previous?.id, nextCueID: next?.id,
                                      laterCueIDs: later.map(\.id), laterEnd: laterEnd,
                                      trackEnd: hasTime ? max(laterEnd, documentDurationMS) : Int.max / 4)
    }

    /// The words of a caption as shown and its string, when `ref` names a word
    /// in it.
    private func captionWordParts(_ ref: CaptionWordRef) -> ([TranscribedWord], String)? {
        guard let layer = layer(id: ref.cueID), layer.isCaption,
              case .text(let content) = layer.content,
              let words = captionWordsAsShown(of: ref.cueID),
              words.indices.contains(ref.index),
              words.count == CaptionWordEdits.tokens(in: content.string).count else { return nil }
        return (words, content.string)
    }

    /// Write a caption's words and string back, its name following its words
    /// and its bar grown, where it has to, to hold them.
    @discardableResult
    private mutating func writeCaption(_ id: UUID, words: [TranscribedWord], string: String,
                                       time: LayerTime? = nil) -> Bool {
        guard !words.isEmpty else { return false }
        updateLayer(id: id) { layer in
            guard case .text(var content) = layer.content, let was = time ?? layer.time else { return }
            content.string = string
            layer.content = .text(content)
            layer.name = CaptionLayers.name(for: string)
            layer.captionWords = words
            layer.time = LayerTime(inMS: min(was.inMS, words[0].startMS),
                                   outMS: max(was.outMS, words[words.count - 1].endMS),
                                   sourceInMS: layer.time?.sourceInMS ?? 0,
                                   sourceLengthMS: layer.time?.sourceLengthMS)
        }
        return true
    }

    /// `pieces` sharing a stretch evenly, the last one taking the remainder.
    static func spread(_ pieces: [String], over span: ClosedRange<Int>) -> [TranscribedWord] {
        let length = span.upperBound - span.lowerBound
        return pieces.enumerated().map { index, text in
            let start = span.lowerBound + length * index / pieces.count
            let end = index == pieces.count - 1 ? span.upperBound
                : span.lowerBound + length * (index + 1) / pieces.count
            return TranscribedWord(text, startMS: start, endMS: end)
        }
    }
}

// MARK: - A fix survives the captions being written again

/// The words somebody fixed by hand, remembered across Write Again.
///
/// Writing captions again replaces every line. Without this, every name and
/// every "a lot" a person had fixed would come back misheard. So before the old
/// lines go, each fixed word is noted with what the machine heard there and
/// when; any newly heard word at the same moment that the machine heard the
/// same way gets the same fix.
public struct CaptionWordFixes: Sendable {
    struct Fix: Sendable {
        var heard: String
        var fixed: [String]
        var startMS: Int
        var endMS: Int
    }

    var fixes: [Fix]

    /// Every hand fix in `document`'s captions. The halves of one split word
    /// are one fix.
    public init(_ document: PhotonzDocument) {
        var found: [Fix] = []
        for layer in document.captionLayers {
            guard let words = document.captionWordsAsShown(of: layer.id) else { continue }
            for word in words {
                guard let heard = word.heardAs else { continue }
                if var last = found.last, last.heard == heard, last.endMS == word.startMS {
                    last.fixed.append(word.text)
                    last.endMS = word.endMS
                    found[found.count - 1] = last
                } else {
                    found.append(Fix(heard: heard, fixed: [word.text], startMS: word.startMS,
                                     endMS: word.endMS))
                }
            }
        }
        fixes = found
    }

    public var isEmpty: Bool { fixes.isEmpty }

    /// How far off a word heard again may land and still be the same word.
    static let slackMS = 250

    /// `cues` with every word heard the way a fixed word was, at its moment,
    /// fixed the same way.
    public func applied(to cues: [CaptionCue]) -> [CaptionCue] {
        guard !fixes.isEmpty else { return cues }
        return cues.map { cue in
            var cue = cue
            cue.words = cue.words.flatMap { word -> [TranscribedWord] in
                let middle = (word.startMS + word.endMS) / 2
                guard let fix = fixes.first(where: {
                    Captions.spine(of: $0.heard) == word.spine
                        && middle >= $0.startMS - Self.slackMS && middle <= $0.endMS + Self.slackMS
                }) else { return [word] }
                return PhotonzDocument.spread(fix.fixed, over: word.startMS...word.endMS).map {
                    TranscribedWord($0.text, startMS: $0.startMS, endMS: $0.endMS, heardAs: word.text)
                }
            }
            return cue
        }
    }
}
