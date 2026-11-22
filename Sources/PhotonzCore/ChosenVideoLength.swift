import Foundation

// **A new video keeps the length it was given until something longer lands
// on it.**
//
// File > New Video at ten seconds, a four second title page put on it, and
// the video was four seconds long: every edit that touches time writes the
// length again as the end of the last clip (`refreshDuration`, `applyTrim`,
// `followLastClip`), and the title was all there was. The person chose ten,
// so ten is a floor under all of them. Something longer still makes the
// video longer, and taking it away goes back to ten, not to the title.
//
// A recording, a cut and anything else not started with New Video has no
// chosen length and is as long as what is in it, exactly as before.

extension PhotonzDocument {

    /// A written length shorter than the one the video was made with is put
    /// back up to it. Nothing for a document with no time or no chosen
    /// length.
    mutating func keepChosenLength() {
        guard let chosen = chosenLengthMS else { return }
        guard let written = durationMS else { return }
        if written < chosen { durationMS = chosen }
    }
}
