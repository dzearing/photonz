import Foundation

/// The tiny slice of key-value storage the experiments store needs. Injecting
/// it keeps `ExperimentsStore` testable without touching the real defaults
/// database, and keeps the store itself free of any app dependency.
public protocol ExperimentsDefaults: AnyObject {
    func experimentsData(forKey key: String) -> Data?
    func setExperimentsData(_ data: Data?, forKey key: String)
    func experimentsString(forKey key: String) -> String?
    func setExperimentsString(_ value: String?, forKey key: String)
}

/// The real backing store: `UserDefaults`.
public final class UserDefaultsExperimentsDefaults: ExperimentsDefaults {
    private let defaults: UserDefaults

    public init(_ defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func experimentsData(forKey key: String) -> Data? {
        defaults.data(forKey: key)
    }

    public func setExperimentsData(_ data: Data?, forKey key: String) {
        defaults.set(data, forKey: key)
    }

    public func experimentsString(forKey key: String) -> String? {
        defaults.string(forKey: key)
    }

    public func setExperimentsString(_ value: String?, forKey key: String) {
        defaults.set(value, forKey: key)
    }
}

/// In-memory storage for tests and previews.
public final class InMemoryExperimentsDefaults: ExperimentsDefaults {
    private var values: [String: Any] = [:]

    public init() {}

    public func experimentsData(forKey key: String) -> Data? { values[key] as? Data }

    public func setExperimentsData(_ data: Data?, forKey key: String) { values[key] = data }

    public func experimentsString(forKey key: String) -> String? { values[key] as? String }

    public func setExperimentsString(_ value: String?, forKey key: String) { values[key] = value }
}

/// Owns the selected release and every release's flag state, each under its own
/// storage key. Editing Next never touches Current, and switching back and forth
/// loses nothing.
///
/// Anything unreadable — corrupt JSON, a release name from a future build, a
/// flag that no longer exists — falls back to the catalog's defaults instead of
/// failing, because a broken preferences blob must never break the app.
public final class ExperimentsStore {
    /// Where the chosen release is persisted.
    public static let releaseKey = "experiments.release"

    /// Where one release's flag state is persisted. Namespaced per release —
    /// this is what keeps the two sets of settings independent.
    public static func settingsKey(for release: Release) -> String {
        "\(release.storageNamespace).flags"
    }

    private let defaults: any ExperimentsDefaults
    /// Loaded lazily and written through on every edit.
    private var cache: [Release: FeatureFlagSettings] = [:]

    public init(defaults: any ExperimentsDefaults) {
        self.defaults = defaults
    }

    /// The release the user has chosen. Takes effect on the next launch (see
    /// `Experiments` in the app layer), so reading this is NOT the same as
    /// asking what's running right now.
    public var selectedRelease: Release {
        get {
            guard let raw = defaults.experimentsString(forKey: Self.releaseKey),
                  let release = Release(rawValue: raw) else { return .default }
            return release
        }
        set {
            defaults.setExperimentsString(newValue.rawValue, forKey: Self.releaseKey)
        }
    }

    /// One release's flags, reconciled with the catalog the code has today.
    public func settings(for release: Release) -> FeatureFlagSettings {
        if let cached = cache[release] { return cached }
        let loaded = load(release)
        cache[release] = loaded
        return loaded
    }

    /// Edits one release's flags in place and persists the result.
    public func update(_ release: Release, _ mutate: (inout FeatureFlagSettings) -> Void) {
        var settings = settings(for: release)
        mutate(&settings)
        cache[release] = settings
        persist(settings, for: release)
    }

    public func setEnabled(_ enabled: Bool, flag: String, in release: Release) {
        update(release) { $0.setEnabled(enabled, for: flag) }
    }

    public func setParameter(_ parameter: String, of flag: String,
                             to value: FeatureParameterValue, in release: Release) {
        update(release) { $0.setParameter(parameter, of: flag, to: value) }
    }

    /// Puts one release back to the catalog's defaults, leaving other releases
    /// alone.
    public func resetToDefaults(for release: Release) {
        let defaultSettings = FeatureCatalog.defaultSettings(for: release)
        cache[release] = defaultSettings
        persist(defaultSettings, for: release)
    }

    // MARK: - Storage

    private func load(_ release: Release) -> FeatureFlagSettings {
        let catalog = FeatureCatalog.flags(for: release)
        guard let data = defaults.experimentsData(forKey: Self.settingsKey(for: release)),
              let stored = try? JSONDecoder().decode(FeatureFlagSettings.self, from: data) else {
            return FeatureCatalog.defaultSettings(for: release)
        }
        return stored.reconciled(with: catalog)
    }

    private func persist(_ settings: FeatureFlagSettings, for release: Release) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.setExperimentsData(data, forKey: Self.settingsKey(for: release))
    }
}
