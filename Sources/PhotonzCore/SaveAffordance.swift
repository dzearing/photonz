import Foundation

/// What Save means for one editor window, right now.
///
/// A person meets Save in two places and they used to work the answer out
/// separately: the File menu decided whether the item was live, and the close
/// confirmation decided whether to ask at all. Nothing held them together, so a
/// recording could greet you with a dimmed Save and, a second later, a sheet
/// insisting there were unsaved changes — reported on 2026-09-18 as "the save
/// is disabled … I close the video and it still says do you want to save
/// changes". Both now read this one answer, and the invariant that they can
/// never contradict each other is a test rather than a hope.
///
/// It is pure on purpose: the app hands in a few plain facts and gets back the
/// whole affordance, so every combination of those facts can be checked without
/// a window on screen.
public enum SaveAffordance: String, Sendable, Equatable, CaseIterable, Codable {
    /// Nothing is loaded in this window yet — an empty window, or a recording
    /// still reading its own length. Save is dimmed and closing asks nothing.
    case nothingToSave
    /// Loaded, and what is on disk already matches. Save stays live, exactly as
    /// it does in any Mac app with an open unedited document: pressing it is a
    /// no-op that reports success.
    case upToDate
    /// Loaded, with edits that are not on disk. Save writes them and closing
    /// asks first.
    case unsavedChanges
    /// A save is running. Save stays live rather than dimming, because the
    /// close sheet is about to ask the same question and the two must not
    /// disagree; pressing either one now waits on the commit already in flight
    /// instead of starting a second.
    case saving
    /// Loaded, with edits, holding a recording that has never been saved
    /// anywhere. Command S on a video saves the project (the card answered on
    /// 2026-09-25), so Save is live and, like Save on any untitled document,
    /// opens the save box for a project that points at the recording; the
    /// recording itself is never written over. Closing asks, with Export beside
    /// Save, because a recording trimmed to send is one Export away.
    case unsavedRecording

    /// The whole affordance from the facts a window knows about itself.
    ///
    /// `isLoaded` is "there is something here to save into": a document for an
    /// image window, a recording whose length has been read for a video one.
    ///
    /// `isUnsavedRecording` is true where the window holds a recording that
    /// has not yet been saved as a project.
    public static func forDocument(isLoaded: Bool, hasChanges: Bool, isSaving: Bool,
                                   isUnsavedRecording: Bool = false) -> SaveAffordance {
        guard isLoaded else { return .nothingToSave }
        if isSaving { return .saving }
        guard hasChanges else { return .upToDate }
        return isUnsavedRecording ? .unsavedRecording : .unsavedChanges
    }

    /// Whether File ▸ Save is live.
    ///
    /// Deliberately not "there are changes": a live Save on an unchanged
    /// document is the Mac idiom, and, more importantly, it means this can only
    /// ever be false when there is nothing to lose. That is what makes the
    /// invariant below hold.
    public var isSaveEnabled: Bool { self != .nothingToSave }

    /// Whether closing this window has to stop and ask before it goes.
    public var asksBeforeClosing: Bool { closingOffersSave }

    /// Whether that question is "do you want to save the changes", with Save.
    public var closingOffersSave: Bool {
        self == .unsavedChanges || self == .saving || self == .unsavedRecording
    }

    /// Whether that same question offers Export beside Save: a recording
    /// trimmed to send leaves as a video from the sheet itself.
    public var closingOffersExport: Bool { self == .unsavedRecording }

    /// Whether pressing Save has real work to do, as opposed to reporting an
    /// immediate success. A save with nothing to write must still report
    /// success; a save that CANNOT write must report failure, and that is the
    /// `nothingToSave` case.
    public var savesSomething: Bool { closingOffersSave }
}
