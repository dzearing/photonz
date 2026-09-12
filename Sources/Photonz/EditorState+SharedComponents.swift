import AppKit
import CoreGraphics
import Observation
import PhotonzCore
import PhotonzRender
import SwiftUI

// One shelf the whole app shares (Next, `next-shared-library`): putting a
// component on it, taking one off it, and keeping this window's document in
// step with it.
//
// The rule that keeps it simple: the shelf is the truth about what a shared
// component LOOKS like, and each document is the truth about where it sits.
// An edit made HERE publishes; an edit made anywhere else arrives.
extension EditorState {

    /// Whether a component can be shared across documents at all.
    var sharedLibraryEnabled: Bool { Experiments.shared.sharedLibraryEnabled }

    var sharedStore: SharedComponentStore { SharedComponentStore.shared }

    // MARK: - What the shelf offers this document

    /// The shared components this document has not taken yet, as shelf items.
    /// One that HAS been taken is dropped from this list because the document
    /// already lists it — one tile per component, exactly the rule the starters
    /// follow.
    var sharedComponentEntries: [LibraryEntry] {
        guard sharedLibraryEnabled, let document else { return [] }
        return sharedStore.shelf.entries(notIn: document)
    }

    /// The shared component behind a shelf tile, nil for anything else. Only
    /// answers for one the document has NOT taken yet: once it is in the
    /// document it is an ordinary component and is described as one.
    func sharedComponent(entryID: String) -> SharedComponent? {
        guard sharedLibraryEnabled, let id = UUID(uuidString: entryID),
              document?.mainComponent(componentID: id) == nil else { return nil }
        return sharedStore.shelf.component(id: id)
    }

    /// What a shared tile draws a picture of: the drawing as the shelf holds
    /// it. Not in any document, so it is rendered off a one-layer document the
    /// way a starter's picture is.
    func sharedPreviewLayer(_ shared: SharedComponent) -> Layer? {
        shared.drawings.first
    }

    /// The picture on a shared component's tile. Cached per size and per
    /// drawing, so a shelf being scrolled renders each tile once and an edit
    /// published from another window draws the new picture.
    func sharedThumbnail(_ shared: SharedComponent, dimension: CGFloat) -> CGImage? {
        guard let preview = sharedPreviewLayer(shared) else { return nil }
        let key = ShelfPictureKey(id: shared.id, dimension: Int(dimension))
        let hash = preview.hashValue
        if let cached = shelfThumbnails[key], cached.hash == hash { return cached.image }
        var layer = preview
        let box = layer.localBounds
        guard box.width > 0, box.height > 0 else { return nil }
        layer.frame.origin = CGPoint(x: -box.minX, y: -box.minY)
        let document = PhotonzDocument(canvasSize: box.size, layers: [layer])
        guard let image = previewRenderer.thumbnail(for: layer.id, in: document, store: store,
                                                    maxDimension: dimension) else { return nil }
        shelfThumbnails[key] = (hash, image)
        return image
    }

    // MARK: - Putting one on the shelf

    /// Whether this component is on the shared shelf.
    func isComponentShared(_ componentID: UUID) -> Bool {
        document?.mainComponent(componentID: componentID)?.isSharedComponent == true
    }

    /// Whether this component's shared original has gone: it still draws, and
    /// it is on its own from here on.
    func isSharedOriginalMissing(_ componentID: UUID) -> Bool {
        guard sharedLibraryEnabled, isComponentShared(componentID) else { return false }
        return sharedStore.shelf.component(id: componentID) == nil
    }

    /// The Component section's Share across documents switch.
    ///
    /// Turning it ON puts this component on the shelf, where every document can
    /// reach it. Turning it OFF takes it off the shelf: this document keeps its
    /// drawing and stops following, and so does every other document that has
    /// one, which is why the other half of that act is telling them so.
    func setComponentShared(_ componentID: UUID, _ shared: Bool) {
        guard sharedLibraryEnabled, document != nil else { return }
        var published: SharedComponent?
        perform {
            if shared {
                published = $0.shareComponent(componentID: componentID)
            } else {
                $0.unshareComponent(componentID: componentID)
            }
        }
        if shared {
            guard let published else { return }
            sharedStore.put(published, from: self)
        } else {
            sharedStore.remove(id: componentID, from: self)
        }
    }

