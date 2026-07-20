import Foundation

/// The window-close decision: closing needs a save prompt exactly when it
/// would lose work — the current document differs from the last saved/opened
/// baseline. Undoing back to the baseline counts as clean again (value
/// equality, not edit count).
public enum ClosePrompt {
    public static func needsSavePrompt(current: PhotonzDocument?,
                                       savedBaseline: PhotonzDocument?) -> Bool {
        guard let current else { return false }
        return current != savedBaseline
    }
}
