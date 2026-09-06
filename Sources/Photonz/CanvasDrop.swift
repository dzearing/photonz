import AppKit
import PhotonzCore
import PhotonzRender
import SwiftUI

// Dropping onto the canvas: a file or a component dragged in from outside,
// where it would land, and the highlight that says so. Split out of
// CanvasView.swift; `CanvasNSView`'s stored properties still live there.

extension CanvasNSView {
    // MARK: - Drag destination (drop an image to add it as a layer)

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if droppedComponent(sender) != nil { return trackComponentDrag(sender) }
        return trackImageDrag(sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        // A component off the shelf lands wherever the pointer is: there is no
        // collage slot to highlight, and the copy is centred on the drop. What
        // it needs instead is the box it would fill and the frame it would
        // join, drawn while the button is still down.
        if droppedComponent(sender) != nil { return trackComponentDrag(sender) }
        return trackImageDrag(sender)
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        hoverSlot = nil
        dropLanding = nil
        draggedImage = nil
        refreshOverlays()
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        hoverSlot = nil
        dropLanding = nil
        draggedImage = nil
        refreshOverlays()
        if let dragged = droppedComponent(sender) {
            return dropComponent(dragged.componentID, version: dragged.version,
                                 atViewPoint: convert(sender.draggingLocation, from: nil))
        }
        // The same reading the pointer answered with: a file the canvas refused
        // in the air is refused on the way down too, so nothing can slip past a
        // no-entry pointer and land anyway.
        guard let url = droppedURL(sender) else { return false }
        let file = CanvasFileDrop.of(url)
        guard file.isAccepted else { return false }
        if file != .package, let target = dropTarget(for: sender) {
            onDropImageURLIntoCollage(url, target.collageID, target.index)
        } else if let viewport {
            onDropImageURL(url, viewport.documentPoint(fromView: convert(sender.draggingLocation, from: nil)))
        } else {
            return false
        }
        return true
    }

    private func dropTarget(for sender: NSDraggingInfo) -> (collageID: UUID, index: Int)? {
        guard let viewport else { return nil }
        let p = viewport.documentPoint(fromView: convert(sender.draggingLocation, from: nil))
        return collageSlotTarget(at: p)
    }

    /// The group you have stepped inside, as a drop reads it: nil out on the
    /// canvas, and nil while groups are switched off, which is the same
    /// reading the marquee takes.
    private var dropGroupContext: UUID? {
        Experiments.shared.layerGroupsEnabled ? groupContext : nil
    }

    /// The component a drag off the Library shelf is carrying, nil for
    /// everything else. Its own pasteboard type, so a dropped file and a
    /// dropped component can never be mistaken for each other.
    private func droppedComponent(_ sender: NSDraggingInfo) -> ComponentDrag.Payload? {
        ComponentDrag.payload(on: sender.draggingPasteboard)
    }

    /// Follows a component drag across the canvas: works out the box the copy
    /// would fill and the frame it would join, draws both, and answers the drag
    /// with what letting go here would actually do. A drop that would be
    /// refused (a copy landing inside its own original) says so with the
    /// ordinary no-entry pointer instead of accepting the drag and scolding
    /// afterwards.
    private func trackComponentDrag(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard let dragged = droppedComponent(sender) else {
            dropLanding = nil
            refreshOverlays()
            return []
        }
        return trackComponentDrag(dragged.componentID, version: dragged.version,
                                  atViewPoint: convert(sender.draggingLocation, from: nil))
    }

    /// The same tracking from a point in this view. Internal so a playtest can
    /// hold a component over the canvas without synthesising a drag session,
    /// which is the only way to photograph what a drag looks like mid air.
    @discardableResult
    func trackComponentDrag(_ componentID: UUID, version: UUID? = nil,
                            atViewPoint viewPoint: CGPoint) -> NSDragOperation {
        guard let viewport, let document else {
            dropLanding = nil
            refreshOverlays()
            return []
        }
        let point = viewport.documentPoint(fromView: viewPoint)
        // One question, asked of the model: the group you have stepped inside
        // takes the drop, so the outline says "this bar" while the button is
        // still down, and where a row would park the piece is where the box is
        // drawn — not under the pointer it is about to leave.
        guard let landing = document.componentDropLanding(
            of: componentID, at: point, inside: dropGroupContext, version: version,
            measure: { TextRasterizer.naturalSize($0) }) else {
            dropLanding = nil
            refreshOverlays()
            return []
        }
        dropLanding = landing
        refreshOverlays()
        return .copy
    }

