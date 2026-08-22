import Observation
import PhotonzCore
import SwiftUI

/// App-level access to the Experiments settings: which release this launch is
/// running, and every release's feature flags.
///
/// Two Photonz experiences live in one binary. Next-gen behavior branches at
/// the call sites that need it (`Experiments.shared.release == .next`) or hides
/// behind a flag (`Experiments.shared.isEnabled(…)`) — there is deliberately no
/// parallel view hierarchy. See `docs/design/experiments.md`.
///
/// Release switching takes a relaunch: the choice reaches AppKit surfaces built
/// outside SwiftUI's environment (the menu-bar agent, the capture overlay, the
/// floating panels), and windows opened under one release shouldn't half-morph
/// into the other. Flag edits inside the running release apply live, because
/// this object is observable and call sites read it when they draw.
@MainActor
@Observable
final class Experiments {
    /// The app-wide instance. A singleton on purpose: AppKit surfaces that
    /// never see the SwiftUI environment still have to read flags.
    static let shared = Experiments()

    /// The release this process is running. Fixed at launch.
    let release: Release

    /// The release that will be running after the next launch. Setting it
    /// persists right away, so the choice survives a crash or a plain quit.
    var selectedRelease: Release {
        didSet {
            guard selectedRelease != oldValue else { return }
            store.selectedRelease = selectedRelease
        }
    }

    /// True while the chosen release isn't the one on screen.
    var needsRelaunch: Bool { selectedRelease != release }

    private let store: ExperimentsStore
    private var settingsByRelease: [Release: FeatureFlagSettings]

    init(store: ExperimentsStore = ExperimentsStore(defaults: UserDefaultsExperimentsDefaults())) {
        self.store = store
        let selected = store.selectedRelease
        release = selected
        selectedRelease = selected
        settingsByRelease = Dictionary(uniqueKeysWithValues:
            Release.allCases.map { ($0, store.settings(for: $0)) })
    }

    // MARK: - Reading (the running release)

    var activeSettings: FeatureFlagSettings { settings(for: release) }

    func isEnabled(_ flag: String) -> Bool { activeSettings.isEnabled(flag) }

    func number(_ flag: String, _ parameter: String) -> Double? {
        activeSettings.number(flag, parameter)
    }

    func string(_ flag: String, _ parameter: String) -> String? {
        activeSettings.string(flag, parameter)
    }

    func boolean(_ flag: String, _ parameter: String) -> Bool? {
        activeSettings.boolean(flag, parameter)
    }

    func selection(_ flag: String, _ parameter: String) -> String? {
        activeSettings.selection(flag, parameter)
    }

    // MARK: - Reading & editing (any release)

    func settings(for release: Release) -> FeatureFlagSettings {
        settingsByRelease[release] ?? FeatureCatalog.defaultSettings(for: release)
    }

    func setEnabled(_ enabled: Bool, flag: String, in release: Release) {
        store.setEnabled(enabled, flag: flag, in: release)
        settingsByRelease[release] = store.settings(for: release)
    }

    func setParameter(_ parameter: String, of flag: String,
                      to value: FeatureParameterValue, in release: Release) {
        store.setParameter(parameter, of: flag, to: value, in: release)
        settingsByRelease[release] = store.settings(for: release)
    }

    /// Puts one release back to the shipped defaults. Other releases are
    /// untouched.
    func resetToDefaults(for release: Release) {
        store.resetToDefaults(for: release)
        settingsByRelease[release] = store.settings(for: release)
    }
}

// MARK: - Flag readers
//
// One place per flag where the raw names and fallbacks live, so call sites stay
// a single readable line. Fallbacks matter: a flag can be off, retired, or
// half-configured, and the app has to behave exactly like stock Photonz then.

extension Experiments {
    /// `release-tag-in-window-title`: returns the title with the release tag
    /// attached, or the title untouched when the flag is off.
    func decorated(windowTitle: String) -> String {
        guard isEnabled(FeatureCatalog.releaseTagFlag) else { return windowTitle }
        let tag = string(FeatureCatalog.releaseTagFlag, FeatureCatalog.releaseTagLabel) ?? release.title
        let placementName = selection(FeatureCatalog.releaseTagFlag, FeatureCatalog.releaseTagPlacement) ?? ""
        let uppercase = boolean(FeatureCatalog.releaseTagFlag, FeatureCatalog.releaseTagUppercase) ?? false
        return ReleaseTag.decorate(windowTitle, tag: tag,
                                   placement: ReleaseTag.Placement(name: placementName) ?? .suffix,
                                   uppercase: uppercase)
    }

    /// `capture-toast-timing`: how long a post-capture toast holds before it
    /// starts fading.
    var captureToastHoldSeconds: Double {
        guard isEnabled(FeatureCatalog.captureToastTimingFlag) else {
            return FeatureCatalog.captureToastHoldSeconds
        }
        return number(FeatureCatalog.captureToastTimingFlag, FeatureCatalog.captureToastHold)
            ?? FeatureCatalog.captureToastHoldSeconds
    }

    /// `capture-toast-timing`: how long that fade takes.
    var captureToastFadeSeconds: Double {
        guard isEnabled(FeatureCatalog.captureToastTimingFlag) else {
            return FeatureCatalog.captureToastFadeSeconds
        }
        return number(FeatureCatalog.captureToastTimingFlag, FeatureCatalog.captureToastFade)
            ?? FeatureCatalog.captureToastFadeSeconds
    }
}
