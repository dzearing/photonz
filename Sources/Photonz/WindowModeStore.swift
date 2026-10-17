import Foundation
import Observation
import PhotonzCore

/// How each mode is arranged, for the whole app (Next, `next-window-modes`).
///
/// Which mode a window is IN is that window's own (`EditorState`'s
/// `windowModeSession`): a recording's window is in its video setup, a
/// picture's window starts in Image, and neither reaches the other. What is
/// kept here, once, is how you like each mode: the sections you turned on or
/// off while in it. A window's panel is the arrangement of the mode it is in,
/// read from here, and a switch ticked in the Sections list is written straight
/// back here for that mode.
///
/// Until 2026-10-17 this store held one mode for every window, so a recording
/// set to Video left every picture opened after it in Video too. What it wrote
/// then is read once and carried across as arrangements only
/// (`WindowModeArrangements.migrating`).
///
/// **Kept per release.** The key carries the running release's namespace, the
/// way the panel choices and the feature flags do.
@MainActor
@Observable
final class WindowModeStore {
    static let shared = WindowModeStore()

    /// Where the arrangements are written, under the running release's own
    /// namespace: `experiments.next.windowModeArrangements`.
    static func defaultsKey(for release: Release) -> String {
        "\(release.storageNamespace).windowModeArrangements"
    }

    /// Where builds before 2026-10-17 wrote the one mode the whole app was in.
    /// Read once, to carry its arrangements across, and never written again.
    static func legacyDefaultsKey(for release: Release) -> String {
        "\(release.storageNamespace).windowMode"
    }

    private let key: String
    private let legacyKey: String
    private let panelKey: String

    private(set) var arrangements: WindowModeArrangements {
        didSet {
            guard arrangements != oldValue else { return }
            write()
        }
    }

    private init() {
        let release = Experiments.shared.release
        key = Self.defaultsKey(for: release)
        legacyKey = Self.legacyDefaultsKey(for: release)
        panelKey = PanelSectionVisibilityStore.defaultsKey(for: release)
        arrangements = Self.read(key: key, legacyKey: legacyKey, panelKey: panelKey)
    }

    func arrangement(of id: String) -> PanelSectionVisibility.Choices {
        arrangements.arrangement(of: id)
    }

    func isBent(_ id: String) -> Bool { arrangements.isBent(id) }

    /// Keep what is on screen as this mode's arrangement.
    func keep(_ choices: PanelSectionVisibility.Choices, for id: String) {
        var next = arrangements
        next.keep(choices, for: id)
        arrangements = next
    }

    /// Put this mode back the way it shipped.
    func reset(_ id: String) {
        var next = arrangements
        next.reset(id)
        arrangements = next
    }

    /// Hand a window's lot back (`WindowModeSession.showEverything`).
    func showEverything(_ session: inout WindowModeSession, hasTime: Bool) {
        var next = arrangements
        session.showEverything(hasTime: hasTime, arrangements: &next)
        arrangements = next
    }

    /// Reads the arrangements back off disk. Only a scripted walk asking the
    /// app to forget them needs this: it wipes the settings after the app has
    /// read them.
    func reload() { arrangements = Self.read(key: key, legacyKey: legacyKey, panelKey: panelKey) }

    // MARK: Written down

    private static func read(key: String, legacyKey: String, panelKey: String) -> WindowModeArrangements {
        let defaults = UserDefaults.standard
        if let stored = defaults.string(forKey: key) {
            return stored.data(using: .utf8)
                .flatMap { try? JSONDecoder().decode(WindowModeArrangements.self, from: $0) }
                ?? WindowModeArrangements()
        }
        // Nothing written under the new key yet: carry across what an older
        // build left, and write it under the new key so this happens once.
        let migrated = WindowModeArrangements.migrating(
            legacySession: defaults.string(forKey: legacyKey),
            livePanel: defaults.string(forKey: panelKey))
        if let data = try? JSONEncoder().encode(migrated),
           let stored = String(data: data, encoding: .utf8) {
            defaults.set(stored, forKey: key)
        }
        return migrated
    }

    private func write() {
        guard let data = try? JSONEncoder().encode(arrangements),
              let stored = String(data: data, encoding: .utf8) else { return }
        UserDefaults.standard.set(stored, forKey: key)
    }
}
