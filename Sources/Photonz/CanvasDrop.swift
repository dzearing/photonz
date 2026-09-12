import AppKit
import PhotonzCore
import PhotonzRender
import SwiftUI

// Dropping onto the canvas: a file or a component dragged in from outside,
// where it would land, and the highlight that says so. Split out of
// CanvasView.swift; `CanvasNSView`'s stored properties still live there.

extension CanvasNSView {
    // MARK: - Drag destination (drop an image to add it as a layer)

    /// What the picture takes, as kinds: a saved text style, a component off
    /// the Library shelf, a file from the Finder. `DragCargo` decides the order
    /// those questions are asked in, so the canvas and the layers panel can
    /// never end up disagreeing about what the same drag is.
    ///
    /// A style drops out of the list while the styles switches are off, so a
    /// shelf nobody can drag from is never met by a picture that would have
    /// taken one.
    private var takes: [DragCargo.Kind] {
        Experiments.shared.textStyleDragEnabled ? [.textStyle, .component, .file] : [.component, .file]
    }

    /// What this drag is carrying.
    private func cargo(_ sender: NSDraggingInfo) -> DragCargo? {
        DragCargo.on(sender.draggingPasteboard, among: takes)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        track(sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        track(sender)
    }

    /// Follows whatever is in the air across the picture, and answers the drag
    /// with what letting go here would do. Entering and moving are the same
    /// question, so they are the same answer.
    private func track(_ sender: NSDraggingInfo) -> NSDragOperation {
        switch cargo(sender) {
        case .textStyle(let style):
            return trackTextStyleDrag(style, atViewPoint: viewPoint(sender))
        case .component(let dragged):
            // A component off the shelf lands wherever the pointer is: there is
            // no collage slot to highlight, and the copy is centred on the
            // drop. What it needs instead is the box it would fill and the
            // frame it would join, drawn while the button is still down.
            return trackComponentDrag(dragged.componentID, version: dragged.version,
                                      atViewPoint: viewPoint(sender))
        default:
            return trackImageDrag(sender)
        }
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        hoverSlot = nil
        dropLanding = nil
        dropHostBox = nil
        draggedImage = nil
        clearTextStyleNote()
        onComponentDragEnded()
        refreshOverlays()
    }

    /// Where the pointer is, in this view's own coordinates.
    private func viewPoint(_ sender: NSDraggingInfo) -> CGPoint {
        convert(sender.draggingLocation, from: nil)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        // Read before the chrome is cleared, and read the one way the tracking
        // read it, so what lands is what the pointer promised. The sentence the
        // canvas drew has to go the moment the button comes up either way.
        let cargo = cargo(sender)
        let point = viewPoint(sender)
        hoverSlot = nil
        dropLanding = nil
        dropHostBox = nil
        draggedImage = nil
        clearTextStyleNote()
        if case .textStyle(let style) = cargo {
            refreshOverlays()
            return dropTextStyle(style, atViewPoint: point)
        }
        // The room closes before the piece lands in it: the drop draws the real
        // picture straight after, and one that is refused still gets its own
        // picture back rather than a gap left open for nothing.
        onComponentDragEnded()
        refreshOverlays()
        if case .component(let dragged) = cargo {
            return dropComponent(dragged.componentID, version: dragged.version,
                                 atViewPoint: point)
        }
        // The same reading the pointer answered with: a file the canvas refused
        // in the air is refused on the way down too, so nothing can slip past a
        // no-entry pointer and land anyway.
        guard let url = DragCargo.fileURL(on: sender.draggingPasteboard) else { return false }
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

    /// Follows a component drag across the canvas: works out the box the copy
    /// would fill and the frame it would join, draws both, and answers the drag
    /// with what letting go here would actually do. A drop that would be
    /// refused (a copy landing inside its own original) says so with the
    /// ordinary no-entry pointer instead of accepting the drag and scolding
    /// afterwards.
    ///
    /// Takes a point rather than the drag, so a playtest can hold a component
    /// over the canvas without synthesising a drag session, which is the only
    /// way to photograph what a drag looks like mid air.
    @discardableResult
    func trackComponentDrag(_ componentID: UUID, version: UUID? = nil,
                            atViewPoint viewPoint: CGPoint) -> NSDragOperation {
        guard let viewport, let document else {
            dropLanding = nil
            dropHostBox = nil
            onComponentDragEnded()
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
            measure: { TextRasterizer.naturalSize($0) },
            arriving: arrivingComponentDrawing(componentID))
        else {
            dropLanding = nil
            dropHostBox = nil
            onComponentDragEnded()
            refreshOverlays()
            return []
        }
        // A row decides the order of what it holds, so it opens the gap the
        // piece is going to take before the button comes up: the pieces either
        // side move along, and the box below is drawn in the space they left.
        onComponentDragMoved(componentID, version, point)
        dropLanding = (landing.rect, landing.host)
        dropHostBox = landing.hostBox
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
        guard let url = DragCargo.fileURL(on: sender.draggingPasteboard),
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

}
