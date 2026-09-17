import Foundation

/// What came of reading EVERY label in a separated picture at once, said in one
/// line (Next, `next-read-every-label`).
///
/// The singular reading's line names one label and the face it came out in
/// ("Save Changes, set in SF Pro Text Semibold"), which is exactly right for
/// one and says nothing useful about forty. Raised once per label it would also
/// be forty pills, last one wins. So the batch has its own line, and it carries
/// the three things a person cannot see by looking at the canvas: how many
/// labels are now words, what family they were all held to, and how many stayed
/// pictures.
///
/// The count of what stayed is the half nobody would otherwise find out about.
/// A label that could not be read looks identical to one that was: same
/// position, same pixels, no outline. Saying how many is what sends somebody to
/// look for them.
///
/// Why the whole picture is read together rather than a label at a time:
/// `docs/design/separate-reads-the-words.md`.
extension TextReading {
    public struct Batch: Hashable, Sendable {
        /// Labels that are words now.
        public let read: Int
        /// Labels that were asked and stayed pictures, because the family the
        /// page voted for could not account for their ink.
        public let stillPictures: Int
        /// The family the page settled on, which every label that came back is
        /// set in. Nil where nothing voted, and then nothing is claimed.
        public let family: String?

        public init(read: Int, stillPictures: Int, family: String?) {
            self.read = read
            self.stillPictures = stillPictures
            self.family = family
        }

        /// How many labels the reading was asked about.
        public var asked: Int { read + stillPictures }

        /// Whether anything at all changed in the document.
        public var landed: Bool { read > 0 }

        /// The verdict, in its own weight at the head of the pill.
        public var title: String {
            guard landed else { return stillPictures == 1 ? "Still a picture" : "Still pictures" }
            return "Turned into text"
        }

        /// The line under it.
        public var detail: String {
            guard landed else {
                guard asked > 1 else { return "It could not be read" }
                return "None of the \(asked) labels could be read"
            }
            var line = read == 1 ? "1 label" : "\(read) labels"
            // The face is named ONCE, for the page. It is the thing that might
            // be wrong, and naming it is what lets somebody look at the labels
            // and disagree — but over forty labels it is one fact about the
            // page, not forty facts about labels.
            if let family, !family.isEmpty { line += ", set in \(family)" }
            guard stillPictures > 0 else { return line }
            return stillPictures == 1
                ? "\(line). 1 stayed a picture"
                : "\(line). \(stillPictures) stayed pictures"
        }

        /// What the pill says while the reading is still going, for a picture
        /// dense enough that the answer is a second or two away.
        public static func working(labels: Int) -> String {
            labels == 1 ? "1 label" : "\(labels) labels"
        }

        /// And the verdict over it, which is the only one in the app that is
        /// not a verdict: it is what is happening right now.
        public static let workingTitle = "Reading the words"
    }
}
