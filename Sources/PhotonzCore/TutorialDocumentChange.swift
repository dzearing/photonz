import Foundation

// What a video guide waits for, read off the document.
//
// The Video track asks a person to trim, cut, bring a clip in, key a title, put
// a transition on a cut and retype a caption. Each has several ways in: Q is
// also a Video menu row and a row on the clip's right click, a clip arrives
// from the Library or from the Finder, a transition from the tiles at a cut or
// from Command T. Wiring an event into each of those would be a dozen wires per
// step, and the one nobody wired is the one a person uses.
//
// Every one of them lands in the document through `EditorState.perform`,
// though. So the step asks one question there, of the document before the edit
// and after it: did THIS kind of thing just happen? Only the question the
// waiting step asks is worked out, so an edit made while no guide waits costs
// nothing at all.

public enum TutorialDocumentChange {

    /// Whether the edit that turned `before` into `after` is the kind of thing
    /// `trigger` waits for. False for every trigger the app announces itself.
    public static func happened(_ trigger: TutorialTrigger, from before: PhotonzDocument,
                                to after: PhotonzDocument) -> Bool {
        switch trigger {
        case .timeTakenOut:
            return after.documentDurationMS < before.documentDurationMS
        case .clipCut:
            return cutCount(after) > cutCount(before)
        case .clipAdded:
            return clipCount(after) > clipCount(before)
        case .titleAdded:
            return titleCount(after) > titleCount(before)
        case .keyAdded:
            return keyCount(after) > keyCount(before)
        case .transitionAdded:
            return transitionCount(after) > transitionCount(before)
        case .captionRetyped:
            return captionWasRetyped(from: before, to: after)
        default:
            return false
        }
    }

    // MARK: - The counts

    /// Clips that play a recording. Sounds on their own are not clips here:
    /// the guide about a second clip is about pictures.
    private static func clips(_ document: PhotonzDocument) -> [Layer] {
        document.allLayers.filter { $0.movie != nil }
    }

    private static func clipCount(_ document: PhotonzDocument) -> Int {
        clips(document).count
    }

    /// Joins inside clips: a clip in three pieces has two.
    private static func cutCount(_ document: PhotonzDocument) -> Int {
        clips(document).reduce(0) { $0 + max(0, ($1.clipPieces?.count ?? 1) - 1) }
    }

    /// Text layers with words in them that are not captions.
    private static func titleCount(_ document: PhotonzDocument) -> Int {
        document.allLayers.filter { layer in
            guard !layer.isCaption, let text = layer.text else { return false }
            return !text.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }.count
    }

    /// Every key on every value, counted the way the panel's diamonds count
    /// them.
    private static func keyCount(_ document: PhotonzDocument) -> Int {
        document.allLayers.reduce(0) { total, layer in
            total + layer.keyableProperties.reduce(0) {
                $0 + document.keyCount(layerID: layer.id, $1)
            }
        }
    }

    /// Transitions on cuts between clips and on joins inside one.
    private static func transitionCount(_ document: PhotonzDocument) -> Int {
        document.allLayers.reduce(0) { total, layer in
            let arriving = layer.arrivalTransition == nil ? 0 : 1
            let joins = layer.clipPieces?.pieces.filter { $0.transitionIn != nil }.count ?? 0
            return total + arriving + joins
        }
    }

    /// A caption that was there before has different words now. Captions
    /// arriving or going are the machine listening or somebody clearing them,
    /// and neither is correcting a word.
    private static func captionWasRetyped(from before: PhotonzDocument,
                                          to after: PhotonzDocument) -> Bool {
        var said: [UUID: String] = [:]
        for caption in before.captionLayers {
            if let text = caption.text { said[caption.id] = text.string }
        }
        guard !said.isEmpty else { return false }
        return after.captionLayers.contains { caption in
            guard let was = said[caption.id], let now = caption.text?.string else { return false }
            return was != now
        }
    }
}
