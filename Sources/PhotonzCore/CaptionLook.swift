import CoreGraphics
import Foundation

// Captions as a track, a look and a lit word
// (`docs/design/mocks/pages/video-captions.html`).
//
// The mock asks three things of captions beyond being written:
//
// - **One layer, one track.** Captions are ONE layer of kind Captions
//   (`Layer.isCaptionsLayer`): a row in the layers list, a box on the picture
//   you move, size and rotate like a rectangle, and one Captions row on the
//   timeline with every cue side by side, the way Premiere's captions track
//   holds them. Inside, the transcript is one text layer per cue with an in and
//   an out, and every cue fills the layer's box, so the box IS where the words
//   sit and its width is their wrap width. There is no Bottom/Middle/Top: the
//   user asked on 2026-09-25 for captions positioned "just like any other
//   layer".
// - **One look per layer.** Caption, Lower third or Karaoke, plus the font,
//   size, colour and background, set once for every caption in the layer
//   (`CaptionLook`, `applyCaptionLook`). It lives on the Captions layer, so a
//   second Captions layer (another language, another speaker) wears its own;
//   the document keeps the last one chosen for the next lot written from
//   scratch.
// - **A lit word.** The word being said lights up as the playhead passes it.
//   Nothing about that is stored: the frame drawn at a moment carries it
//   (`CaptionActiveWord`, applied in `DocumentTime.shownTree`), exactly the way
//   a clip carries the frame of its recording that the moment lands on.

// MARK: - The look

/// How every caption in a Captions layer looks. Where the words sit is not
/// part of it: that is the layer's own box, moved and sized like any other.
public struct CaptionLook: Hashable, Codable, Sendable {

    /// The mock's three named styles.
    public enum Preset: String, Hashable, Codable, Sendable, CaseIterable {
        case caption, lowerThird, karaoke

        public var title: String {
            switch self {
            case .caption: "Caption"
            case .lowerThird: "Lower third"
            case .karaoke: "Karaoke"
            }
        }
    }

    public var preset: Preset
    public var fontName: String
    public var weight: TextWeight
    /// Nil is the size that reads the same on any picture: a share of its
    /// height (`CaptionLayers.fontSize(in:)`).
    public var fontSize: CGFloat?
    public var colorHex: String
    /// The plate behind the words, or nil for words straight on the picture
    /// wearing the readable shadow.
    public var backgroundHex: String?
    /// The colour the word being said lights up in, or nil for none.
    public var activeHex: String?
    public var alignment: TextAlign

    public init(preset: Preset, fontName: String = "SF Pro", weight: TextWeight = .semibold,
                fontSize: CGFloat? = nil, colorHex: String = "#FFFFFF",
                backgroundHex: String? = nil, activeHex: String? = nil,
                alignment: TextAlign = .center) {
        self.preset = preset
        self.fontName = fontName
        self.weight = weight
        self.fontSize = fontSize
        self.colorHex = colorHex
        self.backgroundHex = backgroundHex
        self.activeHex = activeHex
        self.alignment = alignment
    }

    /// The yellow the mock lights the spoken word in.
    public static let activeYellow = "#FFD76A"
    /// The mock's plate: black at sixty per cent, which reads over anything.
    public static let plate = "#00000099"

    /// A named style as it comes.
    public static func preset(_ preset: Preset) -> CaptionLook {
        switch preset {
        case .caption:
            CaptionLook(preset: .caption, backgroundHex: plate, activeHex: activeYellow)
        case .lowerThird:
            CaptionLook(preset: .lowerThird, weight: .medium, backgroundHex: "#000000B3",
                        alignment: .left)
        case .karaoke:
            CaptionLook(preset: .karaoke, weight: .bold, activeHex: activeYellow)
        }
    }

    /// The look every caption comes out in until somebody picks another.
    public static let standard = preset(.caption)

    /// Karaoke lights every word said so far, not just the one being said.
    public var lightsEverythingSaid: Bool { preset == .karaoke }

    /// The size the words are drawn at on a picture this size.
    public func resolvedFontSize(in size: CGSize) -> CGFloat {
        let base = fontSize ?? CaptionLayers.fontSize(in: size)
        return preset == .karaoke && fontSize == nil ? (base * 1.2).rounded() : base
    }
}

// MARK: - The word being said

extension CaptionCue {

