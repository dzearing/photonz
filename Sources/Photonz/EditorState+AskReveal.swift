import PhotonzCore

/// An ask always shows the Agent group with its new row (`AskReveal`): a
/// video in View goes to Edit, a closed panel comes out, and the panel then
/// unfolds the group and scrolls it into view (`InspectorPanel`).
extension EditorState {

    /// Brings out whatever stands between the person and the Agent group.
    /// The panel comes out for this window only: the person's choice for new
    /// windows (`inspectorPreferredVisible`) is left as they made it.
    func bringAgentAreaForward() {
        let panelOut = isLayersPanelVisible && !isInspectorAutoHidden
        let reveal = AskReveal.plan(watching: isWatching, panelOut: panelOut)
        if reveal.switchesToEdit { switchToEditForAnEdit() }
        if reveal.bringsPanelOut {
            isLayersPanelVisible = true
            isInspectorAutoHidden = false
            if reveal.remembersPanelChoice { inspectorPreferredVisible = true }
        }
    }
}
