import AppKit
import PhotonzCore

// What a drag says about itself while it is happening.
//
// A small pill rides under whatever is being dragged and carries the reading
// that drag is CHANGING: where it is going while you move it, how big it is
// becoming while you resize it, sweep a selection box, or pull a point on a
// path. It is there only while the button is down.
//
// It lives HERE, in the canvas view, rather than in `EditorState`, and that is
// the whole reason it can keep up. Every one of these boxes already exists on
// this side: a move and a resize keep theirs in `moveDrag`/`resizeDrag`, a
// sweep in `marquee`, and a path reshape writes `selectedLayerFrame` on every
// single frame (`CanvasPathEdit`). A readout that asked EditorState instead
// would be an observable read on every pointer move, which re-runs the editor
// body sixty times a second — exactly what `EditorCanvasSurface` exists to
// stop — and it would be WRONG for a path drag anyway, because a reshape never
// writes `previewMoves` and the document holds the pre-drag shape for the whole
// gesture.
//
// The rules about what it says and where it goes are `DragReadout`, in
// PhotonzCore, where they are tested.

extension CanvasNSView {

    /// How the pill is drawn. Deliberately the same plate the canvas already
    /// uses for the sentence a drag in the air says (`CanvasTextStyleDrop`), so
    /// the canvas has one voice for "this is about the thing in your hand"
    /// rather than two.
    enum DragReadoutPill {
        /// Room round the words inside the plate.
        static let inset = CGSize(width: 9, height: 4)
        /// How far clear of the box it sits, in screen points, so the gap looks
        /// the same at every zoom.
        static let gap: CGFloat = 12
    }

    /// The type on the pill. It lives on the view rather than in the enum
    /// above because a font is not `Sendable`, and the view is on the main
    /// actor already.
    static let dragReadoutFont = NSFont.systemFont(ofSize: 11, weight: .semibold)

    // MARK: What is being dragged

    /// The drag in flight and the box it is standing on, in CANVAS
    /// coordinates, or nil when nothing is being dragged.
    ///
    /// The order mirrors the order the canvas already resolves a drag in, so
    /// the pill can never describe a different gesture than the one the outline
    /// is following. A press that has not travelled past the click tolerance is
    /// not a drag and gets nothing: a click that happens to pick a layer should
    /// not flash a number at you.
    var dragReadoutSubject: (kind: DragReadout.Kind, box: CGRect, reading: DragReadout.Subject)? {
        guard Experiments.shared.dragReadoutEnabled else { return nil }
        // A path point or lever first, for the same reason `mouseDragged`
        // reads it first: with points showing, the drag belongs to them.
        if let drag = pathAnchorDrag, drag.moved, let box = selectedLayerFrame {
            return reading(.reshape, canvasBox: box, of: drag.layerID)
        }
        if let resizeDrag, resizeDrag.frame != resizeDrag.startFrame {
            return reading(.resize, canvasBox: resizeDrag.frame, of: resizeDrag.layerID)
        }
        if let moveDrag, moveDrag.moved {
            let box = CGRect(origin: moveDrag.snapped.origin, size: moveDrag.size)
            return reading(.move, canvasBox: box, of: moveDrag.layerID)
        }
        if let multiMove, multiMove.moved {
            // A whole selection has no one layer and no one parent, so the box
            // the selection makes on the canvas IS the reading.
            let box = CGRect(origin: multiMove.snapped.origin, size: multiMove.plan.bounds.size)
            return reading(.move, canvasBox: box, of: nil)
        }
        // The two sweeps: the arrow tool's band round layers, and the region
        // tools' band round pixels. Both are answered by the box on screen.
        if let viewport, let marquee, let box = marquee.selectionRect(in: viewport.documentSize) {
            return reading(.sweep, canvasBox: box, of: nil)
        }
        if let viewport, let session = regionDrag,
           let box = session.drag.selectionRect(in: viewport.documentSize) {
            return reading(.sweep, canvasBox: box, of: nil)
        }
        return nil
    }

