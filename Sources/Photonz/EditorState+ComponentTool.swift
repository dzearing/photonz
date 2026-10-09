import CoreGraphics
import Foundation
import PhotonzCore

// The Component insert tool (Next, `next-components`): the UI entry mock's
// `tComp`. Pick it, click the canvas, and a copy of a component lands centred
// on the click, through the same path a drop from the Library takes.
extension EditorState {

    /// The components the tool can place: the Library's Components shelf, in
    /// the shelf's order (yours, the shared shelf's, then the app's own).
    var componentToolOffers: [LibraryEntry] { componentEntries }

    /// The component a click places right now (`ComponentToolChoice`): the
    /// tile picked in the Library, else the one the tool placed last, else the
    /// first on the shelf.
    var componentToolComponentID: UUID? {
        ComponentToolChoice.component(
            libraryPick: selectedLibraryItemID.flatMap(UUID.init(uuidString:)),
            remembered: componentToolMemory,
            offered: componentToolOffers.compactMap { UUID(uuidString: $0.id) })
    }

    /// The tool's capsule picking a component. A component tile picked on the
    /// shelf is moved to the same one, so the shelf and the capsule never name
    /// two different things.
    func setComponentToolComponent(_ id: UUID) {
        componentToolMemory = id
        if let picked = selectedLibraryItemID,
           componentToolOffers.contains(where: { $0.id == picked }) {
            selectLibraryItem(id.uuidString)
        }
    }

    /// A click with the tool: a copy of the component it holds, centred on
    /// `point`, picked, and Select back in hand, the way every tool that makes
    /// something ends (`ArrowCaptionEntry.toolAfterLanding`).
    func placeWithComponentTool(at point: CGPoint) {
        guard componentsEnabled, let componentID = componentToolComponentID else { return }
        let version = shelfComponentVersion(of: componentID)?.id
        guard let placed = placeComponent(componentID: componentID, at: point,
                                          version: version) else { return }
        componentToolMemory = componentID
        setTool(ArrowCaptionEntry.toolAfterLanding(.component, offersCaption: false))
        selectLayer(placed, inGroup: document?.parentID(of: placed))
    }
}
