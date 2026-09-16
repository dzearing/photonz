import Foundation

/// What is STILL in a picture after Separate into Layers, said somewhere that
/// does not fade.
///
/// The command's own answer is the notice pill: how many pieces came out, how
/// many stayed, and that running it again takes the next batch. On a dense
/// capture that is "142 runs of text and 4 boxes. 580 left in the picture, run
/// it again for more", and 3 seconds later there is nothing on screen that says
/// so. Somebody who looked away has no way back to 580 except running the
/// command again and reading fast — which is the one thing that CHANGES the
/// number they were trying to read.
///
/// So the count moves to the one place that keeps it: the second line of the
/// picture's own row in the layers list, the same slot a component row uses to
/// say whether it is the original or a copy (`ComponentRowNote`). It is where
/// the eye already is the instant after a separation, because the layers list
/// is the thing that just changed, and it is on the row of the thing that is
/// still holding the 580.
///
/// The value is session chrome. It never enters the document and never enters
/// the undo history; the app holds it against the picture's BITMAP rather than
/// against the layer, so undoing a separation — which puts the original bitmap
/// back — takes the note with it rather than leaving "580 left" sitting over a
/// picture that now holds all 724 again.
public struct SeparationLeftover: Hashable, Sendable {
    /// What came out, so a picture that came apart completely can say so
    /// rather than saying nothing.
    public let runs: Int
    public let boxes: Int
    /// Read, and left, because the app could not be confident about it. Another
    /// run finds exactly these and refuses them exactly the same way.
    public let skipped: Int
    /// Read perfectly well and left because one command only takes so much
    /// (`SeparateBudget`). THESE are the ones another run reaches.
    public let crowded: Int

    public init(runs: Int, boxes: Int, skipped: Int, crowded: Int) {
        self.runs = runs
        self.boxes = boxes
        self.skipped = skipped
        self.crowded = crowded
    }

    /// Everything still in the picture, for both reasons at once, because that
    /// is the number a person can check by looking at the picture. It is the
    /// pill's own number, kept.
    public var count: Int { skipped + crowded }

    /// Whether another run would reach anything. Only a piece the limit crowded
    /// out comes back: the ones left as unreadable are found and refused the
    /// same way every time, so offering a second run for those is an offer to
    /// do nothing.
    public var offersAnotherBatch: Bool { crowded > 0 }

    /// Whether the picture has anything worth saying at all. Always true: a
    /// picture that came apart completely says so, which is the difference
    /// between "done" and "nobody ever told me".
    private var cameApart: Bool { runs + boxes > 0 }

    /// The line the row prints under the picture's name.
    ///
    /// **Eighteen characters, and that is measured, not a taste.** The line
    /// shares a narrow row with a thumbnail, a padlock and an eye, which on the
    /// dock's own width leaves it about 95 points: "Nothing left to separate"
    /// came out of the app reading "Nothing left to sep…". So each answer is cut
    /// to the shortest true phrase, the COUNT comes first so truncation can only
    /// ever eat the tail, and the sentence a person needs to make sense of it
    /// lives in `help`, one hover away.
    public var text: String {
        guard count > 0 else {
            // Two different nothings and saying the wrong one is a lie. A
            // picture that gave up its pieces is finished; one that never had
            // any is not a screenshot.
            return cameApart ? "Nothing left" : "Nothing readable"
        }
        // A photograph of a mountain finds hundreds of pieces in the grass,
        // none readable and none anything a person would point at. Counting
        // those out loud is a true sentence about texture and a useless one
        // about the photograph: past a handful the plain answer is the honest
        // one, which is the rule the pill already follows
        // (`CopyConfirmation.unreadableWorthNaming`).
        guard cameApart || count <= CopyConfirmation.unreadableWorthNaming else {
            return "Nothing readable"
        }
        guard offersAnotherBatch else { return "\(count) left, unclear" }
        return "\(count) left"
    }

    /// The sentence hovering the line explains, for somebody who has come back
    /// to this picture an hour later and does not remember what it is counting.
    public var help: String {
        guard count > 0 else {
            return cameApart
                ? "Every run of text and every box in this picture is now a layer of its own."
                : "\(Self.nothingReadable). Separate into Layers works on a screenshot of an interface."
        }
        guard cameApart || count <= CopyConfirmation.unreadableWorthNaming else {
            return "\(Self.nothingReadable). Separate into Layers works on a screenshot of an interface."
        }
        let pieces = count == 1 ? "1 piece is" : "\(count) pieces are"
        guard offersAnotherBatch else {
            return "\(pieces) still in this picture. The app could not read them confidently, so it left them where they are."
        }
        return "\(pieces) still in this picture. Separating it again takes the next batch."
    }

    /// What the link beside the count says. The same words as the menu row it
    /// stands in for, plus the word that says this is not the first run.
    public static let againLabel = "Separate again"

    /// The same count said in full, for the line at the foot of the layers
    /// list. The row can say "580 left" because it is printed on the picture it
    /// is counting; a line under the whole list has to name what it is about.
    public static func stillInThePicture(_ count: Int) -> String {
        count == 1 ? "1 left in the picture" : "\(count) left in the picture"
    }

    private static let nothingReadable = "Nothing here reads as text or a box"
}
