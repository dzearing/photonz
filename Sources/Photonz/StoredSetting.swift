import Foundation
import Observation
import PhotonzCore
import SwiftUI

/// A view's stored setting, like `@AppStorage`, that tells the view about a
/// change of ITS OWN value and nothing else.
///
/// `@AppStorage` cannot watch a key with a dot in it (`inspector.width`,
/// `timeline.height`), and SwiftUI then counts every write to any setting in
/// the app as a change to it. On 2026-10-04 that was the editor's panel width:
/// each fold of a panel section wrote its own setting, and the whole editor,
/// canvas, tool bar and timeline, was built again for a width that had not
/// moved (`section-fold-motion-walk`; proven with a bare SwiftUI window, where
/// `x.width` rebuilt on writes of unrelated keys and `xwidth` did not).
///
/// Same use as `@AppStorage`: `@StoredSetting("inspector.width") var width = 264.0`,
/// `$width` for a binding. Every view naming the same key shares one cell.
@MainActor @propertyWrapper
struct StoredSetting<Value>: DynamicProperty {
    private let cell: StoredSettingCell
    private let defaultValue: Value

    init(wrappedValue: Value, _ key: String) {
        cell = .named(key)
        defaultValue = wrappedValue
    }

    var wrappedValue: Value {
        get { (cell.stored as? Value) ?? defaultValue }
        nonmutating set { cell.write(newValue) }
    }

    var projectedValue: Binding<Value> {
        Binding(get: { wrappedValue }, set: { wrappedValue = $0 })
    }
}

/// One stored setting, watched on its own: it changes, and so redraws the
/// views that read it, only when the value the defaults hold for its key does.
@MainActor @Observable
final class StoredSettingCell {
    @ObservationIgnored let key: String
    /// What the defaults hold for the key, as they hand it back. Nil when
    /// nothing is stored and the reader's own default applies.
    private(set) var stored: Any?

    private init(key: String) {
        self.key = key
        stored = UserDefaults.standard.object(forKey: key)
    }

    func write(_ value: Any) {
        UserDefaults.standard.set(value, forKey: key)
        refresh()
    }

    /// Reads the key again, and moves only when its value really changed.
    func refresh() {
        let now = UserDefaults.standard.object(forKey: key)
        if StoredSettingValue.differs(stored, now) { stored = now }
    }

    private static var cells: [String: StoredSettingCell] = [:]
    private static var watch: (any NSObjectProtocol)?

    static func named(_ key: String) -> StoredSettingCell {
        if let cell = cells[key] { return cell }
        let cell = StoredSettingCell(key: key)
        cells[key] = cell
        watchDefaults()
        return cell
    }

    /// One watcher for every cell: any write to the defaults re-reads each
    /// key, which is a dictionary lookup per setting, and only the cell whose
    /// value moved tells anybody.
    private static func watchDefaults() {
        guard watch == nil else { return }
        watch = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: UserDefaults.standard, queue: nil
        ) { _ in
            onMain { for cell in cells.values { cell.refresh() } }
        }
    }
}

/// Runs `work` on the main actor: straight away when the defaults changed on
/// the main thread, which is nearly always, and on the next turn otherwise.
nonisolated func onMain(_ work: @escaping @MainActor @Sendable () -> Void) {
    if Thread.isMainThread {
        MainActor.assumeIsolated { work() }
    } else {
        DispatchQueue.main.async { work() }
    }
}
