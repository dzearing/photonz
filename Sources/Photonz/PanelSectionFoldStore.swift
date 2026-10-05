import Foundation
import Observation
import PhotonzCore

/// Which sections of one window's right hand panel are folded, with one
/// watched cell per section, so folding one tells that section and nothing
/// else.
///
/// The folds used to be the panel's own stored setting, and a fold rebuilt the
/// whole panel: every section's body ran again and the dock was laid out from
/// scratch, 20 to 70ms a click with a clip picked, Appearance the worst. Kept
/// to the section, the same folds measured 5 to 15ms
/// (`section-fold-motion-walk`, 2026-10-04). The panel itself only hears about
/// a fold when it changes how much height the dock's lists get (see
/// `InspectorPanel.toggleCollapsed`) or when the setting was written from
/// outside every panel (`syncs`).
///
/// Still ONE setting on disk, `inspector.collapsed`, in the words it always
/// had, so folds survive a launch, every window folds alike, and every other
/// reader of the key still works. A fold moves the window it was clicked in
/// at once; every other window follows once that motion has settled, without
/// a motion of its own that nobody is watching: two windows animating every
/// fold together was what was still left over a frame on a rectangle's
/// Appearance (2026-10-04).
@MainActor @Observable
final class PanelSectionFoldStore {
    /// Goes up when the folds changed from outside every panel: a walk
    /// forgetting them, the Measurements pill opening its section. The panel
    /// reads it, so that is the one kind of fold that rebuilds the panel.
    private(set) var syncs = 0

    /// Run when a fold made in another window has landed here, so this
    /// window's panel can ask whether it moved its height budget.
    @ObservationIgnored var onFoldFromAnotherWindow: (() -> Void)?

    @ObservationIgnored private var folds = PanelSectionFolds(stored: nil)
    @ObservationIgnored private var cells: [InspectorSectionID: PanelFoldCell] = [:]
    @ObservationIgnored private var isAttached = false
    /// A fold another window made, on its way here.
    @ObservationIgnored private var expected: PanelSectionFolds?

    /// Nothing is read or watched until the panel first asks: SwiftUI makes a
    /// throwaway one of these every time the panel's parent is redrawn.
    init() {}

    /// A section's own cell. Reading it in a body is what ties that body,
    /// and only that body, to the section's fold.
    func cell(_ id: InspectorSectionID) -> PanelFoldCell {
        attach()
        if let cell = cells[id] { return cell }
        let cell = PanelFoldCell(isFolded: folds.contains(id.rawValue))
        cells[id] = cell
        return cell
    }

    /// Whether a section is folded, read without tying the reader to it.
    func isFolded(_ id: InspectorSectionID) -> Bool {
        attach()
        return folds.contains(id.rawValue)
    }

    func toggle(_ id: InspectorSectionID) {
        attach()
        var next = folds
        next.toggle(id.rawValue)
        apply(next)
    }

    /// Opens a section, and says whether it was folded at all.
    @discardableResult
    func open(_ id: InspectorSectionID) -> Bool {
        attach()
        var next = folds
        guard next.open(id.rawValue) else { return false }
        apply(next)
        return true
    }

    private func apply(_ next: PanelSectionFolds) {
        let flipped = next.flipped(from: folds)
        folds = next
        for store in Self.attached where store !== self { store.expected = next }
        UserDefaults.standard.set(next.stored, forKey: InspectorPanel.collapsedKey)
        tellCells(flipped)
    }

    /// The setting changed on disk. A write of this panel's own is already
    /// here and changes nothing. Another window's fold is told to the sections
    /// it flipped; anybody else's to those sections and to the panel.
    private func readSetting() {
        let now = Self.storedFolds
        guard now != folds else { return }
        let flipped = now.flipped(from: folds)
        folds = now
        tellCells(flipped)
        if now == expected {
            expected = nil
            onFoldFromAnotherWindow?()
        } else {
            syncs += 1
        }
    }

    private func tellCells(_ flipped: Set<String>) {
        for name in flipped {
            guard let id = InspectorSectionID(rawValue: name), let cell = cells[id] else { continue }
            cell.fold(folds.contains(name))
        }
    }

    // MARK: Every window's panel

    private func attach() {
        guard !isAttached else { return }
        isAttached = true
        folds = Self.storedFolds
        Self.panels.append(Weak(store: self))
        Self.watchDefaults()
    }

    private static var storedFolds: PanelSectionFolds {
        PanelSectionFolds(stored: UserDefaults.standard.string(forKey: InspectorPanel.collapsedKey))
    }

    private struct Weak { weak var store: PanelSectionFoldStore? }
    private static var panels: [Weak] = []
    private static var attached: [PanelSectionFoldStore] {
        panels.removeAll { $0.store == nil }
        return panels.compactMap(\.store)
    }
    private static var watch: (any NSObjectProtocol)?

    /// One watcher for every panel. It never answers inside the write: a
    /// fold is written inside the click's animation, and the windows nobody
    /// clicked in follow it without one, after the clicked window's motion
    /// and the body it opened coming back into reach have had their frames.
    /// Anything else written to the setting is answered on the next turn.
    private static func watchDefaults() {
        guard watch == nil else { return }
        watch = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: UserDefaults.standard, queue: nil
        ) { _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    for store in attached {
                        guard store.expected != nil else { store.readSetting(); continue }
                        DispatchQueue.main.asyncAfter(deadline: .now() + followDelay) { [weak store] in
                            MainActor.assumeIsolated { store?.readSetting() }
                        }
                    }
                }
            }
        }
    }

    /// A shade past the fold's 0.25s spring.
    private static let followDelay = 0.3
}

/// One section's fold, watched by that section alone.
@MainActor @Observable
final class PanelFoldCell {
    private(set) var isFolded: Bool
    /// The same, read without tying the reader to it: for the header, which
    /// says the fold to VoiceOver once the motion has settled and must not be
    /// redrawn by the click (`CollapsibleSection`).
    @ObservationIgnored private(set) var isFoldedUnwatched: Bool

    init(isFolded: Bool) {
        self.isFolded = isFolded
        isFoldedUnwatched = isFolded
    }

    fileprivate func fold(_ folded: Bool) {
        isFoldedUnwatched = folded
        isFolded = folded
    }
}
