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
/// It is pure on purpose: the app hands in three plain facts and gets back the
/// whole affordance, so every combination of those facts can be checked without
/// a window on screen.
public enum SaveAffordance: String, Sendable, Equatable, CaseIterable, Codable {
    /// Nothing is loaded in this window yet — an empty window, or a recording
    /// still reading its own length — or it holds something untouched that
    /// has nowhere to be saved to. Save is dimmed and closing asks nothing.
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
    /// Loaded, with edits, in a window that has nowhere to save them in place:
    /// a recording opened as a document, until the Command S question is
    /// answered. Save stays dimmed, and closing still asks, because the edits
    /// are work: the sheet offers the two doors that keep them, Save As, which
    /// writes a project pointing at the recording, and Export, which writes a
    /// video. (The name predates Save As reaching recordings; it is kept
    /// because walks and logs read it.)
    case changesOnlyExportKeeps

    /// The whole affordance from the three facts a window knows about itself.
    ///
    /// `isLoaded` is "there is something here to save into": a document for an
    /// image window, a recording whose length has been read for a video one.
    ///
    /// `canSaveInPlace` is false where Save has nowhere safe to write this
    /// window's contents at all.
    public static func forDocument(isLoaded: Bool, hasChanges: Bool, isSaving: Bool,
                                   canSaveInPlace: Bool = true) -> SaveAffordance {
        guard isLoaded else { return .nothingToSave }
        guard canSaveInPlace else { return hasChanges ? .changesOnlyExportKeeps : .nothingToSave }
        if isSaving { return .saving }
        return hasChanges ? .unsavedChanges : .upToDate
    }

    /// Whether File ▸ Save is live.
    ///
    /// Deliberately not "there are changes": a live Save on an unchanged
    /// document is the Mac idiom, and, more importantly, it means this can only
    /// ever be false when there is nothing to lose, or when closing stops to
    /// offer Export instead. That is what makes the invariant below hold.
    public var isSaveEnabled: Bool { self != .nothingToSave && self != .changesOnlyExportKeeps }

    /// Whether closing this window has to stop and ask before it goes.
    public var asksBeforeClosing: Bool { closingOffersSave || closingOffersExport }

    /// Whether that question is "do you want to save the changes", with Save.
    public var closingOffersSave: Bool { self == .unsavedChanges || self == .saving }

    /// Whether that question instead offers Export, because Save has nowhere
    /// to write the changes in place.
    public var closingOffersExport: Bool { self == .changesOnlyExportKeeps }

    /// Whether that same question offers Save As beside Export: somewhere new
    /// is always a place the changes can go, even where Save has none.
    public var closingOffersSaveAs: Bool { self == .changesOnlyExportKeeps }

    /// Whether pressing Save has real work to do, as opposed to reporting an
    /// immediate success. A save with nothing to write must still report
    /// success; a save that CANNOT write must report failure, and that is the
    /// `nothingToSave` case.
    public var savesSomething: Bool { self == .unsavedChanges || self == .saving }
}
