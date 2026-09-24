import PhotonzCore
import SwiftUI

/// **Words**: the lane under a Captions track's cues, one chip per word at the
/// moment it was said (`.wordlane` in `pages/video-captions.html`).
///
/// Words already said are faint, the word being said is lit in the accent,
/// and words still to come read plainly, so the lane tracks the playhead the
/// way the picture's lit word does. A click on a chip puts the playhead on
/// that word.
///
/// **Drawn, not built.** A five minute talk is about a thousand words, and a
/// view per chip meant a thousand views diffed on every step of the playhead:
/// most of the 60ms an arrow key cost on a long captioned recording
/// (`a-long-captioned-recording-walk`). The chips are painted into one canvas
/// instead, the same shapes and type, and the one gesture works out which word
/// a click landed on.
struct CaptionWordsLane: View {
    @Environment(EditorState.self) private var editorState
    let cueIDs: [UUID]
    let laneWidth: CGFloat

    static let height: CGFloat = 22

    /// "Words" in the gutter, with the captions mark, the way the mock labels
    /// the lane.
    static func header(indent: CGFloat) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "captions.bubble").font(.system(size: 9, weight: .semibold))
            Text("Words").font(.system(size: 10, weight: .semibold)).kerning(0.2)
        }
        .foregroundStyle(VideoKit.Palette.comp)
        .padding(.leading, indent + 12)
        .frame(width: TimelineDock.gutter, alignment: .leading)
    }

    var body: some View {
        #if PHOTONZ_PLAYTEST
        let _ = ViewBuildMeter.shared.built(.wordsLane)
        #endif
        // Where the words are depends on the document and the zoom; which one
        // is lit depends on the playhead. Worked out here and lit below, so a
        // step of the playhead repaints the chips without reading every
        // cue's words again.
        CaptionWordChipsView(chips: Self.chips(editorState.captionWordChips(cueIDs: cueIDs),
                                               ruler: editorState.motionStripRuler,
                                               laneWidth: laneWidth),
                             laneWidth: laneWidth)
    }

    /// About how wide a word is at the chip's type, with its padding.
    static func inkWidth(_ text: String) -> CGFloat { CGFloat(text.count) * 5.6 + 12 }

    // MARK: Where the chips go

    struct Chip {
        let word: TranscribedWord
        let x: CGFloat
        let width: CGFloat
    }

    /// Every word that lands in the lane, where it lands. A word scrolled off
    /// either end is left out rather than drawn out of sight.
    static func chips(_ words: [TranscribedWord], ruler: MotionStripRuler, laneWidth: CGFloat) -> [Chip] {
        words.compactMap { word in
            let x0 = laneWidth * ruler.fraction(ofMS: Double(word.startMS))
            let x1 = laneWidth * ruler.fraction(ofMS: Double(word.endMS))
            guard x1 >= 0, x0 <= laneWidth else { return nil }
            return Chip(word: word, x: x0, width: max(3, x1 - x0 - 3))
        }
    }

    /// The chip a click at `x` landed on.
    static func chip(at x: CGFloat, in chips: [Chip]) -> Chip? {
        chips.last { x >= $0.x && x <= $0.x + $0.width }
    }
}

/// The chips themselves, painted, with the word under the playhead lit.
private struct CaptionWordChipsView: View {
    @Environment(EditorState.self) private var editorState
    let chips: [CaptionWordsLane.Chip]
    let laneWidth: CGFloat

    /// The word under the pointer, for the tooltip a chip used to carry.
    @State private var hovered: String?

    private static let chipHeight: CGFloat = 20
    private static let fontSize: CGFloat = 9.5

    var body: some View {
        let now = editorState.documentTimeMS
        let saying = chips.first { $0.word.startMS <= now && now < $0.word.endMS }
        Canvas { context, _ in
            // One path per kind of chip, filled and stroked once: a thousand
            // words drawn one by one was two thousand calls each time the
            // playhead moved. Only chips wide enough for their word are
            // lettered, and those are drawn one by one.
            var plain = Path()
            var lit = Path()
            var edges = Path()
            for chip in chips {
                let rect = CGRect(x: chip.x, y: 0, width: chip.width, height: Self.chipHeight)
                if Self.state(of: chip.word, at: now) == .saying {
                    lit.addRoundedRect(in: rect, cornerSize: CGSize(width: 6, height: 6))
                } else {
                    plain.addRoundedRect(in: rect, cornerSize: CGSize(width: 6, height: 6))
                    // strokeBorder: the line sits inside the chip's edge.
                    edges.addRoundedRect(in: rect.insetBy(dx: 0.5, dy: 0.5),
                                         cornerSize: CGSize(width: 5.5, height: 5.5))
                }
            }
            context.fill(plain, with: .style(VideoKit.Palette.glassThin))
            context.stroke(edges, with: .style(VideoKit.Palette.edgeLo), lineWidth: 1)
            context.fill(lit, with: .style(VideoKit.Palette.accent))
            for chip in chips where chip.width >= CaptionWordsLane.inkWidth(chip.word.text) {
                letter(chip, state: Self.state(of: chip.word, at: now), in: &context)
            }
        }
        .frame(width: laneWidth, height: CaptionWordsLane.height, alignment: .topLeading)
        .contentShape(Rectangle())
        .onTapGesture(coordinateSpace: .local) { point in
            guard let chip = CaptionWordsLane.chip(at: point.x, in: chips) else { return }
            editorState.moveDocumentPlayhead(toMS: chip.word.startMS)
        }
        .onContinuousHover(coordinateSpace: .local) { phase in
            switch phase {
            case .active(let point): hovered = CaptionWordsLane.chip(at: point.x, in: chips)?.word.text
            case .ended: hovered = nil
            }
        }
        .help(hovered ?? "")
        .clipped()
        .accessibilityElement()
        .accessibilityLabel("Words")
        .accessibilityValue(saying?.word.text ?? "")
    }

    // MARK: Painting one

    private enum ChipState { case said, saying, toCome }

    private static func state(of word: TranscribedWord, at ms: Int) -> ChipState {
        if ms >= word.startMS, ms < word.endMS { return .saying }
        return ms >= word.endMS ? .said : .toCome
    }

    /// The word on a chip wide enough to hold it. A word too long for its
    /// chip shows no letters rather than a crumb and an ellipsis; the tooltip
    /// and the cue above say it.
    private func letter(_ chip: CaptionWordsLane.Chip, state: ChipState, in context: inout GraphicsContext) {
        let ink: AnyShapeStyle = switch state {
        case .saying: AnyShapeStyle(Color(red: 0.04, green: 0.05, blue: 0.08))
        case .said: AnyShapeStyle(VideoKit.Palette.faint)
        case .toCome: AnyShapeStyle(VideoKit.Palette.dim)
        }
        let text = Text(chip.word.text)
            .font(.system(size: Self.fontSize, weight: .medium))
            .foregroundStyle(ink)
        context.draw(text, at: CGPoint(x: chip.x + 6, y: Self.chipHeight / 2), anchor: .leading)
    }
}
