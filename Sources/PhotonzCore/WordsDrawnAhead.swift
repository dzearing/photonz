import Foundation

// The moments of a video at which its titles' words are drawn for the first
// time, so the editor can draw them before a hand dragging the playhead gets
// there (`scrubbing-a-long-edit-never-trails-the-pointer-b`, pass 5).
//
// Words are set out and drawn once per text, size and look, and kept: the
// first picture that shows them pays for it. On the 6 minute reference edit
// that was 9 ms inside one refresh's picture the first time a drag crossed
// the title at 2:44 (its letters coming in one by one), against a 7.6 ms
// window, and the picture was three refreshes behind the hand. A text whose
// words are coming in is drawn as pieces, and the same text at rest as one
// picture, so a title is asked for at two moments: part way through its
// reveal and after it.

extension PhotonzDocument {

    /// One moment in the middle of each visible text's reveal, and one after
    /// it (the middle of the stretch, for words with no reveal), in order and
    /// once each. Empty for a document with no time.
    public func momentsToDrawWordsAhead() -> [Int] {
        guard hasTime else { return [] }
        var moments = Set<Int>()
        for layer in layers where layer.isVisible {
            guard let time = layer.time, time.outMS > time.inMS else { continue }
            Self.collectWordMoments(in: layer, stretch: time, into: &moments)
        }
        return moments.sorted()
    }

    /// `stretch` is the clock the text reads its reveal on: the stretch of
    /// the nearest layer holding it that has one (`motionClockMS`).
    private static func collectWordMoments(in layer: Layer, stretch: LayerTime, into moments: inout Set<Int>) {
        guard layer.isVisible else { return }
        let stretch = layer.time ?? stretch
        if case .group(let group) = layer.content {
            for child in group.children {
                collectWordMoments(in: child, stretch: stretch, into: &moments)
            }
            return
        }
        guard case .text(let text) = layer.content,
              !text.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        // The document moment a motion clock reading of `clock` lands on.
        let begins = stretch.inMS - stretch.sourceInMS
        let last = stretch.outMS - 1
        func kept(_ ms: Int) {
            guard ms >= stretch.inMS, ms <= last else { return }
            moments.insert(ms)
        }
        guard let reveal = text.reveal else {
            kept(stretch.inMS + (stretch.outMS - stretch.inMS) / 2)
            return
        }
        // Lines are left to the layout, which alone knows where they break:
        // one piece is enough to say how long the first takes.
        let pieces = TextReveal.spans(in: text.string, unit: reveal.unit)?.count ?? 1
        let length = max(1, reveal.lengthMS(count: max(1, pieces)))
        let home = begins + reveal.startMS + length
        kept(begins + reveal.startMS + length / 2)
        kept(home + max(0, stretch.outMS - home) / 2)
    }
}
