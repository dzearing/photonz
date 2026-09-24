import Foundation
import Observation
import PhotonzCore

/// Which transition ⌘T puts on a cut (`DefaultTransition.swift`).
///
/// A preference, not document content: Premiere and Final Cut both keep the
/// default transition with the app, so picking Push once makes ⌘T a push in
/// every document until you pick again. Same shape as `IconKeylinesStore`, and
/// forgotten with the rest of a walk's `motion` memory.
@MainActor
@Observable
final class DefaultTransitionStore {
    static let shared = DefaultTransitionStore()
    static let defaultsKey = "video.defaultTransition"

    var kind: ClipTransitionKind {
        didSet {
            guard kind != oldValue else { return }
            UserDefaults.standard.set(kind.rawValue, forKey: Self.defaultsKey)
        }
    }

    private init() {
        kind = ClipTransitionKind(storedDefault: UserDefaults.standard.string(forKey: Self.defaultsKey))
    }

    /// Reads the setting back off disk, for a walk that wiped it after the app
    /// had already read it.
    func reload() {
        kind = ClipTransitionKind(storedDefault: UserDefaults.standard.string(forKey: Self.defaultsKey))
    }
}
