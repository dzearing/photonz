import Foundation
import Observation
import PhotonzCore

/// The one canvas grid the whole app shares (Next, `next-canvas-grid`).
///
/// The grid is a view preference, not document content, so there is exactly one
/// of it: two windows open side by side show the same grid, and switching it on
/// in either switches it on in both rather than leaving them disagreeing until
/// the next launch. It is written straight to the app's settings, so it also
/// outlives the launch.
///
/// Reached through `EditorState.canvasGrid`, which is where every view and menu
/// asks for it; this type is the storage behind that one door.
@MainActor
@Observable
final class CanvasGridStore {
    static let shared = CanvasGridStore()
    static let defaultsKey = "canvas.grid"

    var settings: CanvasGridSettings {
        didSet {
            guard settings != oldValue else { return }
            guard let data = try? JSONEncoder().encode(settings) else { return }
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }

    private init() {
        settings = Self.stored()
    }

    /// Reads the settings back off disk. Only a scripted walk asking to forget
    /// the grid needs this: it wipes the stored settings after the app has
    /// already read them, and without this the app would keep drawing the ones
    /// the walk just threw away.
    func reload() { settings = Self.stored() }

    /// Settings written by hand, or by a version that spelled them differently,
    /// come back as the defaults rather than as nothing to draw.
    private static func stored() -> CanvasGridSettings {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode(CanvasGridSettings.self, from: data) else {
            return CanvasGridSettings()
        }
        return decoded
    }
}
