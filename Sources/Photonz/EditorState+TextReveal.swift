import Foundation
import PhotonzCore

// Text that comes in by line, word or letter (`TextReveal.swift`): the panel's
// Reveal section reads and writes the picked text's one reveal here, each
// change one undo step.
extension EditorState {

    /// The text the Reveal section speaks for: one picked text layer on a
    /// video, in Next, that is not a caption. A caption's words already move
    /// with the speech. Its words open for typing count too: double clicking
    /// a title's words is how a piece of it is reached, and the Text section
    /// beside this answers then as well.
    var textRevealLayer: Layer? {
        guard Experiments.shared.titleOnTheTimelineEnabled, documentHasTime,
              let id = colorStyleTargetIDs.count == 1 ? colorStyleTargetIDs.first : editingTextLayerID,
              let layer = document?.layer(id: id), layer.text != nil, !layer.isCaption else { return nil }
        return layer
    }

    /// Its reveal, or nil for words that are simply there.
    var textRevealInHand: TextReveal? { textRevealLayer?.text?.reveal }

    /// Give the picked text a reveal in `style`, keeping what it already had
    /// for everything else, or take it off with nil.
    func setTextRevealStyle(_ style: TextRevealStyle?) {
        guard let layer = textRevealLayer else { return }
        guard let style else {
            setTextReveal(nil, on: layer.id)
            return
        }
        var reveal = layer.text?.reveal ?? TextReveal(style: style, unit: .word)
        guard reveal.style != style || layer.text?.reveal == nil else { return }
        let fresh = TextReveal(style: style, unit: reveal.unit)
        // A typewriter has its own pace; leaving one takes the usual stagger
        // back. Distances belong to the style.
        if reveal.style == .typewriter || style == .typewriter { reveal.staggerMS = fresh.staggerMS }
        // A curve nobody changed follows the style: the ones in depth ease in
        // and out (`TextRevealStyle.defaultCurve`).
        if reveal.curve == reveal.style.defaultCurve { reveal.curve = fresh.curve }
        reveal.style = style
        reveal.amount = fresh.amount
        reveal.direction = fresh.direction
        setTextReveal(reveal, on: layer.id)
    }

    /// Split the picked text's words a new way, at the stagger that unit
    /// usually takes.
    func setTextRevealUnit(_ unit: TextRevealUnit) {
        updateTextReveal { reveal in
            guard reveal.unit != unit else { return }
            reveal.unit = unit
            reveal.staggerMS = TextReveal(style: reveal.style, unit: unit).staggerMS
        }
    }

    func setTextRevealStagger(_ ms: Int) {
        updateTextReveal { $0.staggerMS = max(0, min(ms, 2_000)) }
    }

    func setTextRevealLength(_ ms: Int) {
        updateTextReveal { $0.lengthMS = max(1, min(ms, 5_000)) }
    }

    func setTextRevealOrder(_ order: TextRevealOrder) {
        updateTextReveal { $0.order = order }
    }

    func setTextRevealCurve(_ curve: EasingCurve) {
        updateTextReveal { $0.curve = curve }
    }

    /// How long the picked text's whole reveal takes, counting its pieces as
    /// written. Lines are counted as the lines typed.
    var textRevealTotalMS: Int? {
        guard let text = textRevealLayer?.text, let reveal = text.reveal else { return nil }
        let count = TextReveal.spans(in: text.string, unit: reveal.unit)?.count
            ?? max(1, text.string.split(whereSeparator: \.isNewline).count)
        return reveal.lengthMS(count: count)
    }

    private func updateTextReveal(_ change: (inout TextReveal) -> Void) {
        guard let layer = textRevealLayer, var reveal = layer.text?.reveal else { return }
        let was = reveal
        change(&reveal)
        guard reveal != was else { return }
        setTextReveal(reveal, on: layer.id)
    }

    private func setTextReveal(_ reveal: TextReveal?, on id: UUID) {
        perform { document in
            document.setTextReveal(reveal, layerID: id)
        }
    }
}
