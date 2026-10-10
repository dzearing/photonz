import Foundation
import Observation
import PhotonzCore

/// The curves kept under a name (`SavedCurves.swift`), with the app rather than
/// with one document: a curve drawn for a zoom is offered on the next dissolve,
/// title and fade in every document, the way ⌘T's default transition is
/// (`DefaultTransitionStore`). Forgotten with the rest of a walk's `motion`
/// memory.
@MainActor
@Observable
final class SavedCurveStore {
    static let shared = SavedCurveStore()
    static let defaultsKey = "motion.savedCurves"

    private(set) var curves: SavedCurves

    private init() {
        curves = Self.read()
    }

    /// Keep `curve` as `name`. Answers the name kept, or nil for a blank one.
    @discardableResult
    func save(_ curve: EasingCurve, as name: String) -> String? {
        var next = curves
        guard let kept = next.save(curve, as: name) else { return nil }
        write(next)
        return kept
    }

    func remove(named name: String) {
        var next = curves
        next.remove(named: name)
        write(next)
    }

    /// Reads the list back off disk, for a walk that wiped it after the app
    /// had already read it.
    func reload() {
        curves = Self.read()
    }

    private func write(_ next: SavedCurves) {
        guard next != curves else { return }
        curves = next
        if let data = try? JSONEncoder().encode(next) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }

    private static func read() -> SavedCurves {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let read = try? JSONDecoder().decode(SavedCurves.self, from: data) else { return SavedCurves() }
        return read
    }
}
