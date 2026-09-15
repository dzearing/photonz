import Foundation
import Observation
import PhotonzCore

/// Which of the panel's optional sections you have said yes or no to
/// (Next, `next-panel-sections`).
///
/// One store for the whole app, like `IconKeylinesStore` and `CanvasGridStore`,
/// for the same reason: you are saying how you like the panel, not decorating
/// one window, so turning the Library off in one document turns it off in every
/// document and it is still off after a relaunch.
///
/// **Kept per release.** The key carries the running release's namespace, the
/// way the feature flags do, so arranging Next's panel never disturbs Current's
/// and the day Next is promoted nobody inherits a panel they did not arrange.
/// The rule itself is in `PanelSectionVisibility`, which is pure and tested.
@MainActor
@Observable
final class PanelSectionVisibilityStore {
    static let shared = PanelSectionVisibilityStore()

    /// Where the choice is written, under the running release's own namespace:
    /// `experiments.next.panelSections`.
    static func defaultsKey(for release: Release) -> String {
        "\(release.storageNamespace).panelSections"
    }

    private let key: String

    /// Your answers. Everything absent is automatic, which is the default state
    /// of every section.
    var choices: PanelSectionVisibility.Choices {
        didSet {
            guard choices != oldValue else { return }
            UserDefaults.standard.set(choices.stored, forKey: key)
        }
    }

    private init() {
        key = Self.defaultsKey(for: Experiments.shared.release)
        choices = PanelSectionVisibility.Choices(
            stored: UserDefaults.standard.string(forKey: key) ?? "")
    }

    /// Reads the choice back off disk. Only a scripted walk asking the app to
    /// forget it needs this: it wipes the setting after the app has read it.
    func reload() {
        choices = PanelSectionVisibility.Choices(
            stored: UserDefaults.standard.string(forKey: key) ?? "")
    }

    func set(_ section: InspectorSectionID, shown: Bool) {
        var next = choices
        next.set(section.rawValue, shown: shown)
        choices = next
    }

    func useAutomatic(for section: InspectorSectionID) {
        var next = choices
        next.useAutomatic(for: section.rawValue)
        choices = next
    }

    func useAutomaticForAll() {
        var next = choices
        next.useAutomaticForAll()
        choices = next
    }
}
