import Foundation
import Observation
import PhotonzCore

/// Which pulls snapping has inside an icon frame (Next, `next-icon-frames`):
/// whole units, the keylines, and the shapes already drawn, each switched on
/// its own from View ▸ Snap in Icons.
///
/// A view preference like the keylines themselves (`IconKeylinesStore`), so it
/// holds across every icon frame, every window and every launch. All three are
/// on until somebody turns one off: an icon frame whose points landed anywhere
/// until a menu was found would be the smear the frame exists to prevent.
@MainActor
@Observable
final class IconSnapStore {
    static let shared = IconSnapStore()
    static let defaultsKey = "icon.snap.choices"

    var choices: IconSnapChoices {
        didSet {
            guard choices != oldValue,
                  let data = try? JSONEncoder().encode(choices) else { return }
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }

    private init() {
        choices = Self.stored()
    }

    /// Reads the setting back off disk. Only a scripted walk asking to forget
    /// it needs this: it wipes the setting after the app has already read it.
    func reload() { choices = Self.stored() }

    private static func stored() -> IconSnapChoices {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let choices = try? JSONDecoder().decode(IconSnapChoices.self, from: data)
        else { return .all }
        return choices
    }
}