    /// Words as they sit under a cue's bar now. Words still inside the bar
    /// keep the moments they were heard at; a bar somebody moved or trimmed
    /// off them carries them along, spread across the time it now has, so the
    /// words never fall outside the caption they belong to.
    public static func words(_ words: [TranscribedWord], fittedTo cue: LayerTime) -> [TranscribedWord] {
        guard let first = words.first, let last = words.last else { return words }
        let inside = first.startMS >= cue.inMS - 1 && last.endMS <= cue.outMS + 1
        guard !inside else { return words }
        let heardLength = max(1, last.endMS - first.startMS)
        let span = max(1, cue.outMS - cue.inMS)
        return words.map { word in
            let start = cue.inMS + (word.startMS - first.startMS) * span / heardLength
            let end = cue.inMS + (word.endMS - first.startMS) * span / heardLength
            return word.retimed(startMS: start, endMS: end)
        }
    }
}

/// Which characters of a caption are lit at a moment.
public enum CaptionActiveWord {

    /// A stretch of a string, counted in UTF-16 units the way text layout
    /// counts them.
    public struct Span: Hashable, Sendable {
        public var location: Int
        public var length: Int
        public init(location: Int, length: Int) {
            self.location = location
            self.length = length
        }
    }

    /// The word being said at `ms` (or, `sung`, everything said up to and
    /// including it), or nil before the first word.
    ///
    /// Where the line still has as many words as were heard, each word is lit
    /// at its own time. A line somebody retyped into a different number of
    /// words is lit by share of the time instead, so it still reads as said.
    public static func range(in string: String, words: [TranscribedWord], atMS ms: Int,
                             sung: Bool) -> Span? {
        let tokens = tokenSpans(in: string)
        guard let first = words.first, let last = words.last, !tokens.isEmpty,
              ms >= first.startMS else { return nil }
        let index: Int
        if tokens.count == words.count {
            index = words.lastIndex { $0.startMS <= ms } ?? 0
        } else {
            let length = max(1, last.endMS - first.startMS)
            let share = Double(ms - first.startMS) / Double(length)
            index = min(tokens.count - 1, max(0, Int(share * Double(tokens.count))))
        }
        let token = tokens[index]
        guard sung else { return token }
        return Span(location: tokens[0].location, length: token.location + token.length - tokens[0].location)
    }

    /// The same, for words that belong to a cue whose bar may have been moved
    /// or trimmed since they were heard: words that no longer sit inside the
    /// cue are carried along with it, spread across the time it now has.
    public static func range(in string: String, words: [TranscribedWord], cue: LayerTime,
                             atMS ms: Int, sung: Bool) -> Span? {
        range(in: string, words: CaptionCue.words(words, fittedTo: cue), atMS: ms, sung: sung)
    }

    /// Each run of non-space characters, in UTF-16 units.
    public static func tokenSpans(in string: String) -> [Span] {
        var spans: [Span] = []
        var offset = 0
        var start: Int?
        for character in string {
            let width = character.utf16.count
            if character.isWhitespace {
                if let begun = start { spans.append(Span(location: begun, length: offset - begun)) }
                start = nil
            } else if start == nil {
                start = offset
            }
            offset += width
        }
        if let begun = start { spans.append(Span(location: begun, length: offset - begun)) }
        return spans
    }
}

extension Layer {

    /// This caption as drawn at `ms`: the word being said lit, where its look
    /// lights one. Everything that is not an on-screen caption comes back as
    /// it was.
    func withSpokenWordLit(atTimeMS ms: Int) -> Layer {
        guard isVisible, let words = captionWords, let time,
              case .text(var content) = content, let hex = content.activeWordHex,
              let span = CaptionActiveWord.range(in: content.string, words: words, cue: time,
                                                 atMS: ms, sung: content.activeWordSung == true)
        else { return self }
        content.highlight = TextHighlight(location: span.location, length: span.length, colorHex: hex)
        var lit = self
        lit.content = .text(content)
        return lit
    }

    /// A Captions layer: one layer holding a transcript, one cue each, in its
    /// own look, every cue filling its box.
    public var isCaptionsLayer: Bool { group?.captionLook != nil }

    /// The clip a Captions track holds. The same thing as a Captions layer.
    public var isCaptionGroup: Bool { isCaptionsLayer }

