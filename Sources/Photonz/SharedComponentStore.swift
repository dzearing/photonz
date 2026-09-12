import Foundation
import Observation
import PhotonzCore

/// Where the shared shelf actually lives (Next, `next-shared-library`).
///
/// The model of what a shared component IS is pure and lives in `PhotonzCore`
/// (`SharedComponents`); this is the app's half: one JSON file in Application
/// Support, read once per launch, written whenever the shelf changes, and one
/// place every open window watches.
///
/// The file sits under the BUNDLE ID, so the release app, the dev app and the
/// probe each keep their own shelf and a walk can never write into the shelf
/// somebody is building a kit on.
@MainActor
@Observable
final class SharedComponentStore {
    static let shared = SharedComponentStore()

    /// What is on the shelf right now. Read by the Library panel, so it is
    /// observed rather than fetched.
    private(set) var shelf = SharedComponentShelf()

    /// Bumped on every change, so a window can tell "the shelf changed" from
    /// "I have not looked yet" without comparing whole drawings.
    private(set) var revision = 0

    /// The windows following the shelf. Weak, so a closed window drops out on
    /// its own rather than being unregistered from a deinit that cannot run on
    /// the main actor.
    private var followers: [WeakEditor] = []

    private struct WeakEditor {
        weak var editor: EditorState?
    }

    private let url: URL?

    init(url: URL? = SharedComponentStore.defaultURL()) {
        self.url = url
        load()
    }

    /// `~/Library/Application Support/<bundle id>/shared-components.json`.
    static func defaultURL() -> URL? {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory,
                                                     in: .userDomainMask).first else { return nil }
        let bundle = Bundle.main.bundleIdentifier ?? "com.dzearing.photonz"
        return support.appendingPathComponent(bundle, isDirectory: true)
            .appendingPathComponent("shared-components.json", isDirectory: false)
    }

    private func load() {
        guard let url, let data = try? Data(contentsOf: url),
              let read = try? JSONDecoder().decode(SharedComponentShelf.self, from: data)
        else { return }
        shelf = read
    }

    private func save() {
        guard let url else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(shelf) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    // MARK: - Changing it

    /// Puts a component on the shelf (or back on it, after an edit) and tells
    /// every other open window to follow.
    func put(_ component: SharedComponent, from editor: EditorState? = nil) {
        guard shelf.component(id: component.id) != component else { return }
        shelf.put(component)
        changed(excluding: editor)
    }

    /// The same for a whole edit's worth of components, so one edit that
    /// touched two shared originals writes the file once.
    func put(_ components: [SharedComponent], from editor: EditorState? = nil) {
        let news = components.filter { shelf.component(id: $0.id) != $0 }
        guard !news.isEmpty else { return }
        for component in news { shelf.put(component) }
        changed(excluding: editor)
    }

    /// Takes one off the shelf. Every document that used it keeps its drawing
    /// and says the link broke (`SharedComponentSyncReport`).
    func remove(id: UUID, from editor: EditorState? = nil) {
        guard shelf.component(id: id) != nil else { return }
        shelf.remove(id: id)
        changed(excluding: editor)
    }

    private func changed(excluding editor: EditorState?) {
        revision += 1
        save()
        let shelf = shelf
        followers.removeAll { $0.editor == nil }
        for follower in followers where follower.editor !== editor {
            follower.editor?.sharedShelfChanged(shelf)
        }
    }

    /// Puts the whole shelf back to what it was. The playtest harness's tidy
    /// up: a walk that shares a component hands the next walk the shelf it
    /// started with, the same way it hands back every remembered setting.
    func replace(with shelf: SharedComponentShelf) {
        guard self.shelf != shelf else { return }
        self.shelf = shelf
        changed(excluding: nil)
    }

    // MARK: - Who is watching

    /// A window starts following the shelf. Called once, when its state is
    /// built; the reference is weak, so closing the window is enough.
    func follow(_ editor: EditorState) {
        followers.removeAll { $0.editor == nil || $0.editor === editor }
        followers.append(WeakEditor(editor: editor))
    }
}