    /// Puts a component whose shared original has gone back on the shelf, as
    /// this document draws it. The way back from a shelf that was tidied away:
    /// the drawing is still here, so it can simply be the original again.
    func reshareComponent(_ componentID: UUID) {
        guard sharedLibraryEnabled,
              let published = document?.sharedComponent(componentID: componentID) else { return }
        // It is already marked as following; what is missing is the shelf's
        // copy, so nothing about the document has to change.
        sharedStore.put(published, from: self)
    }

    /// Brings a shared component into the open document, centred on a canvas
    /// point. One undo step: the component, every version of it and the colors
    /// it paints from all arrive or none of them do.
    @discardableResult
    func insertSharedComponent(_ shared: SharedComponent, at point: CGPoint) -> UUID? {
        guard sharedLibraryEnabled, document != nil else { return nil }
        discardDragPreview()
        var placed: UUID?
        let context = dropContext
        perform { placed = $0.adoptSharedComponent(shared, at: point, inside: context) }
        guard let placed else { return nil }
        selectedLibraryItemID = nil
        selectLayer(placed, inGroup: self.document?.parentID(of: placed))
        return placed
    }

    // MARK: - Keeping this window in step

    /// Starts following the shelf. Called once, when the window's state is
    /// built.
    func followSharedShelf() {
        sharedStore.follow(self)
    }

    /// The document this window is about to show, put in step with the shelf
    /// before anybody sees it, so a file opened tomorrow comes up already
    /// wearing today's edits. Hands back what to say about it, if anything.
    @discardableResult
    func syncSharedComponentsOnOpen(_ document: inout PhotonzDocument) -> SharedComponentSyncReport {
        guard sharedLibraryEnabled else { return SharedComponentSyncReport() }
        return document.syncSharedComponents(from: sharedStore.shelf)
    }

    /// The shelf moved under this window: another window published an edit, or
    /// took a component off the shelf.
    ///
    /// It is not an edit of this document, so it records no undo step — and
    /// every step the stack can already return to is put in step too, so ⌘Z on
    /// some unrelated local edit can never hand back somebody else's older
    /// drawing (`History.applyOutsideHistory`).
    func sharedShelfChanged(_ shelf: SharedComponentShelf) {
        guard sharedLibraryEnabled, let document, document.followsSharedComponents else { return }
        var report = SharedComponentSyncReport()
        let moved = applyOutsideHistory { doc in
            report = doc.syncSharedComponents(from: shelf)
        }
        if moved { rerender() }
        // Said whether or not anything moved: a component taken off the shelf
        // changes nothing about the picture, which is exactly why it has to be
        // said out loud.
        announceSharedComponents(report)
    }

    /// An edit just landed in this window: anything it changed about a shared
    /// original goes to the shelf, and from there to every other window.
    ///
    /// Only components that were ALREADY shared before the edit publish, so one
    /// arriving off the shelf never publishes itself straight back, and only
    /// ones whose drawing really changed, so moving a shared button across the
    /// canvas publishes nothing.
    func publishSharedComponents(changedFrom before: PhotonzDocument?) {
        guard sharedLibraryEnabled, let before, let after = document,
              before.followsSharedComponents || after.followsSharedComponents else { return }
        let changed = PhotonzDocument.sharedComponentsToPublish(from: before, to: after)
        guard !changed.isEmpty else { return }
        sharedStore.put(changed, from: self)
    }

    /// Says that a shared original has gone, in the same words and the same
    /// place as every other broken link. A drawing that simply took an edit
    /// says nothing: it is what following the shelf means.
    func announceSharedComponents(_ report: SharedComponentSyncReport) {
        guard sharedLibraryEnabled, !report.linkBreaks.isEmpty else { return }
        raiseCanvasNotice(.linksBroken(report.linkBreaks))
    }
}