    /// What the canvas is currently showing the drag in the air: the box it
    /// would fill and the frame it would join, for a playtest to read back.
    var dropLandingDescription: (rect: CGRect, host: UUID?)? { dropLanding }

    /// Places a copy at a point in this view, which is what a drag from the
    /// shelf ends in. Internal so a playtest can land the same drop without
    /// synthesising a drag session.
    func dropComponent(_ componentID: UUID, version: UUID? = nil,
                       atViewPoint point: CGPoint) -> Bool {
        guard let viewport else { return false }
        onDropComponent(componentID, version, viewport.documentPoint(fromView: point))
        return true
    }

    /// Follows a file dragged in from the Finder (or off the Library shelf,
    /// which carries a file too) across the canvas, and draws the box letting
    /// go here would fill.
    ///
    /// A picture arriving from outside is fitted to the screen under the
    /// pointer, or to the canvas when there is no screen there, and nudged
    /// wholly inside it — so how big it lands is not something you can work out
    /// by looking at the file. Drawing the real box removes the surprise, and
    /// it is drawn from the very call the drop makes (`placementForIncomingImage`)
    /// so the promise and the result cannot drift apart.
    ///
    /// Two cases deliberately draw nothing. Over a collage slot the drop fills
    /// that slot instead, and the slot lights up to say so; a second box would
    /// promise something else. And a `.photonz` file opens a window rather than
    /// landing on this canvas.
    ///
    /// A file the canvas can do nothing with — a text file, an archive, a
    /// folder — is refused from the moment it is over the canvas, so the
    /// pointer shows the no-entry sign instead of a copy badge that promises a
    /// layer and then leaves nothing behind.
    private func trackImageDrag(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard let url = droppedURL(sender),
              draggedFile(url, sequence: sender.draggingSequenceNumber).isAccepted else {
            dropLanding = nil
            hoverSlot = nil
            refreshOverlays()
            return []
        }
        // Highlight the collage slot under the pointer — dropping there fills
        // the slot instead of adding a floating layer.
        hoverSlot = dropTarget(for: sender)
        dropLanding = hoverSlot == nil ? landingForFile(url, sender: sender) : nil
        refreshOverlays()
        return .copy
    }

    /// The box the file under the pointer would land in, in canvas
    /// coordinates, and the screen it would join.
    private func landingForFile(_ url: URL, sender: NSDraggingInfo) -> (rect: CGRect, host: UUID?)? {
        guard let viewport, let document,
              let size = draggedFile(url, sequence: sender.draggingSequenceNumber).pictureSize
        else { return nil }
        let point = viewport.documentPoint(fromView: convert(sender.draggingLocation, from: nil))
        let rect = document.placementForIncomingImage(size: size, at: point)
        guard !rect.isEmpty else { return nil }
        return (rect, document.frameID(under: point))
    }

    /// What the file on the pasteboard is, read once per drag.
    /// `draggingUpdated` fires on every mouse move and the file cannot change
    /// under it, so reading the header again on each one would be pure waste.
    /// A refusal is remembered too: a file that is not a picture stays not a
    /// picture, and re-reading it on every move to be told so again is the
    /// same waste.
    private func draggedFile(_ url: URL, sequence: Int) -> CanvasFileDrop {
        if let measured = draggedImage, measured.sequence == sequence, measured.url == url {
            return measured.drop
        }
        let drop = CanvasFileDrop.of(url)
        draggedImage = (sequence, url, drop)
        return drop
    }

    private func droppedURL(_ sender: NSDraggingInfo) -> URL? {
        sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true])?.first as? URL
    }
}
