import PhotonzCore
import SwiftUI

/// **Words**: the lane under a Captions track's cues, one chip per word at the
/// moment it was said (`.wordlane` in `pages/video-captions.html`).
///
/// Words already said are faint, the word being said is lit in the accent,
/// and words still to come read plainly, so the lane tracks the playhead the
/// way the picture's lit word does. A click on a chip puts the playhead on
/// that word.
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
        let ruler = editorState.motionStripRuler
        let now = editorState.documentTimeMS
        let words = editorState.captionWordChips(cueIDs: cueIDs)
        ZStack(alignment: .topLeading) {
            ForEach(Array(words.enumerated()), id: \.offset) { _, word in
                let x0 = laneWidth * ruler.fraction(ofMS: Double(word.startMS))
                let x1 = laneWidth * ruler.fraction(ofMS: Double(word.endMS))
                let width = max(3, x1 - x0 - 3)
                if x1 >= 0, x0 <= laneWidth {
                    chip(word, width: width, state: state(of: word, at: now))
                        .offset(x: x0)
                }
            }
        }
        .frame(width: laneWidth, height: Self.height, alignment: .topLeading)
        .clipped()
    }

    /// About how wide a word is at the chip's type, with its padding.
    static func inkWidth(_ text: String) -> CGFloat { CGFloat(text.count) * 5.6 + 12 }

    private enum ChipState { case said, saying, toCome }

    private func state(of word: TranscribedWord, at ms: Int) -> ChipState {
        if ms >= word.startMS, ms < word.endMS { return .saying }
        return ms >= word.endMS ? .said : .toCome
    }

    private func chip(_ word: TranscribedWord, width: CGFloat, state: ChipState) -> some View {
        let shape = RoundedRectangle(cornerRadius: 6)
        return shape
            .fill(state == .saying ? AnyShapeStyle(VideoKit.Palette.accent)
                                   : AnyShapeStyle(VideoKit.Palette.glassThin))
            .overlay {
                if state != .saying { shape.strokeBorder(VideoKit.Palette.edgeLo) }
            }
            .overlay(alignment: .leading) {
                // A word too long for its chip shows no letters rather than
                // a crumb and an ellipsis; its tooltip and the cue above say it.
                if width >= Self.inkWidth(word.text) {
                    Text(word.text)
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(state == .saying ? AnyShapeStyle(Color(red: 0.04, green: 0.05, blue: 0.08))
                                         : state == .said ? AnyShapeStyle(VideoKit.Palette.faint)
                                         : AnyShapeStyle(VideoKit.Palette.dim))
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 6)
                }
            }
            .frame(width: width, height: 20)
            .contentShape(shape)
            .onTapGesture { editorState.moveDocumentPlayhead(toMS: word.startMS) }
            .help(word.text)
            .accessibilityLabel(word.text)
    }
}
