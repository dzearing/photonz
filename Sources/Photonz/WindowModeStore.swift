import Foundation
import Observation
import PhotonzCore

/// Which mode the app is in, and what each mode is holding
/// (Next, `next-window-modes`).
///
/// A mode is a named bundle of the panel choices `PanelSectionVisibilityStore`
/// already keeps, so this store owns no arrangement of its own: it hands the
/// panel store a new set on a swap and takes the old one back. That is what
/// keeps a mode from being a second mechanism, and it is why turning a section
/// off by hand while in a mode is not a conflict but simply the mode, bent.
///
/// **One store for the whole app**, like the panel choices it drives and for
/// the same reason: the arrangement it moves is app-wide, so a mode that was
/// per-window would be two settings fighting over one value. The study wants
/// two windows onto one file in two different modes, and that wants the panel
/// choices to become per-window first; it is written up on the task rather than
/// half-built here.
///
/// **Kept per release.** The key carries the running release's namespace, the
/// way the panel choices and the feature flags do.
@MainActor
@Observable
final class WindowModeStore {
    static let shared = WindowModeStore()

    /// Where the mode is written, under the running release's own namespace:
    /// `experiments.next.windowMode`.
    static func defaultsKey(for release: Release) -> String {
        "\(release.storageNamespace).windowMode"
    }

    private let key: String

    /// The mode, and the arrangement each bent mode is holding.
    private(set) var session: WindowModeSession {
        didSet {
            guard session != oldValue else { return }
            write()
        }
    }

    private init() {
        key = Self.defaultsKey(for: Experiments.shared.release)
        session = Self.read(key)
    }

    var mode: WindowMode { session.mode }

    /// What the chip reads: the mode's name, and whether you have bent it.
    ///
    /// Read against the panel's live choices rather than against a copy, so a
    /// switch ticked in the Sections list at the foot of the panel turns the
    /// chip to "Icon, edited" in the same frame.
    var label: String {
        session.chipLabel(with: PanelSectionVisibilityStore.shared.choices)
    }

    var isBent: Bool {
        session.isBent(with: PanelSectionVisibilityStore.shared.choices)
    }

    /// Move the window into another mode. The mode being left keeps whatever
    /// you did to it, so coming back lands on the window you left.
    func swap(to id: String) {
        let panel = PanelSectionVisibilityStore.shared
        var next = session
        panel.choices = next.swap(to: id, leaving: panel.choices)
        session = next
    }

    /// Put this mode back the way it shipped, without leaving it.
    func resetCurrent() {
        let panel = PanelSectionVisibilityStore.shared
        var next = session
        panel.choices = next.resetCurrent()
        session = next
    }

    /// Hand the lot back: every section follows the document again, which is
    /// the window of somebody who never touched a mode. The mode being left
    /// keeps its arrangement, so this is a way out and never a way to lose one.
    func showEverything() {
        let panel = PanelSectionVisibilityStore.shared
        var next = session
        panel.choices = next.showEverything(leaving: panel.choices)
        session = next
    }

    /// Reads the mode back off disk. Only a scripted walk asking the app to
    /// forget it needs this: it wipes the setting after the app has read it.
    func reload() { session = Self.read(key) }

    // MARK: Written down

    private static func read(_ key: String) -> WindowModeSession {
        guard let stored = UserDefaults.standard.string(forKey: key),
              let data = stored.data(using: .utf8),
              let session = try? JSONDecoder().decode(WindowModeSession.self, from: data)
        else { return WindowModeSession() }
        return session
    }

    private func write() {
        guard let data = try? JSONEncoder().encode(session),
              let stored = String(data: data, encoding: .utf8) else { return }
        UserDefaults.standard.set(stored, forKey: key)
    }
}