    /// A Captions layer's look, or nil for every other layer. Setting it on a
    /// group makes it a Captions layer.
    public var captionsLook: CaptionLook? {
        get { group?.captionLook }
        set {
            guard case .group(var group) = content else { return }
            group.captionLook = newValue
            content = .group(group)
        }
    }

    /// A Captions layer given a new box: every cue fills it. The type keeps
    /// its size, because a box is a wrap width, not a zoom.
    func reboxingCaptions(to box: CGRect) -> Layer {
        var layer = self
        let box = box.standardized
        layer.frame = box
        layer.children = children.map { cue in
            var cue = cue
            cue.frame = CGRect(origin: .zero, size: box.size)
            return cue
        }
        return layer
    }
}

// MARK: - Landing and restyling

extension PhotonzDocument {

    /// Every Captions layer in the document, top of the stack first.
    public var captionsLayers: [Layer] {
        var found: [Layer] = []
        forEachLayer { if $0.isCaptionsLayer { found.append($0) } }
        return found
    }

    /// The Captions layer holding a cue, or nil for a cue somebody moved out.
    public func captionsLayer(holding cueID: UUID) -> Layer? {
        captionsLayers.first { layer in layer.children.contains { $0.id == cueID } }
    }

    /// The cues on a captions track, earliest first: every caption inside the
    /// Captions layers on it.
    public func captionCueIDs(onTrack id: UUID) -> [UUID] {
        // The captions under this track's clips, in time order, read in place:
        // a Captions layer holds every cue, and copying each out to sort it
        // was most of the cost of drawing a long captioned timeline.
        let clips = Set(clipIDs(onTrack: id))
        var cues: [(id: UUID, inMS: Int)] = []
        func collect(_ layer: Layer) {
            if layer.isCaption { cues.append((layer.id, layer.time?.inMS ?? 0)); return }
            guard case .group(let group) = layer.content else { return }
            for index in group.children.indices { collect(group.children[index]) }
        }
        for index in layers.indices where clips.contains(layers[index].id) { collect(layers[index]) }
        return cues.sorted { $0.inMS < $1.inMS }.map(\.id)
    }

    /// Put these cues on the document as its captions, in `look` (or the look
    /// the Captions layer already wears, or the document's last, or the
    /// standard one).
    ///
    /// Written again, they replace the cues of the first Captions layer where
    /// it is: its box, its look and its place in the stack are what somebody
    /// chose, and a second press means new words, not a new layer. Otherwise
    /// they land as a new Captions layer in the lower third.
    @discardableResult
    public mutating func landCaptions(_ cues: [CaptionCue], look: CaptionLook? = nil) -> UUID? {
        // Words somebody fixed by hand come back fixed where the same words
        // are heard the same way again (`CaptionWordFixes`).
        let fixed = CaptionWordFixes(self).applied(to: cues)
        let existing = captionsLayers.first
        // Any stray caption outside a Captions layer goes; the first Captions
        // layer's cues are replaced below, and every OTHER Captions layer is
        // somebody's own and stays.
        let held = Set(captionsLayers.flatMap { $0.children.map(\.id) })
        removeLayers(ids: Set(captionLayers.map(\.id)).subtracting(held))
        // Nothing is said after the film ends, so no line is on screen after
        // it either: a line lingering past the last frame would make the film
        // longer by the linger.
        let end = hasTime ? documentDurationMS : Int.max
        let cues = fixed.compactMap { cue -> CaptionCue? in
            guard cue.inMS < end - LayerTime.shortestMS else { return cue.outMS <= end ? cue : nil }
            return CaptionCue(words: cue.words, inMS: cue.inMS, outMS: min(cue.outMS, end))
        }
        guard !cues.isEmpty else {
            if let existing { removeLayers(ids: [existing.id]) }
            return nil
        }
        let chosen = look ?? existing?.captionsLook ?? captionLook ?? .standard
        captionLook = chosen
        let box = existing.map(\.frame)
            ?? CaptionLayers.defaultBox(in: canvasSize, fontSize: chosen.resolvedFontSize(in: canvasSize))
        let children = CaptionLayers.layers(for: cues, in: canvasSize, look: chosen, box: box.size)
        if let existing {
            updateLayer(id: existing.id) { layer in
                layer.children = children
                layer.captionsLook = chosen
            }
            return existing.id
        }
        var content = GroupContent(children: children)
        content.captionLook = chosen
        let layer = Layer(name: CaptionLayers.groupName, content: .group(content), frame: box)
        addLayer(layer)
        return layer.id
    }

