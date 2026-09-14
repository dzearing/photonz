import Foundation
import PhotonzCore

/// Letting a saved colour go on a row in the layers list.
///
/// The list already took a saved TEXT STYLE on a row, and refused a colour with
/// nothing said about why, which is exactly the silence the row drop was built
/// to end. It was refused because a row is not a colour well: a well says what
/// it paints, a row says only the layer's name.
///
/// The rule the user chose on 2026-09-13 is the layer's main colour, NAMED
/// before you let go: the line under the list reads "Paints Fill with Brand"
/// over a box, "Paints Text with Brand" over words, "Paints Border with Brand"
/// over a picture wearing a ring, and a layer with no colour at all says so and
/// stays dark.
///
/// The rules are not a second set: the row hands the document the same question
/// (`PhotonzDocument.colorRowDrop`), which builds the same `ColorDrop.Target` a
/// swatch builds, so the sentence the list says is the sentence a swatch would
/// have said and the drop lands the same single undo step.
extension EditorState {

    /// What letting this colour go on this row would do, in the two terms the
    /// list draws: whether the row lights up, and the one line that says why.
    func colorRowDrop(_ payload: ColorDrag.Payload, onRow id: UUID) -> StyleRowDrop {
        guard let drop = reading(payload, onRow: id) else {
            return StyleRowDrop(rowID: id, lands: false, note: "", layerIDs: [])
        }
        return StyleRowDrop(rowID: id, answer: drop.answer, layerIDs: drop.layerIDs)
    }

    /// Lands a colour let go on a row, in ONE step. The very reading the row
    /// answered the pointer with, so nothing can slip past a refusal and land
    /// anyway.
    @discardableResult
    func dropColor(_ payload: ColorDrag.Payload, onRow id: UUID) -> Bool {
        let drop = reading(payload, onRow: id)
        endStyleRowDrop(from: id)
        guard let drop, drop.answer.lightsUp else { return false }
        discardDragPreview()
        var painted = 0
        perform { painted = $0.paint(drop) }
        guard painted > 0 else { return false }
        // The colour is in your hand now whatever row it landed on, so it joins
        // the recents the way every other way of painting does. Nothing is
        // armed for the next shape, though: the row you aimed at is not
        // necessarily the row you have picked, and a tool quietly taking the
        // colour of a layer somebody never selected is a surprise.
        recordRecentColor(hex: payload.paint.hex)
        return true
    }

    /// The document's answer, asked the one way, so the sentence the pointer
    /// was shown and the paint that lands can never come from two readings.
    private func reading(_ payload: ColorDrag.Payload, onRow id: UUID) -> ColorRowDrop? {
        guard let document else { return nil }
        return document.colorRowDrop(payload.paint, bringing: payload.style, onRow: id,
                                     picked: actionableLayerIDs,
                                     stylesEnabled: colorStylesEnabled)
    }
}
