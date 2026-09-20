import AppKit
import PhotonzCore

/// Says, in the bottom-right corner, that a recording is being saved and then
/// that it saved.
///
/// Saving a trimmed recording re-encodes it. Before this, the whole report was
/// the small arrow on the floating controller swapping itself for a spinner and
/// then going away — reported as "I click Save and it does nothing"
/// (2026-09-19). Copying a recording already ends with a toast in the corner;
/// this is saving doing the same, with the rules for WHEN in `SaveFeedback`.
///
/// The corner, rather than something inside the window, because of the third
/// way into a save: Save in the close confirmation runs the commit and the
/// WINDOW GOES when it lands. An in-window confirmation cannot exist for that
/// one, and the whole point is that all three ways say the same thing.
@MainActor
final class RecordingSaveAnnouncer {
    /// One save in flight. Handed back to `finished` / `failed` so a second
    /// save starting meanwhile can never dismiss the first one's bar.
    @MainActor
    final class Report {
        let url: URL
        /// Fires after `SaveFeedback.quietWindow`, if the save is still going.
        var reveal: Task<Void, Never>?
        /// Nil until the quiet window passes: a short save never makes one.
        var progress: ToastProgress?
        /// The last fraction the encoder reported, kept so progress that
        /// arrives before the bar exists is not thrown away.
        var fraction: Double = 0
        init(url: URL) { self.url = url }
    }

    private let toasts: ToastController
    private let store: CaptureStore
    private let screen: () -> NSScreen
    private let open: (URL) -> Void

    /// `open` is what the toast's Edit does: bring the recording back up.
    init(toasts: ToastController, store: CaptureStore,
         screen: @escaping () -> NSScreen, open: @escaping (URL) -> Void) {
        self.toasts = toasts
        self.store = store
        self.screen = screen
        self.open = open
    }

    /// A commit that will really write something has started. Nothing is drawn
    /// yet: a save that lands inside the quiet window says nothing until it is
    /// done, because a bar that flashes up for a fifth of a second is a flicker
    /// nobody can read rather than a report.
    func began(url: URL) -> Report {
        let report = Report(url: url)
        report.reveal = Task { [weak self, weak report] in
            try? await Task.sleep(for: .seconds(SaveFeedback.quietWindow))
            guard !Task.isCancelled, let self, let report else { return }
            let progress = self.toasts.presentProgress(
                title: SaveFeedback.progressTitle(for: url.lastPathComponent),
                symbol: "arrow.down.doc",
                on: self.screen())
            progress.update(fraction: report.fraction)
            report.progress = progress
        }
        return report
    }

    /// How far the encoder has got. Held even before the bar exists, so the bar
    /// arrives already showing the truth instead of starting at zero.
    func report(_ report: Report, encoded: Double) {
        report.fraction = SaveFeedback.commitFraction(encoded: encoded)
        report.progress?.update(fraction: report.fraction)
    }

    /// The recording is written: take the bar down and say so, named, with the
    /// recording's own thumbnail, in the same toast copying a recording uses.
    func finished(_ report: Report) {
        clear(report)
        let url = report.url
        let entry = store.entries.first(where: { $0.url == url })
        toasts.present(entry: entry, store: store,
                       message: SaveFeedback.savedMessage(for: url.lastPathComponent),
                       on: screen(),
                       editAction: .onHover,
                       onEdit: { [open] in open(url) })
    }

    /// The commit failed. The bar goes, and nothing else is said here: the
    /// window puts up a sheet naming what went wrong and what is still safe,
    /// and a cheerful corner toast next to it would be noise.
    func failed(_ report: Report) {
        clear(report)
    }

    private func clear(_ report: Report) {
        report.reveal?.cancel()
        report.reveal = nil
        if let progress = report.progress {
            toasts.dismissProgress(progress)
            report.progress = nil
        }
    }
}