    /// Dress every Captions layer in `look`, and keep it for the next ones.
    public mutating func applyCaptionLook(_ look: CaptionLook) {
        captionLook = look
        for layer in captionsLayers { applyCaptionLook(look, toCaptions: layer.id) }
    }

    /// Dress one Captions layer in `look`, leaving its box where it is and
    /// every other Captions layer as it was. The document keeps the look for
    /// the next captions written from scratch.
    public mutating func applyCaptionLook(_ look: CaptionLook, toCaptions id: UUID) {
        guard layer(id: id)?.isCaptionsLayer == true else { return }
        captionLook = look
        let size = canvasSize
        updateLayer(id: id) { layer in
            // New type needs room for two lines of itself: the box grows or
            // shrinks up from its floor, where the words sit, and keeps the
            // width somebody gave it.
            let was = layer.captionsLook?.resolvedFontSize(in: size)
            let font = look.resolvedFontSize(in: size)
            if was != font {
                let height = CaptionLayers.band(in: size, lines: 2, fontSize: font).height
                let frame = layer.frame
                layer.frame = CGRect(x: frame.minX, y: frame.maxY - height,
                                     width: frame.width, height: height)
            }
            let box = layer.frame.size
            layer.captionsLook = look
            layer.children = layer.children.map { cue in
                guard cue.isCaption, case .text(let content) = cue.content else { return cue }
                return CaptionLayers.dress(cue, string: content.string, in: size, look: look, box: box)
            }
        }
    }

    /// Retype one caption. Its words keep their timings where they still line
    /// up (`captionCues`), and its name follows its words so the bar on the
    /// timeline says what is on screen. Blank words are not a caption.
    @discardableResult
    public mutating func setCaptionText(id: UUID, to string: String) -> Bool {
        let words = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty, let layer = layer(id: id), layer.isCaption,
              case .text(var content) = layer.content, content.string != words else { return false }
        content.string = words
        updateLayer(id: id) {
            $0.content = .text(content)
            $0.name = CaptionLayers.name(for: words)
        }
        return true
    }

    /// Remember that the app has listened to this sound, so opening the
    /// document again does not listen to it again, even after its captions
    /// were cleared.
    public mutating func noteCaptionsListened(to soundID: UUID) {
        guard !captionsListenedTo.contains(soundID) else { return }
        captionsListenedTo.append(soundID)
    }

    /// A document saved when captions were a plain group of cues sitting in
    /// canvas space, dressed by a document-wide look and placed by a
    /// Bottom/Middle/Top setting, opened as Captions layers: the group gets
    /// the box its cues were in, the cues fill it, and it wears the look.
    /// Nothing moves on the picture and no word or time changes.
    mutating func adoptingCaptionGroups() {
        let look = captionLook ?? .standard
        func adopt(_ list: inout [Layer]) {
            for index in list.indices {
                guard case .group(var group) = list[index].content else { continue }
                if group.captionLook == nil, !group.children.isEmpty,
                   group.children.allSatisfy(\.isCaption) {
                    let origin = list[index].frame.origin
                    let box = group.children.dropFirst().reduce(group.children[0].frame) {
                        $0.union($1.frame)
                    }.offsetBy(dx: origin.x, dy: origin.y)
                    group.captionLook = look
                    list[index].content = .group(group)
                    list[index] = list[index].reboxingCaptions(to: box)
                } else {
                    adopt(&group.children)
                    list[index].content = .group(group)
                }
            }
        }
        adopt(&layers)
    }
}

extension CaptionLayers {

    /// Where a fresh Captions layer lands: centred, across the picture inside
    /// the title-safe inset, two lines tall, sitting on the title-safe floor,
    /// which puts it in the lower third.
    public static func defaultBox(in size: CGSize, fontSize: CGFloat) -> CGRect {
        band(in: size, lines: 2, fontSize: fontSize)
    }

    /// One layer per cue, dressed in `look`, each filling a box this size.
    public static func layers(for cues: [CaptionCue], in size: CGSize, look: CaptionLook,
                              box: CGSize) -> [Layer] {
        cues.map { cue in
            var layer = Layer(name: name(for: cue), content: .text(TextContent(string: cue.text)),
                              frame: .zero)
            layer = dress(layer, string: cue.text, in: size, look: look, box: box)
            layer.time = LayerTime(inMS: cue.inMS, outMS: cue.outMS)
            layer.captionWords = cue.words
            return layer
        }
    }

