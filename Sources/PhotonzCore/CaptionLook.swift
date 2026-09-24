import CoreGraphics
import Foundation

// Captions as a track, a look and a lit word
// (`docs/design/mocks/pages/video-captions.html`).
//
// The mock asks three things of captions beyond being written:
//
// - **One track.** Every cue sits on one Captions row of the timeline, side by
//   side, the way Premiere's captions track holds them. The cues are still
//   ordinary text layers with an in and an out; they land in one group, and a
//   group made of nothing but captions IS the captions track's clip
//   (`Layer.isCaptionGroup`), whose cues the timeline lays out in one lane.
// - **One look.** Caption, Lower third or Karaoke, plus the font, size,
//   colour, background and position, set once for every caption
//   (`CaptionLook`, `applyCaptionLook`). The look is written on the document
//   so the next lot of captions comes out wearing it too.
// - **A lit word.** The word being said lights up as the playhead passes it.
//   Nothing about that is stored: the frame drawn at a moment carries it
//   (`CaptionActiveWord`, applied in `DocumentTime.shownTree`), exactly the way
//   a clip carries the frame of its recording that the moment lands on.

// MARK: - The look

/// How every caption in a document looks.
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

    /// Where on the picture the words sit, always inside the title-safe area.
    public enum Position: String, Hashable, Codable, Sendable, CaseIterable {
        case bottom, middle, top

        public var title: String {
            switch self {
            case .bottom: "Bottom"
            case .middle: "Middle"
            case .top: "Top"
            }
        }

        var verticalAlignment: TextVerticalAlign {
            switch self {
            case .bottom: .bottom
            case .middle: .middle
            case .top: .top
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
    public var position: Position
    public var alignment: TextAlign

    public init(preset: Preset, fontName: String = "SF Pro", weight: TextWeight = .semibold,
                fontSize: CGFloat? = nil, colorHex: String = "#FFFFFF",
                backgroundHex: String? = nil, activeHex: String? = nil,
                position: Position = .bottom, alignment: TextAlign = .center) {
        self.preset = preset
        self.fontName = fontName
        self.weight = weight
        self.fontSize = fontSize
        self.colorHex = colorHex
        self.backgroundHex = backgroundHex
        self.activeHex = activeHex
        self.position = position
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
            return TranscribedWord(word.text, startMS: start, endMS: end, confidence: word.confidence)
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
    static func tokenSpans(in string: String) -> [Span] {
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

    /// A group holding nothing but captions: the clip a Captions track holds.
    public var isCaptionGroup: Bool {
        guard isGroup, !children.isEmpty else { return false }
        return children.allSatisfy(\.isCaption)
    }
}

// MARK: - Landing and restyling

extension PhotonzDocument {

    /// The cues on a captions track, earliest first: every caption inside the
    /// caption groups on it.
    public func captionCueIDs(onTrack id: UUID) -> [UUID] {
        // The captions under this track's clips, in time order, read in place:
        // a Captions group holds every cue, and copying each out to sort it
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

    /// Put these cues on the document as its captions, replacing any it had,
    /// in `look` (or the look the document already has, or the standard one).
    /// They land as one Captions group, which the timeline shows as one
    /// Captions track.
    @discardableResult
    public mutating func landCaptions(_ cues: [CaptionCue], look: CaptionLook? = nil) -> UUID? {
        clearCaptions()
        // Nothing is said after the film ends, so no line is on screen after
        // it either: a line lingering past the last frame would make the film
        // longer by the linger.
        let end = hasTime ? documentDurationMS : Int.max
        let cues = cues.compactMap { cue -> CaptionCue? in
            guard cue.inMS < end - LayerTime.shortestMS else { return cue.outMS <= end ? cue : nil }
            return CaptionCue(words: cue.words, inMS: cue.inMS, outMS: min(cue.outMS, end))
        }
        guard !cues.isEmpty else { return nil }
        let chosen = look ?? captionLook ?? .standard
        captionLook = chosen
        let children = CaptionLayers.layers(for: cues, in: canvasSize, look: chosen)
        let group = Layer(name: CaptionLayers.groupName, content: .group(GroupContent(children: children)),
                          frame: CGRect(origin: .zero, size: .zero))
        addLayer(group)
        return group.id
    }

    /// Dress every caption in `look`, and keep it for the next ones.
    public mutating func applyCaptionLook(_ look: CaptionLook) {
        captionLook = look
        let size = canvasSize
        for caption in captionLayers {
            let origin = parentOrigin(of: caption.id) ?? .zero
            updateLayer(id: caption.id) { layer in
                guard case .text(let content) = layer.content else { return }
                let restyled = CaptionLayers.dress(layer, string: content.string, in: size, look: look)
                layer.content = restyled.content
                layer.style.shadow = restyled.style.shadow
                layer.frame = restyled.frame.offsetBy(dx: -origin.x, dy: -origin.y)
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
}

extension CaptionLayers {

    /// One layer per cue, dressed in `look`.
    public static func layers(for cues: [CaptionCue], in size: CGSize, look: CaptionLook) -> [Layer] {
        cues.map { cue in
            var layer = Layer(name: name(for: cue), content: .text(TextContent(string: cue.text)),
                              frame: .zero)
            layer = dress(layer, string: cue.text, in: size, look: look)
            layer.time = LayerTime(inMS: cue.inMS, outMS: cue.outMS)
            layer.captionWords = cue.words
            return layer
        }
    }

    /// A caption wearing `look`, in canvas coordinates.
    static func dress(_ layer: Layer, string: String, in size: CGSize, look: CaptionLook) -> Layer {
        var layer = layer
        let font = look.resolvedFontSize(in: size)
        var content = TextContent(string: string, fontName: look.fontName, fontSize: font,
                                  colorHex: look.colorHex, weight: look.weight,
                                  alignment: look.alignment,
                                  verticalAlignment: look.position.verticalAlignment)
        content.staysOnOneLine = false
        content.plateHex = look.backgroundHex
        content.activeWordHex = look.activeHex
        content.activeWordSung = look.lightsEverythingSaid ? true : nil
        layer.content = .text(content)
        layer.frame = band(in: size, lines: 2, fontSize: font, position: look.position)
        layer.style.shadow = look.backgroundHex == nil
            ? TextBuilder.autoContrastShadow(forColorHex: look.colorHex) : nil
        return layer
    }

    /// The band a caption's box occupies at a position, inside the title-safe
    /// inset on every side.
    public static func band(in size: CGSize, lines: Int, fontSize: CGFloat,
                            position: CaptionLook.Position) -> CGRect {
        let bottom = band(in: size, lines: lines, fontSize: fontSize)
        switch position {
        case .bottom:
            return bottom
        case .top:
            return CGRect(x: bottom.minX, y: size.height * titleSafeInset,
                          width: bottom.width, height: bottom.height)
        case .middle:
            return CGRect(x: bottom.minX, y: (size.height - bottom.height) / 2,
                          width: bottom.width, height: bottom.height)
        }
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
