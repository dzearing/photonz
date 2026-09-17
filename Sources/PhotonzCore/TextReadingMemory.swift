import CoreGraphics
import Foundation

/// A reading that has landed, kept so its line can be said again after it
/// fades (Next, `next-read-every-label`).
///
/// The line at the foot of the canvas counts what the reading gave up on, and
/// that count is the only way to those labels: they look exactly like the ones
/// that came back. It lasts six seconds. Somebody who reads it, clicks the
/// canvas to look at something and then wants the three stragglers had no way
/// back at all — nothing remembered which labels those were, so getting the
/// count again meant reading the whole page a second time, which is real work
/// for an answer the app already had.
///
/// So the reading is kept for as long as the document is open, and asking for
/// it again says it again at once. What is kept is deliberately small: which
/// labels became words, which stayed pictures and where they were, and the
/// family the page was held to. No pixels, no reading, nothing the document
/// would have to carry — it is session chrome, exactly like the family vote
/// beside it, so a file saved with this on is byte for byte an ordinary file.
///
/// The one thing it must never do is say something that has stopped being
/// true. `standing(given:)` is where that is decided, row by row, against the
/// document as it is NOW.
extension TextReading {
    /// What a row looks like now, as far as a remembered reading cares.
    /// A row that is in neither state — cropped, locked, turned, or gone from
    /// the document — is simply absent, and absent means forgotten.
    public enum RowNow: Hashable, Sendable {
        /// It is words, which is what a label the reading landed looks like.
        case words
        /// It is still a picture, drawn in this box.
        case stillAPicture(box: CGRect)
    }

    public struct Remembered: Hashable, Sendable {
        /// A label the reading gave up on, and the box it filled when it did.
        ///
        /// The box is kept because the words are set at the size the picture
        /// holds them at: a label somebody has since stretched is not the
        /// label the reading gave up on, and it deserves a real second look
        /// rather than a remembered no.
        public struct StillAPicture: Hashable, Sendable {
            public let id: UUID
            public let box: CGRect

            public init(id: UUID, box: CGRect) {
                self.id = id
                self.box = box
            }
        }

        /// The labels that came back as words, in the order the document holds
        /// them.
        public let read: [UUID]
        /// The labels that stayed pictures, in the same order.
        public let stayed: [StillAPicture]
        /// The family the page settled on, named once in the line.
        public let family: String?

        public init(read: [UUID], stayed: [StillAPicture], family: String?) {
            self.read = read
            self.stayed = stayed
            self.family = family
        }

        /// The labels the count is about, which is what pressing it picks
        /// (`CanvasNoticeAction.findStillPictures`).
        public var labels: [UUID] { stayed.map(\.id) }

        /// The line, built from the counts rather than stored, so a reading
        /// said again and the reading said the first time can never disagree
        /// about the same labels.
        public var batch: Batch {
            Batch(read: read.count, stillPictures: stayed.count, family: family)
        }

        /// Whether there is anything here worth saying again.
        ///
        /// Both halves have to be there. With nothing left a picture the line
        /// is a plain report with no count to press, and with nothing landed
        /// the whole line is already about what stayed, with nothing to pick
        /// them out FROM (`Batch.stillPicturesTail`). Either way there is no
        /// way onward to hand back.
        public var isWorthKeeping: Bool { !read.isEmpty && !stayed.isEmpty }

        /// What is left of this reading, given how its rows look now, or nil
        /// where it has stopped describing the document.
        ///
        /// Narrowed, not refused, for the two things that happen to a row on
        /// its own: a label deleted since, and a label somebody read or
        /// retyped by hand. Both leave a smaller true line, and a smaller true
        /// line is worth more than silence.
        ///
        /// Refused outright for the two that mean the reading itself no longer
        /// holds: a label that came back and is a picture again, which is undo
        /// taking the whole reading off, and a straggler drawn in a different
        /// box, which is a label that has changed since the reading gave up on
        /// it. Both send the ask through to a real reading, which is the
        /// honest answer.
        public func standing(given rows: [UUID: RowNow]) -> Remembered? {
            var landed: [UUID] = []
            for id in read {
                switch rows[id] {
                case .words: landed.append(id)
                case .stillAPicture: return nil
                case nil: continue
                }
            }
            var left: [StillAPicture] = []
            for label in stayed {
                switch rows[label.id] {
                case .stillAPicture(let box) where box == label.box: left.append(label)
                case .stillAPicture: return nil
                case .words, nil: continue
                }
            }
            let narrowed = Remembered(read: landed, stayed: left, family: family)
            return narrowed.isWorthKeeping ? narrowed : nil
        }
    }
}