    /// A caption wearing `look`, filling its Captions layer's box. The last
    /// line sits on the box's floor, so a one-line caption and a two-line one
    /// share a baseline, the way subtitles do.
    static func dress(_ layer: Layer, string: String, in size: CGSize, look: CaptionLook,
                      box: CGSize) -> Layer {
        var layer = layer
        let font = look.resolvedFontSize(in: size)
        var content = TextContent(string: string, fontName: look.fontName, fontSize: font,
                                  colorHex: look.colorHex, weight: look.weight,
                                  alignment: look.alignment, verticalAlignment: .bottom)
        content.staysOnOneLine = false
        content.plateHex = look.backgroundHex
        content.activeWordHex = look.activeHex
        content.activeWordSung = look.lightsEverythingSaid ? true : nil
        layer.content = .text(content)
        layer.frame = CGRect(origin: .zero, size: box)
        layer.style.shadow = look.backgroundHex == nil
            ? TextBuilder.autoContrastShadow(forColorHex: look.colorHex) : nil
        return layer
    }

    /// A caption's name for retyped words.
    public static func name(for string: String) -> String {
        name(for: CaptionCue(words: [TranscribedWord(string, startMS: 0, endMS: 1)], inMS: 0, outMS: 1))
    }
}

// MARK: - Listening by itself

/// When the app writes captions without being asked.
public enum CaptionAutoRun {

    /// Listen when the toggle is on, the document has time, there is a sound
    /// worth captioning that has never been listened to, and nobody already
    /// has captions they might have corrected.
    public static func shouldListen(isOn: Bool, hasTime: Bool, soundID: UUID?,
                                    listenedTo: [UUID], hasCaptions: Bool) -> Bool {
        guard isOn, hasTime, !hasCaptions, let soundID else { return false }
        return !listenedTo.contains(soundID)
    }
}

// MARK: - Subtitle files

/// WebVTT: the subtitle file browsers and video sites read.
public enum CaptionsVTT {

    public static let fileExtension = "vtt"

    public static func text(_ cues: [CaptionCue]) -> String {
        "WEBVTT\n\n" + cues.map { cue in
            "\(stamp(cue.inMS)) --> \(stamp(cue.outMS))\n\(cue.text)\n"
        }.joined(separator: "\n")
    }

    /// `00:01:23.456`.
    public static func stamp(_ ms: Int) -> String {
        let ms = max(0, ms)
        return String(format: "%02d:%02d:%02d.%03d",
                      ms / 3_600_000, (ms / 60_000) % 60, (ms / 1_000) % 60, ms % 1_000)
    }
}

/// The two subtitle files captions write out as.
public enum CaptionFileFormat: String, CaseIterable, Sendable {
    case srt, vtt

    public var fileExtension: String {
        switch self {
        case .srt: CaptionsSRT.fileExtension
        case .vtt: CaptionsVTT.fileExtension
        }
    }

    public var title: String {
        switch self {
        case .srt: "SubRip (.srt)"
        case .vtt: "WebVTT (.vtt)"
        }
    }

    public func text(_ cues: [CaptionCue]) -> String {
        switch self {
        case .srt: CaptionsSRT.text(cues)
        case .vtt: CaptionsVTT.text(cues)
        }
    }
}

// MARK: - Out as a film

/// What a film written out does with its captions: draws them on the picture,
/// or leaves the picture clean and writes them as a subtitle file beside it.
public enum CaptionExport: Hashable, Sendable {
    case burnedIn
    case file(CaptionFileFormat)

    public static let choices: [CaptionExport] = [.burnedIn, .file(.srt), .file(.vtt)]

    public var title: String {
        switch self {
        case .burnedIn: "Burned in"
        case .file(.srt): "SRT file"
        case .file(.vtt): "VTT file"
        }
    }

    /// The subtitle file written beside the film, if any.
    public var file: CaptionFileFormat? {
        if case .file(let format) = self { return format }
        return nil
    }
}

extension PhotonzDocument {

    /// The document as a film written out with `captions` draws it.
    public func forExport(captions: CaptionExport) -> PhotonzDocument {
        guard captions != .burnedIn, hasCaptions else { return self }
        var clean = self
        clean.clearCaptions()
        return clean
    }
}
