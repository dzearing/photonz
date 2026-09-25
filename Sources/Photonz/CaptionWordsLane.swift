import AppKit
import PhotonzCore
import SwiftUI

/// **Words**: the lane under a Captions track's cues, one chip per word at the
/// moment it was said (`.wordlane` in `pages/video-captions.html`).
///
/// Words already said are faint, the word being said is lit in the accent,
/// and words still to come read plainly, so the lane tracks the playhead the
/// way the picture's lit word does. A click on a chip puts the playhead on
/// that word, a double click opens it for typing, a drag retimes it and the
/// words after it (Shift: every later line too; Command: the word alone), a
/// drag on either edge stretches it, and a right click has the rest
/// (`EditorState+CaptionWords`).
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

    /// The mock's lane: 26 points, a 20 point chip three down from its top.
    static let height: CGFloat = 26
    static let chipTop: CGFloat = 3

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
                             ruler: editorState.motionStripRuler,
                             laneWidth: laneWidth)
    }

    /// About how wide a word is at the chip's type, with its padding.
    static func inkWidth(_ text: String) -> CGFloat { CGFloat(text.count) * 5.6 + 12 }

    /// What a chip `width` wide says: the whole word where it fits, and
    /// otherwise as much of it as fits with an ellipsis, the way the mock's
    /// chips cut a long word short. Nil where not even one letter fits.
    static func lettering(_ text: String, width: CGFloat) -> String? {
        guard width < inkWidth(text) else { return text }
        let letters = Int(((width - 12) / 5.6).rounded(.down)) - 1
        guard letters >= 1 else { return nil }
        return String(text.prefix(letters)) + "…"
    }

    // MARK: Where the chips go

    struct Chip {
        let ref: CaptionWordRef
        let word: TranscribedWord
        let x: CGFloat
        let width: CGFloat
    }

    /// Every word that lands in the lane, where it lands. A word scrolled off
    /// either end is left out rather than drawn out of sight.
    static func chips(_ words: [EditorState.CaptionWordChip], ruler: MotionStripRuler,
                      laneWidth: CGFloat) -> [Chip] {
        words.compactMap { chip in
            let word = chip.word
            let x0 = laneWidth * ruler.fraction(ofMS: Double(word.startMS))
            let x1 = laneWidth * ruler.fraction(ofMS: Double(word.endMS))
            guard x1 >= 0, x0 <= laneWidth else { return nil }
            return Chip(ref: chip.ref, word: word, x: x0, width: max(3, x1 - x0 - 3))
        }
    }

    /// The chip a click at `x` landed on.
    static func chip(at x: CGFloat, in chips: [Chip]) -> Chip? {
        chips.last { x >= $0.x && x <= $0.x + $0.width }
    }

    /// How close to a chip's end a press has to be to take hold of the edge
    /// rather than the word. A chip too narrow for two edges and a middle is
    /// all middle.
    static let edgeGrip: CGFloat = 4

    /// What a press at `x` on `chip` takes hold of: an edge, or the word.
    static func grip(at x: CGFloat, on chip: Chip) -> CaptionWordGrab? {
        guard chip.width >= edgeGrip * 3 else { return nil }
        if x <= chip.x + edgeGrip { return .start }
        if x >= chip.x + chip.width - edgeGrip { return .end }
        return nil
    }

    /// The word itself, as the keys held say: on its own with Command, with
    /// every later line with Shift, and with the rest of its line otherwise.
    static func bodyGrab(_ flags: NSEvent.ModifierFlags) -> CaptionWordGrab {
        if flags.contains(.command) { return .alone }
        if flags.contains(.shift) { return .carryTrack }
        return .carryRest
    }
}

/// The chips themselves, painted, with the word under the playhead lit.
private struct CaptionWordChipsView: View {
    @Environment(EditorState.self) private var editorState
    let chips: [CaptionWordsLane.Chip]
    let ruler: MotionStripRuler
    let laneWidth: CGFloat

    /// The chip under the pointer, for the tooltip a chip used to carry and
    /// for the right click menu, and where along the lane the pointer is.
    @State private var hovered: CaptionWordsLane.Chip?
    @State private var hoverX: CGFloat = 0
    /// The chip a press began on and what it took hold of, and whether it has
    /// moved far enough to be a drag rather than a click.
    @State private var pressed: (chip: CaptionWordsLane.Chip, edge: CaptionWordGrab?)?
    @State private var dragging = false

    private static let chipHeight: CGFloat = 20
    private static let fontSize: CGFloat = 9.5

