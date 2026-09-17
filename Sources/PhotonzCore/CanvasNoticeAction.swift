import Foundation

/// The one thing a canvas notice may offer you to press.
///
/// The canvas notice (`CopyConfirmation`) is normally inert: it appears
/// unprompted, says its piece, and fades. That rule exists so nothing can turn
/// up under your pointer and take a click you meant for the canvas.
///
/// One case earns a narrow exception. When a key press is REFUSED and the app
/// already knows the single command that would let it through
/// (`RegionSliceRefusal.canBecomeAPicture` → `RasterizePrompt`), sending the
/// person off to find that command in a menu is three steps for an answer the
/// app has already worked out. So the refusal may carry its own way out.
///
/// The second case widens the exception by one step and keeps every part of
/// its shape. Separate into Layers raises a pill saying what came out of a
/// screenshot, and the thing a person wants next — the words in those labels —
/// was a menu row under a menu row that nothing pointed at
/// (`docs/design/separate-reads-the-words.md`). So the pill offers it, once,
/// on the result they are already looking at.
///
/// The third case is not an offer at all: it is the REPORT being reachable.
/// A line that counts something a person cannot otherwise find — three labels
/// that stayed pictures among forty that did not — is true and useless, so the
/// count of them is also the way to them, pressed in the line rather than as a
/// button on the end of it (`Presentation`).
///
/// Deliberately three cases and not a framework: a notice carries at most ONE
/// action, it is always the obvious next move on the thing the notice is
/// about, and it never replaces a permanent home for the same command. The
/// button is a shortcut to the Layer menu row, never the only door to it.
public enum CanvasNoticeAction: Hashable, Sendable {
    /// Turn the layer the refusal was about into a picture, question and all
    /// (`RasterizePrompt`). Carries the layer id captured at the moment of the
    /// refusal: what is selected can change between the refusal and the press,
    /// and a button that bakes whatever happens to be picked NOW would destroy
    /// the wrong layer.
    case turnIntoPicture(layer: UUID)

    /// Read the words in every run a separation just made
    /// (`next-read-every-label`). Carries the runs captured at the moment the
    /// separation landed, for the same reason the case above carries its
    /// layer: selection changes the instant somebody clicks the canvas, and a
    /// button that read whatever happens to be picked NOW would rewrite the
    /// wrong labels.
    case readTheWords(runs: [UUID])

    /// Pick the labels a reading gave up on (`TextReading.Batch`), so the count
    /// of them is also the way to them.
    ///
    /// The third case, and the one that widens the exception in a different
    /// direction: it is not an offer to run a command, it is the report itself
    /// being reachable. A label that stayed a picture looks exactly like one
    /// that came back, so "3 stayed pictures" over a screenshot of forty is a
    /// true sentence a person cannot act on. Carries the labels counted at the
    /// moment the reading landed, for the same reason as the two above.
    case findStillPictures(labels: [UUID])

    /// The layers this action would act on.
    public var layerIDs: [UUID] {
        switch self {
        case .turnIntoPicture(let id): return [id]
        case .readTheWords(let runs): return runs
        case .findStillPictures(let labels): return labels
        }
    }

    /// Where in the pill the action is pressed.
    public enum Presentation: Hashable, Sendable {
        /// A capsule button at the end of the line, after a hairline. What an
        /// OFFER looks like: the line reports, the button answers it.
        case button
        /// The words in the line itself. What a report that is its own way
        /// onward looks like: bolting a button on the end would read as a
        /// second thing to do, when there is only one thing here and the
        /// sentence already names it.
        case wordsInTheLine
    }

    /// See `Presentation`.
    public var presentation: Presentation {
        switch self {
        case .turnIntoPicture, .readTheWords: return .button
        case .findStillPictures: return .wordsInTheLine
        }
    }

    /// What the button says. The same words as the menu row, minus its
    /// ellipsis: on a button three dots read as "more options", and the
    /// question that follows is one press away from either door anyway.
    public var label: String {
        switch self {
        case .turnIntoPicture:
            return RasterizePrompt.menuItem.replacingOccurrences(of: "\u{2026}", with: "")
        // NOT the menu row's own name. "Turn into Text" on a row means that
        // row; on a pill that has just counted forty pieces it would be a
        // promise about which forty is anybody's guess. This says what the
        // press gets you, in the words the study used for it.
        case .readTheWords: return "Read the Words"
        // The count itself, in the words the line already uses for it. Built
        // from `TextReading.Batch` so the sentence and the thing pressed can
        // never say two different numbers (`Batch.stayedPictures`).
        case .findStillPictures(let labels):
            return TextReading.Batch.stayedPictures(labels.count)
        }
    }

    /// The key that does the same thing, shown on the button. The pointer is
    /// not the only way in, and this is where a person learns a key that keeps
    /// working long after the pill has gone.
    ///
    /// Nil where the command has no key. Showing one that does not exist
    /// teaches something false, and Turn into Text is deliberately unbound:
    /// nothing in Photoshop's set is free for it and it is not a command
    /// anybody runs in a stream.
    public var shortcutHint: String? {
        switch self {
        case .turnIntoPicture: return "\u{21E7}\u{2318}R"
        case .readTheWords, .findStillPictures: return nil
        }
    }
}
