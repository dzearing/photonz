import PhotonzCore
import SwiftUI

// The sentence a colour drop target says while a colour is in the air over it
// (Next, `next-color-drag`). The answer itself is worked out in
// `PhotonzCore/ColorDrop.swift`, away from any view; where the words sit is
// `PhotonzCore/DropNotePlacement.swift`; this is only the drawing of it.

/// What a colour drop target is saying, and where the target is.
///
/// The anchor is the target's frame in the window's own coordinates, so the
/// pill can be drawn once over the whole window instead of by each swatch. A
/// swatch is 18pt wide in a 260pt column: a sentence cannot be drawn inside
/// one, and a sentence drawn under the pointer would cover the row below,
/// which is usually the very row somebody is comparing against.
struct ColorDropNote: Equatable {
    /// The words. Written either way round: a target that refuses says why, so
    /// a swatch that stays dark is never a mystery.
    var note: String
    /// Whether letting go here would do anything, which is what the colour of
    /// the pill repeats. Accent for a colour that lands, a plain dark plate
    /// for one that does not, exactly as the text style drop's line does.
    var lands: Bool
    /// The target's frame in the window, which the words sit beside and never
    /// on top of.
    var anchor: CGRect
}

extension EditorState {

    /// Says out loud what letting go on this target would do, or takes the
    /// words away when `answer` is nil.
    ///
    /// Clearing is keyed on the anchor on purpose. Carrying a colour from one
    /// swatch straight onto its neighbour arrives on the second before it
    /// leaves the first, so a blind clear on the way out would wipe the
    /// sentence the second swatch had just started saying.
    func sayColorDrop(_ answer: ColorDrop.Answer?, over anchor: CGRect) {
        guard let answer else {
            if colorDropNote?.anchor == anchor { colorDropNote = nil }
            return
        }
        let saying = ColorDropNote(note: answer.note, lands: answer.lightsUp, anchor: anchor)
        if colorDropNote != saying { colorDropNote = saying }
    }
}

/// Makes a colour drop target say its sentence out loud.
///
/// It goes on the target itself rather than inside `ColorDropTarget` because
/// the delegate has no idea where on screen it is, and where it is is half the
/// answer: the words have to land beside THIS swatch.
struct ColorDropSpeaks: ViewModifier {
    @Environment(EditorState.self) private var editorState
    /// What this target would do with the colour in the air, nil when nothing
    /// is over it.
    let answer: ColorDrop.Answer?

    /// Where this target sits in the window. Kept here rather than in the
    /// editor's state because it changes on every scroll of the panel and
    /// nothing draws from it until a colour is actually overhead.
    @State private var anchor: CGRect = .zero

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { anchor = $0 }
            .onChange(of: answer) { _, latest in
                editorState.sayColorDrop(latest, over: anchor)
            }
            // A panel that reflows out from under an open drag — a selection
            // changed by an undo, a section collapsing — would otherwise leave
            // a sentence hanging beside nothing.
            .onDisappear { editorState.sayColorDrop(nil, over: anchor) }
    }
}

extension View {
    /// Says out loud what letting a colour go here would do.
    func colorDropSpeaks(_ answer: ColorDrop.Answer?) -> some View {
        modifier(ColorDropSpeaks(answer: answer))
    }
}

/// The pill itself, drawn over the whole window beside whichever target is
/// talking.
///
/// One pill at window level, not one per swatch: the panel clips, the column
/// is narrower than the sentence, and two targets can never be talking at
/// once.
struct ColorDropNoteOverlay: View {
    @Environment(EditorState.self) private var editorState
    /// The window's own frame, so the anchor — which is in window
    /// coordinates — can be read in the same space this overlay draws in.
    let bounds: CGRect
    /// The right hand panel, when it is showing. Nearly every colour in the
    /// app lives on a swatch inside it, and words that cleared only the
    /// swatch would lie across the row's own label and switch: the sentence
    /// stands off the whole panel and still lines up with the one swatch.
    /// Nil with the panel put away, and for a window with no panel at all.
    let panel: CGRect?

    /// How big the words turned out to be. Measured rather than guessed: the
    /// sentence is a different length for every answer, and a pill placed from
    /// a guessed size is a pill that sits crooked beside its swatch.
    @State private var size: CGSize = .zero

    var body: some View {
        if let saying = editorState.colorDropNote {
            // Only when the target really is in the panel: the tool bar's own
            // swatch floats on the canvas and has nothing to stand off but
            // itself.
            let clearing = panel.flatMap { $0.intersects(saying.anchor) ? $0 : nil }
            let origin = DropNotePlacement.place(note: size, beside: saying.anchor,
                                                 clearing: clearing, in: bounds)
            pill(saying)
                .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
                .offset(x: origin.x - bounds.minX, y: origin.y - bounds.minY)
                // Invisible for the one pass it takes to measure itself, so
                // nobody sees it flash in the top left corner on its way to
                // the swatch.
                .opacity(size == .zero ? 0 : 1)
                .allowsHitTesting(false)
        }
    }

    private func pill(_ saying: ColorDropNote) -> some View {
        Text(saying.note)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.white)
            .multilineTextAlignment(.leading)
            .lineLimit(3)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: DropNotePlacement.maxWidth, alignment: .leading)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            // The colour repeats what the ring on the target says, so a glance
            // is enough and reading is only needed for the why. Same two
            // colours the text style drop uses, because they are the same
            // two answers.
            .background {
                RoundedRectangle(cornerRadius: 8)
                    .fill(saying.lands ? Color.accentColor : Color.black.opacity(0.78))
            }
            .shadow(color: .black.opacity(0.28), radius: 5, y: 1)
    }
}
