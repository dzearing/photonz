import Foundation
import Observation
import PhotonzCore

/// The documents you opened and saved, kept in the app's settings (Next,
/// `next-recent-documents`). File > Open Recent lists them, and the front
/// door's Recent puts them among your captures. The list itself is
/// `RecentDocuments`; this only keeps it and says when it changed.
@MainActor @Observable
final class RecentDocumentsStore {
    static let shared = RecentDocumentsStore()
    static let defaultsKey = "recentDocuments"

    private(set) var list: RecentDocuments
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var observer: NSObjectProtocol?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        list = Self.read(defaults)
        // A walk forgets the list by clearing the setting, and puts it back
        // the same way, so the setting is the truth and this follows it.
        observer = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: defaults, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
    }

    var isEnabled: Bool { Experiments.shared.recentDocumentsEnabled }

    /// What is still there to open, newest first. Empty with the switch off.
    var documents: [RecentDocument] {
        guard isEnabled else { return [] }
        return list.existing { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// `url` was opened or saved just now.
    func note(_ url: URL) {
        guard isEnabled, url.isFileURL else { return }
        list.note(url, at: .now)
        write()
    }

    func remove(_ url: URL) {
        list.remove(url)
        write()
    }

    /// File > Open Recent > Clear Menu.
    func clear() {
        list.clear()
        write()
    }

    private func reload() {
        let stored = Self.read(defaults)
        if stored != list { list = stored }
    }

    private func write() {
        guard let data = try? JSONEncoder().encode(list) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }

    private static func read(_ defaults: UserDefaults) -> RecentDocuments {
        guard let data = defaults.data(forKey: defaultsKey),
              let list = try? JSONDecoder().decode(RecentDocuments.self, from: data) else { return RecentDocuments() }
        return list
    }
}
