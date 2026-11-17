import Foundation
import PhotonzCore
import PhotonzMedia

/// **What a busy lane paints, read off the document once, not once a frame**
/// (`the-timeline-of-an-hour-long-edit-scrolls-zooms`, pass 7).
///
/// A lane that paints its clips (`TimelinePaint`) worked out, on every frame
/// of a zoom, what each clip on its stretch is: its layer looked up by id, its
/// pieces, keys, holds, fades, level and badges, and for each cut its
/// transition. Near the whole-hour view that is every clip of the edit, and
/// on the 60 minute reference edit it was about a fifth of each zoom frame,
/// for answers that do not change while the timeline zooms or scrolls.
///
/// So they are kept beside the document they were read off, and thrown away
/// the moment the document's layers or tracks are written
/// (`PhotonzDocument.sharesWorkedOutAnswers`) or a switch they depend on
/// flips. What changes with the view (where a clip is, how strongly its
/// pictures show, whether it is picked or under the pointer) is never kept
/// here: the lane works that out each frame.
@MainActor
final class TimelinePaintedFacts {

    /// One clip's document facts, as the painting reads them.
    struct Clip {
        /// The first piece, for the stretch of the file a waveform is read
        /// from, and the piece count, holds and badges the painting skips.
        var piece: ClipPiece?
        var pieceCount = 0
        var isHeld = false
        var pictureHidden = false
        /// A badge on the bar as a picture, and as a sound of its own.
        var hasBadge = false
        var hasSoundBadge = false
        var hasKeys = false
        var hasDrift = false
        var level = AudioLevel()
        /// A gain, a noise cleaning or a cleaned piece: a badge on the sound.
        var levelHasBadge = false
        /// The sound its first piece plays, when it plays one.
        var playedSound: SoundRef?
        /// The picture's fades, when the timeline's fade verbs reach it.
        var fadeInMS = 0
        var fadeOutMS = 0
        var fadeCurve: EasingCurve = .linear
        var movie: MovieRef?
    }

    /// A cut at rest as the painting draws it, or nil for one it leaves to its
    /// view (a hold on black or white).
    typealias Cut = TimelinePaintedCuts.Mark?

    /// The switches the facts were read under: a flip reads them again.
    struct Switches: Equatable {
        var keys: Bool
        var cutRecording: Bool
        var pictureFades: Bool
        var transitions: Bool
    }

    private var document: PhotonzDocument?
    private var switches: Switches?
    private var clips: [UUID: Clip?] = [:]
    private var cuts: [TimelineCutKey: Cut] = [:]

    /// The facts are kept for `document` under `switches`: anything kept for
    /// another document, or under other switches, is let go.
    private func keep(for document: PhotonzDocument, _ switches: Switches) {
        if let kept = self.document, kept.sharesWorkedOutAnswers(with: document), self.switches == switches {
            return
        }
        self.document = document
        self.switches = switches
        clips.removeAll(keepingCapacity: true)
        cuts.removeAll(keepingCapacity: true)
    }

    /// The clip's facts in `document`, worked out by `make` the first time it
    /// is asked for this document. Nil (no layer) is kept too.
    func clip(_ id: UUID, in document: PhotonzDocument, _ switches: Switches, make: () -> Clip?) -> Clip? {
        keep(for: document, switches)
        if let kept = clips[id] { return kept }
        let made = make()
        clips[id] = .some(made)
        return made
    }

    /// The cut's mark in `document`, worked out by `make` the first time.
    func cut(_ id: TimelineCutKey, in document: PhotonzDocument, _ switches: Switches, make: () -> Cut) -> Cut {
        keep(for: document, switches)
        if let kept = cuts[id] { return kept }
        let made = make()
        cuts[id] = .some(made)
        return made
    }
}

/// A cut told by the two clips that meet there. A cut's own `id` is text made
/// from both clips' ids each time it is read, and the busy lanes read it for
/// every cut on every frame of a zoom: about a third of the time the painted
/// cuts took near the whole-hour view (2026-11-17).
struct TimelineCutKey: Hashable {
    let outgoing: UUID
    let incoming: UUID

    init(_ point: TimelineEditPoint) {
        outgoing = point.outgoing
        incoming = point.incoming
    }
}