    var body: some View {
        let now = editorState.documentTimeMS
        let saying = chips.first { $0.word.startMS <= now && now < $0.word.endMS }
        let inHand = editorState.captionWordDrag?.ref
        let typing = editorState.captionWordEdit.flatMap { $0.place == .lane ? $0 : nil }
        Canvas { context, _ in
            // One path per kind of chip, filled and stroked once: a thousand
            // words drawn one by one was two thousand calls each time the
            // playhead moved. Only chips wide enough for their word are
            // lettered, and those are drawn one by one.
            var plain = Path()
            var lit = Path()
            var edges = Path()
            for chip in chips {
                let rect = CGRect(x: chip.x, y: CaptionWordsLane.chipTop, width: chip.width, height: Self.chipHeight)
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
            // The chip in the hand, ringed so the eye can follow it.
            if let held = chips.first(where: { $0.ref == inHand }) {
                let rect = CGRect(x: held.x, y: CaptionWordsLane.chipTop, width: held.width, height: Self.chipHeight)
                context.stroke(Path(roundedRect: rect.insetBy(dx: 0.75, dy: 0.75), cornerRadius: 5.25),
                               with: .style(VideoKit.Palette.accent), lineWidth: 1.5)
            }
            for chip in chips {
                guard let words = CaptionWordsLane.lettering(chip.word.text, width: chip.width) else { continue }
                letter(chip, words, state: Self.state(of: chip.word, at: now), in: &context)
            }
        }
        .frame(width: laneWidth, height: CaptionWordsLane.height, alignment: .topLeading)
        .contentShape(Rectangle())
        .gesture(press)
        .onContinuousHover(coordinateSpace: .local) { phase in
            switch phase {
            case .active(let point):
                hoverX = point.x
                hovered = CaptionWordsLane.chip(at: point.x, in: chips)
                let onEdge = hovered.flatMap { CaptionWordsLane.grip(at: point.x, on: $0) } != nil
                (onEdge ? NSCursor.resizeLeftRight : NSCursor.arrow).set()
            case .ended:
                hovered = nil
                NSCursor.arrow.set()
            }
        }
        .contextMenu { menu }
        .help(hovered.map { "\($0.word.text) · \(Self.seconds($0.word.startMS)) to \(Self.seconds($0.word.endMS))" } ?? "")
        .clipped()
        .overlay(alignment: .topLeading) {
            if let typing, let chip = chips.first(where: { $0.ref == typing.ref }) {
                CaptionWordFieldPlate(session: typing,
                                      font: .systemFont(ofSize: 10.5, weight: .medium),
                                      ink: .white, minWidth: chip.width,
                                      height: Self.chipHeight, radius: 6)
                    .offset(x: chip.x, y: CaptionWordsLane.chipTop)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Words")
        .accessibilityValue(saying?.word.text ?? "")
        .playtestControl("Words", detail: "Timeline")
    }

    private static func seconds(_ ms: Int) -> String { String(format: "%.2fs", Double(ms) / 1000) }

    // MARK: The hand

    /// A press on a chip: a click moves the playhead to the word, a double
    /// click opens it for typing, and a drag retimes or stretches it.
    private var press: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                if pressed == nil {
                    guard let chip = CaptionWordsLane.chip(at: value.startLocation.x, in: chips) else { return }
                    pressed = (chip, CaptionWordsLane.grip(at: value.startLocation.x, on: chip))
                }
                guard let pressed else { return }
                let flags = NSEvent.modifierFlags
                if !dragging {
                    guard abs(value.translation.width) >= 3 else { return }
                    dragging = true
                    editorState.beginCaptionWordDrag(pressed.chip.ref,
                                                     grab: pressed.edge ?? CaptionWordsLane.bodyGrab(flags))
                }
                let ms = ruler.msSpanning(fraction: Double(value.translation.width / max(1, laneWidth)))
                editorState.updateCaptionWordDrag(byMS: Int(ms.rounded()),
                                                  grab: pressed.edge == nil ? CaptionWordsLane.bodyGrab(flags) : nil)
            }
            .onEnded { _ in
                defer {
                    pressed = nil
                    dragging = false
                }
                guard let pressed else { return }
                if dragging {
                    editorState.commitCaptionWordDrag()
                } else if (NSApp.currentEvent?.clickCount ?? 1) >= 2 {
                    editorState.beginEditingCaptionWord(pressed.chip.ref, place: .lane)
                } else {
                    editorState.moveDocumentPlayhead(toMS: pressed.chip.word.startMS)
                }
            }
    }

    /// Right click on a word: what can be done to that word, the way Premiere
    /// puts a clip's verbs on the clip.
    @ViewBuilder private var menu: some View {
        if let chip = hovered {
            let ms = Int(ruler.ms(atFraction: Double(hoverX / max(1, laneWidth))).rounded())
            MenuRowsView(rows: editorState.captionWordMenuRows(chip.ref, place: .lane, atMS: ms))
        }
    }

    // MARK: Painting one

    private enum ChipState { case said, saying, toCome }

    private static func state(of word: TranscribedWord, at ms: Int) -> ChipState {
        if ms >= word.startMS, ms < word.endMS { return .saying }
        return ms >= word.endMS ? .said : .toCome
    }

    /// The word on its chip, cut short with an ellipsis where the chip is too
    /// narrow for it, as the mock draws it (`CaptionWordsLane.lettering`): a
    /// misspelling has to be findable on the lane to be fixed there.
    private func letter(_ chip: CaptionWordsLane.Chip, _ words: String, state: ChipState,
                        in context: inout GraphicsContext) {
        let ink: AnyShapeStyle = switch state {
        case .saying: AnyShapeStyle(Color(red: 0.04, green: 0.05, blue: 0.08))
        case .said: AnyShapeStyle(VideoKit.Palette.faint)
        case .toCome: AnyShapeStyle(VideoKit.Palette.dim)
        }
        let text = Text(words)
            .font(.system(size: Self.fontSize, weight: .medium))
            .foregroundStyle(ink)
        context.draw(text, at: CGPoint(x: chip.x + 6, y: CaptionWordsLane.chipTop + Self.chipHeight / 2),
                     anchor: .leading)
    }
}
