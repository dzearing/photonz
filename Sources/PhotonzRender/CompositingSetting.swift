import PhotonzCore
import Synchronization

/// Where every renderer that has not been told otherwise mixes see-through
/// paint (`CompositingSpace`).
///
/// The app sets `shared` from the release it is running: Next mixes the way a
/// browser does, Current in light as it always has. A renderer following a
/// setting reads it at every frame, so flipping the switch in the Experiments
/// window reaches a canvas that is already open.
public final class CompositingSetting: Sendable {
    /// The one the app sets, and every `DocumentRenderer()` follows.
    public static let shared = CompositingSetting(.standard)

    private let value: Mutex<CompositingSpace>

    public init(_ space: CompositingSpace) {
        value = Mutex(space)
    }

    public var space: CompositingSpace {
        get { value.withLock { $0 } }
        set { value.withLock { $0 = newValue } }
    }
}
