// How every control in the dock says Mixed.
//
// The word itself lives in PhotonzCore (`MixedValue`). This is the other half:
// what it LOOKS like, in one place, because a design review on 2026-09-04 found
// the same word drawn four different ways down one panel. A menu said Mixed at
// full strength, like a choice someone had made; a slider said it two steps
// down, like a value that was not there; a field said it one step down; and the
// alignment rows said nothing at all and simply went blank.
//
// One rule now, and it is worth writing down because it is the thing every new
// control has to follow:
//
//   Mixed goes where that control shows its VALUE, in one weight, everywhere.
//
// The weight is one step quieter than a real value: Mixed is not something you
// chose, so it must not read as loud as something you did, and it is not a hint
// either, so it must not fade into the captions around it. A control with no
// room for the word — a row of picture buttons has no text in it at all — says
// it at the trailing end of its own caption row, which is exactly where a
// slider already writes its readout, so the two line up down the panel.
//
// What Mixed never is: absent. A control that goes blank leaves the reader to
// work out whether the layers differ or the value is simply empty, and those
// are different answers.

import PhotonzCore
import SwiftUI

enum MixedLook {
    /// The one strength the word is drawn at, whatever control it is in.
    static var style: AnyShapeStyle { AnyShapeStyle(.secondary) }

    /// What a control's value slot is drawn in: the Mixed strength while the
    /// layers differ, and the control's own strength while they agree.
    static func style(_ isMixed: Bool, otherwise: some ShapeStyle) -> AnyShapeStyle {
        isMixed ? style : AnyShapeStyle(otherwise)
    }

    /// The same one step quieter, for a control that is a PICTURE rather than
    /// text: a switch has no words in it to restyle, and while it has no
    /// position it must not read as an off somebody chose. Every switch
    /// speaking for several picked things wears this while they disagree.
    static let controlOpacity: Double = 0.55
}

/// The word Mixed for a control that cannot write it where its value lives.
///
/// A segmented row of alignment buttons is a picture, not a number, so it has
/// nowhere to put a word: it used to answer a mixed selection by lighting no
/// segment at all, which reads exactly like a control that has not been set.
/// The word goes at the trailing end of the row's caption instead, in the same
/// weight and the same font a slider's readout uses.
struct MixedWord: View {
    var body: some View {
        Text(MixedValue.text)
            .font(.caption)
            .foregroundStyle(MixedLook.style)
    }
}
