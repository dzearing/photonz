import Foundation
import Observation
import PhotonzCore

/// The measure tool's remembered look, ONE per app rather than one per editor
/// window.
///
/// Each window used to load its own copy when it opened and write the whole of
/// it back on every measure edit, so a window left open from earlier kept
/// starting measurements in the old colours, and its next edit put the old
/// colours back over a change made in another window. "Any change to a caliper
/// becomes what every new measurement starts with" (the user, 2026-10-13) has
/// to mean every window.
///
/// It follows the stored setting as well as writing it: anything that changes
/// or removes the stored look in this process (a walk's setup forgetting it,
/// most often) is picked up at once rather than at the next window.
@MainActor
@Observable
final class MeasureMemory {
    static let shared = MeasureMemory()

    var styles: MeasureStyles {
        didSet {
            guard styles != oldValue, !following else { return }
            let data = try? JSONEncoder().encode(styles)
            stored = data
            UserDefaults.standard.set(data, forKey: EditorState.measureStylesKey)
        }
    }

    /// What was last read from or written to the stored setting, so a change
    /// notice for some other setting costs one comparison and no decode.
    @ObservationIgnored private var stored: Data?
    /// True while taking the stored setting in, so reading it never writes it
    /// back (a forgotten setting stays forgotten).
    @ObservationIgnored private var following = false

    private init() {
        stored = UserDefaults.standard.data(forKey: EditorState.measureStylesKey)
        styles = Self.decode(stored)
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification,
                                               object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { MeasureMemory.shared.followStoredSetting() }
        }
    }

    private func followStoredSetting() {
        let data = UserDefaults.standard.data(forKey: EditorState.measureStylesKey)
        guard data != stored else { return }
        stored = data
        let read = Self.decode(data)
        guard read != styles else { return }
        following = true
        styles = read
        following = false
    }

    private static func decode(_ data: Data?) -> MeasureStyles {
        guard let data, let styles = try? JSONDecoder().decode(MeasureStyles.self, from: data) else {
            return MeasureStyles()
        }
        return styles
    }
}