    /// The numbers to print, for a box the canvas is holding.
    ///
    /// The canvas works in canvas space and shows a box with its slack already
    /// taken off; a layer's numbers are stored in its PARENT'S space with the
    /// slack in. The pill goes through the same door a commit does
    /// (`EditorState.storedCanvasFrame`), so the number under the pointer is
    /// the number the drag is about to land, and the Position and Size fields
    /// read the same thing the moment you let go. Without it a label inside a
    /// button would say where it sits on the canvas while the panel says where
    /// it sits in the button.
    private func reading(_ kind: DragReadout.Kind, canvasBox: CGRect, of id: UUID?)
        -> (kind: DragReadout.Kind, box: CGRect, reading: DragReadout.Subject) {
        guard let id, let document, let layer = document.layer(id: id),
              let parent = document.parentSpaceFrame(layer.withSlack(canvasBox), of: id)
        else { return (kind, canvasBox, DragReadout.subject(kind, box: canvasBox)) }
        return (kind, canvasBox, DragReadout.subject(kind, box: parent))
    }

    /// The words the pill is carrying RIGHT NOW, for a scripted walk to read
    /// back, or nil when no drag is being described. It is the string that was
    /// actually put on the layer, so a walk claims what a person can see.
    var liveDragReadout: String? { dragReadoutShown }

    // MARK: Drawing it

    func setUpDragReadoutChrome() {
        dragReadoutLayer.strokeColor = nil
        dragReadoutLayer.lineWidth = 0
        // Solid and dark rather than tinted: it sits over whatever is being
        // dragged, which may be a photograph, a white screen or a dark one, and
        // the numbers have to read over all three.
        dragReadoutLayer.fillColor = CGColor(gray: 0, alpha: 0.82)
        dragReadoutLayer.isHidden = true
        // Above the selection chrome and the snap guides: a number hidden
        // behind the outline it is describing is not a number.
        dragReadoutLayer.zPosition = 101
        dragReadoutTextLayer.alignmentMode = .center
        dragReadoutTextLayer.foregroundColor = NSColor.white.cgColor
        dragReadoutLayer.addSublayer(dragReadoutTextLayer)
        layer?.addSublayer(dragReadoutLayer)
    }

    /// Puts the pill under the drag, or takes it away. Called from
    /// `refreshOverlays`, so it lands on the same frame as everything else the
    /// drag moves and cannot lag a frame behind the box it is labelling.
    func refreshDragReadout() {
        guard let viewport, let subject = dragReadoutSubject else {
            hideDragReadout()
            return
        }
        let words = DragReadout.text(subject.reading)
        let font = Self.dragReadoutFont
        let inset = DragReadoutPill.inset
        let text = CGSize(width: (words as NSString)
                            .size(withAttributes: [.font: font]).width.rounded(.up),
                          height: (font.ascender - font.descender).rounded(.up))
        let plate = DragReadout.plate(for: viewRect(forDocRect: subject.box, in: viewport),
                                      size: CGSize(width: text.width + inset.width * 2,
                                                   height: text.height + inset.height * 2),
                                      in: bounds, gap: DragReadoutPill.gap)
        dragReadoutLayer.frame = bounds
        dragReadoutLayer.path = CGPath(roundedRect: plate,
                                       cornerWidth: plate.height / 2,
                                       cornerHeight: plate.height / 2, transform: nil)
        dragReadoutTextLayer.string = words
        dragReadoutTextLayer.font = font
        dragReadoutTextLayer.fontSize = font.pointSize
        dragReadoutTextLayer.contentsScale = window?.backingScaleFactor ?? 2
        dragReadoutTextLayer.frame = CGRect(x: plate.minX + inset.width,
                                            y: plate.minY + inset.height,
                                            width: text.width, height: text.height)
        dragReadoutLayer.isHidden = false
        dragReadoutShown = words
    }

    /// Takes it away. The moment the button is up there is no drag to describe,
    /// and a pill left behind would be a number about something that stopped
    /// happening.
    func hideDragReadout() {
        guard dragReadoutShown != nil || !dragReadoutLayer.isHidden else { return }
        dragReadoutLayer.isHidden = true
        dragReadoutLayer.path = nil
        dragReadoutShown = nil
    }
}
