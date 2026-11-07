import PhotonzCore
import SwiftUI

extension EnvironmentValues {
    /// What this picture's lengths read in. An environment value rather than a
    /// question each row asks the document, so a row is redrawn when the unit
    /// changes and left alone on every other edit.
    @Entry var lengthUnit: LengthUnit = .point
}

/// Hands the panel the picture's unit. A modifier, so that the document
/// changing costs this one read and not a pass over the panel under it.
struct PanelLengthUnit: ViewModifier {
    @Environment(EditorState.self) private var editorState

    func body(content: Content) -> some View {
        content.environment(\.lengthUnit, editorState.lengthUnit)
    }
}
