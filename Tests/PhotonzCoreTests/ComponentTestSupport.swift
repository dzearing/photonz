import Foundation
@testable import PhotonzCore

extension PhotonzDocument {
    /// Make Component as the editor leaves it, minus the instance it stands
    /// on the canvas: the original keeps its id and goes into the component
    /// library, and nothing is left in the picture, so a fixture that places
    /// its own copies counts exactly those (`ComponentLibrary.swift`).
    @discardableResult
    mutating func makeComponentInLibrary(id: UUID, name: String? = nil) -> UUID? {
        guard let componentID = makeComponent(id: id, name: name) else { return nil }
        if let standIn = parkOriginals()[id] { removeLayer(id: standIn) }
        return componentID
    }
}
