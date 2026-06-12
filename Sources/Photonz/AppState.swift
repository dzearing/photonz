import CoreGraphics
import Observation
import PhotonzCore
import PhotonzRender
import SwiftUI
import UniformTypeIdentifiers

@MainActor
@Observable
final class AppState {
    private(set) var history: History?
    let store = ImageStore()
    private let renderer = DocumentRenderer()

    /// The composited document, refreshed after every edit.
    private(set) var renderedImage: CGImage?
    var isImporterPresented = false
    var zoom: CGFloat = 1

    var document: PhotonzDocument? { history?.current }
    var canUndo: Bool { history?.canUndo ?? false }
    var canRedo: Bool { history?.canRedo ?? false }

    func openImage(at url: URL) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return }
        let ref = store.register(image)
        history = History(document: .withBaseImage(ref))
        zoom = 1
        rerender()
    }

    func perform(_ mutate: (inout PhotonzDocument) -> Void) {
        history?.perform(mutate)
        rerender()
    }

    func undo() {
        history?.undo()
        rerender()
    }

    func redo() {
        history?.redo()
        rerender()
    }

    private func rerender() {
        guard let document = history?.current else {
            renderedImage = nil
            return
        }
        renderedImage = renderer.render(document, store: store)
    }
}
