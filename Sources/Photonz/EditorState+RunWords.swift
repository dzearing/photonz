import CoreGraphics
import Foundation
import PhotonzCore
import PhotonzRender

/// A separated run of text says the words that are in it (Next,
/// `next-a-separated-row-says-its-words`).
///
/// Separate into Layers hands back a hundred and forty pieces called Text 1 to
/// Text 142, and the words are right there in each one's picture. This reads
/// them, so the layers list can be read and searched rather than counted.
///
/// Three rules decide the shape of it, and all three come out of the study
/// `docs/design/separate-reads-the-words.md`:
///
/// - **Nothing is put on the canvas, and nothing is an edit.** A reading is a
///   guess about pixels. It names a row and it does nothing else: no undo step
///   is spent, the file does not go edited, and a wrong word costs nothing but
///   a wrong word in a list. Turn into Text is still the one and only thing
///   that puts a guess ON the canvas, one run at a time, where one press takes
///   it back.
///
///   What the reading FOUND is kept, though, written into the document
///   alongside the layers (`ReadWords.swift`) so that opening a file full of
///   separated runs costs nothing and a row says the same words it said last
///   time. It is filed outside history and outside the saved baseline, so it
///   still spends no undo step and still leaves the file looking exactly as
///   edited as the person left it.
/// - **The words only, never the face.** `TextReader.read` also identifies the
///   family, the weight and the size, and the study measured that as where its
///   mistakes are: four of thirty one runs of this app's own window came back
///   in a face the window does not contain, all four called a confident
///   verdict, and the WORDS were right in every one. A row wants the
///   characters. `TextReader.words` stops there, costs about half as much on a
///   dense page, and answers on the sixty runs of that page whose face the app
///   cannot match at all.
/// - **After the command, never inside it.** Separate into Layers stays as fast
///   as it is. The reading starts once the pieces have landed and fills the
///   names in behind it, in the order the list draws them, so the rows nearest
///   the top say their words first.
@MainActor
extension EditorState {

    /// How many readings are handed to the list at a time.
    ///
    /// One at a time would be a hundred and forty rebuilds of a hundred and
    /// forty rows for one page. A whole page at a time would be one silent
    /// second and then everything at once. A dozen is about a tenth of a second
    /// of work per batch on a dense page, which reads as the list filling in.
    private static let wordsBatch = 12

    /// Reads the words off every separated run the app has not read yet.
    ///
    /// Safe to call as often as you like: a run whose words are already known
    /// is skipped, including one whose reading came back empty, so a picture
    /// with nothing readable in it is asked once and never again. "Already
    /// known" now spans saves as well as sessions, so a file that was saved
    /// with its readings in it opens with nothing pending at all and this does
    /// no work whatsoever.
    func readWordsOffRuns() {
        guard Experiments.shared.separatedRowSaysItsWordsEnabled, let document else { return }
        // In the order the layers list draws them, top down, so the rows a
        // person is looking at say their words first and the reading appears to
        // travel down the list.
        var seen = Set<ImageRef>()
        let pending: [(ref: ImageRef, image: CGImage)] = document
            .layerRows(expanded: document.openableGroupIDs, selected: [], marksOutOfView: false)
            .compactMap { document.layer(id: $0.id) }
            .filter { $0.isARunOfText == true }
            .compactMap { layer -> (ImageRef, CGImage)? in
                guard let ref = layer.imageRef, !document.readWords.hasBeenRead(ref),
                      seen.insert(ref).inserted, let image = store.image(for: ref)
                else { return nil }
                return (ref, image)
            }
        guard !pending.isEmpty else { return }

        // A second separation calls the first pass off rather than leaving both
        // grinding: the runs it had not reached are still unread, so the new
        // pass picks them up along with its own.
        wordReadingPass?.cancel()
        readingWordsOffPictures = true
        let batch = Self.wordsBatch
        wordReadingPass = Task { [weak self] in
            var next = 0
            while next < pending.count {
                let slice = Array(pending[next..<min(next + batch, pending.count)])
                next += batch
                // Off the main thread and at a priority that yields to anything
                // the person is doing: nothing on screen is waiting for this,
                // every row already says something, and the words arriving a
                // moment later is the whole design. A batch is spread over the
                // cores, so it costs about what its slowest single reading
                // costs rather than the sum of a dozen.
                let found = await Task.detached(priority: .utility) {
                    await withTaskGroup(of: (ImageRef, String).self) { group in
                        for (ref, image) in slice {
                            group.addTask { (ref, TextReader.words(in: image) ?? "") }
                        }
                        var landed: [(ImageRef, String)] = []
                        for await one in group { landed.append(one) }
                        return landed
                    }
                }.value
                guard !Task.isCancelled else { return }
                self?.rememberWords(found)
            }
            self?.readingWordsOffPictures = false
        }
    }

    /// Files what a batch came back with, into the document.
    ///
    /// An empty string is a real answer — this picture holds no words — and it
    /// is what stops the same switch or icon being read again every time the
    /// pass runs, or every time the file is opened.
    ///
    /// Written through `applyWithoutMarkingEdited` for two reasons at once: it
    /// is not something the person did, so it spends no undo step and reaches
    /// the steps already on the stack (undo a separation, do it again, and the
    /// reading is still there); and it must not make the file look edited,
    /// because nobody would understand a save prompt for words the app read to
    /// itself. It rides along with the next real save.
    private func rememberWords(_ found: [(ImageRef, String)]) {
        applyWithoutMarkingEdited { $0.readWords.remember(found) }
    }

    /// Calls off a reading in flight: a new document in this window, whose
    /// pictures are not these pictures.
    ///
    /// What was READ is not forgotten here any more, because it is not held
    /// here any more — it belongs to the document, and the outgoing document
    /// takes its own readings with it.
    func forgetWordsReadOffPictures() {
        wordReadingPass?.cancel()
        wordReadingPass = nil
        readingWordsOffPictures = false
        // What the runs of that document voted their family to be goes, though:
        // these are not those runs.
        familyTheRunsAreSetIn = [:]
        // And the readings already made in this window, for the same reason:
        // a line about labels that are not in front of anybody any more.
        rememberedReadings = []
    }

    /// What the layers list and the find field name a separated run from:
    /// empty while the flag is off, so the list is exactly the one it was.
    var readWordsForRows: [ImageRef: String] {
        guard Experiments.shared.separatedRowSaysItsWordsEnabled else { return [:] }
        return document?.readWords.byPicture ?? [:]
    }
}
