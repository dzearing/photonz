import AppKit
import PhotonzCore
import SwiftUI

// Edit Original: a component's original, opened in a space of its own.
//
// An original lives in the document's component library, not on the canvas
// (`ComponentLibrary.swift` in the core), so editing one cannot mean selecting
// it on the canvas. Edit Original swaps the window over to a document holding
// only that component's drawings, the way Figma opens a main component and
// Sketch has its symbols page: everything you already know how to do to a
// group works on it, with its own undo, and the title bar says what you are in
// and has Done. Done (or Escape with nothing picked) writes the drawings back
// as ONE undo step on the document you came from, and every instance follows.

/// The document waiting under an open Edit Original space.
struct OriginalSpaceSession {
    /// The component being edited.
    let componentID: UUID
    /// The document's own stack, exactly as it was when the space opened.
    let parent: History
    /// The space as it opened, so Done on a space nobody touched records
    /// nothing.
    let opened: PhotonzDocument
    /// Where the camera was, so coming back lands where you left.
    let parentViewport: Viewport?
    /// What was picked when you left, so it is picked again when you return.
    let cameFrom: UUID?
    let cameFromGroup: UUID?
}

extension EditorState {

    /// Whether the window is showing a component's original rather than the
    /// document.
    var isEditingOriginal: Bool { originalSpace != nil }

    /// What the title bar names while a space is open.
    var originalSpaceName: String? {
        guard let session = originalSpace else { return nil }
        return document?.mainComponent(componentID: session.componentID)?.name
            ?? session.parent.current.mainComponent(componentID: session.componentID)?.name
    }

    /// Whether Edit Original would do anything for the picked layer: one copy
    /// of a component this document holds.
    var canEditPickedOriginal: Bool { pickedOriginal != nil }

    /// The component and version the picked copy shows.
    private var pickedOriginal: (componentID: UUID, version: UUID?)? {
        guard componentsEnabled, originalSpace == nil, let document,
              actionableLayerIDs.count == 1, let id = actionableLayerIDs.first,
              let layer = document.layer(id: id), let componentID = layer.instanceOf,
              document.mainComponent(componentID: componentID) != nil
        else { return nil }
        return (componentID, layer.instanceVersionID)
    }

    /// Layer ▸ Edit Original, and the same row on a copy's right-click menu.
    func editPickedOriginal() {
        guard let picked = pickedOriginal else { return }
        editOriginal(componentID: picked.componentID, version: picked.version)
    }

    /// Opens a component's original in its own space. With a version named,
    /// that drawing is the one picked when it opens, so a copy showing
    /// Disabled lands on the Disabled drawing.
    func editOriginal(componentID: UUID, version: UUID? = nil) {
        guard componentsEnabled else { return }
        // One space at a time: opening another finishes this one first.
        if originalSpace != nil { finishEditingOriginal() }
        discardDragPreview()
        guard let history, let space = history.current.editingSpace(forComponent: componentID)
        else { return }
        let spaceHistory = History(document: space, parksOriginals: false)
        originalSpace = OriginalSpaceSession(componentID: componentID, parent: history,
                                             opened: spaceHistory.current,
                                             parentViewport: viewport,
                                             cameFrom: selectedLayerID,
                                             cameFromGroup: groupContextID)
        selectedLibraryItemID = nil
        swapHistory(spaceHistory, viewport: nil)
        if let drawing = spaceHistory.current.mainComponent(componentID: componentID, version: version) {
            selectLayer(drawing.id, inGroup: nil)
        }
        TutorialController.shared.note(.originalOpened, from: self)
    }

    /// Done: back to the document, with the edit made in the space written into
    /// it as one undo step. Nothing is recorded for a space nobody changed.
    func finishEditingOriginal() {
        guard let session = originalSpace, let space = document else { return }
        originalSpace = nil
        swapHistory(session.parent, viewport: session.parentViewport)
        if space != session.opened {
            perform { $0.returnFromEditingSpace(space, componentID: session.componentID) }
        }
        if let id = session.cameFrom, document?.layer(id: id) != nil {
            selectLayer(id, inGroup: session.cameFromGroup)
        }
        // Last, after the copy you came from is picked again, so a guide step
        // after Done that waits on picking a copy waits for the person.
        TutorialController.shared.note(.originalFinished, from: self)
    }

    /// The component a walk means by "the selected component": the picked
    /// original, the one a picked copy follows, or the picked Library tile.
    var playtestPickedComponentID: UUID? {
        if let id = selectedLayerID, let layer = document?.layer(id: id),
           let componentID = layer.componentID ?? layer.instanceOf {
            return componentID
        }
        return selectedComponentID
    }

    /// Escape with nothing left to let go of leaves the space, the way it
    /// steps out of a group. Returns whether it did.
    func leaveOriginalSpaceOnEscape() -> Bool {
        guard originalSpace != nil else { return false }
        finishEditingOriginal()
        return true
    }
}

/// The title bar while an original is open: what you are editing, and Done.
/// Centred in the bar like the window's title, because which thing the window
/// is showing is the title bar's one purpose (UX-PATTERNS, the placement
/// contract).
struct OriginalSpaceTitleBar: View {
    @Environment(EditorState.self) private var editorState

    var body: some View {
        if let name = editorState.originalSpaceName {
            HStack(spacing: 8) {
                ComponentMark(size: 11)
                Text(name)
                    .font(.system(size: 12.5, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .accessibilityLabel(OriginalSpaceCopy.editing(name))
                Button(OriginalSpaceCopy.done) { editorState.finishEditingOriginal() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .help(OriginalSpaceCopy.doneHelp)
                    .playtestControl(OriginalSpaceCopy.done, detail: name)
                    .tutorialAnchor(.originalDone)
            }
            .fixedSize()
            .frame(maxWidth: .infinity)
            .padding(.horizontal, TitlebarDocumentLine.endClearance)
            .frame(height: TitlebarDocumentLine.barHeight)
        }
    }
}

/// The words the space puts on screen.
enum OriginalSpaceCopy {
    static let done = "Done"
    static let doneHelp = "Back to the document. Every copy takes the change."
    static let menuDone = "Done Editing Original"
    static let menuEdit = "Edit Original"
    static func editing(_ name: String) -> String { "Editing \(name)" }
}
